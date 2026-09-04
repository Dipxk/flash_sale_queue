class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :flash_sale, null: false, foreign_key: true
      t.references :queue_entry, null: false, foreign_key: true, index: { unique: true }
      t.references :inventory_reservation, null: false, foreign_key: true
      t.string :user_token, null: false
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "completed"

      t.timestamps
    end

    add_index :orders, :idempotency_key, unique: true
    add_index :orders, [:flash_sale_id, :user_token], unique: true
  end
end
