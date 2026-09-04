class MetricsController < ApplicationController
  def show
    # Refresh live gauges from DB for dashboard consumers
    FlashSale.find_each do |sale|
      MetricsCollector.gauge("queue.depth.#{sale.id}", sale.waiting_count)
      MetricsCollector.gauge("queue.active.#{sale.id}", sale.active_checkout_count)
      MetricsCollector.gauge("stock.remaining.#{sale.id}", sale.stock_remaining)
    end

    render json: MetricsCollector.snapshot
  end

  def prometheus
    render plain: MetricsCollector.prometheus_text, content_type: "text/plain; version=0.0.4"
  end
end
