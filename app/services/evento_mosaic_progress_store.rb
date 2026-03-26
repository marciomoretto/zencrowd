class EventoMosaicProgressStore
  EXPIRATION = 2.hours

  class << self
    def write(evento_id:, progress_key:, payload:)
      key = cache_key(evento_id: evento_id, progress_key: progress_key)

      if null_store?
        fallback_store[key] = payload
      else
        Rails.cache.write(key, payload, expires_in: EXPIRATION)
      end
    end

    def read(evento_id:, progress_key:)
      key = cache_key(evento_id: evento_id, progress_key: progress_key)

      if null_store?
        fallback_store[key]
      else
        Rails.cache.read(key)
      end
    end

    private

    def cache_key(evento_id:, progress_key:)
      "eventos:#{evento_id}:mosaic:#{progress_key}"
    end

    def null_store?
      Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    end

    def fallback_store
      @fallback_store ||= {}
    end
  end
end
