class User < ApplicationRecord
  PIX_KEY_TYPES = %w[cpf phone random].freeze

  # Authentication
  has_secure_password

  before_validation :normalize_cpf
  before_validation :normalize_phone

  # Enums
  enum role: { admin: 0, annotator: 1, reviewer: 2, uploader: 3, finance: 4, visitor: 5 }

  # Associations
  has_many :uploaded_images, class_name: 'Image', foreign_key: 'uploader_id', dependent: :restrict_with_error
  has_many :reserved_images, class_name: 'Image', foreign_key: 'reserver_id', dependent: :nullify
  has_many :uploaded_tiles, class_name: 'Tile', foreign_key: 'uploader_id', dependent: :restrict_with_error
  has_many :reserved_tiles, class_name: 'Tile', foreign_key: 'reserver_id', dependent: :nullify
  has_many :annotations, dependent: :restrict_with_error
  has_many :reviews, foreign_key: 'reviewer_id', dependent: :restrict_with_error
  has_many :processing_sessions, foreign_key: 'started_by_user_id', dependent: :nullify

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :usp_login, uniqueness: true, allow_nil: true
  validates :cpf, uniqueness: true, allow_nil: true
  validates :phone, uniqueness: true, allow_nil: true
  validates :name, presence: true
  validates :role, presence: { allow_blank: false }
  validates :blocked, inclusion: { in: [true, false] }
  validates :requested_payment_reais, numericality: { greater_than_or_equal_to: 0 }
  validates :pix_key, presence: true, if: :usp_onboarded?
  validates :pix_key_type, inclusion: { in: PIX_KEY_TYPES }, if: :usp_onboarded?
  validates :cpf, presence: true, format: { with: /\A\d{11}\z/, message: 'deve conter 11 digitos numericos' }, if: :usp_onboarded?
  validate :validate_pix_key_format, if: :usp_onboarded?

  private

  def usp_onboarded?
    usp_login.present? && onboarding_completed?
  end

  def normalize_cpf
    self.cpf = cpf.to_s.gsub(/\D/, '').presence
  end

  def normalize_phone
    self.phone = phone.to_s.gsub(/\D/, '').presence
  end

  def validate_pix_key_format
    return if pix_key.blank? || pix_key_type.blank?

    normalized_pix = pix_key.to_s.gsub(/\D/, '')
    case pix_key_type
    when 'cpf'
      errors.add(:pix_key, 'deve conter 11 digitos para chave CPF') unless normalized_pix.match?(/\A\d{11}\z/)
    when 'phone'
      unless normalized_pix.match?(/\A\d{10,11}\z/)
        errors.add(:pix_key, 'deve conter DDD e numero para chave de telefone')
      end
    end
  end
end
