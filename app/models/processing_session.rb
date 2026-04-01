class ProcessingSession < ApplicationRecord
  enum status: {
    queued: 0,
    running: 1,
    completed: 2,
    failed: 3,
    superseded: 4
  }

  belongs_to :resource, polymorphic: true
  belongs_to :started_by_user, class_name: 'User', optional: true

  validates :flow, presence: true
  validates :status, presence: true
  validates :resource_type, presence: true
  validates :resource_id, presence: true
  validates :progress_key, presence: true, uniqueness: true
  validates :payload, presence: true
  validates :started_at, presence: true

  scope :active, -> { where(status: [statuses[:queued], statuses[:running]]) }
end
