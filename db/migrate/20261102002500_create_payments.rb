class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.references :annotator, null: false, foreign_key: { to_table: :users }
      t.references :processed_by, null: false, foreign_key: { to_table: :users }
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.datetime :paid_at, null: false

      t.timestamps
    end

    create_table :payment_items do |t|
      t.references :payment, null: false, foreign_key: true
      t.references :tile, null: false, foreign_key: { to_table: :images }, index: { unique: true }
      t.decimal :amount, precision: 10, scale: 2, null: false

      t.timestamps
    end
  end
end
