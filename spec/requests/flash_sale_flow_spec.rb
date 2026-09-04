require "rails_helper"

RSpec.describe "Flash sale API", type: :request do
  it "creates a sale, joins queue, admits, and checks out" do
    post "/flash_sales", params: {
      flash_sale: {
        name: "Drop",
        starts_at: 1.minute.ago,
        ends_at: 1.hour.from_now,
        total_stock: 2,
        max_concurrent_checkouts: 2
      }
    }, as: :json
    expect(response).to have_http_status(:created)
    sale_id = JSON.parse(response.body)["id"]

    post "/flash_sales/#{sale_id}/queue", as: :json
    body = JSON.parse(response.body)
    token = body["user_token"]
    expect(token).to be_present

    QueueReleaseJob.new.perform(sale_id)

    get "/flash_sales/#{sale_id}/queue/#{token}"
    expect(JSON.parse(response.body)["status"]).to eq("active")

    post "/flash_sales/#{sale_id}/checkout",
         params: { user_token: token },
         headers: { "Idempotency-Key" => SecureRandom.uuid },
         as: :json
    expect(response).to have_http_status(:ok)

    get "/metrics"
    expect(response).to have_http_status(:ok)
    metrics = JSON.parse(response.body)
    expect(metrics).to have_key("latency_ms")
    expect(metrics).to have_key("counters")
  end

  it "rate limits excessive traffic" do
    allow(Rails.configuration.x).to receive(:rate_limit_per_minute).and_return(5)
    sale = create(:flash_sale)

    statuses = 20.times.map do
      get "/flash_sales/#{sale.id}"
      response.status
    end

    expect(statuses).to include(429)
  end
end
