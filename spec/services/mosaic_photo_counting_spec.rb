require 'rails_helper'
require 'securerandom'

RSpec.describe 'Contagem nas fotos originais' do
  # Mosaico 2000x1000 formado por duas fotos deslocadas so na horizontal:
  #   foto 0: 1800x1000, x do mosaico = x da foto
  #   foto 1: 1200x1000, x do mosaico = x da foto + 800
  # A sobreposicao (800..1800) pertence a foto 0 ate x=1000 e a foto 1 dali em diante.
  class FakePhotoBackend
    attr_reader :windows

    def initialize(people, offsets)
      @people = people
      @offsets = offsets
      @windows = []
    end

    def prepare(source_path:); end
    def prepare_photos(_blobs); end

    def photo_source(blob)
      "photo-#{blob.key}"
    end

    def infer(items)
      items.each do |item|
        offset = item.image ? @offsets.fetch(item.image) : 0 # sem image: janela do proprio mosaico
        rect = item.window
        @windows << [item.image, rect.x, rect.y]
        # Toda foto ve todas as pessoas dentro dela; o P2PNet devolve na imagem redimensionada (metade, aqui).
        points = @people.filter_map do |x, y|
          photo_x = x - offset
          [(photo_x - rect.x) * 0.5, (y - rect.y) * 0.5] if rect.contains?(photo_x, y)
        end
        yield item, MosaicCounting::Outcome.new(status: :ok, points: points, resized_width: rect.width / 2, resized_height: rect.height / 2)
      end
    end

    def cleanup; end
  end

  let(:test_dir) { Rails.root.join('tmp', "photo_counting_spec_#{SecureRandom.hex(6)}") }
  let(:mosaic_path) { test_dir.join('mosaic_20261023_120000_compressed.jpg') }
  let(:blob_a) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a'), filename: 'a.jpg', content_type: 'image/jpeg') }
  let(:blob_b) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('b'), filename: 'b.jpg', content_type: 'image/jpeg') }

  before do
    require 'vips'
    FileUtils.mkdir_p(test_dir)
    allow(P2pnetInferenceSettings).to receive(:tile_max_pixels).and_return(1_000_000)
    allow(P2pnetInferenceSettings).to receive(:tile_overlap_px).and_return(100)

    (Vips::Image.black(2000, 1000, bands: 3) + 120).cast(:uchar).write_to_file(mosaic_path.to_s)
    write_engine_outputs(test_dir)
    MosaicPhotoMapping.publish!(mosaic_path: mosaic_path, source_dir: test_dir)
  end

  after { FileUtils.rm_rf(test_dir) }

  def write_engine_outputs(dir, keys: [blob_a.key, blob_b.key])
    File.write(dir.join(MosaicPhotoMapping::ENGINE_JSON_NAME), JSON.generate(
      mosaic_width: 2000,
      mosaic_height: 1000,
      photos: [
        { index: 0, filename: '00000_a.jpg', key: keys[0], width: 1800, height: 1000, photo_to_mosaic: [[1, 0, 0], [0, 1, 0], [0, 0, 1]] },
        { index: 1, filename: '00001_b.jpg', key: keys[1], width: 1200, height: 1000, photo_to_mosaic: [[1, 0, 800], [0, 1, 0], [0, 0, 1]] }
      ]
    ))

    # Mapa de donos em meia resolucao (1000x500): indice + 1, foto 0 ate x=1000 do mosaico.
    left = Vips::Image.black(500, 500) + 1
    right = Vips::Image.black(500, 500) + 2
    left.join(right, :horizontal).cast(:ushort).write_to_file(dir.join(MosaicPhotoMapping::ENGINE_PNG_NAME).to_s)
  end

  describe MosaicPhotoMapping do
    let(:mapping) { described_class.for_mosaic(mosaic_path) }

    it 'le o mapa publicado ao lado do mosaico' do
      expect(mapping).to be_usable_for(width: 2000, height: 1000)
      expect(mapping).not_to be_usable_for(width: 1000, height: 500)
      expect(mapping.owner_at(10, 10)).to eq(0)
      expect(mapping.owner_at(999, 999)).to eq(0)
      expect(mapping.owner_at(1001, 10)).to eq(1)
      expect(mapping.owner_at(2000, 10)).to be_nil
      expect(mapping.photos.last.to_mosaic(100, 50)).to eq([900, 50])
    end

    it 'nao serve sem a chave de alguma foto' do
      write_engine_outputs(test_dir, keys: [blob_a.key, nil])
      MosaicPhotoMapping.publish!(mosaic_path: mosaic_path, source_dir: test_dir)

      expect(mapping).not_to be_usable_for(width: 2000, height: 1000)
    end
  end

  describe MosaicTempGridCutter do
    let(:people) { [[10, 10], [700, 500], [850, 200], [999, 900], [1001, 900], [1300, 300], [1799, 999], [1990, 10]] }
    let(:backend) { FakePhotoBackend.new(people, "photo-#{blob_a.key}" => 0, "photo-#{blob_b.key}" => 800) }
    let(:cutter) { described_class.new(source_path: mosaic_path.to_s, evento_id: 1, pasta_nome: 'Voo') }

    before { allow(MosaicCounting).to receive(:build).and_return(backend) }

    it 'conta cada pessoa uma unica vez, inclusive onde as fotos se sobrepoem' do
      result = cutter.call

      expect(result.success?).to be(true)
      expect(result.total_heads).to eq(people.size)
      expect(result.points.map { |x, y| [x.round, y.round] }).to match_array(people)
      expect(result.piece_counts.sum { |piece| piece[:estimated_heads] }).to eq(people.size)
    end

    it 'nao roda inferencia nas janelas que a foto nao possui no mosaico' do
      cutter.call

      # Foto 0 (1800 px) tem cores em x 0-600, 600-1200 e 1200-1800; a ultima fica toda com a foto 1.
      photo_a_columns = backend.windows.select { |image, _x, _y| image == "photo-#{blob_a.key}" }.map { |_image, x, _y| x }.uniq
      expect(photo_a_columns.size).to eq(2)
      expect(backend.windows.map(&:first).uniq.size).to eq(2)
    end

    it 'volta a contar no mosaico quando uma foto nao existe mais' do
      blob_b.destroy

      result = cutter.call

      expect(result.success?).to be(true)
      expect(result.total_heads).to eq(people.size)
      expect(backend.windows.map(&:first).uniq).to eq([nil])
    end
  end
end
