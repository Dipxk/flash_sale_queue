class FlashSale < ApplicationRecord
  has_many :queue_entries, dependent: :destroy

  validates :name, presence: true
  validates :total_stock, :stock_remaining, :max_concurrent_checkouts,
            numericality: { greater_than_or_equal_to: 0 }
  validate :ends_at_after_starts_at

  def live?
    now = Time.current
    now >= starts_at && now <= ends_at && stock_remaining > 0
  end

  def active_checkout_count
    queue_entries.where(status: "active").count
  end

  def capacity_available?
    active_checkout_count < max_concurrent_checkouts
  end

  # Atomically decrements stock so two concurrent checkouts can never both
  # succeed when only one unit is left. Uses a conditional UPDATE at the
  # database level instead of read-then-write in Ruby, which would race.
  #
  # Returns true if a unit was successfully reserved, false if sold out.
  def reserve_unit!
    updated_rows = FlashSale.where(id: id)
                            .where("stock_remaining > 0")
                            .update_all("stock_remaining = stock_remaining - 1")
    updated_rows > 0
  end

  private

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, "must be after starts_at") if ends_at <= starts_at
  end
end
