require 'fileutils'
require 'json'

# Relacao entre as fotos originais e o mosaico, exportada pelo motor (lib/mosaico/mosaico_dji.py, etapa 15.1):
#   sources_<ts>.json  matriz 3x3 de cada foto (pixel da foto -> pixel do mosaico) e a chave do blob da foto
#   sources_<ts>.png   foto dona de cada pixel do mosaico (indice + 1; 0 = vazio), possivelmente reduzido
# Fica ao lado de mosaic_<ts>_compressed.jpg e permite contar nas fotos em resolucao nativa sem contar ninguem duas
# vezes: um ponto da foto i so vale se cair num pixel do mosaico que pertence a i.
class MosaicPhotoMapping
  ENGINE_JSON_NAME = 'mosaico_fotos.json'.freeze
  ENGINE_PNG_NAME = 'mosaico_fontes.png'.freeze

  Photo = Struct.new(:index, :key, :width, :height, :matrix, keyword_init: true) do
    def to_mosaic(x, y)
      [
        (matrix[0][0] * x) + (matrix[0][1] * y) + matrix[0][2],
        (matrix[1][0] * x) + (matrix[1][1] * y) + matrix[1][2]
      ]
    end
  end

  class << self
    def sidecar_paths(mosaic_path)
      path = Pathname.new(mosaic_path.to_s)
      stamp = path.basename.to_s[/\Amosaic_(.+?)(?:_compressed)?\.[a-z]+\z/i, 1]
      return nil unless stamp

      [path.dirname.join("sources_#{stamp}.json"), path.dirname.join("sources_#{stamp}.png")]
    end

    # Copia as saidas do motor (em source_dir) para junto do mosaico publicado.
    def publish!(mosaic_path:, source_dir:)
      json_target, png_target = sidecar_paths(mosaic_path)
      json_source = Pathname.new(source_dir.to_s).join(ENGINE_JSON_NAME)
      png_source = Pathname.new(source_dir.to_s).join(ENGINE_PNG_NAME)
      return false unless json_target && File.file?(json_source) && File.file?(png_source)

      FileUtils.cp(json_source, json_target)
      FileUtils.cp(png_source, png_target)
      [json_target, png_target].each { |target| MosaicStorage.sync_to_other_roots(target) }
      true
    end

    # Grava a chave do blob em cada foto do JSON do motor, a partir do nome do arquivo usado como entrada.
    def attach_keys!(source_dir:, keys_by_filename:)
      json_path = Pathname.new(source_dir.to_s).join(ENGINE_JSON_NAME)
      return unless File.file?(json_path)

      payload = JSON.parse(File.read(json_path))
      payload['photos'].each { |photo| photo['key'] ||= keys_by_filename[photo['filename']] }
      File.write(json_path, JSON.generate(payload))
    end

    def for_mosaic(mosaic_path)
      json_path, png_path = sidecar_paths(mosaic_path)
      return nil unless json_path && File.file?(json_path) && File.file?(png_path)

      new(json_path: json_path, png_path: png_path)
    rescue JSON::ParserError, Vips::Error => e
      Rails.logger.warn("Mapa foto -> mosaico ilegivel para #{mosaic_path}: #{e.class} - #{e.message}")
      nil
    end
  end

  attr_reader :photos, :mosaic_width, :mosaic_height

  def initialize(json_path:, png_path:)
    require 'vips'

    payload = JSON.parse(File.read(json_path))
    @mosaic_width = payload.fetch('mosaic_width').to_i
    @mosaic_height = payload.fetch('mosaic_height').to_i
    @complete = payload.fetch('photos').all? { |photo| photo['key'].present? }
    @photos = payload.fetch('photos').map do |photo|
      Photo.new(
        index: photo.fetch('index').to_i,
        key: photo['key'],
        width: photo.fetch('width').to_i,
        height: photo.fetch('height').to_i,
        matrix: photo.fetch('photo_to_mosaic')
      )
    end

    owners = Vips::Image.new_from_file(png_path.to_s)
    owners = owners.extract_band(0) if owners.bands > 1
    @owners_width = owners.width
    @owners_height = owners.height
    @owners = owners.cast(:ushort).write_to_memory
  end

  # So da para contar nas fotos se todas tem chave (o blob da foto) e o mapa bate com o mosaico em uso.
  def usable_for?(width:, height:)
    @complete && photos.any? && width == mosaic_width && height == mosaic_height
  end

  # Indice da foto dona do pixel do mosaico (coordenadas do mosaico), ou nil fora da area coberta.
  def owner_at(mosaic_x, mosaic_y)
    return nil unless mosaic_x >= 0 && mosaic_y >= 0 && mosaic_x < mosaic_width && mosaic_y < mosaic_height

    owner_x = [(mosaic_x * @owners_width / mosaic_width).floor, @owners_width - 1].min
    owner_y = [(mosaic_y * @owners_height / mosaic_height).floor, @owners_height - 1].min
    value = @owners.byteslice(((owner_y * @owners_width) + owner_x) * 2, 2).unpack1('S')
    value.zero? ? nil : value - 1
  end

  def owns?(photo, photo_x, photo_y)
    owner_at(*photo.to_mosaic(photo_x, photo_y)) == photo.index
  end

  # A foto e dona de alguma parte do retangulo (coordenadas da foto)? Amostra uma grade de pontos.
  # Com 32x32 amostras o passo fica em ~30 px numa janela de ~1.000 px (cerca de 1 m nas fotos de drone).
  def owns_any?(photo, rect, samples: 32)
    (0...samples).any? do |row|
      (0...samples).any? do |col|
        owns?(photo, rect.x + ((col + 0.5) * rect.width / samples), rect.y + ((row + 0.5) * rect.height / samples))
      end
    end
  end
end
