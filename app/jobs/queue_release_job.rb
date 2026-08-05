class QueueReleaseJob
  include Sidekiq::Job

  # Run this job on a schedule (every 5-10 seconds) via sidekiq-cron,
  # or simply re-enqueue itself at the end of perform for a simple loop.
  def perform(flash_sale_id)
    flash_sale = FlashSale.find_by(id: flash_sale_id)
    return unless flash_sale&.live?

    expire_stale_entries(flash_sale)

    slots_open = flash_sale.max_concurrent_checkouts - flash_sale.active_checkout_count
    return if slots_open <= 0

    next_in_line = flash_sale.queue_entries
                              .where(status: "waiting")
                              .order(:position)
                              .limit(slots_open)

    next_in_line.each(&:activate!)

    # Re-enqueue so this keeps running while the sale is live.
    # In production, prefer sidekiq-cron over self-requeueing.
    QueueReleaseJob.perform_in(5.seconds, flash_sale_id) if flash_sale.reload.live?
  end

  private

  def expire_stale_entries(flash_sale)
    flash_sale.queue_entries
              .where(status: "active")
              .where("expires_at < ?", Time.current)
              .update_all(status: "expired")
  end
end
