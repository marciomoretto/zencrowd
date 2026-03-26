class CreateEventosAndAddEventoToImagens < ActiveRecord::Migration[7.1]
  def change
    create_table :eventos do |t|
      t.string :nome, null: false
      t.integer :categoria

      t.timestamps
    end

    add_reference :imagens, :evento, foreign_key: true
  end
end
