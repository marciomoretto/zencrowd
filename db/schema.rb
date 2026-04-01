# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_01_140500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "annotation_points", force: :cascade do |t|
    t.bigint "annotation_id", null: false
    t.integer "x", null: false
    t.integer "y", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["annotation_id"], name: "index_annotation_points_on_annotation_id"
  end

  create_table "annotations", force: :cascade do |t|
    t.bigint "image_id", null: false
    t.bigint "user_id", null: false
    t.datetime "submitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["image_id", "user_id"], name: "index_annotations_on_image_id_and_user_id"
    t.index ["image_id"], name: "index_annotations_on_image_id"
    t.index ["user_id"], name: "index_annotations_on_user_id"
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "assignments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "image_id", null: false
    t.integer "status"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["image_id"], name: "index_assignments_on_image_id"
    t.index ["user_id"], name: "index_assignments_on_user_id"
  end

  create_table "datasets", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "created_by_id", null: false
    t.integer "tiles_count", default: 0, null: false
    t.integer "points_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_datasets_on_created_at"
    t.index ["created_by_id"], name: "index_datasets_on_created_by_id"
  end

  create_table "drones", force: :cascade do |t|
    t.string "modelo", null: false
    t.string "lente", null: false
    t.decimal "fov_diag_deg", precision: 6, scale: 2, null: false
    t.string "aspect_ratio", default: "4:3", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["modelo", "lente"], name: "index_drones_on_modelo_and_lente", unique: true
  end

  create_table "evento_mosaic_piece_head_counts", force: :cascade do |t|
    t.bigint "evento_id", null: false
    t.string "pasta_nome", null: false
    t.integer "row_index", null: false
    t.integer "col_index", null: false
    t.integer "estimated_heads", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["evento_id", "pasta_nome", "row_index", "col_index"], name: "idx_evento_mosaic_piece_head_counts_unique", unique: true
    t.index ["evento_id"], name: "index_evento_mosaic_piece_head_counts_on_evento_id"
  end

  create_table "evento_pasta_head_estimates", force: :cascade do |t|
    t.bigint "evento_id", null: false
    t.string "pasta_nome", null: false
    t.integer "estimated_heads", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["evento_id", "pasta_nome"], name: "idx_evento_pasta_head_estimates_unique", unique: true
    t.index ["evento_id"], name: "index_evento_pasta_head_estimates_on_evento_id"
  end

  create_table "eventos", force: :cascade do |t|
    t.string "nome", null: false
    t.integer "categoria"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cidade"
    t.string "local"
    t.date "data"
    t.bigint "drone_id"
    t.index ["drone_id"], name: "index_eventos_on_drone_id"
  end

  create_table "imagem_tiles", force: :cascade do |t|
    t.bigint "imagem_id", null: false
    t.bigint "tile_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["imagem_id", "tile_id"], name: "index_imagem_tiles_on_imagem_id_and_tile_id", unique: true
    t.index ["imagem_id"], name: "index_imagem_tiles_on_imagem_id"
  end

  create_table "imagens", force: :cascade do |t|
    t.datetime "data_hora", null: false
    t.string "gps_location", null: false
    t.string "cidade", null: false
    t.string "local", null: false
    t.string "nome_do_evento"
    t.integer "posicao"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "exif_metadata", default: {}, null: false
    t.jsonb "xmp_metadata", default: {}, null: false
    t.bigint "evento_id"
    t.string "pasta"
    t.index ["data_hora"], name: "index_imagens_on_data_hora"
    t.index ["evento_id"], name: "index_imagens_on_evento_id"
  end

  create_table "images", force: :cascade do |t|
    t.string "original_filename", null: false
    t.string "storage_path", null: false
    t.integer "status", default: 0, null: false
    t.decimal "task_value", precision: 10, scale: 2
    t.bigint "uploader_id", null: false
    t.bigint "reserver_id"
    t.datetime "reserved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_annotators", default: 1
    t.integer "head_count"
    t.datetime "reservation_expires_at"
    t.index ["reservation_expires_at"], name: "index_images_on_reservation_expires_at"
    t.index ["reserver_id", "status"], name: "index_images_on_reserver_id_and_status"
    t.index ["reserver_id"], name: "index_images_on_reserver_id"
    t.index ["status"], name: "index_images_on_status"
    t.index ["uploader_id"], name: "index_images_on_uploader_id"
  end

  create_table "processing_sessions", force: :cascade do |t|
    t.string "flow", null: false
    t.integer "status", default: 0, null: false
    t.string "resource_type", null: false
    t.bigint "resource_id", null: false
    t.string "scope_key"
    t.string "progress_key", null: false
    t.string "job_id"
    t.bigint "started_by_user_id"
    t.jsonb "payload", default: {}, null: false
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "last_heartbeat_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["flow", "resource_type", "resource_id", "scope_key", "status"], name: "idx_processing_sessions_active_lookup"
    t.index ["progress_key"], name: "index_processing_sessions_on_progress_key", unique: true
    t.index ["resource_type", "resource_id", "created_at"], name: "idx_processing_sessions_resource_timeline"
    t.index ["started_by_user_id"], name: "index_processing_sessions_on_started_by_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "annotation_id", null: false
    t.bigint "reviewer_id", null: false
    t.integer "status", null: false
    t.text "comment"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["annotation_id", "reviewer_id"], name: "index_reviews_on_annotation_id_and_reviewer_id"
    t.index ["annotation_id"], name: "index_reviews_on_annotation_id"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
  end

  create_table "tile_point_sets", force: :cascade do |t|
    t.bigint "tile_id", null: false
    t.string "axis", default: "image", null: false
    t.jsonb "points", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "finalized_at"
    t.index ["finalized_at"], name: "index_tile_point_sets_on_finalized_at"
    t.index ["tile_id"], name: "index_tile_point_sets_on_tile_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.integer "role", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.boolean "blocked", default: false, null: false
    t.decimal "requested_payment_reais", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "requested_payment_at"
    t.string "usp_login"
    t.string "pix_key"
    t.boolean "onboarding_completed", default: true, null: false
    t.string "cpf"
    t.string "phone"
    t.string "pix_key_type", default: "cpf"
    t.index ["blocked"], name: "index_users_on_blocked"
    t.index ["cpf"], name: "index_users_on_cpf", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["usp_login"], name: "index_users_on_usp_login", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "annotation_points", "annotations"
  add_foreign_key "annotations", "images"
  add_foreign_key "annotations", "users"
  add_foreign_key "assignments", "images"
  add_foreign_key "assignments", "users"
  add_foreign_key "datasets", "users", column: "created_by_id"
  add_foreign_key "evento_mosaic_piece_head_counts", "eventos"
  add_foreign_key "evento_pasta_head_estimates", "eventos"
  add_foreign_key "eventos", "drones"
  add_foreign_key "imagem_tiles", "imagens"
  add_foreign_key "imagem_tiles", "images", column: "tile_id"
  add_foreign_key "imagens", "eventos"
  add_foreign_key "images", "users", column: "reserver_id"
  add_foreign_key "images", "users", column: "uploader_id"
  add_foreign_key "processing_sessions", "users", column: "started_by_user_id"
  add_foreign_key "reviews", "annotations"
  add_foreign_key "reviews", "users", column: "reviewer_id"
  add_foreign_key "tile_point_sets", "images", column: "tile_id"
end
