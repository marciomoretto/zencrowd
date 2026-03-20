class AddDataToEventos < ActiveRecord::Migration[7.1]
  def change
    add_column :eventos, :data, :date
  end
end
