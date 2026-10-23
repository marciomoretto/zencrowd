require 'rails_helper'

RSpec.describe MosaicPhotoSyncJob do
  let(:imagem) { create(:imagem, evento: create(:evento), pasta: '18h') }
  let(:store) { instance_double(MosaicRendering::PhotoStore, ensure_uploaded!: 1) }

  before do
    allow(MosaicRendering::PhotoStore).to receive(:new).and_return(store)
    allow(PrepareMosaicCacheJob).to receive(:schedule)
  end

  it 'envia a foto ao bucket e agenda o preparo da pasta' do
    allow(MosaicRendering::Settings).to receive(:cloud_run?).and_return(true)

    described_class.perform_now(imagem.id)

    expect(store).to have_received(:ensure_uploaded!).with([imagem.arquivo.blob])
    expect(PrepareMosaicCacheJob).to have_received(:schedule).with(evento_id: imagem.evento_id, pasta_param: '18h')
  end

  it 'nao faz nada sem o backend do Cloud Run' do
    allow(MosaicRendering::Settings).to receive(:cloud_run?).and_return(false)

    described_class.perform_now(imagem.id)

    expect(store).not_to have_received(:ensure_uploaded!)
  end
end
