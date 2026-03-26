class AnnotationPoint < ApplicationRecord
  # Associations
  belongs_to :annotation

  # Validations
  validates :annotation, presence: true
  validates :x, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :y, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
