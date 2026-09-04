# Sliding-window rate limiter backed by Redis sorted sets.
class RateLimiter
  def initialize(limit: nil, window_seconds: 60)
    @limit_override = limit
    @window = window_seconds
  end

  def limit
    @limit_override || Rails.configuration.x.rate_limit_per_minute
  end

  # Returns [allowed?, remaining, reset_at]
  def allow?(identity)
    now = Time.now.to_f
    window_start = now - @window
    key = "rate_limit:#{identity}"
    member = "#{now}:#{SecureRandom.hex(4)}"
    current_limit = limit

    count = AppRedis.with do |redis|
      redis.zremrangebyscore(key, "-inf", window_start)
      redis.zadd(key, now, member)
      card = redis.zcard(key)
      redis.expire(key, @window.ceil + 1)
      card
    end

    reset_at = (now + @window).to_i

    if count <= current_limit
      remaining = current_limit - count
      [ true, remaining, reset_at ]
    else
      AppRedis.with { |r| r.zrem(key, member) }
      MetricsCollector.increment("rate_limit.rejected")
      [ false, 0, reset_at ]
    end
  end
end
