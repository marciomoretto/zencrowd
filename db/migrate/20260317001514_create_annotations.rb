class CreateAnnotations < ActiveRecord::Migration[7.1]
  def change
    create_table :annotations do |t|
      t.references :image, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :submitted_at

      t.timestamps
    end

    add_index :annotations, [:image_id, :user_id]
  end
end
