module MosaicRendering
  # Copia das fotos no bucket do Cloud Run, uma por blob (mosaic-photos/<blob.key>), enviada logo apos o upload
  # para que o render nao precise reenviar tudo. Uma regra de ciclo de vida do bucket apaga copias antigas;
  # ensure_uploaded! reenvia o que faltar.
  class PhotoStore
    PREFIX = 'mosaic-photos'.freeze
    UPLOAD_THREADS = 8

    def self.object_name(blob)
      "#{PREFIX}/#{blob.key}"
    end

    # Entrada do manifest.json lido pelo worker (cloud_run/render_worker/worker.py).
    def self.manifest_entry(blob)
      { object: object_name(blob), key: blob.key, name: blob.filename.to_s }
    end

    def initialize(bucket: nil)
      @bucket = bucket
    end

    # Envia, em paralelo, os blobs que ainda nao estao no bucket. on_progress recebe (enviados_ou_conferidos, total).
    def ensure_uploaded!(blobs, on_progress: nil)
      blobs = Array(blobs)
      queue = Queue.new
      blobs.each { |blob| queue << blob }

      done = 0
      uploaded = 0
      failure = nil
      mutex = Mutex.new

      workers = Array.new([UPLOAD_THREADS, blobs.size].min) do
        Thread.new do
          loop do
            break if mutex.synchronize { failure }

            blob = begin
              queue.pop(true)
            rescue ThreadError
              break
            end

            begin
              sent = upload_unless_present(blob)
              mutex.synchronize do
                done += 1
                uploaded += 1 if sent
              end
            rescue StandardError => e
              mutex.synchronize { failure ||= e }
            end
          end
        end
      end

      until workers.none?(&:alive?)
        workers.each { |worker| worker.join(2) }
        report(on_progress, done, blobs.size)
      end

      raise failure if failure

      uploaded
    end

    private

    def upload_unless_present(blob)
      name = self.class.object_name(blob)
      return false if bucket.file(name)

      with_local_path(blob) { |path| bucket.create_file(path, name, content_type: blob.content_type) }
      true
    end

    # No servico Disk le direto do arquivo, sem carregar a foto na memoria.
    def with_local_path(blob, &block)
      service = blob.service
      if service.respond_to?(:path_for)
        path = service.path_for(blob.key)
        return yield(path) if File.file?(path)
      end

      blob.open { |file| block.call(file.path) }
    end

    def report(callback, done, total)
      callback&.call(done, total)
    rescue StandardError
      nil
    end

    def bucket
      @bucket ||= begin
        require 'google/cloud/storage'
        storage = Google::Cloud::Storage.new(project_id: Settings.project_id, credentials: Settings.credentials)
        storage.bucket(Settings.bucket, skip_lookup: true)
      end
    end
  end
end
