class CreateEventoMosaicPieceHeadCounts < ActiveRecord::Migration[7.1]
  def change
    create_table :evento_mosaic_piece_head_counts do |t|
      t.references :evento, null: false, foreign_key: true
      t.string :pasta_nome, null: false
      t.integer :row_index, null: false
      t.integer :col_index, null: false
      t.integer :estimated_heads, null: false, default: 0

      t.timestamps
    end

    add_index :evento_mosaic_piece_head_counts,
              [:evento_id, :pasta_nome, :row_index, :col_index],
              unique: true,
              name: 'idx_evento_mosaic_piece_head_counts_unique'
  end
end
