# Idempotent checkout: one order per user/sale and per idempotency key.
class CheckoutService
  Result = Struct.new(:success?, :status, :body, :replayed, keyword_init: true)

  def initialize(flash_sale:, user_token:, idempotency_key:, request_path:)
    @flash_sale = flash_sale
    @user_token = user_token
    @idempotency_key = idempotency_key
    @request_path = request_path
  end

  def call
    return missing_key unless @idempotency_key.present?

    fingerprint = Digest::SHA256.hexdigest([ @flash_sale.id, @user_token ].join(":"))

    existing = IdempotencyKey.find_by(key: @idempotency_key)
    if existing&.completed_at
      if existing.request_fingerprint != fingerprint
        return Result.new(
          success?: false,
          status: :conflict,
          body: { error: "Idempotency key reused with different payload" },
          replayed: false
        )
      end
      MetricsCollector.increment("checkout.idempotent_replay")
      return Result.new(
        success?: existing.response_status < 400,
        status: existing.response_status,
        body: existing.response_body,
        replayed: true
      )
    end

    begin
      record = IdempotencyKey.create!(
        key: @idempotency_key,
        request_path: @request_path,
        request_fingerprint: fingerprint,
        response_status: 0,
        response_body: {},
        locked_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      sleep 0.05
      return call
    end

    result = perform_checkout
    record.update!(
      response_status: Rack::Utils.status_code(result.status),
      response_body: result.body,
      completed_at: Time.current
    )
    result
  end

  private

  def missing_key
    Result.new(
      success?: false,
      status: :bad_request,
      body: { error: "Idempotency-Key header is required" },
      replayed: false
    )
  end

  def perform_checkout
    entry = @flash_sale.queue_entries.find_by(user_token: @user_token)
    return failure(:not_found, "No queue entry found") unless entry

    if entry.status == "checked_out"
      order = Order.find_by(queue_entry_id: entry.id)
      return success(order) if order
    end

    if entry.status != "active"
      return failure(:forbidden, "You have not been let through the queue yet")
    end

    if entry.expired?
      expire_entry!(entry)
      return failure(:gone, "Your checkout window expired")
    end

    reservation = InventoryReservation.find_by(queue_entry_id: entry.id, status: "held")
    unless reservation
      # Lazy reserve at checkout if admission didn't create one yet
      reserve_result = ReservationService.new(flash_sale: @flash_sale, queue_entry: entry).reserve!
      unless reserve_result.success?
        return failure(:unprocessable_entity, "Sold out")
      end
      reservation = reserve_result.reservation
    end

    if reservation.expired?
      ReservationService.release_expired!(reservation)
      return failure(:gone, "Your inventory reservation expired")
    end

    order = nil
    ActiveRecord::Base.transaction do
      entry.lock!
      return failure(:conflict, "Already checked out") if entry.status == "checked_out"

      order = Order.create!(
        flash_sale: @flash_sale,
        queue_entry: entry,
        inventory_reservation: reservation,
        user_token: @user_token,
        idempotency_key: @idempotency_key,
        status: "completed"
      )

      ReservationService.confirm!(reservation)
      entry.update!(status: "checked_out")
    end

    AdmissionControl.new(@flash_sale).release!
    MetricsCollector.increment("checkout.success")
    InventoryChannel.broadcast_stock(@flash_sale)
    QueueChannel.broadcast_to_user(entry.reload)

    success(order)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent duplicate — return existing order
    order = Order.find_by(flash_sale_id: @flash_sale.id, user_token: @user_token) ||
            Order.find_by(idempotency_key: @idempotency_key)
    MetricsCollector.increment("checkout.idempotent_replay")
    success(order)
  rescue ActiveRecord::StatementInvalid => e
    MetricsCollector.increment("database.errors")
    raise if e.message.exclude?("flash_sales_stock_non_negative")

    MetricsCollector.increment("oversell.prevented")
    failure(:unprocessable_entity, "Sold out")
  end

  def expire_entry!(entry)
    entry.update!(status: "expired")
    AdmissionControl.new(@flash_sale).release!
    reservation = InventoryReservation.find_by(queue_entry_id: entry.id, status: "held")
    ReservationService.release_expired!(reservation) if reservation
  end

  def success(order)
    Result.new(
      success?: true,
      status: :ok,
      body: {
        success: true,
        message: "Order placed",
        order_id: order.id,
        flash_sale_id: order.flash_sale_id
      },
      replayed: false
    )
  end

  def failure(status, message)
    MetricsCollector.increment("checkout.failure")
    Result.new(success?: false, status: status, body: { error: message }, replayed: false)
  end
end
