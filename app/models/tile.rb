class Tile < Image
	has_many :imagem_tiles, foreign_key: :tile_id, dependent: :destroy, inverse_of: :tile
	has_many :imagens, through: :imagem_tiles, source: :imagem
	has_one :tile_point_set, foreign_key: :tile_id, dependent: :destroy, inverse_of: :tile
end
