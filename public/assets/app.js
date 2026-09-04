import { createConsumer } from "https://esm.sh/@rails/actioncable@8.0.200";

const API = "";
const params = new URLSearchParams(window.location.search);
const SALE_KEY = "threshold_sale_id";
const TOKEN_KEY = "threshold_user_token";

const els = {
  stockMeta: document.getElementById("stockMeta"),
  joinBtn: document.getElementById("joinBtn"),
  newSaleBtn: document.getElementById("newSaleBtn"),
  joinHint: document.getElementById("joinHint"),
  peopleAhead: document.getElementById("peopleAhead"),
  queueCopy: document.getElementById("queueCopy"),
  statusValue: document.getElementById("statusValue"),
  positionValue: document.getElementById("positionValue"),
  tokenValue: document.getElementById("tokenValue"),
  checkoutBtn: document.getElementById("checkoutBtn"),
  checkoutHint: document.getElementById("checkoutHint"),
  expiresAt: document.getElementById("expiresAt"),
  doneEyebrow: document.getElementById("doneEyebrow"),
  doneTitle: document.getElementById("doneTitle"),
  doneCopy: document.getElementById("doneCopy"),
  againBtn: document.getElementById("againBtn"),
  liveDot: document.getElementById("liveDot"),
  stages: {
    join: document.getElementById("stageJoin"),
    queue: document.getElementById("stageQueue"),
    checkout: document.getElementById("stageCheckout"),
    done: document.getElementById("stageDone"),
  },
};

let sale = null;
let userToken = localStorage.getItem(TOKEN_KEY);
let consumer = null;
let queueSub = null;
let inventorySub = null;
let pollTimer = null;

function show(stage) {
  Object.values(els.stages).forEach((node) => node.setAttribute("data-active", "false"));
  els.stages[stage].setAttribute("data-active", "true");
}

function setBusy(btn, busy, label) {
  btn.disabled = busy;
  if (label) btn.textContent = label;
}

