# Atomic Redis admission control for concurrent checkout slots.
#
# Uses a Lua script so CHECK + INCR cannot race across Sidekiq workers.
# Slots are released explicitly on checkout, expiry, or reservation release.
class AdmissionControl
  ACQUIRE_LUA = <<~LUA
    local key = KEYS[1]
    local max = tonumber(ARGV[1])
    local current = tonumber(redis.call('GET', key) or '0')
    if current < max then
      return redis.call('INCR', key)
    end
    return 0
  LUA

  RELEASE_LUA = <<~LUA
    local key = KEYS[1]
    local current = tonumber(redis.call('GET', key) or '0')
    if current > 0 then
      return redis.call('DECR', key)
    end
    redis.call('SET', key, 0)
    return 0
  LUA

  def initialize(flash_sale)
    @flash_sale = flash_sale
  end

  def key
    "flash_sale:#{@flash_sale.id}:active_checkouts"
  end

  def try_acquire!
    result = AppRedis.with do |redis|
      redis.eval(ACQUIRE_LUA, keys: [key], argv: [@flash_sale.max_concurrent_checkouts])
    end
    acquired = result.to_i > 0
    MetricsCollector.increment(acquired ? "admission.acquired" : "admission.rejected")
    acquired
  end

  def release!
    AppRedis.with do |redis|
      redis.eval(RELEASE_LUA, keys: [key])
    end
    MetricsCollector.increment("admission.released")
  end

  def active_count
    AppRedis.with { |r| r.get(key).to_i }
  end

  def sync_from_db!
    count = @flash_sale.queue_entries.where(status: "active").count
    AppRedis.with { |r| r.set(key, count) }
    count
  end

  def reset!
    AppRedis.with { |r| r.del(key) }
  end
end
