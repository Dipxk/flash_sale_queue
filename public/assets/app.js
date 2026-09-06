import { createConsumer } from "https://esm.sh/@rails/actioncable@8.0.200";

const API = "";
const params = new URLSearchParams(window.location.search);
const SALE_KEY = "threshold_sale_id";
const TOKEN_KEY = "threshold_user_token";
const IDEM_KEY = "threshold_idempotency_key";

const els = {
  stockMeta: document.getElementById("stockMeta"),
  livePill: document.getElementById("livePill"),
  liveDot: document.getElementById("liveDot"),
  joinBtn: document.getElementById("joinBtn"),
  crowdBtn: document.getElementById("crowdBtn"),
  crowdMoreBtn: document.getElementById("crowdMoreBtn"),
  newSaleBtn: document.getElementById("newSaleBtn"),
  joinHint: document.getElementById("joinHint"),
  joinCoach: document.getElementById("joinCoach"),
  peopleAhead: document.getElementById("peopleAhead"),
  queueCopy: document.getElementById("queueCopy"),
  statusValue: document.getElementById("statusValue"),
  positionValue: document.getElementById("positionValue"),
  nextValue: document.getElementById("nextValue"),
  lineViz: document.getElementById("lineViz"),
  maxSlotsLabel: document.getElementById("maxSlotsLabel"),
  checkoutBtn: document.getElementById("checkoutBtn"),
  dupCheckoutBtn: document.getElementById("dupCheckoutBtn"),
  checkoutHint: document.getElementById("checkoutHint"),
  expiresAt: document.getElementById("expiresAt"),
  doneEyebrow: document.getElementById("doneEyebrow"),
  doneTitle: document.getElementById("doneTitle"),
  doneCopy: document.getElementById("doneCopy"),
  againBtn: document.getElementById("againBtn"),
  boardStock: document.getElementById("boardStock"),
  boardWaiting: document.getElementById("boardWaiting"),
  boardActive: document.getElementById("boardActive"),
  barStock: document.getElementById("barStock"),
  barWaiting: document.getElementById("barWaiting"),
  barActive: document.getElementById("barActive"),
  activityFeed: document.getElementById("activityFeed"),
  journeySteps: [...document.querySelectorAll(".journey-step")],
  stages: {
    join: document.getElementById("stageJoin"),
    queue: document.getElementById("stageQueue"),
    checkout: document.getElementById("stageCheckout"),
    done: document.getElementById("stageDone"),
  },
};

let sale = null;
let userToken = localStorage.getItem(TOKEN_KEY);
let lastIdempotencyKey = localStorage.getItem(IDEM_KEY);
let consumer = null;
let queueSub = null;
let inventorySub = null;
let pollTimer = null;
let boardTimer = null;

function show(stage) {
  Object.values(els.stages).forEach((node) => node.setAttribute("data-active", "false"));
  els.stages[stage].setAttribute("data-active", "true");
  updateJourney(stage);
}

function updateJourney(stage) {
  const order = ["join", "queue", "checkout", "done"];
  const idx = order.indexOf(stage);
  els.journeySteps.forEach((btn) => {
    const step = btn.dataset.step;
    const stepIdx = order.indexOf(step);
    btn.dataset.active = String(step === stage);
    btn.dataset.done = String(stepIdx < idx);
    btn.disabled = stepIdx > idx;
  });
}

function setBusy(btn, busy, label) {
  if (!btn) return;
  btn.disabled = busy;
  if (label) btn.textContent = label;
}

function logActivity(message, emphasize = null) {
  const li = document.createElement("li");
  li.innerHTML = emphasize ? message.replace(emphasize, `<em>${emphasize}</em>`) : message;
  els.activityFeed.prepend(li);
  while (els.activityFeed.children.length > 12) {
    els.activityFeed.lastElementChild.remove();
  }
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

function updateBoard(data) {
  if (!data) return;
  const stock = data.stock_remaining ?? 0;
  const total = data.total_stock || Math.max(stock, 1);
  const waiting = data.waiting ?? 0;
  const active = data.active_checkouts ?? 0;
  const maxActive = data.max_concurrent_checkouts || 2;

  els.boardStock.textContent = `${stock}/${total}`;
  els.boardWaiting.textContent = String(waiting);
  els.boardActive.textContent = `${active}/${maxActive}`;
  els.barStock.style.width = `${Math.max(0, Math.min(100, (stock / total) * 100))}%`;
  els.barWaiting.style.width = `${Math.max(8, Math.min(100, waiting * 8))}%`;
  els.barActive.style.width = `${Math.max(0, Math.min(100, (active / maxActive) * 100))}%`;
  if (els.maxSlotsLabel) els.maxSlotsLabel.textContent = String(maxActive);
  els.stockMeta.textContent = `${data.name || "Drop"} · ${stock} left · ${waiting} waiting · ${active} in checkout`;
}

function renderLine(peopleAhead = 0, status = "waiting") {
  if (!els.lineViz) return;
  els.lineViz.innerHTML = "";
  const ahead = Math.min(Number(peopleAhead) || 0, 24);
  for (let i = 0; i < ahead; i += 1) {
    const d = document.createElement("div");
    d.className = "person";
    d.title = "Shopper ahead";
    els.lineViz.appendChild(d);
  }
  const you = document.createElement("div");
  you.className = `person you${status === "active" ? " active" : ""}`;
  you.title = "You";
  els.lineViz.appendChild(you);
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
        total_stock: 8,
        max_concurrent_checkouts: 2,
      },
    }),
  });
  if (!ok) throw new Error(body?.error || "Could not create sale");
  localStorage.setItem(SALE_KEY, String(body.id));
  logActivity(`New drop created with ${body.stock_remaining} units`, "New drop");
  return loadSale(body.id);
}

