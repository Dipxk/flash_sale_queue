class InventoryReservation < ApplicationRecord
  belongs_to :flash_sale
  belongs_to :queue_entry
  has_one :order, dependent: :restrict_with_exception

  validates :user_token, presence: true
  validates :status, inclusion: { in: %w[held confirmed released expired] }
  validates :expires_at, presence: true

  def expired?
    status == "held" && Time.current > expires_at
  end

  def held?
    status == "held"
  end
end
