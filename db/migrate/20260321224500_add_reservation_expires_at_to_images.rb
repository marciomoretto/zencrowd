class AddReservationExpiresAtToImages < ActiveRecord::Migration[7.1]
  def change
    add_column :images, :reservation_expires_at, :datetime
    add_index :images, :reservation_expires_at
  end
end