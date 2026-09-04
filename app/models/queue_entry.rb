class QueueEntry < ApplicationRecord
  belongs_to :flash_sale
  has_one :inventory_reservation, dependent: :destroy
  has_one :order, dependent: :nullify

  validates :user_token, presence: true, uniqueness: true
  validates :position, presence: true
  validates :status, inclusion: { in: %w[waiting active checked_out expired] }

  ACTIVE_WINDOW_SECONDS = ENV.fetch("RESERVATION_TTL_SECONDS", "120").to_i

  def self.next_position_for(flash_sale)
    # Advisory lock per sale so concurrent joins cannot get the same position
    FlashSale.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)", flash_sale.id ])
    )
    max_position = flash_sale.queue_entries.maximum(:position) || 0
    max_position + 1
  end

  def activate!
    update!(
      status: "active",
      activated_at: Time.current,
      expires_at: Time.current + ACTIVE_WINDOW_SECONDS.seconds
    )
  end

  def expired?
    status == "active" && expires_at.present? && Time.current > expires_at
  end

  def people_ahead
    return 0 unless status == "waiting"

    flash_sale.queue_entries
              .where(status: "waiting")
              .where("position < ?", position)
              .count
  end
end
