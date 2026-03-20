class ImagemCutProgressStore
  EXPIRATION = 2.hours

  class << self
    def write(imagem_id:, progress_key:, payload:)
      key = cache_key(imagem_id: imagem_id, progress_key: progress_key)

      if null_store?
        fallback_store[key] = payload
      else
        Rails.cache.write(key, payload, expires_in: EXPIRATION)
      end
    end

    def read(imagem_id:, progress_key:)
      key = cache_key(imagem_id: imagem_id, progress_key: progress_key)

      if null_store?
        fallback_store[key]
      else
        Rails.cache.read(key)
      end
    end

    def write_feedback(imagem_id:, feedback_key:, payload:)
      key = feedback_cache_key(imagem_id: imagem_id, feedback_key: feedback_key)

      if null_store?
        fallback_store[key] = payload
      else
        Rails.cache.write(key, payload, expires_in: EXPIRATION)
      end
    end

    def read_feedback(imagem_id:, feedback_key:)
      key = feedback_cache_key(imagem_id: imagem_id, feedback_key: feedback_key)

      if null_store?
        fallback_store[key]
      else
        Rails.cache.read(key)
      end
    end

    def delete_feedback(imagem_id:, feedback_key:)
      key = feedback_cache_key(imagem_id: imagem_id, feedback_key: feedback_key)

      if null_store?
        fallback_store.delete(key)
      else
        Rails.cache.delete(key)
      end
    end

    private

    def cache_key(imagem_id:, progress_key:)
      "imagens:#{imagem_id}:corte:#{progress_key}"
    end

    def feedback_cache_key(imagem_id:, feedback_key:)
      "imagens:#{imagem_id}:corte_feedback:#{feedback_key}"
    end

    def null_store?
      Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    end

    def fallback_store
      @fallback_store ||= {}
    end
  end
end
