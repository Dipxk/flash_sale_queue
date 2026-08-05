class CreateFlashSales < ActiveRecord::Migration[7.1]
  def change
    create_table :flash_sales do |t|
      t.string :name, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :total_stock, null: false
      t.integer :stock_remaining, null: false
      t.integer :max_concurrent_checkouts, null: false, default: 50

      t.timestamps
    end
  end
end
