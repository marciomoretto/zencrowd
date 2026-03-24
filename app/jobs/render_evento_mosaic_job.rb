class RenderEventoMosaicJob < ApplicationJob
  queue_as :default

  include Rails.application.routes.url_helpers

  def perform(evento_id, pasta_param, progress_key)
    evento = Evento.find_by(id: evento_id)
    unless evento
      write_failed(evento_id: evento_id, progress_key: progress_key, error: 'Evento nao encontrado para gerar mosaico.')
      return
    end

    generator = EventoMosaicGenerator.new(evento: evento, pasta_param: pasta_param)

    progress_callback = lambda do |payload|
      status_payload = progress_payload(payload)
      EventoMosaicProgressStore.write(
        evento_id: evento.id,
        progress_key: progress_key,
        payload: status_payload.merge(status: 'running')
      )
    end

    result = generator.call(progress_callback: progress_callback)
    redirect_url = pasta_uploader_evento_path(evento, pasta: result[:pasta_param], mosaic_preview: result[:preview_url])

    EventoMosaicProgressStore.write(
      evento_id: evento.id,
      progress_key: progress_key,
      payload: {
        status: 'completed',
        progress: 100,
        stage: 'completed',
        message: 'Mosaico gerado com sucesso.',
        redirect_url: redirect_url,
        preview_url: result[:preview_url]
      }
    )
  rescue StandardError => e
    Rails.logger.error("Erro ao gerar mosaico para evento ##{evento_id}: #{e.class} - #{e.message}")
    write_failed(evento_id: evento_id, progress_key: progress_key, error: e.message)
  end

  private

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
    EventoMosaicProgressStore.write(
      evento_id: evento_id,
      progress_key: progress_key,
      payload: {
        status: 'failed',
        progress: 0,
        stage: 'failed',
        error: error,
        message: error
      }
    )
  end
end