async function loadSale(id) {
  const { ok, body } = await api(`/flash_sales/${id}`);
  if (!ok) return null;
  sale = body;
  updateBoard(sale);
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

async function refreshBoard() {
  if (!sale?.id) return;
  const { ok, body } = await api(`/flash_sales/${sale.id}`);
  if (!ok) return;
  sale = { ...sale, ...body };
  updateBoard(sale);
}

function disconnectCable() {
  queueSub?.unsubscribe();
  inventorySub?.unsubscribe();
  queueSub = null;
  inventorySub = null;
  consumer?.disconnect();
  consumer = null;
  els.liveDot.classList.remove("on");
  els.livePill.classList.remove("on");
}

function cableUrl() {
  const proto = window.location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${window.location.host}/cable`;
}

function connectInventory(saleId) {
  if (!consumer) {
    consumer = createConsumer(`${cableUrl()}?user_token=${encodeURIComponent(userToken || "spectator")}`);
  }
  inventorySub?.unsubscribe();
  inventorySub = consumer.subscriptions.create(
    { channel: "InventoryChannel", flash_sale_id: saleId },
    {
      connected: () => {
        els.liveDot.classList.add("on");
        els.livePill.classList.add("on");
      },
      disconnected: () => {
        els.liveDot.classList.remove("on");
        els.livePill.classList.remove("on");
      },
      received: (data) => {
        if (!sale) return;
        sale = {
          ...sale,
          stock_remaining: data.stock_remaining,
          waiting: data.waiting,
          active_checkouts: data.active_checkouts,
          live: data.live,
        };
        updateBoard(sale);
      },
    }
  );
}

function connectQueue(token) {
  disconnectCable();
  consumer = createConsumer(`${cableUrl()}?user_token=${encodeURIComponent(token)}`);
  if (sale) connectInventory(sale.id);

  queueSub = consumer.subscriptions.create(
    { channel: "QueueChannel" },
    {
      connected: () => {
        els.liveDot.classList.add("on");
        els.livePill.classList.add("on");
      },
      received: (data) => applyQueueUpdate(data),
    }
  );
}

function applyQueueUpdate(data) {
  els.statusValue.textContent = data.status;
  els.positionValue.textContent = data.position ?? "—";
  els.peopleAhead.textContent = String(data.people_ahead ?? "—");
  renderLine(data.people_ahead, data.status);

  if (data.status === "waiting") {
    const n = data.people_ahead ?? 0;
    els.queueCopy.textContent =
      n === 0
        ? "You’re next. As soon as a checkout slot frees, Redis admission lets you through."
        : `${n} shoppers ahead. Only a few people can check out at once — that’s intentional.`;
    els.nextValue.textContent = "Waiting for a free checkout slot";
    show("queue");
  } else if (data.status === "active") {
    if (data.expires_at) {
      const exp = new Date(data.expires_at);
      els.expiresAt.textContent = `Inventory reservation held until ${exp.toLocaleTimeString()}`;
    }
    els.nextValue.textContent = "Checkout open — complete before expiry";
    logActivity("You were admitted to checkout", "admitted");
    show("checkout");
  } else if (data.status === "checked_out") {
    els.doneEyebrow.textContent = "Order placed";
    els.doneTitle.textContent = "You’re in.";
    els.doneCopy.textContent =
      "Success. Stock was reserved with a conditional SQL update, so two shoppers could never claim the same unit.";
    logActivity("Order completed — no oversell", "Order completed");
    show("done");
    stopPolling();
    refreshBoard();
  } else if (data.status === "expired") {
    els.doneEyebrow.textContent = "Slot expired";
    els.doneTitle.textContent = "Time’s up.";
    els.doneCopy.textContent =
      "Your checkout window expired. The reserved unit returned to inventory automatically.";
    logActivity("Reservation expired — stock returned", "expired");
    show("done");
    stopPolling();
    refreshBoard();
  }
}

function startPolling(token) {
  stopPolling();
  pollTimer = setInterval(async () => {
    if (!sale) return;
    const { ok, body } = await api(`/flash_sales/${sale.id}/queue/${token}`);
    if (ok) applyQueueUpdate({ ...body, user_token: token, position: body.position });
    refreshBoard();
  }, 2000);
}

function stopPolling() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
}

async function crowdQueue(count = 8) {
  await ensureSale();
  setBusy(els.crowdBtn, true, "Crowding…");
  setBusy(els.crowdMoreBtn, true, "Adding…");
  els.joinHint.textContent = "";
  let joined = 0;
  const jobs = Array.from({ length: count }, () =>
    api(`/flash_sales/${sale.id}/queue`, { method: "POST" }).then((res) => {
      if (res.ok) joined += 1;
      return res;
    })
  );
  await Promise.all(jobs);
  await refreshBoard();
  logActivity(`Crowded the drop with ${joined} fake shoppers`, `${joined} fake shoppers`);
  els.joinCoach.textContent = joined
    ? `Nice — ${joined} shoppers are in line. Now enter as yourself and watch your position.`
    : "Couldn’t crowd right now — try again or reset the drop.";
  setBusy(els.crowdBtn, false, "Crowd the drop (8 shoppers)");
  setBusy(els.crowdMoreBtn, false, "Add 5 more shoppers");
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
    lastIdempotencyKey = null;
    localStorage.removeItem(IDEM_KEY);
    logActivity(`You joined at position #${body.position}`, "You joined");
    applyQueueUpdate(body);
    connectQueue(userToken);
    startPolling(userToken);
    refreshBoard();
  } catch (err) {
    els.joinHint.textContent = err.message;
  } finally {
    setBusy(els.joinBtn, false, "Enter the queue as me");
  }
}

