class AddDroneToEventos < ActiveRecord::Migration[7.1]
  def change
    add_reference :eventos, :drone, foreign_key: true, null: true
  end
end
