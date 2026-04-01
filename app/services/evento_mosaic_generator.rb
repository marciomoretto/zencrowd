class EventoMosaicGenerator
  TOP_BOTTOM_OCCLUSION_TRIM_RATIO = 0.05
  OCCLUSION_COVERAGE_THRESHOLD = 0.98
  OCCLUSION_SAMPLE_GRID_X = 14
  OCCLUSION_SAMPLE_GRID_Y = 10

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

    selection = build_image_paths
    image_paths = Array(selection[:paths])
    raise StandardError, 'Nao ha imagens validas associadas a esta pasta para gerar mosaico.' if image_paths.empty?

    output_dir = Rails.root.join('tmp', 'zenmosaic', "evento_#{@evento.id}", safe_file_fragment(pasta_nome), Time.current.strftime('%Y%m%d_%H%M%S')).to_s

    result = render_mosaic_with_occlusion_pruning(
      image_paths: image_paths,
      output_dir: output_dir,
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

    optimization = (result[:optimization].is_a?(Hash) ? result[:optimization] : {}).merge(
      source_total_count: selection[:source_total_count].to_i,
      source_zenital_count: selection[:source_zenital_count].to_i,
      preselected_count: selection[:selected_count].to_i,
      preselection_mode: selection[:selection_mode].to_s
    )

    {
      preview_url: preview_url,
      pasta_param: pasta_param,
      pasta_nome: pasta_nome,
      optimization: optimization
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

    imagens = imagens.to_a
    tolerance = AppSetting.zenith_tolerance_degrees
    zenitais = imagens.select { |imagem| imagem.zenital?(tolerance_degrees: tolerance) }

    imagens_selecionadas = if zenitais.any?
                            zenitais
                          else
                            imagens
                          end

    selection_mode = zenitais.any? ? 'zenital_only' : 'fallback_all'

    input_dir = Rails.root.join(
      'tmp',
      'zenmosaic_inputs',
      "evento_#{@evento.id}",
      safe_file_fragment(pasta_nome),
      Time.current.strftime('%Y%m%d_%H%M%S')
    ).to_s
    FileUtils.mkdir_p(input_dir)

    paths = imagens_selecionadas.each_with_index.filter_map do |imagem, index|
      next unless imagem.arquivo.attached?

      path = materialize_attachment_path_for_mosaic(imagem.arquivo, input_dir, index)
      path if path.present? && File.exist?(path)
    end

    {
      paths: paths,
      source_total_count: imagens.size,
      source_zenital_count: zenitais.size,
      selected_count: imagens_selecionadas.size,
      selection_mode: selection_mode
    }
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

  def render_mosaic_with_occlusion_pruning(image_paths:, output_dir:, progress_callback:)
    emit_progress(progress_callback, stage: 'preview', status: 'started', message: 'Construindo preview')

    preview_bundle = Zenmosaic.build_preview(
      profile_data: {
        fov_diag_deg: @evento.drone.fov_diag_deg.to_f,
        aspect_ratio: parse_aspect_ratio(@evento.drone.aspect_ratio)
      },
      paths: image_paths,
      output_dir: output_dir,
      export_geojson: true,
      export_manifest: true
    )

    emit_progress(progress_callback, stage: 'preview', status: 'completed', message: 'Preview concluido')

    optimization = prune_fully_occluded_preview_items!(preview_bundle)
    profile_name = fetch_hash_value(fetch_hash_value(preview_bundle, :request, 'request'), :profile_name, 'profile_name')

    mosaics = Zenmosaic::MosaicRenderer.render_hourly(
      preview_result: fetch_hash_value(preview_bundle, :preview, 'preview'),
      profile_name: profile_name,
      output_dir: output_dir,
      downsample_native: 1,
      compressed_scale: 0.35,
      compressed_quality: 88,
      progress_callback: progress_callback
    )

    {
      collection: Array(fetch_hash_value(mosaics, :collections, 'collections')).first,
      optimization: optimization
    }
  end

  def prune_fully_occluded_preview_items!(preview_bundle)
    return { enabled: false, input_count: 0, discarded_count: 0, output_count: 0 } unless occlusion_pruning_enabled?

    preview = fetch_hash_value(preview_bundle, :preview, 'preview')
    collections = Array(fetch_hash_value(preview, :collections, 'collections'))

    input_count = 0
    discarded_count = 0

    collections.each do |collection|
      items = Array(fetch_hash_value(collection, :items, 'items'))
      input_count += items.size

      kept = []
      discarded_paths = []

      items.each do |item|
        polygon = extract_item_polygon(item)
        coverage_polygon = extract_coverage_polygon(item)
        kept << { item: item, polygon: polygon, coverage_polygon: coverage_polygon }
      end

      # Iteratively remove polygons whose useful area is already covered by the
      # union of the remaining ones, approximated by interior sampling points.
      loop do
        removed_any = false

        kept.each_with_index do |entry, index|
          coverage = entry[:coverage_polygon]
          next if coverage.blank?

          others = kept.each_with_index.filter_map do |other, other_index|
            next if other_index == index

            other[:polygon] || other[:coverage_polygon]
          end

          next if others.empty?
          next unless polygon_covered_by_union?(coverage, others)

          path = fetch_hash_value(entry[:item], :image_path, 'image_path')
          discarded_paths << path if path.present?
          kept.delete_at(index)
          discarded_count += 1
          removed_any = true
          break
        end

        break unless removed_any
      end

      kept_items = kept.map { |entry| entry[:item] }
      set_hash_value(collection, :items, kept_items)
      existing_discarded = Array(fetch_hash_value(collection, :discarded_paths, 'discarded_paths'))
      set_hash_value(collection, :discarded_paths, (existing_discarded + discarded_paths).compact.uniq)
    end

    {
      enabled: true,
      input_count: input_count,
      discarded_count: discarded_count,
      output_count: input_count - discarded_count
    }
  rescue StandardError
    { enabled: true, input_count: 0, discarded_count: 0, output_count: 0 }
  end

  def occlusion_pruning_enabled?
    value = ENV.fetch('MOSAIC_OCCLUSION_PRUNING', 'true').to_s.strip.downcase
    !%w[0 false no off].include?(value)
  end

  def extract_item_polygon(item)
    geometry = fetch_hash_value(item, :geometry, 'geometry')
    kind = fetch_hash_value(geometry, :type, 'type').to_s
    coordinates = fetch_hash_value(geometry, :coordinates, 'coordinates')

    if kind == 'Polygon'
      return normalize_ring(Array(coordinates).first)
    end

    if kind == 'MultiPolygon'
      polygons = Array(coordinates)
      largest = polygons.max_by do |poly|
        ring = normalize_ring(Array(poly).first)
        polygon_area(ring)
      end
      return normalize_ring(Array(largest).first)
    end

    nil
  rescue StandardError
    nil
  end

  def extract_coverage_polygon(item)
    trimmed = build_trimmed_polygon_from_transform(item, TOP_BOTTOM_OCCLUSION_TRIM_RATIO)
    return trimmed if trimmed.present?

    extract_item_polygon(item)
  end

  def build_trimmed_polygon_from_transform(item, trim_ratio)
    transform = fetch_hash_value(item, :transform, 'transform')
    x0 = to_float(fetch_hash_value(transform, :x0, 'x0'))
    y0 = to_float(fetch_hash_value(transform, :y0, 'y0'))
    half_w = to_float(fetch_hash_value(transform, :half_w, 'half_w'))
    half_h = to_float(fetch_hash_value(transform, :half_h, 'half_h'))
    rotation_deg = to_float(fetch_hash_value(transform, :rotation_deg, 'rotation_deg')) || 0.0

    return nil if [x0, y0, half_w, half_h].any?(&:nil?)
    return nil if half_w <= 0 || half_h <= 0

    ratio = [[trim_ratio.to_f, 0.0].max, 0.49].min
    inner_half_h = half_h * (1.0 - (ratio * 2.0))
    return nil if inner_half_h <= 0.0

    theta = rotation_deg * Math::PI / 180.0
    cos_t = Math.cos(theta)
    sin_t = Math.sin(theta)

    corners = [
      [-half_w, -inner_half_h],
      [half_w, -inner_half_h],
      [half_w, inner_half_h],
      [-half_w, inner_half_h]
    ]

    corners.map do |dx, dy|
      [
        x0 + (dx * cos_t - dy * sin_t),
        y0 + (dx * sin_t + dy * cos_t)
      ]
    end
  rescue StandardError
    nil
  end

  def to_float(value)
    return nil if value.nil?

    Float(value)
  rescue StandardError
    nil
  end

  def normalize_ring(ring)
    points = Array(ring).filter_map do |point|
      next unless point.is_a?(Array) && point.length >= 2

      x = Float(point[0]) rescue nil
      y = Float(point[1]) rescue nil
      next if x.nil? || y.nil?

      [x, y]
    end

    points.length >= 3 ? points : nil
  end

  def polygon_area(ring)
    return 0.0 if ring.blank? || ring.length < 3

    area2 = 0.0
    ring.each_with_index do |(x1, y1), idx|
      x2, y2 = ring[(idx + 1) % ring.length]
      area2 += (x1 * y2) - (x2 * y1)
    end

    area2.abs / 2.0
  end

  def polygon_contains_polygon?(container, candidate)
    return false if container.blank? || candidate.blank?

    candidate.all? { |point| point_inside_or_on_polygon?(point, container) }
  end

  def point_inside_or_on_polygon?(point, polygon)
    x, y = point

    polygon.each_with_index do |(x1, y1), idx|
      x2, y2 = polygon[(idx + 1) % polygon.length]
      return true if point_on_segment?(x, y, x1, y1, x2, y2)
    end

    inside = false
    j = polygon.length - 1

    polygon.each_with_index do |(xi, yi), i|
      xj, yj = polygon[j]
      intersects = ((yi > y) != (yj > y)) && (x < ((xj - xi) * (y - yi) / ((yj - yi).nonzero? || 1e-12)) + xi)
      inside = !inside if intersects
      j = i
    end

    inside
  end

  def point_on_segment?(px, py, x1, y1, x2, y2)
    epsilon = 1e-9
    cross = (px - x1) * (y2 - y1) - (py - y1) * (x2 - x1)
    return false unless cross.abs <= epsilon

    min_x, max_x = [x1, x2].minmax
    min_y, max_y = [y1, y2].minmax

    px >= (min_x - epsilon) && px <= (max_x + epsilon) && py >= (min_y - epsilon) && py <= (max_y + epsilon)
  end

  def polygon_covered_by_union?(candidate_polygon, container_polygons)
    return false if candidate_polygon.blank? || container_polygons.blank?

    samples = sample_points_for_polygon(candidate_polygon)
    return false if samples.empty?

    covered = samples.count do |point|
      container_polygons.any? { |poly| point_inside_or_on_polygon?(point, poly) }
    end

    (covered.to_f / samples.length) >= OCCLUSION_COVERAGE_THRESHOLD
  rescue StandardError
    false
  end

  def sample_points_for_polygon(polygon)
    return [] if polygon.blank?

    xs = polygon.map { |(x, _)| x }
    ys = polygon.map { |(_, y)| y }
    min_x, max_x = xs.minmax
    min_y, max_y = ys.minmax
    return polygon if min_x == max_x || min_y == max_y

    step_x = (max_x - min_x) / OCCLUSION_SAMPLE_GRID_X.to_f
    step_y = (max_y - min_y) / OCCLUSION_SAMPLE_GRID_Y.to_f

    points = []
    OCCLUSION_SAMPLE_GRID_X.times do |gx|
      OCCLUSION_SAMPLE_GRID_Y.times do |gy|
        px = min_x + ((gx + 0.5) * step_x)
        py = min_y + ((gy + 0.5) * step_y)
        points << [px, py] if point_inside_or_on_polygon?([px, py], polygon)
      end
    end

    points.empty? ? polygon : points
  rescue StandardError
    polygon
  end

  def fetch_hash_value(hash, symbol_key, string_key)
    return nil unless hash.is_a?(Hash)

    return hash[symbol_key] if hash.key?(symbol_key)
    return hash[string_key] if hash.key?(string_key)

    nil
  end

  def set_hash_value(hash, key, value)
    return unless hash.is_a?(Hash)

    if hash.key?(key)
      hash[key] = value
    elsif hash.key?(key.to_s)
      hash[key.to_s] = value
    else
      hash[key] = value
    end
  end

  def emit_progress(callback, payload)
    callback&.call(payload)
  rescue StandardError
    nil
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
