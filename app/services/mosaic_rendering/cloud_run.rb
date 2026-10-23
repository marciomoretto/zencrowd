require 'json'
require 'securerandom'

module MosaicRendering
  class CloudRun
    INPUT_PREFIX = 'input'.freeze
    OUTPUT_PREFIX = 'output'.freeze
    STATUS_OBJECT = 'status.json'.freeze
    OUTPUT_MOSAIC_NAME = 'mosaico.jpg'.freeze

    UPLOAD_THREADS = 8
    # Duracao tipica do render usada apenas para estimar a barra de progresso.
    EXPECTED_RENDER_SECONDS = 600

    def initialize(storage: nil, jobs_client: nil, sleeper: Kernel.method(:sleep))
      @storage = storage
      @jobs_client = jobs_client
      @sleeper = sleeper
    end

    # on_progress recebe (progress, message), com progress entre 0 e 100 relativo a esta etapa.
    def render!(input_dir:, output_dir:, on_progress: nil)
      @on_progress = on_progress
      ensure_input_dir!(input_dir)

      @run_id = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
      upload_inputs!(input_dir)

      report_progress(50, 'Iniciando a montagem no Cloud Run...')
      operation = start_job
      status_payload = wait_for_status(operation)
      ensure_successful_status!(status_payload)

      report_progress(95, 'Baixando o mosaico gerado...')
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
      paths = Dir.glob(File.join(input_dir, '*')).sort.select { |path| File.file?(path) }
      queue = Queue.new
      paths.each { |path| queue << path }

      total = paths.size
      uploaded = 0
      failure = nil
      mutex = Mutex.new
      report_progress(0, "Enviando #{total} imagem(ns) ao Cloud Run...")

      workers = Array.new([UPLOAD_THREADS, total].min) do
        Thread.new do
          loop do
            break if mutex.synchronize { failure }

            path = begin
              queue.pop(true)
            rescue ThreadError
              break
            end

            begin
              bucket.create_file(path, object_name("#{INPUT_PREFIX}/#{File.basename(path)}"))
              mutex.synchronize { uploaded += 1 }
            rescue StandardError => e
              mutex.synchronize { failure ||= e }
            end
          end
        end
      end

      until workers.none?(&:alive?)
        workers.each { |worker| worker.join(2) }
        report_progress(40 * uploaded / total, "Enviando imagens ao Cloud Run (#{uploaded}/#{total})...")
      end

      raise failure if failure
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
      started_at = monotonic_now
      deadline = started_at + Settings.timeout_seconds

      loop do
        operation.reload! unless operation.done?
        status_payload = read_status_payload
        return status_payload if status_payload

        raise_if_execution_finished_without_status(operation) if operation.done?
        raise BackendError, 'Tempo limite excedido aguardando a montagem do mosaico no Cloud Run.' if monotonic_now > deadline

        report_render_wait(monotonic_now - started_at)
        @sleeper.call(Settings.poll_seconds)
      end
    end

    # Barra assintotica de 50% a 94%: avanca com o tempo sem nunca "completar" antes do worker.
    def report_render_wait(elapsed_seconds)
      ratio = 1 - Math.exp(-elapsed_seconds / EXPECTED_RENDER_SECONDS.to_f)
      minutes = (elapsed_seconds / 60).floor
      report_progress(50 + (44 * ratio).round, "Montando mosaico no Cloud Run (#{minutes} min decorridos)...")
    end

    def report_progress(progress, message)
      @on_progress&.call(progress, message)
    rescue StandardError
      nil
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
