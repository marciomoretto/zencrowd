class User < ApplicationRecord
  # Authentication
  has_secure_password

  # Enums
  enum role: { admin: 0, annotator: 1, reviewer: 2 }

  # Associations
  has_many :uploaded_images, class_name: 'Image', foreign_key: 'uploader_id', dependent: :restrict_with_error
  has_many :reserved_images, class_name: 'Image', foreign_key: 'reserver_id', dependent: :nullify
  has_many :uploaded_tiles, class_name: 'Tile', foreign_key: 'uploader_id', dependent: :restrict_with_error
  has_many :reserved_tiles, class_name: 'Tile', foreign_key: 'reserver_id', dependent: :nullify
  has_many :annotations, dependent: :restrict_with_error
  has_many :reviews, foreign_key: 'reviewer_id', dependent: :restrict_with_error

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: { allow_blank: false }
  validates :blocked, inclusion: { in: [true, false] }
end