async function api(path, options = {}) {
  const res = await fetch(`${API}${path}`, {
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { error: text };
  }
  return { ok: res.ok, status: res.status, body, headers: res.headers };
}

function updateStockMeta(data) {
  if (!data) return;
  els.stockMeta.textContent = `${data.name} · ${data.stock_remaining}/${data.total_stock} left · ${data.waiting || 0} waiting`;
}

async function createSale() {
  const now = new Date();
  const ends = new Date(now.getTime() + 60 * 60 * 1000);
  const { ok, body } = await api("/flash_sales", {
    method: "POST",
    body: JSON.stringify({
      flash_sale: {
        name: `Drop ${now.toLocaleTimeString()}`,
        starts_at: new Date(now.getTime() - 60_000).toISOString(),
        ends_at: ends.toISOString(),
        total_stock: 10,
        max_concurrent_checkouts: 3,
      },
    }),
  });
  if (!ok) throw new Error(body?.error || "Could not create sale");
  localStorage.setItem(SALE_KEY, String(body.id));
  return loadSale(body.id);
}

async function loadSale(id) {
  const { ok, body } = await api(`/flash_sales/${id}`);
  if (!ok) return null;
  sale = body;
  updateStockMeta(sale);
  connectInventory(sale.id);
  return sale;
}

async function ensureSale() {
  const forced = params.get("sale");
  const stored = forced || localStorage.getItem(SALE_KEY);
  if (stored) {
    const existing = await loadSale(stored);
    if (existing?.live) return existing;
  }
  return createSale();
}

function disconnectCable() {
  queueSub?.unsubscribe();
  inventorySub?.unsubscribe();
  queueSub = null;
  inventorySub = null;
  consumer?.disconnect();
  consumer = null;
  els.liveDot.classList.remove("on");
}

function connectInventory(saleId) {
  if (!consumer) {
    consumer = createConsumer(`${cableUrl()}?user_token=${encodeURIComponent(userToken || "spectator")}`);
  }
  inventorySub?.unsubscribe();
  inventorySub = consumer.subscriptions.create(
    { channel: "InventoryChannel", flash_sale_id: saleId },
    {
      connected: () => els.liveDot.classList.add("on"),
      disconnected: () => els.liveDot.classList.remove("on"),
      received: (data) => {
        if (sale) {
          sale.stock_remaining = data.stock_remaining;
          sale.waiting = data.waiting;
          sale.live = data.live;
          updateStockMeta({ ...sale, ...data, name: sale.name, total_stock: sale.total_stock });
        }
      },
    }
  );
}

function cableUrl() {
  const proto = window.location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${window.location.host}/cable`;
}

function connectQueue(token) {
  if (!consumer) {
    consumer = createConsumer(`${cableUrl()}?user_token=${encodeURIComponent(token)}`);
  } else {
    // reconnect with identity token
    disconnectCable();
    consumer = createConsumer(`${cableUrl()}?user_token=${encodeURIComponent(token)}`);
    if (sale) connectInventory(sale.id);
  }

  queueSub?.unsubscribe();
  queueSub = consumer.subscriptions.create(
    { channel: "QueueChannel" },
    {
      connected: () => els.liveDot.classList.add("on"),
      received: (data) => applyQueueUpdate(data),
    }
  );
}

function applyQueueUpdate(data) {
  els.statusValue.textContent = data.status;
  els.positionValue.textContent = data.position ?? "—";
  els.tokenValue.textContent = data.user_token || userToken || "—";
  els.peopleAhead.textContent = String(data.people_ahead ?? "—");

  if (data.status === "waiting") {
    const n = data.people_ahead ?? 0;
    els.queueCopy.textContent =
      n === 0
        ? "You’re next. Admission opens as soon as a checkout slot frees up."
        : `${n} people ahead of you. Hang tight — we’ll push you through when a slot opens.`;
    show("queue");
  } else if (data.status === "active") {
    if (data.expires_at) {
      const exp = new Date(data.expires_at);
      els.expiresAt.textContent = `Reservation holds until ${exp.toLocaleTimeString()}`;
    }
    show("checkout");
  } else if (data.status === "checked_out") {
    els.doneEyebrow.textContent = "Order placed";
    els.doneTitle.textContent = "You’re in.";
    els.doneCopy.textContent = "Checkout completed. Inventory was reserved atomically — no oversell.";
    show("done");
    stopPolling();
  } else if (data.status === "expired") {
    els.doneEyebrow.textContent = "Slot expired";
    els.doneTitle.textContent = "Time’s up.";
    els.doneCopy.textContent = "Your checkout window expired and inventory was released back to the pool.";
    show("done");
    stopPolling();
  }
}

function startPolling(token) {
  stopPolling();
  pollTimer = setInterval(async () => {
    if (!sale) return;
    const { ok, body } = await api(`/flash_sales/${sale.id}/queue/${token}`);
    if (ok) applyQueueUpdate({ ...body, user_token: token, position: body.position });
  }, 2500);
}

function stopPolling() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
}

async function joinQueue() {
  els.joinHint.textContent = "";
  setBusy(els.joinBtn, true, "Joining…");
  try {
    await ensureSale();
    const { ok, body, status } = await api(`/flash_sales/${sale.id}/queue`, { method: "POST" });
    if (!ok) {
      els.joinHint.textContent = body?.error || `Could not join (${status})`;
      return;
    }
    userToken = body.user_token;
    localStorage.setItem(TOKEN_KEY, userToken);
    applyQueueUpdate(body);
    connectQueue(userToken);
    startPolling(userToken);
  } catch (err) {
    els.joinHint.textContent = err.message;
  } finally {
    setBusy(els.joinBtn, false, "Enter the queue");
  }
}

async function checkout() {
  els.checkoutHint.textContent = "";
  setBusy(els.checkoutBtn, true, "Placing order…");
  try {
    const key = `${userToken}-web-${Date.now()}`;
    const { ok, body, status } = await api(`/flash_sales/${sale.id}/checkout`, {
      method: "POST",
      headers: {
        "Idempotency-Key": key,
        "X-User-Token": userToken,
      },
      body: JSON.stringify({ user_token: userToken }),
    });
    if (!ok) {
      els.checkoutHint.textContent = body?.error || `Checkout failed (${status})`;
      return;
    }
    applyQueueUpdate({ status: "checked_out", people_ahead: 0, user_token: userToken });
  } catch (err) {
    els.checkoutHint.textContent = err.message;
  } finally {
    setBusy(els.checkoutBtn, false, "Place order");
  }
}

async function resumeIfPossible() {
  await ensureSale();
  if (!userToken || !sale) {
    show("join");
    return;
  }
  const { ok, body } = await api(`/flash_sales/${sale.id}/queue/${userToken}`);
  if (!ok) {
    localStorage.removeItem(TOKEN_KEY);
    userToken = null;
    show("join");
    return;
  }
  applyQueueUpdate({ ...body, user_token: userToken });
  if (body.status === "waiting" || body.status === "active") {
    connectQueue(userToken);
    startPolling(userToken);
  }
}

els.joinBtn.addEventListener("click", joinQueue);
els.checkoutBtn.addEventListener("click", checkout);
els.newSaleBtn.addEventListener("click", async () => {
  localStorage.removeItem(TOKEN_KEY);
  userToken = null;
  stopPolling();
  disconnectCable();
  setBusy(els.newSaleBtn, true, "Creating…");
  try {
    await createSale();
    show("join");
  } catch (err) {
    els.joinHint.textContent = err.message;
  } finally {
    setBusy(els.newSaleBtn, false, "Start a new drop");
  }
});
els.againBtn.addEventListener("click", async () => {
  localStorage.removeItem(TOKEN_KEY);
  userToken = null;
  stopPolling();
  disconnectCable();
  await createSale();
  show("join");
});

resumeIfPossible().catch((err) => {
  els.joinHint.textContent = err.message;
  show("join");
});
