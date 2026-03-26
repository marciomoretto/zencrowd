class AddHeadCountToImages < ActiveRecord::Migration[7.1]
  def change
    add_column :images, :head_count, :integer
  end
end
