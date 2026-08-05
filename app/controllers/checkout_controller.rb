class CheckoutController < ApplicationController
  # POST /flash_sales/:flash_sale_id/checkout
  # Body: { user_token: "..." }
  #
  # Only succeeds if the caller's queue entry is "active" (i.e. the queue
  # let them through) AND stock is still available. This is the choke
  # point that prevents overselling during the traffic spike.
  def create
    flash_sale = FlashSale.find(params[:flash_sale_id])
    entry = flash_sale.queue_entries.find_by(user_token: params[:user_token])

    return render json: { error: "No queue entry found" }, status: :not_found unless entry

    if entry.status != "active"
      return render json: { error: "You have not been let through the queue yet" },
                    status: :forbidden
    end

    if entry.expired?
      entry.update!(status: "expired")
      return render json: { error: "Your checkout window expired" }, status: :gone
    end

    if flash_sale.reserve_unit!
      entry.update!(status: "checked_out")
      render json: { success: true, message: "Order placed" }, status: :ok
    else
      render json: { error: "Sold out" }, status: :unprocessable_entity
    end
  end
end
