require 'rails_helper'

RSpec.describe Evento, type: :model do
  describe 'validations' do
    it 'is valid with nome' do
      evento = build(:evento, nome: 'Feira de Campo')

      expect(evento).to be_valid
    end

    it 'requires nome' do
      evento = build(:evento, nome: nil)

      expect(evento).not_to be_valid
      expect(evento.errors[:nome]).to include('não pode ficar em branco')
    end
  end

  describe 'enum categoria' do
    it 'supports direita, esquerda and outro' do
      expect(described_class.defined_enums['categoria'].keys).to contain_exactly('direita', 'esquerda', 'outro')
    end

    it 'allows categoria to be nil' do
      evento = build(:evento, categoria: nil)

      expect(evento).to be_valid
    end
  end

  describe 'associations with imagens' do
    it 'can be related to multiple imagens' do
      evento = create(:evento)
      imagem1 = create(:imagem)
      imagem2 = create(:imagem)

      evento.imagens << [imagem1, imagem2]

      expect(evento.imagens).to contain_exactly(imagem1, imagem2)
      expect(imagem1.reload.evento).to eq(evento)
      expect(imagem2.reload.evento).to eq(evento)
    end
  end
end
