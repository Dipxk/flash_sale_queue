class CreateInventoryReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_reservations do |t|
      t.references :flash_sale, null: false, foreign_key: true
      t.references :queue_entry, null: false, foreign_key: true
      t.string :user_token, null: false
      t.string :status, null: false, default: "held"
      # held -> confirmed | released | expired
      t.datetime :expires_at, null: false
      t.datetime :released_at
      t.string :release_reason

      t.timestamps
    end

    add_index :inventory_reservations, :user_token
    add_index :inventory_reservations, [:flash_sale_id, :status]
    add_index :inventory_reservations, [:status, :expires_at]
    add_index :inventory_reservations, :queue_entry_id, unique: true,
              where: "status = 'held'",
              name: "index_held_reservations_on_queue_entry"
  end
end
