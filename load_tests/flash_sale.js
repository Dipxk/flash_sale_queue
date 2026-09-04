import http from "k6/http";
import { check, sleep } from "k6";
import { Counter, Trend, Rate } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const VUS = Number(__ENV.VUS || 100);
const DURATION = __ENV.DURATION || "30s";

const checkoutsOk = new Counter("checkouts_ok");
const checkoutsFail = new Counter("checkouts_fail");
const rateLimited = new Counter("rate_limited");
const soldOutJoins = new Counter("sold_out_or_closed");
const queueWait = new Trend("queue_wait_ms");
const oversellSuspect = new Counter("oversell_suspect");
const dbErrors = new Counter("db_errors");
const joinSuccess = new Rate("join_success");

export const options = {
  scenarios: {
    flash_sale_spike: {
      executor: "per-vu-iterations",
      vus: VUS,
      iterations: 1,
      maxDuration: DURATION,
      gracefulStop: "30s",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.5"],
    http_req_duration: ["p(95)<20000"],
    checks: ["rate>0.9"],
  },
};

export function setup() {
  const stock = Number(__ENV.STOCK || Math.max(VUS, 100));
  const payload = JSON.stringify({
    flash_sale: {
      name: `Load Test ${Date.now()}`,
      starts_at: new Date(Date.now() - 60_000).toISOString(),
      ends_at: new Date(Date.now() + 60 * 60_000).toISOString(),
      total_stock: stock,
      max_concurrent_checkouts: Number(__ENV.MAX_CHECKOUTS || 50),
    },
  });

  const res = http.post(`${BASE_URL}/flash_sales`, payload, {
    headers: { "Content-Type": "application/json" },
  });

  check(res, { "sale created": (r) => r.status === 201 });
  if (res.status !== 201) {
    throw new Error(`Failed to create sale: ${res.status} ${res.body}`);
  }
  const body = res.json();
  return { saleId: body.id, stock: body.stock_remaining };
}

export default function (data) {
  const joinRes = http.post(`${BASE_URL}/flash_sales/${data.saleId}/queue`);
  if (joinRes.status === 429) {
    rateLimited.add(1);
    return;
  }
  if (joinRes.status === 422) {
    soldOutJoins.add(1);
    joinSuccess.add(false);
    return;
  }
  if (joinRes.status >= 500) {
    dbErrors.add(1);
    joinSuccess.add(false);
    return;
  }

  const ok = check(joinRes, { "joined queue": (r) => r.status === 201 });
  joinSuccess.add(ok);
  if (!ok) return;

  const token = joinRes.json("user_token");
  const started = Date.now();
  let admitted = false;

  for (let i = 0; i < 60; i++) {
    const statusRes = http.get(
      `${BASE_URL}/flash_sales/${data.saleId}/queue/${token}`
    );
    if (statusRes.status === 429) {
      rateLimited.add(1);
      sleep(0.25);
      continue;
    }
    if (statusRes.status >= 500) {
      dbErrors.add(1);
      break;
    }
    const status = statusRes.json("status");
    if (status === "active") {
      admitted = true;
      queueWait.add(Date.now() - started);
      break;
    }
    if (status === "expired" || status === "checked_out") break;
    sleep(0.2);
  }

  if (!admitted) return;

  const key = `${token}-checkout`;
  for (let attempt = 0; attempt < 2; attempt++) {
    const checkoutRes = http.post(
      `${BASE_URL}/flash_sales/${data.saleId}/checkout`,
      JSON.stringify({ user_token: token }),
      {
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": key,
          "X-User-Token": token,
        },
      }
    );

    if (checkoutRes.status === 429) {
      rateLimited.add(1);
    } else if (checkoutRes.status === 200) {
      checkoutsOk.add(1);
    } else if (checkoutRes.status >= 500) {
      dbErrors.add(1);
      checkoutsFail.add(1);
    } else {
      checkoutsFail.add(1);
    }
  }
}

export function teardown(data) {
  const res = http.get(`${BASE_URL}/flash_sales/${data.saleId}`);
  if (res.status === 200) {
    const stock = res.json("stock_remaining");
    console.log(`FINAL_STOCK=${stock}`);
    if (stock < 0) oversellSuspect.add(1);
  }

  const metrics = http.get(`${BASE_URL}/metrics`);
  if (metrics.status === 200) {
    console.log("METRICS_SNAPSHOT=" + metrics.body);
  }
}
