FactoryBot.define do
  factory :flash_sale do
    name { "Limited Drop" }
    starts_at { 1.minute.ago }
    ends_at { 1.hour.from_now }
    total_stock { 10 }
    stock_remaining { 10 }
    max_concurrent_checkouts { 3 }
  end

  factory :queue_entry do
    flash_sale
    user_token { SecureRandom.uuid }
    sequence(:position) { |n| n }
    status { "waiting" }
  end

  factory :inventory_reservation do
    flash_sale
    queue_entry
    user_token { queue_entry.user_token }
    status { "held" }
    expires_at { 2.minutes.from_now }
  end

  factory :order do
    flash_sale
    queue_entry
    inventory_reservation
    user_token { queue_entry.user_token }
    idempotency_key { SecureRandom.uuid }
    status { "completed" }
  end
end
