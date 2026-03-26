class EventoMosaicPieceHeadCount < ApplicationRecord
  belongs_to :evento

  validates :pasta_nome, presence: true
  validates :row_index, numericality: { only_integer: true, greater_than: 0 }
  validates :col_index, numericality: { only_integer: true, greater_than: 0 }
  validates :estimated_heads, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :row_index, uniqueness: { scope: [:evento_id, :pasta_nome, :col_index] }
end
