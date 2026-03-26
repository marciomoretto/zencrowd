class CreateImagensAndImagemTiles < ActiveRecord::Migration[7.1]
  def change
    create_table :imagens do |t|
      t.datetime :data_hora, null: false
      t.string :gps_location, null: false
      t.string :cidade, null: false
      t.string :local, null: false
      t.string :nome_do_evento
      t.integer :posicao

      t.timestamps
    end

    add_index :imagens, :data_hora

    create_table :imagem_tiles do |t|
      t.references :imagem, null: false, foreign_key: { to_table: :imagens }
      t.bigint :tile_id, null: false

      t.timestamps
    end

    add_index :imagem_tiles, [:imagem_id, :tile_id], unique: true
    add_foreign_key :imagem_tiles, :images, column: :tile_id
  end
end
