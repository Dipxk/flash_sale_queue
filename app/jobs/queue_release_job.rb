class QueueReleaseJob
  include Sidekiq::Job

  sidekiq_options queue: :critical, retry: 8, dead: true

  # Idempotent: Redis admission control + row status checks prevent double-admit.
  def perform(flash_sale_id)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    flash_sale = FlashSale.find_by(id: flash_sale_id)
    return unless flash_sale&.live?

    expire_stale_entries(flash_sale)

    admission = AdmissionControl.new(flash_sale)

    flash_sale.max_concurrent_checkouts.times do
      break unless flash_sale.reload.live?
      break unless admit_next!(flash_sale, admission)
    end

    MetricsCollector.gauge("queue.depth.#{flash_sale_id}", flash_sale.waiting_count)
    MetricsCollector.gauge("queue.active.#{flash_sale_id}", admission.active_count)

    if flash_sale.reload.live? && flash_sale.queue_entries.where(status: "waiting").exists?
      interval = Rails.configuration.x.queue_release_interval_seconds
      QueueReleaseJob.perform_in(interval.seconds, flash_sale_id)
    end
  ensure
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
    MetricsCollector.observe_latency(elapsed_ms)
    MetricsCollector.increment("sidekiq.queue_release.runs")
  end

  private

  def admit_next!(flash_sale, admission)
    entry = nil

    ActiveRecord::Base.transaction do
      entry = flash_sale.queue_entries
                        .where(status: "waiting")
                        .order(:position)
                        .lock("FOR UPDATE SKIP LOCKED")
                        .first
      return false unless entry

      # Mark as active only after Redis slot acquired (outside would race; do inside)
      unless admission.try_acquire!
        raise ActiveRecord::Rollback
      end

      entry.activate!
    end

    return false unless entry&.status == "active"

    reserve = ReservationService.new(flash_sale: flash_sale, queue_entry: entry).reserve!
    unless reserve.success?
      entry.update!(status: "expired")
      admission.release!
      return false
    end

    QueueChannel.broadcast_to_user(entry)
    MetricsCollector.increment("queue.admitted")
    true
  rescue StandardError
    admission.release! if entry&.status == "active"
    raise
  end

  def expire_stale_entries(flash_sale)
    stale = flash_sale.queue_entries
                      .where(status: "active")
                      .where("expires_at < ?", Time.current)

    stale.find_each do |entry|
      reservation = InventoryReservation.find_by(queue_entry_id: entry.id, status: "held")
      if reservation
        ReservationService.release_expired!(reservation)
      else
        entry.update!(status: "expired")
        AdmissionControl.new(flash_sale).release!
        QueueChannel.broadcast_to_user(entry)
      end
    end
  end
end
