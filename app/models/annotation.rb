class Annotation < ApplicationRecord
  # Associations
  belongs_to :image
  belongs_to :user
  has_many :annotation_points, dependent: :destroy
  has_one :review, dependent: :destroy

  # Active Storage (Arquivos da submissão)
  has_one_attached :projeto_tar
  has_one_attached :dados_csv
  has_one_attached :config_json

  # Validations
  validates :image, presence: true
  validates :user, presence: true
  validate :validate_attached_files

  # Nested attributes
  accepts_nested_attributes_for :annotation_points, allow_destroy: true

  private

  # Validação de segurança para garantir o formato correto
  def validate_attached_files
    if projeto_tar.attached? && !projeto_tar.filename.to_s.end_with?('.tar')
      errors.add(:projeto_tar, 'deve ser um arquivo .tar')
    end

    if dados_csv.attached? && !dados_csv.filename.to_s.end_with?('.csv')
      errors.add(:dados_csv, 'deve ser um arquivo .csv')
    end

    if config_json.attached? && !config_json.filename.to_s.end_with?('.json')
    errors.add(:config_json, 'deve ser um arquivo .json')
    end
  end
end