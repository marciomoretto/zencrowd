class AddCidadeELocalToEventos < ActiveRecord::Migration[7.1]
  def change
    add_column :eventos, :cidade, :string
    add_column :eventos, :local, :string
  end
end
