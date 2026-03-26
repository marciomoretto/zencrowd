require 'rails_helper'

RSpec.describe ImagemTile, type: :model do
  describe 'validations' do
    it 'does not allow duplicate tile for the same imagem' do
      imagem = create(:imagem)
      tile = create(:tile)

      create(:imagem_tile, imagem: imagem, tile: tile)
      duplicate = build(:imagem_tile, imagem: imagem, tile: tile)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:tile_id]).to include('já está em uso')
    end
  end
end
