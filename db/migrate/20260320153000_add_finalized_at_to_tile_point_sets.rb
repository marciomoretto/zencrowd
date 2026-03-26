class AddFinalizedAtToTilePointSets < ActiveRecord::Migration[7.1]
  def change
    add_column :tile_point_sets, :finalized_at, :datetime
    add_index :tile_point_sets, :finalized_at
  end
end
