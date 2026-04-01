class AddCpfToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :cpf, :string unless column_exists?(:users, :cpf)
    add_index :users, :cpf, unique: true unless index_exists?(:users, :cpf)
  end
end
