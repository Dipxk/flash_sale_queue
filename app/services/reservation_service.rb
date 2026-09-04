# Holds inventory with TTL. Stock is decremented atomically on create and
# returned exactly once on expire/release via conditional UPDATEs.
class ReservationService
  Result = Struct.new(:success?, :reservation, :error, keyword_init: true)

  def initialize(flash_sale:, queue_entry:)
    @flash_sale = flash_sale
    @queue_entry = queue_entry
    @ttl = Rails.configuration.x.reservation_ttl_seconds.seconds
  end

  def reserve!
    existing = InventoryReservation.find_by(queue_entry_id: @queue_entry.id, status: "held")
    return Result.new(success?: true, reservation: existing) if existing

    reserved = @flash_sale.reserve_unit!
    unless reserved
      MetricsCollector.increment("reservation.failure")
      return Result.new(success?: false, error: "sold_out")
    end

    reservation = InventoryReservation.create!(
      flash_sale: @flash_sale,
      queue_entry: @queue_entry,
      user_token: @queue_entry.user_token,
      status: "held",
      expires_at: Time.current + @ttl
    )

    ReservationExpiryJob.perform_in(@ttl + 1.second, reservation.id)
    MetricsCollector.increment("reservation.success")
    InventoryChannel.broadcast_stock(@flash_sale)

    Result.new(success?: true, reservation: reservation)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent create for same queue_entry — return the winner
    existing = InventoryReservation.find_by!(queue_entry_id: @queue_entry.id, status: "held")
    Result.new(success?: true, reservation: existing)
  end

  def self.release_expired!(reservation)
    return false unless reservation.status == "held"
    return false if reservation.expires_at > Time.current

    released = false
    ActiveRecord::Base.transaction do
      locked = InventoryReservation.lock.find_by(id: reservation.id, status: "held")
      next unless locked
      next if locked.expires_at > Time.current

      restored = FlashSale.where(id: locked.flash_sale_id)
                          .where("stock_remaining < total_stock")
                          .update_all("stock_remaining = stock_remaining + 1")

      if restored == 1
        locked.update!(status: "expired", released_at: Time.current, release_reason: "ttl_expired")
        released = true
      else
        # Safety: if we somehow can't restore, still mark expired to avoid double-release loops
        locked.update!(status: "expired", released_at: Time.current, release_reason: "ttl_expired_no_restore")
        MetricsCollector.increment("reservation.restore_skipped")
        released = true
      end
    end

    if released
      MetricsCollector.increment("reservation.expired")
      sale = reservation.flash_sale
      AdmissionControl.new(sale).release!
      entry = reservation.queue_entry
      if entry.status == "active"
        entry.update!(status: "expired")
      end
      InventoryChannel.broadcast_stock(sale)
      QueueChannel.broadcast_to_user(entry)
    end

    released
  end

  def self.confirm!(reservation)
    reservation.update!(status: "confirmed", released_at: Time.current, release_reason: "checkout")
  end
end
