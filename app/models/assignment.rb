class Assignment < ApplicationRecord
  belongs_to :user
  belongs_to :image

  def tile
    image
  end

  def tile=(value)
    self.image = value
  end
end
