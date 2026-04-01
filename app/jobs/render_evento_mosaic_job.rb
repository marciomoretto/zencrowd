class RenderEventoMosaicJob < ApplicationJob
  queue_as :mosaic

  include Rails.application.routes.url_helpers

  def perform(evento_id, pasta_param, progress_key)
    evento = Evento.find_by(id: evento_id)
    unless evento
      write_failed(evento_id: evento_id, progress_key: progress_key, error: 'Evento nao encontrado para gerar mosaico.')
      return
    end

    pasta_nome = pasta_param.to_s.strip.presence || 'Sem pasta'
    lock_key = "zencrowd:lock:mosaic_render:evento:#{evento.id}:pasta:#{safe_fragment(pasta_nome)}"

    lock_acquired = ProcessingLock.with_lock(lock_key, ttl_seconds: 30.minutes.to_i) do
      process_render(evento: evento, pasta_param: pasta_param, progress_key: progress_key)
    end

    return if lock_acquired

    write_failed(
      evento_id: evento.id,
      progress_key: progress_key,
      error: 'Ja existe um render de mosaico em andamento para esta pasta.'
    )
  rescue StandardError => e
    Rails.logger.error("Erro ao gerar mosaico para evento ##{evento_id}: #{e.class} - #{e.message}")
    write_failed(evento_id: evento_id, progress_key: progress_key, error: e.message)
  end

  private

  def process_render(evento:, pasta_param:, progress_key:)

    generator = EventoMosaicGenerator.new(evento: evento, pasta_param: pasta_param)

    progress_callback = lambda do |payload|
      status_payload = progress_payload(payload)
      EventoMosaicProgressStore.write(
        evento_id: evento.id,
        progress_key: progress_key,
        payload: status_payload.merge(status: 'running')
      )

      ProcessingSessionTracker.running!(
        progress_key: progress_key,
        payload: status_payload.merge(status: 'running')
      )
    end

    result = generator.call(progress_callback: progress_callback)
    optimization = result[:optimization].is_a?(Hash) ? result[:optimization] : {}

    if optimization[:enabled]
      Rails.cache.write(
        mosaic_optimization_cache_key(evento.id, result[:pasta_nome]),
        optimization.merge(updated_at: Time.current.to_i),
        expires_in: 12.hours
      )
    end

    if optimization[:enabled]
      Rails.logger.info(
        "Render mosaico evento ##{evento.id}: total_pasta=#{optimization[:source_total_count]}, " \
        "zenitais=#{optimization[:source_zenital_count]}, preselecionadas=#{optimization[:preselected_count]}, " \
        "modo_preselecao=#{optimization[:preselection_mode]}, consideradas=#{optimization[:input_count]}, " \
        "descartadas_por_oclusao=#{optimization[:discarded_count]}, renderizadas=#{optimization[:output_count]}"
      )
    end

    redirect_url = pasta_uploader_evento_path(evento, pasta: result[:pasta_param], mosaic_preview: result[:preview_url])

    completed_payload = {
      status: 'completed',
      progress: 100,
      stage: 'completed',
      message: 'Mosaico gerado com sucesso.',
      redirect_url: redirect_url,
      preview_url: result[:preview_url]
    }

    EventoMosaicProgressStore.write(
      evento_id: evento.id,
      progress_key: progress_key,
      payload: completed_payload
    )

    ProcessingSessionTracker.complete!(progress_key: progress_key, payload: completed_payload)
  end

  def progress_payload(payload)
    progress = estimate_progress(payload)
    {
      progress: progress,
      stage: payload[:stage].to_s,
      message: payload[:message].presence || 'Gerando mosaico...'
    }
  end

  def estimate_progress(payload)
    stage = payload[:stage].to_s
    status = payload[:status].to_s

    if payload[:progress]
      return [[payload[:progress].to_i, 0].max, 99].min
    end

    case [stage, status]
    when ['preview', 'started']
      8
    when ['preview', 'completed']
      30
    when ['render', 'started']
      40
    when ['render', 'completed']
      95
    else
      # Attempt to derive progress from collection/image counters if available.
      current = payload[:image_index] || payload[:collection_index]
      total = payload[:total_images] || payload[:total_collections]

      if current && total.to_i.positive?
        ratio = current.to_f / total.to_f
        return (40 + (ratio * 50)).round.clamp(40, 95)
      end

      50
    end
  end

  def write_failed(evento_id:, progress_key:, error:)
    failed_payload = {
      status: 'failed',
      progress: 0,
      stage: 'failed',
      error: error,
      message: error
    }

    EventoMosaicProgressStore.write(
      evento_id: evento_id,
      progress_key: progress_key,
      payload: failed_payload
    )

    ProcessingSessionTracker.fail!(progress_key: progress_key, payload: failed_payload)
  end

  def mosaic_optimization_cache_key(evento_id, pasta_nome)
    text = pasta_nome.to_s.strip
    text = 'sem_pasta' if text.empty?
    fragment = text.gsub(/[^a-zA-Z0-9._-]/, '_')
    "uploader:evento:#{evento_id}:pasta:#{fragment}:mosaic_optimization"
  end

  def safe_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end
end
