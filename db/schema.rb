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

ActiveRecord::Schema[7.1].define(version: 2026_03_19_190000) do
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
    t.index ["image_id"], name: "index_annotations_on_image_id"
    t.index ["user_id"], name: "index_annotations_on_user_id"
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
    t.index ["reserver_id", "status"], name: "index_images_on_reserver_id_and_status"
    t.index ["reserver_id"], name: "index_images_on_reserver_id"
    t.index ["status"], name: "index_images_on_status"
    t.index ["uploader_id"], name: "index_images_on_uploader_id"
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

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "name"
    t.integer "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.boolean "blocked", default: false, null: false
    t.index ["blocked"], name: "index_users_on_blocked"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "annotation_points", "annotations"
  add_foreign_key "annotations", "images"
  add_foreign_key "annotations", "users"
  add_foreign_key "assignments", "images"
  add_foreign_key "assignments", "users"
  add_foreign_key "images", "users", column: "reserver_id"
  add_foreign_key "images", "users", column: "uploader_id"
  add_foreign_key "reviews", "annotations"
  add_foreign_key "reviews", "users", column: "reviewer_id"
end
