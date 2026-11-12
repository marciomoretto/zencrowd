class CreateReviewCorrections < ActiveRecord::Migration[7.1]
  def change
    create_table :review_corrections do |t|
      t.references :annotation, null: false, foreign_key: true, index: { unique: true }
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.jsonb :original_points, null: false, default: []
      t.jsonb :points, null: false, default: []
      t.integer :added_count, null: false, default: 0
      t.integer :removed_count, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
  end
end
