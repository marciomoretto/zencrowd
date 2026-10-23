# Apaga em paralelo os arquivos temporarios de uma execucao no bucket (ex.: os ~1.500 JSONs de resultado de uma
# contagem). Cada requisicao ao GCS leva ~1,5 s a partir do servidor, entao apagar em serie, no fim da contagem,
# segurava o usuario por ~15 min. O bucket tambem tem regra de ciclo de vida (7 dias) como rede de seguranca.
class GcsPrefixCleanupJob < ApplicationJob
  queue_as :default

  DELETE_THREADS = 32

  def perform(prefix)
    prefix = prefix.to_s
    return if prefix.blank? || !prefix.end_with?('/')

    queue = Queue.new
    bucket.files(prefix: prefix).all { |file| queue << file }
    total = queue.size

    Array.new([DELETE_THREADS, total].min) do
      Thread.new do
        loop do
          file = begin
            queue.pop(true)
          rescue ThreadError
            break
          end

          begin
            file.delete
          rescue StandardError => e
            Rails.logger.warn("Nao foi possivel apagar #{file.name} do GCS: #{e.class} - #{e.message}")
          end
        end
      end
    end.each(&:join)

    Rails.logger.info("GCS: #{total} arquivo(s) apagado(s) em #{prefix}")
  end

  private

  def bucket
    @bucket ||= begin
      require 'google/cloud/storage'
      settings = MosaicCounting::Settings
      storage = Google::Cloud::Storage.new(project_id: settings.project_id, credentials: settings.credentials)
      storage.bucket(settings.bucket, skip_lookup: true)
    end
  end
end
