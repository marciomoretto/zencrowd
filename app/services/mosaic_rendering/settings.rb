require 'base64'
require 'json'

module MosaicRendering
  class Settings
    DEFAULT_REGION = 'southamerica-east1'.freeze
    DEFAULT_JOB = 'zencrowd-mosaic-render'.freeze
    DEFAULT_TIMEOUT_SECONDS = 40 * 60
    DEFAULT_POLL_SECONDS = 5

    class << self
      def backend
        ENV.fetch('MOSAIC_RENDER_BACKEND', 'local').to_s.strip.downcase.presence || 'local'
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
        ENV.fetch('CLOUD_RUN_RENDER_JOB', DEFAULT_JOB).to_s.strip.presence || DEFAULT_JOB
      end

      def timeout_seconds
        positive_integer('CLOUD_RUN_RENDER_TIMEOUT_SECONDS', DEFAULT_TIMEOUT_SECONDS)
      end

      def poll_seconds
        positive_integer('CLOUD_RUN_RENDER_POLL_SECONDS', DEFAULT_POLL_SECONDS)
      end

      def credentials
        encoded = ENV.fetch('GCP_CREDENTIALS_BASE64', '').to_s.strip
        return nil if encoded.empty?

        JSON.parse(Base64.strict_decode64(encoded))
      rescue ArgumentError, JSON::ParserError
        raise BackendError, 'GCP_CREDENTIALS_BASE64 invalida: esperado o JSON da chave da conta de servico em Base64.'
      end

      private

      def required(name)
        ENV.fetch(name, '').to_s.strip.presence ||
          raise(BackendError, "Variavel de ambiente #{name} nao configurada para a montagem do mosaico no Cloud Run.")
      end

      def positive_integer(name, default)
        value = ENV.fetch(name, default).to_i
        value.positive? ? value : default
      end
    end
  end
end
