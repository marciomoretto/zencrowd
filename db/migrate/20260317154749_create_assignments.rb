class CreateAssignments < ActiveRecord::Migration[7.1]
  def change
    create_table :assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :image, null: false, foreign_key: true
      t.integer :status
      t.datetime :expires_at

      t.timestamps
    end
  end
end
