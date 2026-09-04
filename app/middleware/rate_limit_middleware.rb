class RateLimitMiddleware
  def initialize(app)
    @app = app
    @limiter = RateLimiter.new
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return @app.call(env) if skip?(path)

    identity = client_identity(env)
    allowed, remaining, reset_at = @limiter.allow?(identity)
    limit = @limiter.limit

    if allowed
      status, headers, body = @app.call(env)
      headers = headers.merge(rate_headers(limit, remaining, reset_at))
      [ status, headers, body ]
    else
      MetricsCollector.increment("http.rate_limited")
      [
        429,
        rate_headers(limit, 0, reset_at).merge(
          "Content-Type" => "application/json",
          "Retry-After" => [ reset_at - Time.now.to_i, 1 ].max.to_s
        ),
        [ { error: "Rate limit exceeded" }.to_json ]
      ]
    end
  end

  private

  def skip?(path)
    path == "/up" || path.start_with?("/metrics") || path.start_with?("/sidekiq") || path.start_with?("/cable")
  end

  def client_identity(env)
    forwarded = env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip
    ip = forwarded.presence || env["REMOTE_ADDR"] || "unknown"
    token = env["HTTP_X_USER_TOKEN"].presence
    token ? "token:#{token}" : "ip:#{ip}"
  end

  def rate_headers(limit, remaining, reset_at)
    {
      "X-RateLimit-Limit" => limit.to_s,
      "X-RateLimit-Remaining" => remaining.to_s,
      "X-RateLimit-Reset" => reset_at.to_s
    }
  end
end
