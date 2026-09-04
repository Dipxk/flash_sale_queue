class InventoryChannel < ApplicationCable::Channel
  def subscribed
    flash_sale = FlashSale.find_by(id: params[:flash_sale_id])
    reject && return unless flash_sale

    stream_for flash_sale
    transmit self.class.payload_for(flash_sale)
  end

  def self.broadcast_stock(flash_sale)
    broadcast_to(flash_sale, payload_for(flash_sale))
  end

  def self.payload_for(flash_sale)
    {
      type: "inventory_update",
      flash_sale_id: flash_sale.id,
      stock_remaining: flash_sale.stock_remaining,
      live: flash_sale.live?,
      waiting: flash_sale.waiting_count,
      active_checkouts: flash_sale.active_checkout_count
    }
  end
end
