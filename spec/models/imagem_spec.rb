require 'rails_helper'

RSpec.describe Imagem, type: :model do
  describe 'validations' do
    it 'is valid with required fields and attached file' do
      imagem = build(:imagem)

      expect(imagem).to be_valid
    end

    it 'requires attached file' do
      imagem = build(:imagem)
      imagem.arquivo.detach

      expect(imagem).not_to be_valid
      expect(imagem.errors[:arquivo]).to include('não pode ficar em branco')
    end

    it 'requires base metadata fields' do
      imagem = build(:imagem, data_hora: nil, gps_location: nil, cidade: nil, local: nil)

      expect(imagem).not_to be_valid
      expect(imagem.errors[:data_hora]).to include('não pode ficar em branco')
      expect(imagem.errors[:gps_location]).to include('não pode ficar em branco')
      expect(imagem.errors[:cidade]).to include('não pode ficar em branco')
      expect(imagem.errors[:local]).to include('não pode ficar em branco')
    end
  end

  describe 'enum posicao' do
    it 'supports esquerda, direita and outro' do
      expect(described_class.defined_enums['posicao'].keys).to contain_exactly('esquerda', 'direita', 'outro')
    end
  end

  describe 'associations with tiles' do
    it 'can be related to multiple tiles' do
      imagem = create(:imagem)
      tile1 = create(:tile)
      tile2 = create(:tile)

      imagem.tiles << [tile1, tile2]

      expect(imagem.tiles).to contain_exactly(tile1, tile2)
    end
  end
end
