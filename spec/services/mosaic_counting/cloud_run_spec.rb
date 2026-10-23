require 'rails_helper'
require 'json'
require 'stringio'

RSpec.describe MosaicCounting::CloudRun do
  FakeGcsFile = Struct.new(:name, :content) do
    def download
      StringIO.new(content)
    end
  end

  class FakeGcsBucket
    attr_reader :objects

    def initialize
      @objects = {}
    end

    def create_file(source, name, **_options)
      @objects[name] = source.respond_to?(:read) ? source.read : File.binread(source)
    end

    def files(prefix:)
      matches = @objects.select { |name, _| name.start_with?(prefix) }.map { |name, content| FakeGcsFile.new(name, content) }
      Class.new do
        define_method(:all) do |&block|
          block ? matches.each(&block) : matches
        end
      end.new
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

  let(:bucket) { FakeGcsBucket.new }
  let(:storage) { instance_double('Google::Cloud::Storage::Project', bucket: bucket) }
  let(:window) { MosaicTilePlanner::Rect.new(0, 0, 1000, 800) }
  let(:items) do
    [
      MosaicCounting::Item.new(id: 'r1c1-d0-0', window: window),
      MosaicCounting::Item.new(id: 'r1c2-d0-1', window: window),
      MosaicCounting::Item.new(id: 'r2c1-d0-2', window: window)
    ]
  end
  let(:source_path) { Rails.root.join('tmp', "cloud_run_spec_#{SecureRandom.hex(4)}.jpg").to_s }

  before do
    File.binwrite(source_path, 'fake-jpeg')
    stub_const('ENV', ENV.to_hash.merge(
      'GCP_PROJECT_ID' => 'proj', 'GCS_MOSAIC_BUCKET' => 'bkt', 'CLOUD_RUN_COUNT_MAX_TASKS' => '2',
      'CLOUD_RUN_COUNT_JOB' => 'meu-job'
    ))
  end

  after { FileUtils.rm_f(source_path) }

  def backend_with(jobs_client)
    described_class.new(storage: storage, jobs_client: jobs_client, sleeper: ->(_seconds) {})
  end

  # Simula o worker: grava um resultado por janela no "bucket".
  def jobs_client_writing(results, operation: FakeOperation.new(true, false, nil))
    client = double('jobs_client')
    allow(client).to receive(:run_job) do |request|
      env = request[:overrides][:container_overrides].first[:env].to_h { |var| [var[:name], var[:value]] }
      results.each do |id, payload|
        bucket.objects["#{env['COUNT_RUN_PREFIX']}/#{env['COUNT_ROUND']}/results/#{id}.json"] = JSON.generate(payload)
      end
      operation
    end
    client
  end

  it 'envia o mosaico e o manifesto, dispara o job com as tasks limitadas e devolve os resultados' do
    results = {
      'r1c1-d0-0' => { id: 'r1c1-d0-0', status: 'ok', points: [[10.5, 20.0]], resized_width: 896, resized_height: 768 },
      'r1c2-d0-1' => { id: 'r1c2-d0-1', status: 'oom' },
      'r2c1-d0-2' => { id: 'r2c1-d0-2', status: 'ok', points: [], resized_width: 896, resized_height: 768 }
    }
    jobs_client = jobs_client_writing(results)
    backend = backend_with(jobs_client)

    backend.prepare(source_path: source_path)
    outcomes = {}
    backend.infer(items) { |item, outcome| outcomes[item.id] = outcome }

    expect(outcomes['r1c1-d0-0']).to be_ok
    expect(outcomes['r1c1-d0-0'].points).to eq([[10.5, 20.0]])
    expect(outcomes['r1c1-d0-0'].resized_width).to eq(896)
    expect(outcomes['r1c2-d0-1']).to be_oom
    expect(outcomes['r2c1-d0-2']).to be_ok

    expect(jobs_client).to have_received(:run_job).with(
      hash_including(name: 'projects/proj/locations/southamerica-east1/jobs/meu-job',
                     overrides: hash_including(task_count: 2))
    )

    manifest_name = bucket.objects.keys.find { |name| name.end_with?('round-0/manifest.json') }
    manifest = JSON.parse(bucket.objects[manifest_name])
    expect(manifest['items'].first).to eq('id' => 'r1c1-d0-0', 'x' => 0, 'y' => 0, 'width' => 1000, 'height' => 800)
    expect(manifest['mosaic']).to eq('mosaic.jpg')
    expect(bucket.objects.keys.any? { |name| name.end_with?('/mosaic.jpg') }).to be(true)
  end

  it 'conta janelas das fotos originais sem enviar o mosaico' do
    jobs_client = jobs_client_writing(
      { 'p0' => { id: 'p0', status: 'ok', points: [[1, 2]], resized_width: 128, resized_height: 128 } }
    )
    backend = backend_with(jobs_client)
    blob = instance_double(ActiveStorage::Blob, key: 'abc123')

    backend.prepare(source_path: nil)
    expect(backend.photo_source(blob)).to eq('mosaic-photos/abc123')
    item = MosaicCounting::Item.new(id: 'p0', window: window, image: backend.photo_source(blob))
    outcomes = []
    backend.infer([item]) { |_item, outcome| outcomes << outcome }

    manifest = JSON.parse(bucket.objects.find { |name, _| name.end_with?('round-0/manifest.json') }.last)
    expect(manifest['mosaic']).to be_nil
    expect(manifest['items'].first['image']).to eq('mosaic-photos/abc123')
    expect(bucket.objects.keys.grep(/mosaic\.jpg/)).to be_empty
    expect(outcomes.first.points).to eq([[1, 2]])
  end

  it 'usa uma rodada nova (outro prefixo) a cada chamada de infer' do
    jobs_client = jobs_client_writing(
      { 'a' => { id: 'a', status: 'ok', points: [], resized_width: 128, resized_height: 128 } }
    )
    backend = backend_with(jobs_client)
    backend.prepare(source_path: source_path)
    item = MosaicCounting::Item.new(id: 'a', window: window)

    2.times { backend.infer([item]) { |_item, _outcome| } }

    expect(bucket.objects.keys.grep(%r{round-0/manifest.json}).size).to eq(1)
    expect(bucket.objects.keys.grep(%r{round-1/manifest.json}).size).to eq(1)
  end

  it 'falha quando o job termina e faltam resultados' do
    jobs_client = jobs_client_writing({ 'r1c1-d0-0' => { id: 'r1c1-d0-0', status: 'ok', points: [], resized_width: 1, resized_height: 1 } })
    backend = backend_with(jobs_client)
    backend.prepare(source_path: source_path)

    expect { backend.infer(items) { |_item, _outcome| } }
      .to raise_error(MosaicCounting::BackendError, /sem processar 2 janela/)
  end

  it 'falha quando o worker reporta erro em uma janela' do
    jobs_client = jobs_client_writing({ 'r1c1-d0-0' => { id: 'r1c1-d0-0', status: 'error', error: 'kaboom' } })
    backend = backend_with(jobs_client)
    backend.prepare(source_path: source_path)

    expect { backend.infer(items) { |_item, _outcome| } }
      .to raise_error(MosaicCounting::BackendError, /kaboom/)
  end

  it 'converte falha ao iniciar o job em BackendError' do
    jobs_client = double('jobs_client')
    allow(jobs_client).to receive(:run_job).and_raise(StandardError, 'permission denied')
    backend = backend_with(jobs_client)
    backend.prepare(source_path: source_path)

    expect { backend.infer(items) { |_item, _outcome| } }
      .to raise_error(MosaicCounting::BackendError, /permission denied/)
  end
