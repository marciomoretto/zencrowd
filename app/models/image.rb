class Image < ApplicationRecord
  # Associations
  belongs_to :uploader, class_name: 'User', foreign_key: 'uploader_id'
  belongs_to :reserver, class_name: 'User', foreign_key: 'reserver_id', optional: true
  has_many :annotations, dependent: :restrict_with_error

  # Enums
  enum status: {
    available: 0,
    reserved: 1,
    submitted: 2,
    in_review: 3,
    approved: 4,
    rejected: 5,
    paid: 6
  }

  # Validations
  validates :original_filename, presence: true
  validates :storage_path, presence: true
  validates :status, presence: true
  validates :task_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Custom validations
  validate :user_can_reserve_only_one_image, if: :reserved?

  private

  def user_can_reserve_only_one_image
    return if reserver.nil?
    
    other_reserved = Image.where(reserver_id: reserver_id, status: :reserved)
                          .where.not(id: id)
                          .exists?
    
    if other_reserved
      errors.add(:base, 'User already has a reserved image')
    end
  end
end
