require "sidekiq"
require "sidekiq/web"

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  config.death_handlers << ->(job, ex) do
    Rails.logger.error(
      "[SidekiqDead] class=#{job['class']} jid=#{job['jid']} args=#{job['args']} error=#{ex.class}: #{ex.message}"
    )
    MetricsCollector.increment("sidekiq.dead_jobs")
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
