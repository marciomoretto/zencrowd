require 'fileutils'
require 'securerandom'

class ImagemTileCutter
  Result = Struct.new(
    :success?,
    :error,
    :created_count,
    :counted_count,
    :warning_count,
    :error_count,
    :message_counts,
    keyword_init: true
  )

  MIN_GRID_SIZE = 1
  MAX_GRID_SIZE = 4

  def initialize(imagem:, uploader:, rows:, cols:)
    @imagem = imagem
    @uploader = uploader
    @rows = rows.to_i
    @cols = cols.to_i
  end

  def call(replace_existing: false, &progress_callback)
    return failure('Imagem sem arquivo anexado.') unless @imagem.arquivo.attached?
    return failure('Linhas e colunas devem estar entre 1 e 4.') unless valid_grid_size?
    ensure_vips_available!

    created_paths = []
    created_count = 0
    counted_count = 0
    warning_count = 0
    error_count = 0
    message_counts = Hash.new(0)
    total_count = @rows * @cols

    emit_progress(progress_callback, processed_count: 0, total_count: total_count, created_count: 0)

    ActiveRecord::Base.transaction do
      remove_existing_tiles! if replace_existing

      @imagem.arquivo.blob.open do |source_file|
        source_image = Vips::Image.new_from_file(source_file.path)
        x_edges = build_edges(source_image.width, @cols)
        y_edges = build_edges(source_image.height, @rows)

        @rows.times do |row_index|
          @cols.times do |col_index|
            x = x_edges[col_index]
            y = y_edges[row_index]
            width = x_edges[col_index + 1] - x
            height = y_edges[row_index + 1] - y

            raise CutterError, 'Imagem muito pequena para o grid selecionado.' if width <= 0 || height <= 0

            cropped_tile = source_image.crop(x, y, width, height)
            storage_rel_path, storage_abs_path = build_storage_paths(row_index, col_index)

            cropped_tile.write_to_file(storage_abs_path.to_s)
            created_paths << storage_abs_path

            tile_record = Tile.create!(
              original_filename: generated_original_filename(row_index, col_index),
              storage_path: storage_rel_path,
              status: :available,
              uploader: @uploader
            )

            @imagem.imagem_tiles.create!(tile: tile_record)
            created_count += 1

            count_result = TileHeadCounter.call(tile: tile_record, expose_error: true)
            case count_result[:status]
            when :ok
              counted_count += 1
            when :warning
              warning_count += 1
              increment_reason_count(message_counts, count_result[:message])
            else
              error_count += 1
              increment_reason_count(message_counts, count_result[:message])
            end

            emit_progress(progress_callback, processed_count: created_count, total_count: total_count, created_count: created_count)
          end
        end
      end
    end

    Result.new(
      success?: true,
      created_count: created_count,
      counted_count: counted_count,
      warning_count: warning_count,
      error_count: error_count,
      message_counts: message_counts
    )
  rescue StandardError => e
    cleanup_files(created_paths || [])
    failure(error_message_for(e))
  end

  private

  class CutterError < StandardError; end

  def valid_grid_size?
    @rows.between?(MIN_GRID_SIZE, MAX_GRID_SIZE) && @cols.between?(MIN_GRID_SIZE, MAX_GRID_SIZE)
  end

  def ensure_vips_available!
    require 'vips'
  rescue LoadError
    raise CutterError, "Dependencia 'vips' nao encontrada. Rode com 'bundle exec' e instale as dependencias (gem ruby-vips e libvips)."
  end

  def remove_existing_tiles!
    @imagem.imagem_tiles.includes(:tile).to_a.each do |imagem_tile|
      tile = imagem_tile.tile
      imagem_tile.destroy!
      next unless tile
      next unless tile.imagem_tiles.reload.none?

      tile.destroy!
    end
  end

  def build_edges(total, slices)
    edges = Array.new(slices + 1) { |index| ((index * total.to_f) / slices).round }
    edges[0] = 0
    edges[-1] = total
    edges
  end

  def build_storage_paths(row_index, col_index)
    filename = "#{timestamp_prefix}_img#{@imagem.id}_r#{row_index + 1}c#{col_index + 1}_#{SecureRandom.hex(8)}#{output_extension}"
    absolute_path = upload_directory.join(filename)
    relative_path = File.join('storage', 'uploads', 'images', filename)

    [relative_path, absolute_path]
  end

  def generated_original_filename(row_index, col_index)
    "#{base_filename}_r#{row_index + 1}_c#{col_index + 1}#{output_extension}"
  end

  def base_filename
    @base_filename ||= begin
      raw_base = File.basename(@imagem.arquivo.filename.to_s, '.*')
      safe_base = raw_base.gsub(/[^0-9A-Za-z_-]+/, '_').gsub(/\A_+|_+\z/, '')
      safe_base.presence || 'tile'
    end
  end

  def output_extension
    @output_extension ||= begin
      ext = File.extname(@imagem.arquivo.filename.to_s).downcase
      ext == '.png' ? '.png' : '.jpg'
    end
  end

  def timestamp_prefix
    @timestamp_prefix ||= Time.current.strftime('%Y%m%d%H%M%S')
  end

  def upload_directory
    @upload_directory ||= begin
      directory = Rails.root.join('storage', 'uploads', 'images')
      FileUtils.mkdir_p(directory) unless Dir.exist?(directory)
      directory
    end
  end

  def cleanup_files(paths)
    paths.each do |path|
      File.delete(path) if File.exist?(path)
    end
  end

  def error_message_for(error)
    return error.message if error.is_a?(CutterError)
    return error.record.errors.full_messages.join(', ') if error.is_a?(ActiveRecord::RecordInvalid)

    'Nao foi possivel cortar a imagem. Tente novamente.'
  end

  def failure(message)
    Result.new(
      success?: false,
      error: message,
      created_count: 0,
      counted_count: 0,
      warning_count: 0,
      error_count: 0,
      message_counts: {}
    )
  end

  def increment_reason_count(message_counts, message)
    reason = message.to_s.strip
    return if reason.blank?

    message_counts[reason] += 1
  end

  def emit_progress(progress_callback, processed_count:, total_count:, created_count:)
    return unless progress_callback

    progress_callback.call(
      processed_count: processed_count,
      total_count: total_count,
      created_count: created_count
    )
  end
end
