class Payment < ApplicationRecord
  belongs_to :annotator, class_name: 'User'
  belongs_to :processed_by, class_name: 'User'
  has_many :payment_items, dependent: :restrict_with_error
  has_many :tiles, through: :payment_items

  validates :amount, numericality: { greater_than: 0 }
  validates :paid_at, presence: true
end
