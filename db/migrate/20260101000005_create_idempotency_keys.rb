class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.string :key, null: false
      t.string :request_path, null: false
      t.string :request_fingerprint, null: false
      t.integer :response_status, null: false
      t.jsonb :response_body, null: false, default: {}
      t.datetime :locked_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :idempotency_keys, :key, unique: true
  end
end
