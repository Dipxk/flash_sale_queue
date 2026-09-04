require_relative "boot"
require_relative "../app/middleware/request_metrics_middleware"
require_relative "../app/middleware/rate_limit_middleware"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module FlashSaleQueueStarter
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true

    # Action Cable needs cookies/session middleware even in API mode for some
    # clients; we identify connections via user_token query param instead.
    config.action_cable.mount_path = "/cable"
    config.action_cable.disable_request_forgery_protection = true

    config.middleware.use Rack::Cors do
      allow do
        origins "*"
        resource "*",
                 headers: :any,
                 methods: %i[get post put patch delete options head],
                 expose: %w[X-RateLimit-Limit X-RateLimit-Remaining X-RateLimit-Reset Retry-After Idempotency-Replayed]
      end
    end

    config.middleware.use RequestMetricsMiddleware
    config.middleware.use RateLimitMiddleware

    config.x.rate_limit_per_minute = ENV.fetch("RATE_LIMIT_PER_MINUTE", "120").to_i
    config.x.reservation_ttl_seconds = ENV.fetch("RESERVATION_TTL_SECONDS", "120").to_i
    config.x.queue_release_interval_seconds = ENV.fetch("QUEUE_RELEASE_INTERVAL_SECONDS", "2").to_i
  end
end
