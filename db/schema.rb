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

ActiveRecord::Schema[8.1].define(version: 2026_01_01_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "flash_sales", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.integer "max_concurrent_checkouts", default: 50, null: false
    t.string "name", null: false
    t.datetime "starts_at", null: false
    t.integer "stock_remaining", null: false
    t.integer "total_stock", null: false
    t.datetime "updated_at", null: false
  end

  create_table "queue_entries", force: :cascade do |t|
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "flash_sale_id", null: false
    t.integer "position", null: false
    t.string "status", default: "waiting", null: false
    t.datetime "updated_at", null: false
    t.string "user_token", null: false
    t.index ["flash_sale_id", "position"], name: "index_queue_entries_on_flash_sale_id_and_position"
    t.index ["flash_sale_id", "status"], name: "index_queue_entries_on_flash_sale_id_and_status"
    t.index ["flash_sale_id"], name: "index_queue_entries_on_flash_sale_id"
    t.index ["user_token"], name: "index_queue_entries_on_user_token", unique: true
  end

  add_foreign_key "queue_entries", "flash_sales"
end
