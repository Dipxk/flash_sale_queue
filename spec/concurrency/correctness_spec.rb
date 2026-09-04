require "rails_helper"

RSpec.describe "Concurrency correctness", type: :request do
  def join_queue(sale)
    post "/flash_sales/#{sale.id}/queue"
    expect(response).to have_http_status(:created)
    JSON.parse(response.body)
  end

  def checkout!(sale, user_token, key: SecureRandom.uuid)
    post "/flash_sales/#{sale.id}/checkout",
         params: { user_token: user_token },
         headers: { "Idempotency-Key" => key, "CONTENT_TYPE" => "application/json" },
         as: :json
    response
  end

  describe "stock never goes negative under contention" do
    it "allows at most total_stock successful checkouts" do
      sale = create(:flash_sale, total_stock: 5, stock_remaining: 5, max_concurrent_checkouts: 50)
      tokens = 20.times.map { join_queue(sale)["user_token"] }

      # Admit everyone possible
      5.times { QueueReleaseJob.new.perform(sale.id) }

      successes = Concurrent::AtomicFixnum? rescue nil
      success_count = 0
      mutex = Mutex.new

      threads = tokens.map do |token|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            res = checkout!(sale, token)
            mutex.synchronize { success_count += 1 } if res.status == 200
          end
        end
      end
      threads.each(&:join)

      sale.reload
      expect(sale.stock_remaining).to be >= 0
      expect(Order.where(flash_sale_id: sale.id).count).to eq(success_count)
      expect(success_count).to eq(5)
      expect(sale.stock_remaining).to eq(0)
    end
  end

  describe "final unit race" do
    it "lets only one of two concurrent checkouts claim the last unit" do
      sale = create(:flash_sale, total_stock: 1, stock_remaining: 1, max_concurrent_checkouts: 10)
      t1 = join_queue(sale)["user_token"]
      t2 = join_queue(sale)["user_token"]
      QueueReleaseJob.new.perform(sale.id)

      results = []
      mutex = Mutex.new
      threads = [ t1, t2 ].map do |token|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            res = checkout!(sale, token)
            mutex.synchronize { results << res.status }
          end
        end
      end
      threads.each(&:join)

      expect(results.count(200)).to eq(1)
      expect(Order.where(flash_sale_id: sale.id).count).to eq(1)
      expect(sale.reload.stock_remaining).to eq(0)
    end
  end

  describe "idempotent checkout" do
    it "does not create duplicate orders on retries" do
      sale = create(:flash_sale, total_stock: 3, stock_remaining: 3, max_concurrent_checkouts: 5)
      token = join_queue(sale)["user_token"]
      QueueReleaseJob.new.perform(sale.id)
      key = SecureRandom.uuid

      responses = 5.times.map { checkout!(sale, token, key: key) }

      expect(responses.map(&:status).uniq).to eq([ 200 ])
      expect(Order.where(flash_sale_id: sale.id).count).to eq(1)
      expect(responses.count { |r| r.headers["Idempotency-Replayed"] == "true" }).to be >= 1
    end
  end

  describe "reservation expiry" do
    it "returns inventory exactly once" do
      sale = create(:flash_sale, total_stock: 1, stock_remaining: 1, max_concurrent_checkouts: 5)
      token = join_queue(sale)["user_token"]
      QueueReleaseJob.new.perform(sale.id)

      reservation = InventoryReservation.find_by!(user_token: token, status: "held")
      expect(sale.reload.stock_remaining).to eq(0)

      reservation.update!(expires_at: 1.second.ago)

      released = 10.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ReservationService.release_expired!(reservation.reload)
          end
        end
      end.map(&:value)

      expect(released.count(true)).to eq(1)
      expect(sale.reload.stock_remaining).to eq(1)
      expect(reservation.reload.status).to eq("expired")
    end
  end

  describe "Sidekiq retry idempotency" do
    it "does not double-admit the same waiting user" do
      sale = create(:flash_sale, total_stock: 5, stock_remaining: 5, max_concurrent_checkouts: 2)
      5.times { join_queue(sale) }

      3.times { QueueReleaseJob.new.perform(sale.id) }

      active = sale.queue_entries.where(status: "active").count
      expect(active).to be <= 2
      expect(AdmissionControl.new(sale).active_count).to be <= 2
    end
  end

  describe "admission limits" do
    it "never admits more than max_concurrent_checkouts" do
      sale = create(:flash_sale, total_stock: 100, stock_remaining: 100, max_concurrent_checkouts: 3)
      20.times { join_queue(sale) }

      threads = 5.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            QueueReleaseJob.new.perform(sale.id)
          end
        end
      end
      threads.each(&:join)

      expect(sale.queue_entries.where(status: "active").count).to be <= 3
      expect(AdmissionControl.new(sale).active_count).to be <= 3
    end
  end
end
