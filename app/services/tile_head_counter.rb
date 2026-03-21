class TileHeadCounter
  MAX_P2PNET_PIXELS = 12_000_000
  OOM_TILE_UPLOAD_ALERT = 'Imagem muito grande, tente quebrar em pedaços menores.'

  class << self
    def call(tile:, expose_error: false)
      library_error_message = ensure_p2pnet_library_loaded
      if library_error_message.present?
        Rails.logger.warn("P2PNet unavailable for tile ##{tile.id}: #{library_error_message}")

        return {
          status: :error,
          message: (expose_error ? library_error_message : nil)
        }
      end

      image_path = image_file_path(tile)
      if image_path.blank?
        return {
          status: :error,
          message: (expose_error ? 'Arquivo do tile não foi encontrado para contagem.' : nil)
        }
      end

      return { status: :warning, message: OOM_TILE_UPLOAD_ALERT } if image_too_large_for_p2pnet?(image_path)

      output_path = p2pnet_output_path_for(tile)

      result = CrowdCountingP2PNet.annotate(
        image_path: image_path,
        output_path: output_path.to_s,
        threshold: 0.5,
        device: ENV.fetch('P2PNET_DEVICE', 'cpu')
      )

      tile.update_columns(
        head_count: result.count,
        task_value: task_value_from_head_count(result.count)
      )
      { status: :ok, count: result.count }
    rescue CrowdCountingP2PNet::InferenceError => e
      return { status: :warning, message: OOM_TILE_UPLOAD_ALERT } if oom_like_error?(e)

      summarized_error = compact_error_message(e)
      Rails.logger.warn("P2PNet inference failed for tile ##{tile.id}: #{summarized_error} | raw=#{e.message.to_s.lines.first.to_s.strip}")

      {
        status: :error,
        message: (expose_error ? "Falha na inferência: #{summarized_error}" : nil)
      }
    rescue StandardError => e
      summarized_error = compact_error_message(e)
      Rails.logger.warn("P2PNet head count unavailable for tile ##{tile.id}: #{e.class} - #{summarized_error}")

      {
        status: :error,
        message: (expose_error ? "Erro interno ao contar cabeças: #{summarized_error}" : nil)
      }
    ensure
      File.delete(output_path) if output_path && File.exist?(output_path)
    end

    private

    def image_file_path(tile)
      return nil if tile.storage_path.blank?

      raw_path = Pathname.new(tile.storage_path)
      full_path = raw_path.absolute? ? raw_path : Rails.root.join(raw_path)
      full_path = full_path.cleanpath

      storage_root = Rails.root.join('storage').cleanpath.to_s
      return nil unless full_path.to_s.start_with?(storage_root)
      return nil unless File.file?(full_path)

      full_path.to_s
    end

    def p2pnet_output_path_for(tile)
      output_dir = Rails.root.join('tmp', 'p2pnet_tiles')
      FileUtils.mkdir_p(output_dir)
      output_dir.join("tile-#{tile.id}-#{SecureRandom.hex(6)}.jpg")
    end

    def image_too_large_for_p2pnet?(file_path)
      image = Vips::Image.new_from_file(file_path, access: :sequential)
      (image.width * image.height) > MAX_P2PNET_PIXELS
    rescue StandardError
      false
    end

    def oom_like_error?(error)
      message = error.message.to_s.downcase

      message.include?('oom') ||
        message.include?('out of memory') ||
        message.include?('cannot allocate memory') ||
        message.include?('killed') ||
        message.include?('exit 137') ||
        message.include?('137')
    end

    def compact_error_message(error)
      lines = error.message.to_s.lines.map(&:strip).reject(&:blank?)
      candidate = lines.find do |line|
        !(line.downcase.start_with?('traceback') || line.downcase.start_with?('file "'))
      end

      (candidate.presence || error.class.to_s).truncate(180)
    end

    def ensure_p2pnet_library_loaded
      return nil if defined?(CrowdCountingP2PNet)

      require 'crowd_counting_p2pnet'
      return nil if defined?(CrowdCountingP2PNet)

      'Biblioteca de contagem indisponível no servidor. Reinicie a aplicação.'
    rescue LoadError => e
      details = compact_error_message(e)
      "Biblioteca de contagem indisponível no servidor (#{details}). Rode bundle install e reinicie o servidor."
    rescue StandardError => e
      details = compact_error_message(e)
      "Biblioteca de contagem indisponível no servidor (#{details})."
    end

    def task_value_from_head_count(head_count)
      AppSetting.task_value_for_estimated_heads(head_count)
    rescue StandardError
      nil
    end
  end
end
