require "connection_pool"
require "redis"

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

REDIS_POOL = ConnectionPool.new(size: ENV.fetch("REDIS_POOL_SIZE", 25).to_i, timeout: 5) do
  Redis.new(url: redis_url, timeout: 1, reconnect_attempts: 2)
end

module AppRedis
  module_function

  def with(&block)
    REDIS_POOL.with(&block)
  end
end
