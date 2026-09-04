class QueueController < ApplicationController
  # POST /flash_sales/:flash_sale_id/queue
  def create
    flash_sale = FlashSale.find(params[:flash_sale_id])

    unless flash_sale.live?
      return render json: { error: "Sale is not currently live" }, status: :unprocessable_entity
    end

    user_token = SecureRandom.uuid
    entry = nil

    ActiveRecord::Base.transaction do
      position = QueueEntry.next_position_for(flash_sale)
      entry = flash_sale.queue_entries.create!(
        user_token: user_token,
        position: position,
        status: "waiting"
      )
    end

    MetricsCollector.increment("queue.joined")
    MetricsCollector.gauge("queue.depth.#{flash_sale.id}", flash_sale.waiting_count)

    # Kick off release loop if not already running.
    QueueReleaseJob.perform_async(flash_sale.id)

    InventoryChannel.broadcast_stock(flash_sale)
    QueueChannel.broadcast_to_user(entry)

    render json: {
      user_token: entry.user_token,
      position: entry.position,
      people_ahead: entry.people_ahead,
      status: entry.status,
      cable: {
        url: ENV.fetch("ACTION_CABLE_URL", "/cable"),
        channel: "QueueChannel",
        params: { user_token: entry.user_token }
      }
    }, status: :created
  end

  # GET /flash_sales/:flash_sale_id/queue/:user_token
  # Kept for compatibility; prefer Action Cable for live updates.
  def show
    entry = QueueEntry.find_by!(user_token: params[:user_token])

    if entry.expired?
      reservation = InventoryReservation.find_by(queue_entry_id: entry.id, status: "held")
      if reservation
        ReservationService.release_expired!(reservation)
        entry.reload
      else
        entry.update!(status: "expired")
        AdmissionControl.new(entry.flash_sale).release!
      end
    end

    render json: {
      status: entry.status,
      people_ahead: entry.people_ahead,
      position: entry.position,
      expires_at: entry.expires_at,
      admitted: entry.status == "active"
    }
  end
end
