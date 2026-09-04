# THRESHOLD — Flash Sale Virtual Waiting Room

Production-oriented Rails API + live UI for high-demand flash sales:
shoppers enter a queue, get admitted under Redis concurrency limits, hold
expiring inventory reservations, and check out idempotently — without overselling.

## Stack

- Ruby on Rails 8 (API + Action Cable + static UI)
- PostgreSQL (atomic stock updates + check constraints)
- Redis (admission control, rate limiting, metrics, Action Cable)
- Sidekiq (queue release + reservation expiry)
- Docker Compose (local)
- k6 load tests

## Quick start (Docker)

```bash
docker compose up --build
```

Open **http://localhost:3000** for the UI.

Useful endpoints:

| Path | Purpose |
|------|---------|
| `/` | Waiting-room UI |
| `/up` | Health check |
| `/metrics` | JSON metrics |
| `/sidekiq` | Sidekiq Web (dev) |

## API flow

```bash
# Create a sale
curl -s -X POST http://localhost:3000/flash_sales \
  -H 'Content-Type: application/json' \
  -d '{"flash_sale":{"name":"Drop","starts_at":"2026-09-01T00:00:00Z","ends_at":"2026-12-01T00:00:00Z","total_stock":10,"max_concurrent_checkouts":3}}'

# Join queue
curl -s -X POST http://localhost:3000/flash_sales/1/queue

# Poll status
curl -s http://localhost:3000/flash_sales/1/queue/USER_TOKEN

# Checkout (Idempotency-Key required)
curl -s -X POST http://localhost:3000/flash_sales/1/checkout \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: demo-1' \
  -d '{"user_token":"USER_TOKEN"}'
```

## Tests

```bash
docker compose exec -e RAILS_ENV=test \
  -e DATABASE_URL=postgres://flash_sale:flash_sale@db:5432/flash_sale_queue_test \
  -e REDIS_URL=redis://redis:6379/15 \
  -e RATE_LIMIT_PER_MINUTE=100000 \
  web bash -c "bundle exec rails db:prepare && bundle exec rspec"
```

## Load tests

```bash
./load_tests/run.sh
# Optional 10k VU run:
RUN_10K=1 ./load_tests/run.sh
```

### Measured results (local Docker, macOS)

**Smoke — 50 VUs, stock 50**
- Join success: 100%
- Throughput: ~91 req/s
- p95 latency: ~856 ms
- HTTP failures: 0%
- Successful checkouts (incl. idempotent retries): 100
- Final stock: 0

**Spike — 1,000 VUs, stock 200**
- Join success: 100% (1000/1000)
- Throughput: ~150 req/s
- p95 latency: ~9.3 s (includes queue wait under capped concurrent checkouts)
- HTTP failures: 0%
- Successful checkouts (incl. idempotent retries): 400
- Final stock: 0 (no oversell)

5,000 VU runs saturated the local Docker host (connection timeouts) — use a larger machine or hosted environment for that tier.

## Architecture

```
Browser UI ──HTTP──► Rails API ──SQL──► PostgreSQL
    │                    │
    └──Action Cable──────┤
                         ├──Redis (admission / rate limit / metrics / cable)
                         └──Sidekiq workers (admit + expire reservations)
```

### Concurrency strategy

1. **Queue admission** — Redis Lua `GET`+`INCR` so workers cannot over-admit past `max_concurrent_checkouts`
2. **Inventory** — conditional `UPDATE … WHERE stock_remaining > 0` plus DB check constraints
3. **Reservations** — TTL-backed holds; Sidekiq releases stock exactly once on expiry
4. **Checkout** — required `Idempotency-Key`; unique indexes on orders prevent duplicates
5. **Rate limiting** — Redis sliding window; `429` + `Retry-After` / `X-RateLimit-*` headers

## Hosting (Fly.io)

```bash
fly apps create flash-sale-queue
fly postgres create --name flash-sale-queue-db --region iad
fly postgres attach flash-sale-queue-db -a flash-sale-queue
fly redis create --name flash-sale-queue-redis --region iad
fly secrets set RAILS_MASTER_KEY="$(cat config/master.key)" -a flash-sale-queue
# Also set REDIS_URL from the redis create output if not auto-attached
fly deploy
```

App URL: `https://flash-sale-queue.fly.dev`

## Resume bullets (measured)

- Built a Rails flash-sale waiting room with Redis Lua admission control, Sidekiq-backed expiring inventory reservations, and idempotent checkout; concurrency tests verified no oversell.
- Load-tested with k6 at 1,000 concurrent users: 100% queue-join success, ~150 req/s, 0% HTTP failures, and checkouts capped to stock under atomic PostgreSQL reservations.
