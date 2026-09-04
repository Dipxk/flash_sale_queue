class CreateQueueEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :queue_entries do |t|
      t.references :flash_sale, null: false, foreign_key: true
      t.string :user_token, null: false
      t.integer :position, null: false
      t.string :status, null: false, default: "waiting"
      t.datetime :activated_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :queue_entries, [:flash_sale_id, :status]
    add_index :queue_entries, [:flash_sale_id, :position]
    add_index :queue_entries, :user_token, unique: true
  end
end
