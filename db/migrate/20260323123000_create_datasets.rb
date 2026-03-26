class CreateDatasets < ActiveRecord::Migration[7.1]
  def change
    create_table :datasets do |t|
      t.string :name, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :tiles_count, null: false, default: 0
      t.integer :points_count, null: false, default: 0

      t.timestamps
    end

    add_index :datasets, :created_at
  end
end
