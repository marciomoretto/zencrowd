class AddPastaToImagens < ActiveRecord::Migration[7.1]
  def change
    add_column :imagens, :pasta, :string
  end
end