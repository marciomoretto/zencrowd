class CutEventoMosaicJob < ApplicationJob
  queue_as :mosaic
  MAX_P2PNET_PIXELS = 12_000_000

  def perform(evento_id, pasta_nome, source_path, rows, cols, progress_key)
    evento = Evento.find_by(id: evento_id)
    unless evento
      write_failed(evento_id: evento_id, progress_key: progress_key, error: 'Evento nao encontrado para corte do mosaico.')
      return
    end

    lock_key = "zencrowd:lock:mosaic_cut:evento:#{evento.id}:pasta:#{safe_file_fragment(pasta_nome)}"
    lock_acquired = ProcessingLock.with_lock(lock_key, ttl_seconds: 45.minutes.to_i) do
      process_cut(
        evento: evento,
        pasta_nome: pasta_nome,
        source_path: source_path,
        rows: rows,
        cols: cols,
        progress_key: progress_key
      )
    end

    return if lock_acquired

    write_failed(
      evento_id: evento.id,
      progress_key: progress_key,
      error: 'Ja existe um corte de mosaico em andamento para esta pasta.'
    )
  rescue StandardError => e
    Rails.logger.error("Erro no corte/contagem do mosaico para evento ##{evento_id}: #{e.class} - #{e.message}")
    write_failed(evento_id: evento_id, progress_key: progress_key, error: e.message)
  end

  private

  def process_cut(evento:, pasta_nome:, source_path:, rows:, cols:, progress_key:)

    cutter = MosaicTempGridCutter.new(
      source_path: source_path,
      rows: rows,
      cols: cols,
      evento_id: evento.id,
      pasta_nome: pasta_nome
    )

    progress_callback = lambda do |payload|
      progress_payload = {
        status: 'running',
        processed_count: payload[:processed_count].to_i,
        total_count: payload[:total_count].to_i,
        message: payload[:message].presence || 'Contando cabecas nos recortes...'
      }

      EventoMosaicCutProgressStore.write(
        evento_id: evento.id,
        progress_key: progress_key,
        payload: progress_payload
      )

      ProcessingSessionTracker.running!(progress_key: progress_key, payload: progress_payload)
    end

    result = cutter.call(progress_callback: progress_callback)
    unless result.success?
      write_failed(evento_id: evento.id, progress_key: progress_key, error: result.error)
      return
    end

    points_preview_url = generate_points_preview(evento_id: evento.id, pasta_nome: pasta_nome, source_path: source_path)

    ActiveRecord::Base.transaction do
      record = evento.pasta_head_estimates.find_or_initialize_by(pasta_nome: pasta_nome)
      record.estimated_heads = result.total_heads.to_i
      record.save!

      evento.mosaic_piece_head_counts.where(pasta_nome: pasta_nome).delete_all

      rows = Array(result.piece_counts)
      if rows.any?
        now = Time.current
        evento.mosaic_piece_head_counts.insert_all!(
          rows.map do |piece|
            {
              evento_id: evento.id,
              pasta_nome: pasta_nome,
              row_index: piece[:row_index].to_i,
              col_index: piece[:col_index].to_i,
              estimated_heads: piece[:estimated_heads].to_i,
              created_at: now,
              updated_at: now
            }
          end
        )
      end
    end

    completed_payload = {
      status: 'completed',
      processed_count: result.files_count.to_i,
      total_count: result.files_count.to_i,
      total_heads: result.total_heads.to_i,
      piece_counts: Array(result.piece_counts).map { |piece| piece.slice(:row_index, :col_index, :estimated_heads) },
      output_dir: result.output_dir,
      points_preview_url: points_preview_url,
      message: "Contagem concluida: #{result.total_heads} cabecas estimadas."
    }

    EventoMosaicCutProgressStore.write(
      evento_id: evento.id,
      progress_key: progress_key,
      payload: completed_payload
    )

    ProcessingSessionTracker.complete!(progress_key: progress_key, payload: completed_payload)
  end

  def write_failed(evento_id:, progress_key:, error:)
    failed_payload = {
      status: 'failed',
      processed_count: 0,
      total_count: 0,
      error: error,
      message: error
    }

    EventoMosaicCutProgressStore.write(
      evento_id: evento_id,
      progress_key: progress_key,
      payload: failed_payload
    )

    ProcessingSessionTracker.fail!(progress_key: progress_key, payload: failed_payload)
  end

  def generate_points_preview(evento_id:, pasta_nome:, source_path:)
    return nil unless source_path.present? && File.exist?(source_path)

    ensure_p2pnet_available!

    output_dir = Rails.root.join('public', 'mosaics', "evento_#{evento_id}", safe_file_fragment(pasta_nome))
    FileUtils.mkdir_p(output_dir)

    output_path = output_dir.join("points_#{Time.current.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(4)}.jpg")

    prepared_image = prepare_image_for_inference(source_path)

    CrowdCountingP2PNet.annotate(
      image_path: prepared_image[:path],
      output_path: output_path.to_s,
      threshold: 0.5,
      device: ENV.fetch('P2PNET_DEVICE', 'cpu')
    )

    public_root = Rails.root.join('public').to_s
    relative = output_path.to_s.sub(%r{\A#{Regexp.escape(public_root)}/?}, '')
    "/#{relative}"
  rescue StandardError => e
    Rails.logger.warn("Falha ao gerar preview com pontos do mosaico para evento ##{evento_id}: #{e.class} - #{e.message}")
    nil
  ensure
    cleanup_prepared_image(prepared_image)
  end

  def ensure_p2pnet_available!
    return if defined?(CrowdCountingP2PNet)

    require 'crowd_counting_p2pnet'
    return if defined?(CrowdCountingP2PNet)

    raise StandardError, 'Biblioteca de contagem indisponivel no servidor. Reinicie a aplicacao.'
  rescue LoadError
    raise StandardError, 'Biblioteca de contagem indisponivel no servidor. Rode bundle install e reinicie a aplicacao.'
  end

  def safe_file_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end

  def prepare_image_for_inference(source_path)
    image = Vips::Image.new_from_file(source_path, access: :sequential)
    total_pixels = image.width * image.height
    return { path: source_path, temporary: false } if total_pixels <= MAX_P2PNET_PIXELS

    scale_ratio = Math.sqrt(MAX_P2PNET_PIXELS.to_f / total_pixels)
    scaled_image = image.resize(scale_ratio)

    output_dir = Rails.root.join('tmp', 'p2pnet_tiles')
    FileUtils.mkdir_p(output_dir)
    prepared_path = output_dir.join("mosaic-points-prepared-#{SecureRandom.hex(6)}.jpg")
    scaled_image.write_to_file(prepared_path.to_s)

    {
      path: prepared_path.to_s,
      temporary: true
    }
  rescue StandardError => e
    Rails.logger.warn("Nao foi possivel redimensionar mosaico antes da inferencia de points: #{e.class} - #{e.message}")
    { path: source_path, temporary: false }
  end

  def cleanup_prepared_image(prepared_image)
    return unless prepared_image.is_a?(Hash)
    return unless prepared_image[:temporary]

    path = prepared_image[:path].to_s
    return if path.blank?
    return unless File.exist?(path)

    File.delete(path)
  rescue StandardError
    nil
  end
end
