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
      @objects[name] = File.binread(source)
    end

    def files(prefix:)
      matches = @objects.keys.grep(/\A#{Regexp.escape(prefix)}/).map { |name| FakeBlob.new(@objects, name) }
      FakeFileCollection.new(matches)
    end

    def file(name)
      FakeBlob.new(@objects, name)
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
  let(:input_dir) { Rails.root.join('tmp', "mosaic_render_cloud_input_#{SecureRandom.hex(4)}") }
  let(:output_dir) { Rails.root.join('tmp', "mosaic_render_cloud_output_#{SecureRandom.hex(4)}") }

  before do
    FileUtils.mkdir_p(input_dir)
    FileUtils.mkdir_p(output_dir)
    File.binwrite(input_dir.join('frame_1.jpg'), 'jpeg-content')

    stub_const('ENV', ENV.to_hash.merge(
      'GCP_PROJECT_ID' => 'proj',
      'GCS_MOSAIC_BUCKET' => 'bucket',
      'CLOUD_RUN_RENDER_JOB' => 'mosaic-job'
    ))
  end

  after do
    FileUtils.rm_rf(input_dir)
    FileUtils.rm_rf(output_dir)
  end

  def build_backend(jobs_client)
    described_class.new(storage: storage, jobs_client: jobs_client, sleeper: ->(_seconds) {})
  end

  it 'uploads inputs, starts Cloud Run job and downloads mosaico.jpg' do
    jobs_client = double('jobs_client')
    allow(jobs_client).to receive(:run_job) do |request|
      env = request[:overrides][:container_overrides].first[:env].to_h { |var| [var[:name], var[:value]] }
      run_prefix = env.fetch('MOSAIC_RUN_PREFIX')
      bucket.objects["#{run_prefix}/status.json"] = JSON.generate(status: 'ok')
      bucket.objects["#{run_prefix}/output/mosaico.jpg"] = 'mosaic-jpeg'
      FakeOperation.new(true, false, nil)
    end

    backend = build_backend(jobs_client)
    output_path = backend.render!(input_dir: input_dir, output_dir: output_dir)

    expect(output_path).to eq(output_dir.join('mosaico.jpg').to_s)
    expect(File.binread(output_path)).to eq('mosaic-jpeg')
    expect(jobs_client).to have_received(:run_job).with(
      hash_including(
        name: 'projects/proj/locations/southamerica-east1/jobs/mosaic-job',
        overrides: hash_including(task_count: 1)
      )
    )
  end

  it 'raises BackendError when worker returns an error status' do
    jobs_client = double('jobs_client')
    allow(jobs_client).to receive(:run_job) do |request|
      env = request[:overrides][:container_overrides].first[:env].to_h { |var| [var[:name], var[:value]] }
      run_prefix = env.fetch('MOSAIC_RUN_PREFIX')
      bucket.objects["#{run_prefix}/status.json"] = JSON.generate(status: 'error', error: 'ExifTool missing')
      FakeOperation.new(true, false, nil)
    end

    backend = build_backend(jobs_client)

    expect do
      backend.render!(input_dir: input_dir, output_dir: output_dir)
    end.to raise_error(MosaicRendering::BackendError, /ExifTool missing/)
  end
end
