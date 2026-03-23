class CreateDrones < ActiveRecord::Migration[7.1]
  def change
    create_table :drones do |t|
      t.string :modelo, null: false
      t.string :lente, null: false
      t.decimal :fov_diag_deg, precision: 6, scale: 2, null: false
      t.string :aspect_ratio, null: false, default: '4:3'

      t.timestamps
    end

    add_index :drones, [:modelo, :lente], unique: true
  end
end
