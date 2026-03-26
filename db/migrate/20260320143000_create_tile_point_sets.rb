class CreateTilePointSets < ActiveRecord::Migration[7.1]
  def change
    create_table :tile_point_sets do |t|
      t.references :tile, null: false, foreign_key: { to_table: :images }, index: { unique: true }
      t.string :axis, null: false, default: 'image'
      t.jsonb :points, null: false, default: []

      t.timestamps
    end
  end
end
