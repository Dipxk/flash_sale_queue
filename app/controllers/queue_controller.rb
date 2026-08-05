class QueueController < ApplicationController
  # POST /flash_sales/:flash_sale_id/queue
  # Joins the queue for a flash sale. Returns a user_token the client must
  # save (e.g. in localStorage) to poll their status afterward.
  def create
    flash_sale = FlashSale.find(params[:flash_sale_id])

    unless flash_sale.live?
      return render json: { error: "Sale is not currently live" }, status: :unprocessable_entity
    end

    user_token = SecureRandom.uuid
    entry = flash_sale.queue_entries.create!(
      user_token: user_token,
      position: QueueEntry.next_position_for(flash_sale),
      status: "waiting"
    )

    # Kick off the release job the first time someone joins an empty queue,
    # so it starts polling/releasing without waiting on a cron tick.
    QueueReleaseJob.perform_async(flash_sale.id) if flash_sale.queue_entries.count == 1

    render json: {
      user_token: entry.user_token,
      position: entry.position,
      people_ahead: entry.people_ahead
    }, status: :created
  end

  # GET /flash_sales/:flash_sale_id/queue/:user_token
  # Client polls this to find out if they've been let through yet.
  def show
    entry = QueueEntry.find_by!(user_token: params[:user_token])

    if entry.expired?
      entry.update!(status: "expired")
    end

    render json: {
      status: entry.status,
      people_ahead: entry.people_ahead,
      expires_at: entry.expires_at
    }
  end
end
