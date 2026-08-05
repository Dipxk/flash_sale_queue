# Flash Sale Queue System

Rails API that implements a virtual waiting room for flash sales: users join a queue and are released into checkout in controlled batches, with atomic stock reservation to prevent overselling.

## Running locally

**Prerequisites already set up on this machine:**
- Ruby 3.2.3 via [mise](https://mise.jdx.dev) (`eval "$(mise activate zsh)"`)
- PostgreSQL + Redis via Docker (`flash_sale_pg`, `flash_sale_redis`)

```bash
# Ensure Docker services are up
docker start flash_sale_pg flash_sale_redis

# Terminal 1 — Sidekiq
bundle exec sidekiq

# Terminal 2 — Rails
bin/rails server
```

Visit http://localhost:3000 — API only (test with curl / Postman). Sidekiq Web UI: http://localhost:3000/sidekiq

## End-to-end test

```bash
# Create a sale
bin/rails runner 'FlashSale.create!(name: "Limited Drop", starts_at: Time.current, ends_at: Time.current + 1.hour, total_stock: 5, stock_remaining: 5, max_concurrent_checkouts: 2)'

# Join queue
curl -X POST http://localhost:3000/flash_sales/1/queue

# Poll status (use returned user_token)
curl http://localhost:3000/flash_sales/1/queue/<user_token>

# Checkout once status is "active"
curl -X POST http://localhost:3000/flash_sales/1/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_token": "<user_token>"}'
```

With `max_concurrent_checkouts: 2`, a 3rd joiner stays `"waiting"` until a slot frees (checkout or 2-minute expiry).
