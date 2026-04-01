class EventoMosaicGenerator
  module ZenmosaicColorCanvasPatch
    private

    def run_command!(args)
      super(patch_canvas_creation_command(args))
    end

    def patch_canvas_creation_command(args)
      return args unless args.is_a?(Array)
      return args unless args.length >= 5
      return args unless args[0] == 'convert' && args[1] == '-size' && args[3] == 'xc:none'

      output_path = args.last.to_s
      return args if output_path.start_with?('PNG32:')

      patched = args.dup
      patched[-1] = "PNG32:#{output_path}"
      patched
    rescue StandardError
      args
    end
  end

  def initialize(evento:, pasta_param:)
    @evento = evento
    @pasta_param = pasta_param.to_s.strip
    @pasta_nome = @pasta_param.presence || 'Sem pasta'
  end

  attr_reader :pasta_param, :pasta_nome

  def call(progress_callback: nil)
    ensure_zenmosaic_available!
    ensure_drone!

    image_paths = build_image_paths
    raise StandardError, 'Nao ha imagens validas associadas a esta pasta para gerar mosaico.' if image_paths.empty?

    output_dir = Rails.root.join('tmp', 'zenmosaic', "evento_#{@evento.id}", safe_file_fragment(pasta_nome), Time.current.strftime('%Y%m%d_%H%M%S')).to_s

    result = Zenmosaic.render_mosaic(
      profile_data: {
        fov_diag_deg: @evento.drone.fov_diag_deg.to_f,
        aspect_ratio: parse_aspect_ratio(@evento.drone.aspect_ratio)
      },
      paths: image_paths,
      output_dir: output_dir,
      export_geojson: true,
      export_manifest: true,
      progress_callback: progress_callback
    )

    native_path = result.dig(:collection, :output_path_native)
    compressed_path = result.dig(:collection, :output_path_compressed)

    mosaic_image_path = resolve_mosaic_image_path(compressed_path.presence || native_path, output_dir)
    raise StandardError, 'Falha ao gerar mosaico: nao foi encontrada uma imagem de saida para exibicao.' unless mosaic_image_path.present?

    preview_url = publish_mosaic_preview(
      source_path: mosaic_image_path,
      evento_id: @evento.id,
      pasta_nome: pasta_nome,
      native_path: native_path,
      compressed_path: compressed_path
    )

    {
      preview_url: preview_url,
      pasta_param: pasta_param,
      pasta_nome: pasta_nome
    }
  end

  private

  def ensure_zenmosaic_available!
    if defined?(Zenmosaic) && Zenmosaic.respond_to?(:render_mosaic)
      ensure_zenmosaic_color_canvas_patch!
      return
    end

    require 'zenmosaic'
    if defined?(Zenmosaic) && Zenmosaic.respond_to?(:render_mosaic)
      ensure_zenmosaic_color_canvas_patch!
      return
    end

    raise StandardError, 'Zenmosaic nao esta disponivel no ambiente atual. Reinicie o container web apos o bundle install e tente novamente.'
  rescue LoadError
    raise StandardError, 'Zenmosaic nao esta disponivel no ambiente atual. Reinicie o container web apos o bundle install e tente novamente.'
  end

  def ensure_zenmosaic_color_canvas_patch!
    renderer = Zenmosaic::MosaicRenderer
    singleton = renderer.singleton_class
    return if singleton.ancestors.include?(ZenmosaicColorCanvasPatch)

    singleton.prepend(ZenmosaicColorCanvasPatch)
  rescue StandardError
    nil
  end

  def ensure_drone!
    return if @evento.drone.present?

    raise StandardError, 'Nao foi possivel gerar o mosaico: este evento ainda nao tem drone associado. Defina a chave do drone no evento e tente novamente.'
  end

  def build_image_paths
    imagens = if pasta_param.present?
                @evento.imagens.where(pasta: pasta_param)
              else
                @evento.imagens.where(pasta: [nil, ''])
              end

    input_dir = Rails.root.join(
      'tmp',
      'zenmosaic_inputs',
      "evento_#{@evento.id}",
      safe_file_fragment(pasta_nome),
      Time.current.strftime('%Y%m%d_%H%M%S')
    ).to_s
    FileUtils.mkdir_p(input_dir)

    imagens.each_with_index.filter_map do |imagem, index|
      next unless imagem.arquivo.attached?

      path = materialize_attachment_path_for_mosaic(imagem.arquivo, input_dir, index)
      path if path.present? && File.exist?(path)
    end
  end

  def materialize_attachment_path_for_mosaic(attachment, input_dir, index)
    blob = attachment.blob
    return nil unless blob.content_type.to_s.start_with?('image/')

    extension = blob.filename.extension_with_delimiter
    extension = '.jpg' if extension.blank?
    base_name = safe_file_fragment(blob.filename.base)
    file_name = format('%05d_%s%s', index, base_name, extension)
    target_path = File.join(input_dir, file_name)

    File.binwrite(target_path, blob.download)
    target_path
  rescue StandardError
    nil
  end

  def parse_aspect_ratio(value)
    parts = value.to_s.split(':').map(&:strip)
    return [4, 3] unless parts.length == 2

    width = parts[0].to_i
    height = parts[1].to_i
    return [4, 3] if width <= 0 || height <= 0

    [width, height]
  end

  def safe_file_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end

  def resolve_mosaic_image_path(preferred_path, output_dir)
    if preferred_path.present? && File.exist?(preferred_path) && image_file_path?(preferred_path)
      return preferred_path
    end

    pattern = File.join(output_dir, '**', '*.{jpg,jpeg,png,webp,tif,tiff}')
    candidates = Dir.glob(pattern, File::FNM_CASEFOLD)
    return nil if candidates.empty?

    candidates.max_by { |path| File.mtime(path) }
  rescue StandardError
    nil
  end

  def image_file_path?(path)
    %w[.jpg .jpeg .png .webp .tif .tiff].include?(File.extname(path).downcase)
  end

  def publish_mosaic_preview(source_path:, evento_id:, pasta_nome:, native_path: nil, compressed_path: nil)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    event_fragment = "evento_#{evento_id}"
    pasta_fragment = safe_file_fragment(pasta_nome)

    relative_dir = File.join('mosaics', event_fragment, pasta_fragment)
    public_dir = Rails.root.join('public', relative_dir)
    FileUtils.mkdir_p(public_dir)

    candidates = []

    if compressed_path.present? && File.exist?(compressed_path)
      compressed_target = build_preview_candidate(public_dir: public_dir, timestamp: timestamp, prefix: 'compressed', source_path: compressed_path)
      candidates << compressed_target if compressed_target.present? && File.exist?(compressed_target)
    end

    if native_path.present? && File.exist?(native_path)
      native_target = build_preview_candidate(public_dir: public_dir, timestamp: timestamp, prefix: 'native', source_path: native_path)
      candidates << native_target if native_target.present? && File.exist?(native_target)
    end

    if candidates.empty?
      fallback_ext = File.extname(source_path).downcase.presence || '.jpg'
      fallback_target = File.join(public_dir, "mosaic_#{timestamp}_fallback#{fallback_ext}")
      FileUtils.cp(source_path, fallback_target)
      candidates << fallback_target
    end

    selected_path = select_best_preview_candidate(candidates)
    selected_relative = selected_path.to_s.sub(%r{\A#{Regexp.escape(Rails.root.join('public').to_s)}/?}, '')

    "/#{selected_relative}"
  end

  def build_preview_candidate(public_dir:, timestamp:, prefix:, source_path:)
    ext = File.extname(source_path).downcase
    if %w[.jpg .jpeg .png .webp].include?(ext)
      target_path = File.join(public_dir, "mosaic_#{timestamp}_#{prefix}#{ext}")
      FileUtils.cp(source_path, target_path)
      return target_path if File.exist?(target_path)
    end

    target_path = File.join(public_dir, "mosaic_#{timestamp}_#{prefix}.jpg")
    ok = system(
      'convert',
      source_path,
      '-background', 'white',
      '-alpha', 'remove',
      '-alpha', 'off',
      '-colorspace', 'sRGB',
      '-quality', '92',
      target_path,
      out: File::NULL,
      err: File::NULL
    )
    ok && File.exist?(target_path) ? target_path : nil
  rescue StandardError
    nil
  end

  def select_best_preview_candidate(candidates)
    return candidates.first if candidates.length <= 1

    # Keep compressed output as the first candidate and only fall back when
    # it is objectively worse or unreadable.
    scored = candidates.map { |path| [path, mosaic_preview_score(path)] }
    best = scored.max_by { |(_, score)| score }
    best&.first || candidates.first
  end

  def mosaic_preview_score(path)
    return -1.0 unless path.present? && File.exist?(path)

    format = '%[fx:mean.r],%[fx:mean.g],%[fx:mean.b],%[fx:mean]'
    output = `identify -format "#{format}" "#{path}" 2>/dev/null`.to_s.strip
    values = output.split(',').map { |v| Float(v) rescue nil }
    return -1.0 if values.any?(&:nil?) || values.length < 4

    r, g, b, mean = values
    color_distance = (r - g).abs + (g - b).abs + (r - b).abs
    color_distance - ((mean - 0.5).abs * 0.2)
  rescue StandardError
    -1.0
  end
end
