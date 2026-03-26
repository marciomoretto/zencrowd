class CreateEventoPastaHeadEstimates < ActiveRecord::Migration[7.1]
  def change
    create_table :evento_pasta_head_estimates do |t|
      t.references :evento, null: false, foreign_key: true
      t.string :pasta_nome, null: false
      t.integer :estimated_heads, null: false, default: 0

      t.timestamps
    end

    add_index :evento_pasta_head_estimates,
              [:evento_id, :pasta_nome],
              unique: true,
              name: 'idx_evento_pasta_head_estimates_unique'
  end
end
