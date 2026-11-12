class AddMessageToReviews < ActiveRecord::Migration[7.1]
  def change
    add_column :reviews, :message, :text
  end
end
