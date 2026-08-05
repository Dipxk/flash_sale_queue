class FlashSalesController < ApplicationController
  def show
    flash_sale = FlashSale.find(params[:id])
    render json: {
      id: flash_sale.id,
      name: flash_sale.name,
      live: flash_sale.live?,
      stock_remaining: flash_sale.stock_remaining,
      active_checkouts: flash_sale.active_checkout_count,
      max_concurrent_checkouts: flash_sale.max_concurrent_checkouts
    }
  end
end
