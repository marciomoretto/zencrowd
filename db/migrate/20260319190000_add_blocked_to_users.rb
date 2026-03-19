class AddBlockedToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :blocked, :boolean, default: false, null: false
    add_index :users, :blocked
  end
end
