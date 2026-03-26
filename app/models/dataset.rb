class Dataset < ApplicationRecord
  belongs_to :creator, class_name: 'User', foreign_key: :created_by_id

  has_one_attached :archive

  validates :name, presence: true
  validates :tiles_count, numericality: { greater_than_or_equal_to: 0 }
  validates :points_count, numericality: { greater_than_or_equal_to: 0 }
end
