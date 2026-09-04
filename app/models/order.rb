class Order < ApplicationRecord
  belongs_to :flash_sale
  belongs_to :queue_entry
  belongs_to :inventory_reservation

  validates :user_token, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[completed] }
end
