class RequestMetricsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if env["PATH_INFO"].to_s.start_with?("/metrics")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    MetricsCollector.record_request

    status, headers, body = @app.call(env)
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
    MetricsCollector.observe_latency(elapsed_ms)
    MetricsCollector.increment("http.status.#{status}")

    [ status, headers, body ]
  rescue ActiveRecord::StatementInvalid
    MetricsCollector.increment("database.errors")
    raise
  end
end