async function checkout({ reuseKey = false } = {}) {
  els.checkoutHint.textContent = "";
  const label = reuseKey ? "Retrying…" : "Placing order…";
  setBusy(els.checkoutBtn, true, label);
  setBusy(els.dupCheckoutBtn, true);
  try {
    if (!reuseKey || !lastIdempotencyKey) {
      lastIdempotencyKey = `${userToken}-web-${Date.now()}`;
      localStorage.setItem(IDEM_KEY, lastIdempotencyKey);
    }
    const { ok, body, status, headers } = await api(`/flash_sales/${sale.id}/checkout`, {
      method: "POST",
      headers: {
        "Idempotency-Key": lastIdempotencyKey,
        "X-User-Token": userToken,
      },
      body: JSON.stringify({ user_token: userToken }),
    });
    if (!ok) {
      els.checkoutHint.textContent = body?.error || `Checkout failed (${status})`;
      return;
    }
    const replayed = headers.get("Idempotency-Replayed") === "true";
    if (replayed) {
      logActivity("Duplicate checkout blocked by idempotency key", "Duplicate checkout");
      els.checkoutHint.textContent = "Replay detected — same order returned, no double charge/stock hit.";
    } else {
      logActivity("Checkout succeeded", "Checkout");
    }
    applyQueueUpdate({ status: "checked_out", people_ahead: 0, user_token: userToken });
  } catch (err) {
    els.checkoutHint.textContent = err.message;
  } finally {
    setBusy(els.checkoutBtn, false, "Place order");
    setBusy(els.dupCheckoutBtn, false, "Retry same order (idempotent)");
  }
}

async function resetDemo() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(IDEM_KEY);
  userToken = null;
  lastIdempotencyKey = null;
  stopPolling();
  disconnectCable();
  els.activityFeed.innerHTML = "";
  logActivity("Demo reset — starting a fresh drop", "Demo reset");
  await createSale();
  show("join");
}

async function resumeIfPossible() {
  await ensureSale();
  boardTimer = setInterval(refreshBoard, 4000);
  if (!userToken || !sale) {
    show("join");
    logActivity("Demo ready — crowd the drop, then join", "Demo ready");
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
els.crowdBtn.addEventListener("click", () => crowdQueue(8));
els.crowdMoreBtn?.addEventListener("click", () => crowdQueue(5));
els.checkoutBtn.addEventListener("click", () => checkout({ reuseKey: false }));
els.dupCheckoutBtn?.addEventListener("click", () => checkout({ reuseKey: true }));
els.newSaleBtn.addEventListener("click", async () => {
  setBusy(els.newSaleBtn, true, "Resetting…");
  try {
    await resetDemo();
  } catch (err) {
    els.joinHint.textContent = err.message;
  } finally {
    setBusy(els.newSaleBtn, false, "Reset drop");
  }
});
els.againBtn.addEventListener("click", () => resetDemo());

resumeIfPossible().catch((err) => {
  els.joinHint.textContent = err.message;
  show("join");
});
