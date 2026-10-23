require 'json'
require 'securerandom'

module MosaicCounting
  # Paraleliza a inferencia em um Cloud Run Job: o mosaico vai para o GCS, cada task processa uma fatia das
  # janelas (cloud_run/count_worker) e grava um JSON por janela, que este backend le por polling.
  class CloudRun
    def initialize(storage: nil, jobs_client: nil, sleeper: Kernel.method(:sleep))
      @storage = storage
      @jobs_client = jobs_client
      @sleeper = sleeper
      @round = 0
    end

    def prepare(source_path:)
      @run_id = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
      @mosaic_name = nil
      return if source_path.nil?

      @mosaic_name = "mosaic#{File.extname(source_path).downcase.presence || '.jpg'}"
      bucket.create_file(source_path, object_name(@mosaic_name))
    end

    # As fotos ja costumam estar no bucket desde o upload (MosaicRendering::PhotoStore); reenvia as que faltarem.
    def prepare_photos(blobs)
      MosaicRendering::PhotoStore.new(bucket: bucket).ensure_uploaded!(blobs)
    end

    def photo_source(blob)
      MosaicRendering::PhotoStore.object_name(blob)
    end

    def infer(items, &on_result)
      return if items.empty?

      round_name = "round-#{@round}"
      @round += 1

      write_manifest(round_name, items)
      operation = start_job(round_name, items.size)
      collect_results(round_name, items, operation, &on_result)
    end

    def cleanup
      return unless @run_id

      bucket.files(prefix: "#{run_root}/").all.each(&:delete)
    rescue StandardError => e
      Rails.logger.warn("Nao foi possivel limpar arquivos do GCS (#{run_root}): #{e.class} - #{e.message}")
    end

    private

    def write_manifest(round_name, items)
      manifest = {
        threshold: P2pnetInferenceSettings.threshold,
        device: Settings.device,
        mosaic: @mosaic_name,
        items: items.map do |item|
          window = item.window
          { id: item.id, x: window.x, y: window.y, width: window.width, height: window.height, image: item.image }.compact
        end
      }

      bucket.create_file(
        StringIO.new(JSON.generate(manifest)),
        object_name("#{round_name}/manifest.json"),
        content_type: 'application/json'
      )
    end

    def start_job(round_name, item_count)
      jobs_client.run_job(
        name: job_path,
        overrides: {
          task_count: [item_count, Settings.max_tasks].min,
          container_overrides: [
            {
              env: [
                { name: 'COUNT_BUCKET', value: Settings.bucket },
                { name: 'COUNT_RUN_PREFIX', value: run_root },
                { name: 'COUNT_ROUND', value: round_name }
              ]
            }
          ]
        }
      )
    rescue StandardError => e
      raise BackendError, "Nao foi possivel iniciar a contagem no Cloud Run: #{e.message.to_s.lines.first.to_s.strip}"
    end

    def collect_results(round_name, items, operation, &on_result)
      pending = items.index_by(&:id)
      deadline = monotonic_now + Settings.timeout_seconds

      loop do
        operation.reload! unless operation.done?
        finished = operation.done?

        fetch_new_results(round_name, pending, &on_result)
        return if pending.empty?

        raise_if_job_failed(operation, pending) if finished
        raise BackendError, 'Tempo limite excedido aguardando a contagem no Cloud Run.' if monotonic_now > deadline

        @sleeper.call(Settings.poll_seconds)
      end
    end

    def fetch_new_results(round_name, pending)
      prefix = object_name("#{round_name}/results/")

      bucket.files(prefix: prefix).all do |file|
        item_id = File.basename(file.name, '.json')
        item = pending[item_id]
        next unless item

        outcome = parse_outcome(JSON.parse(file.download.read))
        pending.delete(item_id)
        yield item, outcome
      end
    end

    def parse_outcome(payload)
      case payload['status']
      when 'ok'
        Outcome.new(
          status: :ok,
          points: payload['points'],
          resized_width: payload['resized_width'],
          resized_height: payload['resized_height']
        )
      when 'oom'
        Outcome.new(status: :oom)
      else
        raise BackendError, "Falha na inferencia no Cloud Run: #{payload['error'].presence || 'erro desconhecido'}"
      end
    end

    def raise_if_job_failed(operation, pending)
      detail = operation.error? ? operation.error.message : execution_summary(operation)
      raise BackendError, "A execucao no Cloud Run terminou sem processar #{pending.size} janela(s). #{detail}".strip
    end

    def execution_summary(operation)
      execution = operation.response
      return '' unless execution.respond_to?(:failed_count)

      "Tasks com sucesso: #{execution.succeeded_count}, com falha: #{execution.failed_count}."
    end

    def bucket
      @bucket ||= storage.bucket(Settings.bucket, skip_lookup: true)
    end

    def storage
      @storage ||= begin
        require 'google/cloud/storage'
        Google::Cloud::Storage.new(project_id: Settings.project_id, credentials: Settings.credentials)
      end
    end

    def jobs_client
      @jobs_client ||= begin
        require 'google/cloud/run/v2'
        credentials = Settings.credentials
        Google::Cloud::Run::V2::Jobs::Client.new { |config| config.credentials = credentials if credentials }
      end
    end

    def job_path
      "projects/#{Settings.project_id}/locations/#{Settings.region}/jobs/#{Settings.job_name}"
    end

    def run_root
      "runs/#{@run_id}"
    end

    def object_name(name)
      "#{run_root}/#{name}"
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
