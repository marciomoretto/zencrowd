class PaymentItem < ApplicationRecord
  belongs_to :payment
  belongs_to :tile, class_name: 'Tile'

  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :tile_id, uniqueness: true
end
