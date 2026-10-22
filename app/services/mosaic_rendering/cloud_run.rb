require 'json'
require 'securerandom'

module MosaicRendering
  class CloudRun
    INPUT_PREFIX = 'input'.freeze
    OUTPUT_PREFIX = 'output'.freeze
    STATUS_OBJECT = 'status.json'.freeze
    OUTPUT_MOSAIC_NAME = 'mosaico.jpg'.freeze

    def initialize(storage: nil, jobs_client: nil, sleeper: Kernel.method(:sleep))
      @storage = storage
      @jobs_client = jobs_client
      @sleeper = sleeper
    end

    def render!(input_dir:, output_dir:)
      ensure_input_dir!(input_dir)

      @run_id = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
      upload_inputs!(input_dir)

      operation = start_job
      status_payload = wait_for_status(operation)
      ensure_successful_status!(status_payload)

      download_output!(output_dir)
    ensure
      cleanup
    end

    def cleanup
      return unless @run_id

      bucket.files(prefix: "#{run_root}/").all.each(&:delete)
    rescue StandardError => e
      Rails.logger.warn("Nao foi possivel limpar arquivos do GCS (#{run_root}): #{e.class} - #{e.message}")
    end

    private

    def ensure_input_dir!(input_dir)
      unless Dir.exist?(input_dir)
        raise BackendError, "Diretorio de entrada do mosaico nao encontrado: #{input_dir}"
      end

      has_images = Dir.glob(File.join(input_dir, '*')).any? { |path| File.file?(path) }
      return if has_images

      raise BackendError, 'Nao ha imagens para enviar ao worker de mosaico no Cloud Run.'
    end

    def upload_inputs!(input_dir)
      Dir.glob(File.join(input_dir, '*')).sort.each do |path|
        next unless File.file?(path)

        bucket.create_file(path, object_name("#{INPUT_PREFIX}/#{File.basename(path)}"))
      end
    end

    def start_job
      jobs_client.run_job(
        name: job_path,
        overrides: {
          task_count: 1,
          container_overrides: [
            {
              env: [
                { name: 'MOSAIC_BUCKET', value: Settings.bucket },
                { name: 'MOSAIC_RUN_PREFIX', value: run_root }
              ]
            }
          ]
        }
      )
    rescue StandardError => e
      raise BackendError, "Nao foi possivel iniciar a montagem do mosaico no Cloud Run: #{e.message.to_s.lines.first.to_s.strip}"
    end

    def wait_for_status(operation)
      deadline = monotonic_now + Settings.timeout_seconds

      loop do
        operation.reload! unless operation.done?
        status_payload = read_status_payload
        return status_payload if status_payload

        raise_if_execution_finished_without_status(operation) if operation.done?
        raise BackendError, 'Tempo limite excedido aguardando a montagem do mosaico no Cloud Run.' if monotonic_now > deadline

        @sleeper.call(Settings.poll_seconds)
      end
    end

    def read_status_payload
      status_blob = bucket.file(object_name(STATUS_OBJECT))
      return nil unless status_blob&.exists?

      JSON.parse(status_blob.download.read)
    end

    def ensure_successful_status!(payload)
      return if payload['status'] == 'ok'

      error = payload['error'].to_s.strip
      error = 'erro desconhecido' if error.empty?
      raise BackendError, error
    end

    def download_output!(output_dir)
      output_path = output_dir.join(OUTPUT_MOSAIC_NAME)
      blob = bucket.file(object_name("#{OUTPUT_PREFIX}/#{OUTPUT_MOSAIC_NAME}"))
      raise BackendError, 'Worker finalizou sem gravar o mosaico de saida.' unless blob&.exists?

      blob.download(output_path.to_s)
      raise BackendError, 'Worker finalizou sem gerar um mosaico valido.' unless File.file?(output_path) && File.size(output_path).positive?

      output_path.to_s
    end

    def raise_if_execution_finished_without_status(operation)
      detail = operation.error? ? operation.error.message : execution_summary(operation)
      raise BackendError, "A execucao no Cloud Run terminou sem publicar o status da montagem do mosaico. #{detail}".strip
    end

    def execution_summary(operation)
      execution = operation.response
      return '' unless execution.respond_to?(:succeeded_count)

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
      "mosaic-runs/#{@run_id}"
    end

    def object_name(name)
      "#{run_root}/#{name}"
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
