class FlashSalesController < ApplicationController
  def show
    flash_sale = FlashSale.find(params[:id])
    render json: {
      id: flash_sale.id,
      name: flash_sale.name,
      live: flash_sale.live?,
      stock_remaining: flash_sale.stock_remaining,
      total_stock: flash_sale.total_stock,
      waiting: flash_sale.waiting_count,
      active_checkouts: flash_sale.active_checkout_count,
      max_concurrent_checkouts: flash_sale.max_concurrent_checkouts,
      starts_at: flash_sale.starts_at,
      ends_at: flash_sale.ends_at
    }
  end

  def create
    flash_sale = FlashSale.create!(flash_sale_params.merge(
      stock_remaining: flash_sale_params[:total_stock] || flash_sale_params["total_stock"]
    ))
    AdmissionControl.new(flash_sale).reset!

    render json: {
      id: flash_sale.id,
      name: flash_sale.name,
      stock_remaining: flash_sale.stock_remaining,
      max_concurrent_checkouts: flash_sale.max_concurrent_checkouts
    }, status: :created
  end

  private

  def flash_sale_params
    params.require(:flash_sale).permit(
      :name, :starts_at, :ends_at, :total_stock, :max_concurrent_checkouts
    )
  end
end
