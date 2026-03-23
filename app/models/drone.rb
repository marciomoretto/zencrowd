class Drone < ApplicationRecord
  ASPECT_RATIOS = ['1:1', '3:2', '4:3', '5:4', '16:9'].freeze

  before_validation :normalize_text_fields

  validates :modelo, presence: true
  validates :lente, presence: true
  validates :fov_diag_deg, presence: true, numericality: { greater_than: 0 }
  validates :aspect_ratio, presence: true, inclusion: { in: ASPECT_RATIOS }
  validates :modelo, uniqueness: {
    scope: :lente,
    case_sensitive: false,
    message: 'com esta lente ja esta cadastrado'
  }

  def chave
    "#{modelo} + #{lente}"
  end

  private

  def normalize_text_fields
    self.modelo = modelo.to_s.strip
    self.lente = lente.to_s.strip
    self.aspect_ratio = aspect_ratio.to_s.strip
  end
end
