class ReservationExpiryJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 10, dead: true

  # Idempotent: only held + past-expiry reservations are released, exactly once.
  def perform(reservation_id)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    reservation = InventoryReservation.find_by(id: reservation_id)
    return unless reservation
    return unless reservation.status == "held"

    if reservation.expires_at > Time.current
      # Woke up early — reschedule
      delay = [ (reservation.expires_at - Time.current).ceil, 1 ].max
      ReservationExpiryJob.perform_in(delay.seconds, reservation_id)
      return
    end

    ReservationService.release_expired!(reservation)
  ensure
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
    MetricsCollector.increment("sidekiq.reservation_expiry.runs")
    MetricsCollector.observe_latency(elapsed_ms)
  end
end
