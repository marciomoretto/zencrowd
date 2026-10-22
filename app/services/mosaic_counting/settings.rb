module MosaicCounting
  class Settings
    DEFAULT_REGION = 'southamerica-east1'.freeze
    DEFAULT_JOB = 'zencrowd-p2pnet-count'.freeze
    DEFAULT_MAX_TASKS = 10
    DEFAULT_TIMEOUT_SECONDS = 40 * 60
    DEFAULT_POLL_SECONDS = 3

    class << self
      def backend
        ENV.fetch('MOSAIC_COUNT_BACKEND', 'local').to_s.strip.downcase.presence || 'local'
      end

      def cloud_run?
        backend == 'cloud_run'
      end

      def project_id
        required('GCP_PROJECT_ID')
      end

      def bucket
        required('GCS_MOSAIC_BUCKET')
      end

      def region
        ENV.fetch('GCP_REGION', DEFAULT_REGION).to_s.strip.presence || DEFAULT_REGION
      end

      def job_name
        ENV.fetch('CLOUD_RUN_COUNT_JOB', DEFAULT_JOB).to_s.strip.presence || DEFAULT_JOB
      end

      def device
        ENV.fetch('CLOUD_RUN_COUNT_DEVICE', 'cpu').to_s.strip.presence || 'cpu'
      end

      # Quantas tasks (instancias) no maximo; limitado tambem pelo paralelismo configurado no Job.
      def max_tasks
        positive_integer('CLOUD_RUN_COUNT_MAX_TASKS', DEFAULT_MAX_TASKS)
      end

      def timeout_seconds
        positive_integer('CLOUD_RUN_COUNT_TIMEOUT_SECONDS', DEFAULT_TIMEOUT_SECONDS)
      end

      def poll_seconds
        positive_integer('CLOUD_RUN_COUNT_POLL_SECONDS', DEFAULT_POLL_SECONDS)
      end

      private

      def required(name)
        ENV.fetch(name, '').to_s.strip.presence ||
          raise(BackendError, "Variavel de ambiente #{name} nao configurada para a contagem no Cloud Run.")
      end

      def positive_integer(name, default)
        value = ENV.fetch(name, default).to_i
        value.positive? ? value : default
      end
    end
  end
end
