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

ActiveRecord::Schema[7.1].define(version: 2026_03_17_001617) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
  end

  add_foreign_key "annotation_points", "annotations"
  add_foreign_key "annotations", "images"
  add_foreign_key "annotations", "users"
  add_foreign_key "images", "users", column: "reserver_id"
  add_foreign_key "images", "users", column: "uploader_id"
  add_foreign_key "reviews", "annotations"
  add_foreign_key "reviews", "users", column: "reviewer_id"
end
