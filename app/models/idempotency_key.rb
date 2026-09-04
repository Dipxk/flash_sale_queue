class IdempotencyKey < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :request_path, :request_fingerprint, presence: true
end
