class CreateEventoRelatorios < ActiveRecord::Migration[7.1]
  def change
    create_table :evento_relatorios do |t|
      t.references :evento, null: false, foreign_key: true, index: { unique: true }
      t.text :conteudo_md, null: false, default: ''

      t.timestamps
    end
  end
end
