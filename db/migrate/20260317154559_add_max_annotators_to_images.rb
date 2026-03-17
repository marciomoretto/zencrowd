class AddMaxAnnotatorsToImages < ActiveRecord::Migration[7.1]
  def change
    add_column :images, :max_annotators, :integer, default: 1
  end
end