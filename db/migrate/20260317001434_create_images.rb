class CreateImages < ActiveRecord::Migration[7.1]
  def change
    create_table :images do |t|
      t.string :original_filename, null: false
      t.string :storage_path, null: false
      t.integer :status, null: false, default: 0
      t.decimal :task_value, precision: 10, scale: 2
      t.bigint :uploader_id, null: false
      t.bigint :reserver_id
      t.datetime :reserved_at

      t.timestamps
    end

    add_foreign_key :images, :users, column: :uploader_id
    add_foreign_key :images, :users, column: :reserver_id
    add_index :images, :uploader_id
    add_index :images, :reserver_id
    add_index :images, :status
    add_index :images, [:reserver_id, :status]
  end
end
