class AddPhoneAndPixKeyTypeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :phone, :string unless column_exists?(:users, :phone)
    add_column :users, :pix_key_type, :string, default: 'cpf' unless column_exists?(:users, :pix_key_type)
  end
end
