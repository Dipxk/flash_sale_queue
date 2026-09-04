import http from "k6/http";
import { check, sleep } from "k6";
import { Counter } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const finalUnitWins = new Counter("final_unit_wins");
const finalUnitLosses = new Counter("final_unit_losses");

export const options = {
  vus: Number(__ENV.VUS || 50),
  duration: "20s",
};

export function setup() {
  const payload = JSON.stringify({
    flash_sale: {
      name: `Final Unit ${Date.now()}`,
      starts_at: new Date(Date.now() - 60_000).toISOString(),
      ends_at: new Date(Date.now() + 60 * 60_000).toISOString(),
      total_stock: 1,
      max_concurrent_checkouts: Number(__ENV.VUS || 50),
    },
  });
  const res = http.post(`${BASE_URL}/flash_sales`, payload, {
    headers: { "Content-Type": "application/json" },
  });
  check(res, { created: (r) => r.status === 201 });
  return { saleId: res.json("id") };
}

export default function (data) {
  const join = http.post(`${BASE_URL}/flash_sales/${data.saleId}/queue`);
  if (join.status !== 201) {
    sleep(0.2);
    return;
  }
  const token = join.json("user_token");

  for (let i = 0; i < 30; i++) {
    const st = http.get(`${BASE_URL}/flash_sales/${data.saleId}/queue/${token}`);
    if (st.status === 200 && st.json("status") === "active") {
      const checkout = http.post(
        `${BASE_URL}/flash_sales/${data.saleId}/checkout`,
        JSON.stringify({ user_token: token }),
        {
          headers: {
            "Content-Type": "application/json",
            "Idempotency-Key": `${token}-final`,
          },
        }
      );
      if (checkout.status === 200) finalUnitWins.add(1);
      else finalUnitLosses.add(1);
      return;
    }
    sleep(0.2);
  }
}

export function teardown(data) {
  const res = http.get(`${BASE_URL}/flash_sales/${data.saleId}`);
  console.log(`FINAL_STOCK=${res.json("stock_remaining")}`);
  console.log(`FINAL_SALE=${JSON.stringify(res.json())}`);
}
