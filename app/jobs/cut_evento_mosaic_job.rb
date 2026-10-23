class CutEventoMosaicJob < ApplicationJob
  queue_as :mosaic

  def perform(evento_id, pasta_nome, source_path, progress_key)
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

  def process_cut(evento:, pasta_nome:, source_path:, progress_key:)

    cutter = MosaicTempGridCutter.new(
      source_path: source_path,
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

    points_preview_url = generate_points_preview(
      evento_id: evento.id,
      pasta_nome: pasta_nome,
      source_path: source_path,
      points: result.points
    )

    ActiveRecord::Base.transaction do
      record = evento.pasta_head_estimates.find_or_initialize_by(pasta_nome: pasta_nome)
      record.estimated_heads = result.total_heads.to_i
      record.save!

      evento.mosaic_piece_head_counts.where(pasta_nome: pasta_nome).delete_all

      piece_rows = Array(result.piece_counts)
      if piece_rows.any?
        now = Time.current
        evento.mosaic_piece_head_counts.insert_all!(
          piece_rows.map do |piece|
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
      grid_rows: result.rows,
      grid_cols: result.cols,
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

  POINT_MARKER_RADIUS_PX = 5
  POINT_MARKER_INK = [30, 144, 255].freeze

  # Desenha no mosaico em resolucao maxima os pontos ja contados pelos recortes (sem nova inferencia).
  def generate_points_preview(evento_id:, pasta_nome:, source_path:, points:)
    return nil unless source_path.present? && File.exist?(source_path)

    require 'vips'

    output_dir = MosaicStorage.ensure_event_dir(evento_id: evento_id, pasta_nome: pasta_nome)
    output_path = output_dir.join("points_#{Time.current.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(4)}.jpg")

    annotated = Vips::Image.new_from_file(source_path).mutate do |canvas|
      Array(points).each do |point_x, point_y|
        canvas.draw_circle!(POINT_MARKER_INK, point_x.round, point_y.round, POINT_MARKER_RADIUS_PX, fill: true)
      end
    end
    annotated.write_to_file(output_path.to_s, Q: 90)

    MosaicStorage.url_for_absolute_path(output_path)
  rescue StandardError => e
    Rails.logger.warn("Falha ao gerar preview com pontos do mosaico para evento ##{evento_id}: #{e.class} - #{e.message}")
    nil
  end

  def safe_file_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end
end
