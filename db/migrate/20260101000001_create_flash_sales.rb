class CreateFlashSales < ActiveRecord::Migration[8.1]
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

    add_check_constraint :flash_sales, "stock_remaining >= 0", name: "flash_sales_stock_non_negative"
    add_check_constraint :flash_sales, "stock_remaining <= total_stock", name: "flash_sales_stock_lte_total"
  end
end