end

RSpec.describe MosaicCounting::Settings do
  it 'usa o backend local por padrao e cloud_run quando configurado' do
    stub_const('ENV', ENV.to_hash.except('MOSAIC_COUNT_BACKEND'))
    expect(described_class.cloud_run?).to be(false)

    stub_const('ENV', ENV.to_hash.merge('MOSAIC_COUNT_BACKEND' => ' Cloud_Run '))
    expect(described_class.cloud_run?).to be(true)
    expect(MosaicCounting.build(work_dir: '/tmp')).to be_a(MosaicCounting::CloudRun)
  end

  it 'exige projeto e bucket' do
    stub_const('ENV', ENV.to_hash.except('GCP_PROJECT_ID', 'GCS_MOSAIC_BUCKET'))

    expect { described_class.project_id }.to raise_error(MosaicCounting::BackendError, /GCP_PROJECT_ID/)
    expect { described_class.bucket }.to raise_error(MosaicCounting::BackendError, /GCS_MOSAIC_BUCKET/)
  end

  it 'decodifica a chave da conta de servico em Base64 e cai no ADC quando ausente' do
    key = { 'type' => 'service_account', 'private_key' => "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n" }

    stub_const('ENV', ENV.to_hash.merge('GCP_CREDENTIALS_BASE64' => Base64.strict_encode64(JSON.generate(key))))
    expect(described_class.credentials).to eq(key)

    stub_const('ENV', ENV.to_hash.except('GCP_CREDENTIALS_BASE64'))
    expect(described_class.credentials).to be_nil
  end

  it 'rejeita chave Base64 invalida com mensagem clara' do
    stub_const('ENV', ENV.to_hash.merge('GCP_CREDENTIALS_BASE64' => 'isso-nao-e-base64!'))
    expect { described_class.credentials }.to raise_error(MosaicCounting::BackendError, /GCP_CREDENTIALS_BASE64/)

    stub_const('ENV', ENV.to_hash.merge('GCP_CREDENTIALS_BASE64' => Base64.strict_encode64('nao e json')))
    expect { described_class.credentials }.to raise_error(MosaicCounting::BackendError, /GCP_CREDENTIALS_BASE64/)
  end

  it 'aplica padroes validos para valores invalidos' do
    stub_const('ENV', ENV.to_hash.merge('CLOUD_RUN_COUNT_MAX_TASKS' => '0', 'GCP_REGION' => ' '))

    expect(described_class.max_tasks).to eq(10)
    expect(described_class.region).to eq('southamerica-east1')
  end
end
