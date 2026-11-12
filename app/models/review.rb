class Review < ApplicationRecord
  MESSAGE_MAX_LENGTH = 5_000

  # Associations
  belongs_to :annotation
  belongs_to :reviewer, class_name: 'User'

  # Enums
  enum status: { approved: 0, rejected: 1 }

  # Validations
  validates :annotation, presence: true
  validates :reviewer, presence: true
  validates :status, presence: true
  validates :message, length: { maximum: MESSAGE_MAX_LENGTH }
  validate :reviewer_must_have_reviewer_role

  private

  def reviewer_must_have_reviewer_role
    if reviewer && !reviewer.reviewer?
      errors.add(:reviewer, 'must have reviewer role')
    end
  end
end
