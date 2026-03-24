require 'fileutils'

class MosaicTempGridCutter
  Result = Struct.new(:success?, :error, :output_dir, :files_count, keyword_init: true)

  MIN_ROWS = 1
  MAX_ROWS = 4
  MIN_COLS = 1
  MAX_COLS = 8

  def initialize(source_path:, rows:, cols:, evento_id:, pasta_nome:)
    @source_path = source_path.to_s
    @rows = rows.to_i
    @cols = cols.to_i
    @evento_id = evento_id
    @pasta_nome = pasta_nome.to_s
  end

  def call
    return failure('Arquivo de mosaico nao encontrado.') unless File.exist?(@source_path)
    return failure('Linhas devem estar entre 1 e 4 e colunas entre 1 e 8.') unless valid_grid_size?

    ensure_vips_available!

    source_image = Vips::Image.new_from_file(@source_path)
    x_edges = build_edges(source_image.width, @cols)
    y_edges = build_edges(source_image.height, @rows)

    output_dir = build_output_dir
    FileUtils.mkdir_p(output_dir)

    generated = 0

    @rows.times do |row_index|
      @cols.times do |col_index|
        x = x_edges[col_index]
        y = y_edges[row_index]
        width = x_edges[col_index + 1] - x
        height = y_edges[row_index + 1] - y

        raise CutterError, 'Mosaico muito pequeno para o grid selecionado.' if width <= 0 || height <= 0

        tile = source_image.crop(x, y, width, height)
        tile.write_to_file(File.join(output_dir, tile_name(row_index, col_index)))
        generated += 1
      end
    end

    Result.new(success?: true, output_dir: output_dir, files_count: generated)
  rescue StandardError => e
    failure(error_message_for(e))
  end

  private

  class CutterError < StandardError; end

  def valid_grid_size?
    @rows.between?(MIN_ROWS, MAX_ROWS) && @cols.between?(MIN_COLS, MAX_COLS)
  end

  def ensure_vips_available!
    require 'vips'
  rescue LoadError
    raise CutterError, "Dependencia 'vips' nao encontrada. Rode com 'bundle exec' e instale as dependencias (gem ruby-vips e libvips)."
  end

  def build_edges(total, slices)
    edges = Array.new(slices + 1) { |index| ((index * total.to_f) / slices).round }
    edges[0] = 0
    edges[-1] = total
    edges
  end

  def build_output_dir
    Rails.root.join(
      'tmp',
      'mosaic_cuts',
      "evento_#{@evento_id}",
      safe_file_fragment(@pasta_nome),
      Time.current.strftime('%Y%m%d_%H%M%S')
    ).to_s
  end

  def tile_name(row_index, col_index)
    format('mosaic_r%02dc%02d.jpg', row_index + 1, col_index + 1)
  end

  def safe_file_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end

  def error_message_for(error)
    return error.message if error.is_a?(CutterError)

    'Nao foi possivel cortar o mosaico. Tente novamente.'
  end

  def failure(message)
    Result.new(success?: false, error: message, output_dir: nil, files_count: 0)
  end
end
