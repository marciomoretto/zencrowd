# Roda o motor de mosaico no Cloud Run em modo "prepare" com as fotos que ja chegaram na pasta: so preenche o cache
# de SIFT e de registro de pares, que o render final reaproveita.
#
# Debounce: uma rajada de uploads agenda uma unica rodada (DEBOUNCE depois da primeira foto). A marca de "agendado"
# e apagada quando a rodada comeca, entao fotos que chegam durante ela agendam a proxima.
class PrepareMosaicCacheJob < ApplicationJob
  queue_as :processing

  DEBOUNCE = 30.seconds
  BUSY_RETRY = 2.minutes
  MIN_PHOTOS = 2

  class << self
    def schedule(evento_id:, pasta_param:, wait: DEBOUNCE)
      return false unless MosaicRendering::Settings.cloud_run?

      key = scheduled_key(evento_id, pasta_param)
      return false unless Rails.cache.write(key, true, unless_exist: true, expires_in: 30.minutes)

      set(wait: wait).perform_later(evento_id, pasta_param.to_s)
      true
    end

    def scheduled_key(evento_id, pasta_param)
      "zencrowd:mosaic_prepare:scheduled:evento:#{evento_id}:pasta:#{safe_fragment(pasta_param)}"
    end

    def lock_key(evento_id, pasta_param)
      "zencrowd:lock:mosaic_prepare:evento:#{evento_id}:pasta:#{safe_fragment(pasta_param)}"
    end

    def safe_fragment(value)
      text = value.to_s.strip
      text = 'sem_pasta' if text.empty?
      text.gsub(/[^a-zA-Z0-9._-]/, '_')
    end
  end

  def perform(evento_id, pasta_param)
    Rails.cache.delete(self.class.scheduled_key(evento_id, pasta_param))

    evento = Evento.find_by(id: evento_id)
    return unless evento

    pasta_nome = pasta_param.to_s.strip.presence || 'Sem pasta'
    # O render ja calcula (e grava no cache) tudo que o preparo faria.
    return if ProcessingSessionTracker.find_active(flow: 'mosaic_render', resource: evento, scope_key: pasta_nome)

    acquired = ProcessingLock.with_lock(self.class.lock_key(evento_id, pasta_param), ttl_seconds: 45.minutes.to_i) do
      prepare(evento, pasta_param, pasta_nome)
    end

    self.class.schedule(evento_id: evento_id, pasta_param: pasta_param, wait: BUSY_RETRY) unless acquired
  end

  private

  def prepare(evento, pasta_param, pasta_nome)
    photos = MosaicRendering::PhotoSelection.for(evento: evento, pasta_param: pasta_param).blobs
    return if photos.size < MIN_PHOTOS

    MosaicRendering::CloudRun.new.prepare!(
      photos: photos,
      cache_prefix: MosaicRendering::CloudRun.cache_prefix(evento_id: evento.id, pasta_nome: pasta_nome)
    )
  rescue MosaicRendering::BackendError => e
    # O preparo e so uma otimizacao: se falhar, o render calcula tudo normalmente.
    Rails.logger.warn("Preparo do mosaico falhou (evento ##{evento.id}, pasta #{pasta_nome}): #{e.message}")
  end
end
