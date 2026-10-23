require 'rails_helper'
require 'json'
require 'securerandom'
require 'stringio'

RSpec.describe MosaicRendering::CloudRun do
  FakeFileCollection = Struct.new(:files) do
    def all
      block_given? ? files.each { |file| yield file } : files
    end
  end

  class FakeBlob
    attr_reader :name

    def initialize(objects, name)
      @objects = objects
      @name = name
    end

    def exists?
      @objects.key?(name)
    end

    def download(destination = nil)
      content = @objects[name]
      return StringIO.new(content.to_s) unless destination

      File.binwrite(destination, content.to_s)
    end

    def delete
      @objects.delete(name)
    end
  end

  class FakeBucket
    attr_reader :objects

    def initialize
      @objects = {}
    end

    def create_file(source, name, **_options)
      @objects[name] = source.respond_to?(:read) ? source.read : File.binread(source)
    end

    def files(prefix:)
      matches = @objects.keys.grep(/\A#{Regexp.escape(prefix)}/).map { |name| FakeBlob.new(@objects, name) }
      FakeFileCollection.new(matches)
    end

    # Como o google-cloud-storage: nil quando o objeto nao existe.
    def file(name)
      @objects.key?(name) ? FakeBlob.new(@objects, name) : nil
    end
  end

  FakeOperation = Struct.new(:finished, :failed, :response) do
    def done?
      finished
    end

    def reload!; end

    def error?
      failed
    end

    def error
      Struct.new(:message).new('boom')
    end
  end

  let(:bucket) { FakeBucket.new }
  let(:storage) { instance_double('Google::Cloud::Storage::Project', bucket: bucket) }
  let(:output_dir) { Rails.root.join('tmp', "mosaic_render_cloud_output_#{SecureRandom.hex(4)}") }
  let(:cache_prefix) { 'mosaic-cache/evento_7/Voo_1' }
  let(:photos) do
    Array.new(3) do |index|
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new("jpeg-#{index}"), filename: "DJI_#{index}.JPG", content_type: 'image/jpeg')
    end
  end

  before do
    FileUtils.mkdir_p(output_dir)

    stub_const('ENV', ENV.to_hash.merge(
      'GCP_PROJECT_ID' => 'proj',
      'GCS_MOSAIC_BUCKET' => 'bucket',
      'CLOUD_RUN_RENDER_JOB' => 'mosaic-job'
    ))
  end

  after do
    FileUtils.rm_rf(output_dir)
  end

  def build_backend(jobs_client)
    described_class.new(storage: storage, jobs_client: jobs_client, sleeper: ->(_seconds) {})
  end

  # Simula o worker: guarda o manifest lido e publica status (e o mosaico, no modo render).
  def fake_jobs_client(status: { status: 'ok' }, manifests: [])
    jobs_client = double('jobs_client')
    allow(jobs_client).to receive(:run_job) do |request|
      env = request[:overrides][:container_overrides].first[:env].to_h { |var| [var[:name], var[:value]] }
      run_prefix = env.fetch('MOSAIC_RUN_PREFIX')
      manifest = JSON.parse(bucket.objects.fetch("#{run_prefix}/manifest.json"))
      manifests << manifest
      bucket.objects["#{run_prefix}/status.json"] = JSON.generate(status)
      bucket.objects["#{run_prefix}/output/mosaico.jpg"] = 'mosaic-jpeg' if manifest['mode'] == 'render'
      FakeOperation.new(true, false, nil)
    end
    jobs_client
  end

  it 'sends only missing photos, writes the manifest and downloads mosaico.jpg' do
    bucket.objects["mosaic-photos/#{photos.first.key}"] = 'already-there'
    manifests = []
    jobs_client = fake_jobs_client(manifests: manifests)

    output_path = build_backend(jobs_client).render!(photos: photos, output_dir: output_dir, cache_prefix: cache_prefix)

    expect(File.binread(output_path)).to eq('mosaic-jpeg')
    expect(bucket.objects["mosaic-photos/#{photos.first.key}"]).to eq('already-there')
    expect(bucket.objects["mosaic-photos/#{photos.last.key}"]).to eq('jpeg-2')
    expect(manifests.first).to include('mode' => 'render', 'cache_prefix' => cache_prefix)
    expect(manifests.first['photos']).to eq(
      photos.map { |blob| { 'object' => "mosaic-photos/#{blob.key}", 'key' => blob.key, 'name' => blob.filename.to_s } }
    )
    expect(jobs_client).to have_received(:run_job).with(
      hash_including(
        name: 'projects/proj/locations/southamerica-east1/jobs/mosaic-job',
        overrides: hash_including(task_count: 1)
      )
    )
  end

  it 'removes only the run prefix from the bucket, keeping photos and cache' do
    bucket.objects["#{cache_prefix}/sift/abc__v1.npz"] = 'sift'
    backend = build_backend(fake_jobs_client)
    backend.render!(photos: photos, output_dir: output_dir, cache_prefix: cache_prefix)

    expect(bucket.objects.keys).to contain_exactly(
      "#{cache_prefix}/sift/abc__v1.npz",
      *photos.map { |blob| "mosaic-photos/#{blob.key}" }
    )
  end

  it 'reports progress in order while checking photos and waiting' do
    updates = []
    backend = build_backend(fake_jobs_client)
    backend.render!(photos: photos, output_dir: output_dir, cache_prefix: cache_prefix,
                    on_progress: ->(progress, message) { updates << [progress, message] })

    expect(updates.map(&:first)).to eq(updates.map(&:first).sort)
    expect(updates.first.last).to match(/Conferindo 3 imagem/)
    expect(updates.last.last).to match(/Baixando o mosaico/)
  end

  it 'runs the job in prepare mode without downloading a mosaic' do
    manifests = []
    build_backend(fake_jobs_client(manifests: manifests)).prepare!(photos: photos, cache_prefix: cache_prefix)

    expect(manifests.first['mode']).to eq('prepare')
    expect(bucket.objects.keys.grep(/mosaic-runs/)).to be_empty
  end

  it 'raises BackendError when worker returns an error status' do
    backend = build_backend(fake_jobs_client(status: { status: 'error', error: 'ExifTool missing' }))

    expect do
      backend.render!(photos: photos, output_dir: output_dir, cache_prefix: cache_prefix)
    end.to raise_error(MosaicRendering::BackendError, /ExifTool missing/)
  end

  it 'raises BackendError when there are no photos' do
    expect do
      build_backend(double('jobs_client')).render!(photos: [], output_dir: output_dir, cache_prefix: cache_prefix)
    end.to raise_error(MosaicRendering::BackendError, /Nao ha imagens/)
  end

  it 'builds a filesystem-safe cache prefix per evento and pasta' do
    expect(described_class.cache_prefix(evento_id: 25, pasta_nome: '18h 30/b')).to eq('mosaic-cache/evento_25/18h_30_b')
    expect(described_class.cache_prefix(evento_id: 25, pasta_nome: '')).to eq('mosaic-cache/evento_25/sem_pasta')
  end
end
