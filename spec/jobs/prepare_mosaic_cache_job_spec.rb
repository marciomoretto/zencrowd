require 'rails_helper'

RSpec.describe PrepareMosaicCacheJob do
  include ActiveJob::TestHelper

  let(:evento) { create(:evento) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(MosaicRendering::Settings).to receive(:cloud_run?).and_return(true)
  end

  describe '.schedule' do
    it 'agenda uma unica rodada por rajada de uploads' do
      expect do
        3.times { described_class.schedule(evento_id: evento.id, pasta_param: '18h') }
      end.to have_enqueued_job(described_class).with(evento.id, '18h').exactly(:once)
    end

    it 'nao agenda sem o backend do Cloud Run' do
      allow(MosaicRendering::Settings).to receive(:cloud_run?).and_return(false)

      expect(described_class.schedule(evento_id: evento.id, pasta_param: '18h')).to be(false)
    end
  end

  describe '#perform' do
    let(:renderer) { instance_double(MosaicRendering::CloudRun, prepare!: true) }

    before do
      allow(MosaicRendering::CloudRun).to receive(:new).and_return(renderer)
      allow(ProcessingSessionTracker).to receive(:find_active).and_return(nil)
      allow(ProcessingLock).to receive(:with_lock) { |*_args, **_opts, &block| block.call || true }
    end

    it 'prepara o cache com as fotos da pasta e libera novos agendamentos' do
      imagens = create_list(:imagem, 2, evento: evento, pasta: '18h')
      described_class.schedule(evento_id: evento.id, pasta_param: '18h')

      described_class.perform_now(evento.id, '18h')

      expect(renderer).to have_received(:prepare!).with(
        photos: imagens.map { |imagem| imagem.arquivo.blob },
        cache_prefix: 'mosaic-cache/evento_' + evento.id.to_s + '/18h'
      )
      expect(described_class.schedule(evento_id: evento.id, pasta_param: '18h')).to be(true)
    end

    it 'nao roda com menos de duas fotos' do
      create(:imagem, evento: evento, pasta: '18h')

      described_class.perform_now(evento.id, '18h')

      expect(renderer).not_to have_received(:prepare!)
    end

    it 'nao roda enquanto o mosaico da pasta esta sendo gerado' do
      create_list(:imagem, 2, evento: evento, pasta: '18h')
      allow(ProcessingSessionTracker).to receive(:find_active).and_return(double('session'))

      described_class.perform_now(evento.id, '18h')

      expect(renderer).not_to have_received(:prepare!)
    end

    it 'reagenda quando outro preparo da mesma pasta esta em andamento' do
      allow(ProcessingLock).to receive(:with_lock).and_return(false)

      expect do
        described_class.perform_now(evento.id, '18h')
      end.to have_enqueued_job(described_class).with(evento.id, '18h')
    end

    it 'so registra o erro quando o Cloud Run falha' do
      create_list(:imagem, 2, evento: evento, pasta: '18h')
      allow(renderer).to receive(:prepare!).and_raise(MosaicRendering::BackendError, 'boom')

      expect { described_class.perform_now(evento.id, '18h') }.not_to raise_error
    end
  end
end
