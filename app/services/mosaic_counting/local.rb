require 'fileutils'
require 'securerandom'

module MosaicCounting
  # Roda o P2PNet no proprio servidor, uma janela por vez.
  class Local
    TILE_JPEG_QUALITY = 95

    def initialize(work_dir:)
      @work_dir = work_dir
    end

    def prepare(source_path:)
      ensure_p2pnet_available!

      require 'vips'
      @image = Vips::Image.new_from_file(source_path)
    end

    def infer(items)
      items.each { |item| yield item, infer_window(item.window) }
    end

    def cleanup; end

    private

    def infer_window(window)
      window_path = File.join(@work_dir, "window_#{SecureRandom.hex(6)}.jpg")
      output_path = p2pnet_output_path

      @image.crop(window.x, window.y, window.width, window.height)
            .write_to_file(window_path, Q: TILE_JPEG_QUALITY)

      result = CrowdCountingP2PNet.annotate(
        image_path: window_path,
        output_path: output_path,
        threshold: P2pnetInferenceSettings.threshold,
        device: P2pnetInferenceSettings.device
      )

      payload = result.raw_payload || {}
      Outcome.new(
        status: :ok,
        points: Array(result.points),
        resized_width: payload['resized_width'] || window.width,
        resized_height: payload['resized_height'] || window.height
      )
    rescue CrowdCountingP2PNet::InferenceError => e
      return Outcome.new(status: :oom) if oom_like_error?(e)

      raise BackendError, "Falha na inferencia para recorte do mosaico: #{compact_error_message(e)}"
    rescue BackendError
      raise
    rescue StandardError => e
      raise BackendError, "Erro ao contar cabecas nos recortes do mosaico: #{compact_error_message(e)}"
    ensure
      [window_path, output_path].compact.each { |path| File.delete(path) if File.exist?(path) }
    end

    def ensure_p2pnet_available!
      return if defined?(CrowdCountingP2PNet)

      require 'crowd_counting_p2pnet'
      return if defined?(CrowdCountingP2PNet)

      raise BackendError, 'Biblioteca de contagem indisponivel no servidor. Reinicie a aplicacao.'
    rescue LoadError
      raise BackendError, 'Biblioteca de contagem indisponivel no servidor. Rode bundle install e reinicie a aplicacao.'
    end

    def p2pnet_output_path
      output_dir = Rails.root.join('tmp', 'p2pnet_tiles')
      FileUtils.mkdir_p(output_dir)
      output_dir.join("mosaic-cut-#{SecureRandom.hex(6)}.jpg").to_s
    end

    def oom_like_error?(error)
      message = error.message.to_s.downcase

      message.include?('oom') ||
        message.include?('out of memory') ||
        message.include?('cannot allocate memory') ||
        message.include?('killed') ||
        message.include?('exit 137')
    end

    def compact_error_message(error)
      lines = error.message.to_s.lines.map(&:strip).reject(&:blank?)
      candidate = lines.find do |line|
        !(line.downcase.start_with?('traceback') || line.downcase.start_with?('file "'))
      end

      (candidate.presence || error.class.to_s).truncate(180)
    end
  end
end
