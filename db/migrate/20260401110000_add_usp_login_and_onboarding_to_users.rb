class AddUspLoginAndOnboardingToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :usp_login, :string unless column_exists?(:users, :usp_login)
    add_column :users, :pix_key, :string unless column_exists?(:users, :pix_key)
    add_column :users, :onboarding_completed, :boolean, null: false, default: true unless column_exists?(:users, :onboarding_completed)

    add_index :users, :usp_login, unique: true unless index_exists?(:users, :usp_login)
  end
end
