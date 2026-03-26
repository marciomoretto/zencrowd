class AddPaymentRequestFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :requested_payment_reais, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :users, :requested_payment_at, :datetime
  end
end
