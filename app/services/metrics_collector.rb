# Redis-backed metrics for portfolio observability.
# Stores counters, gauges, and latency samples for percentile estimates.
class MetricsCollector
  LATENCY_KEY = "metrics:latency_ms"
  MAX_LATENCY_SAMPLES = 5_000

  class << self
    def increment(name, by: 1)
      AppRedis.with { |r| r.hincrby("metrics:counters", name, by) }
    rescue StandardError => e
      Rails.logger.warn("[Metrics] increment failed: #{e.message}")
    end

    def gauge(name, value)
      AppRedis.with { |r| r.hset("metrics:gauges", name, value) }
    rescue StandardError => e
      Rails.logger.warn("[Metrics] gauge failed: #{e.message}")
    end

    def observe_latency(ms)
      AppRedis.with do |r|
        r.lpush(LATENCY_KEY, ms.round(3))
        r.ltrim(LATENCY_KEY, 0, MAX_LATENCY_SAMPLES - 1)
      end
    rescue StandardError => e
      Rails.logger.warn("[Metrics] latency failed: #{e.message}")
    end

    def record_request
      increment("http.requests")
      # Per-second rough counter via incr + expire window
      bucket = Time.now.to_i
      AppRedis.with do |r|
        key = "metrics:rps:#{bucket}"
        r.incr(key)
        r.expire(key, 10)
      end
    rescue StandardError
      nil
    end

    def snapshot
      counters = AppRedis.with { |r| r.hgetall("metrics:counters") }
      gauges = AppRedis.with { |r| r.hgetall("metrics:gauges") }
      samples = AppRedis.with { |r| r.lrange(LATENCY_KEY, 0, -1) }.map(&:to_f).sort
      rps = current_rps

      {
        requests_per_second: rps,
        latency_ms: percentiles(samples),
        counters: counters.transform_values(&:to_i),
        gauges: gauges.transform_values { |v| numeric(v) },
        generated_at: Time.current.iso8601
      }
    end

    def prometheus_text
      data = snapshot
      lines = []
      lines << "# HELP flash_sale_requests_per_second Approximate RPS"
      lines << "# TYPE flash_sale_requests_per_second gauge"
      lines << "flash_sale_requests_per_second #{data[:requests_per_second]}"

      data[:latency_ms].each do |pct, val|
        lines << "# TYPE flash_sale_latency_ms gauge"
        lines << "flash_sale_latency_ms{quantile=\"#{pct}\"} #{val}"
      end

      data[:counters].each do |name, val|
        metric = sanitize(name)
        lines << "# TYPE flash_sale_#{metric} counter"
        lines << "flash_sale_#{metric} #{val}"
      end

      data[:gauges].each do |name, val|
        metric = sanitize(name)
        lines << "# TYPE flash_sale_#{metric} gauge"
        lines << "flash_sale_#{metric} #{val}"
      end

      lines.join("\n") + "\n"
    end

    def reset!
      AppRedis.with do |r|
        r.del("metrics:counters", "metrics:gauges", LATENCY_KEY)
      end
    end

    private

    def current_rps
      bucket = Time.now.to_i
      AppRedis.with { |r| r.get("metrics:rps:#{bucket}").to_i }
    end

    def percentiles(samples)
      return { p50: 0, p95: 0, p99: 0 } if samples.empty?

      {
        p50: percentile(samples, 0.50),
        p95: percentile(samples, 0.95),
        p99: percentile(samples, 0.99)
      }
    end

    def percentile(sorted, pct)
      idx = ((sorted.length - 1) * pct).round
      sorted[idx].round(3)
    end

    def numeric(value)
      Float(value)
    rescue ArgumentError, TypeError
      value
    end

    def sanitize(name)
      name.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
    end
  end
end
