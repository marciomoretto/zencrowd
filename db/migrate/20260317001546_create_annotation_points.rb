class CreateAnnotationPoints < ActiveRecord::Migration[7.1]
  def change
    create_table :annotation_points do |t|
      t.references :annotation, null: false, foreign_key: true, index: true
      t.integer :x, null: false
      t.integer :y, null: false

      t.timestamps
    end
  end
end
