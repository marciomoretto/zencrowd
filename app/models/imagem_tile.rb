class ImagemTile < ApplicationRecord
  belongs_to :imagem, class_name: 'Imagem', inverse_of: :imagem_tiles
  belongs_to :tile, class_name: 'Tile', foreign_key: :tile_id, inverse_of: :imagem_tiles

  validates :tile_id, uniqueness: { scope: :imagem_id }
end
