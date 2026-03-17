class Annotation < ApplicationRecord
  # Associations
  belongs_to :image
  belongs_to :user
  has_many :annotation_points, dependent: :destroy
  has_one :review, dependent: :destroy

  # Validations
  validates :image, presence: true
  validates :user, presence: true

  # Nested attributes
  accepts_nested_attributes_for :annotation_points, allow_destroy: true
end
