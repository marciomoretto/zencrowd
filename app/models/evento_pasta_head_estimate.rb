class EventoPastaHeadEstimate < ApplicationRecord
  belongs_to :evento

  validates :pasta_nome, presence: true
  validates :estimated_heads, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
