class CreateReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :reviews do |t|
      t.references :annotation, null: false, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false
      t.text :comment
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :reviews, [:annotation_id, :reviewer_id]
  end
end
