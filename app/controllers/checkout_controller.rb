class CheckoutController < ApplicationController
  # POST /flash_sales/:flash_sale_id/checkout
  # Headers: Idempotency-Key (required), X-User-Token (optional, for rate-limit identity)
  # Body: { user_token: "..." }
  def create
    flash_sale = FlashSale.find(params[:flash_sale_id])
    idempotency_key = request.headers["Idempotency-Key"].presence || params[:idempotency_key]

    result = CheckoutService.new(
      flash_sale: flash_sale,
      user_token: params[:user_token],
      idempotency_key: idempotency_key,
      request_path: request.path
    ).call

    headers["Idempotency-Replayed"] = "true" if result.replayed
    render json: result.body, status: result.status
  end
end
