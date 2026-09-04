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

ActiveRecord::Schema[8.1].define(version: 2026_01_01_000005) do
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
    t.check_constraint "stock_remaining <= total_stock", name: "flash_sales_stock_lte_total"
    t.check_constraint "stock_remaining >= 0", name: "flash_sales_stock_non_negative"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "locked_at"
    t.string "request_fingerprint", null: false
    t.string "request_path", null: false
    t.jsonb "response_body", default: {}, null: false
    t.integer "response_status", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_idempotency_keys_on_key", unique: true
  end

  create_table "inventory_reservations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "flash_sale_id", null: false
    t.bigint "queue_entry_id", null: false
    t.string "release_reason"
    t.datetime "released_at"
    t.string "status", default: "held", null: false
    t.datetime "updated_at", null: false
    t.string "user_token", null: false
    t.index ["flash_sale_id", "status"], name: "index_inventory_reservations_on_flash_sale_id_and_status"
    t.index ["flash_sale_id"], name: "index_inventory_reservations_on_flash_sale_id"
    t.index ["queue_entry_id"], name: "index_held_reservations_on_queue_entry", unique: true, where: "((status)::text = 'held'::text)"
    t.index ["queue_entry_id"], name: "index_inventory_reservations_on_queue_entry_id"
    t.index ["status", "expires_at"], name: "index_inventory_reservations_on_status_and_expires_at"
    t.index ["user_token"], name: "index_inventory_reservations_on_user_token"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "flash_sale_id", null: false
    t.string "idempotency_key", null: false
    t.bigint "inventory_reservation_id", null: false
    t.bigint "queue_entry_id", null: false
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.string "user_token", null: false
    t.index ["flash_sale_id", "user_token"], name: "index_orders_on_flash_sale_id_and_user_token", unique: true
    t.index ["flash_sale_id"], name: "index_orders_on_flash_sale_id"
    t.index ["idempotency_key"], name: "index_orders_on_idempotency_key", unique: true
    t.index ["inventory_reservation_id"], name: "index_orders_on_inventory_reservation_id"
    t.index ["queue_entry_id"], name: "index_orders_on_queue_entry_id", unique: true
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

  add_foreign_key "inventory_reservations", "flash_sales"
  add_foreign_key "inventory_reservations", "queue_entries"
  add_foreign_key "orders", "flash_sales"
  add_foreign_key "orders", "inventory_reservations"
  add_foreign_key "orders", "queue_entries"
  add_foreign_key "queue_entries", "flash_sales"
end
