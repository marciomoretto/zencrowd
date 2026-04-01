class CreateProcessingSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :processing_sessions do |t|
      t.string :flow, null: false
      t.integer :status, null: false, default: 0
      t.string :resource_type, null: false
      t.bigint :resource_id, null: false
      t.string :scope_key
      t.string :progress_key, null: false
      t.string :job_id
      t.references :started_by_user, foreign_key: { to_table: :users }, null: true
      t.jsonb :payload, null: false, default: {}
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.datetime :last_heartbeat_at

      t.timestamps
    end

    add_index :processing_sessions, :progress_key, unique: true
    add_index :processing_sessions, [:flow, :resource_type, :resource_id, :scope_key, :status], name: :idx_processing_sessions_active_lookup
    add_index :processing_sessions, [:resource_type, :resource_id, :created_at], name: :idx_processing_sessions_resource_timeline
  end
end
