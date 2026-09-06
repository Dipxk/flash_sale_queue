import { createConsumer } from "https://esm.sh/@rails/actioncable@8.0.200";

const SALE_KEY = "threshold_sale_id";
const TOKEN_KEY = "threshold_user_token";
const IDEM_KEY = "threshold_idem_key";

const NAMES = [
  "Maya", "Jordan", "Alex", "Sam", "Riley", "Casey", "Drew", "Avery",
  "Quinn", "Blake", "Nora", "Kai", "Reese", "Sky", "Devon", "Harper"
];

const els = {
  views: {
    store: document.getElementById("viewStore"),
    queue: document.getElementById("viewQueue"),
    checkout: document.getElementById("viewCheckout"),
    done: document.getElementById("viewDone"),
  },
  engToggle: document.getElementById("engToggle"),
  engPanel: document.getElementById("engPanel"),
  onlinePill: document.getElementById("onlinePill"),
  onlineCount: document.getElementById("onlineCount"),
  startBtn: document.getElementById("startBtn"),
  demoBtn: document.getElementById("demoBtn"),
  storeHint: document.getElementById("storeHint"),
  heroStock: document.getElementById("heroStock"),
  heroWaiting: document.getElementById("heroWaiting"),
  heroLanes: document.getElementById("heroLanes"),
  aheadNum: document.getElementById("aheadNum"),
  aheadLabel: document.getElementById("aheadLabel"),
  crowd: document.getElementById("crowd"),
  placeNum: document.getElementById("placeNum"),
  statusText: document.getElementById("statusText"),
  queueStock: document.getElementById("queueStock"),
  queueCoach: document.getElementById("queueCoach"),
  queueHint: document.getElementById("queueHint"),
  feed: document.getElementById("feed"),
  addCrowdBtn: document.getElementById("addCrowdBtn"),
  expiresAt: document.getElementById("expiresAt"),
  buyBtn: document.getElementById("buyBtn"),
  retryBtn: document.getElementById("retryBtn"),
  buyHint: document.getElementById("buyHint"),
  doneEyebrow: document.getElementById("doneEyebrow"),
  doneTitle: document.getElementById("doneTitle"),
  doneCopy: document.getElementById("doneCopy"),
  againBtn: document.getElementById("againBtn"),
};

let sale = null;
let userToken = localStorage.getItem(TOKEN_KEY);
let idemKey = localStorage.getItem(IDEM_KEY);
let consumer = null;
let queueSub = null;
let inventorySub = null;
let pollTimer = null;
let boardTimer = null;
let demoRunning = false;

function show(view) {
  Object.entries(els.views).forEach(([key, node]) => {
    node.dataset.active = String(key === view);
  });
}

function busy(btn, on, label) {
  if (!btn) return;
  btn.disabled = on;
  if (label) btn.textContent = label;
}

function feed(msg, boldBit = null) {
  const li = document.createElement("li");
  li.innerHTML = boldBit ? msg.replace(boldBit, `<b>${boldBit}</b>`) : msg;
  els.feed.prepend(li);
  while (els.feed.children.length > 14) els.feed.lastChild.remove();
}

function initials(name) {
  return name.slice(0, 1).toUpperCase();
}

function randName() {
  return NAMES[Math.floor(Math.random() * NAMES.length)];
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });
  const text = await res.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = { error: text }; }
  return { ok: res.ok, status: res.status, body, headers: res.headers };
}

function paintSale(data) {
  if (!data) return;
  sale = { ...sale, ...data };
  els.heroStock.textContent = String(data.stock_remaining ?? "—");
  els.heroWaiting.textContent = String(data.waiting ?? 0);
  els.heroLanes.textContent = String(data.max_concurrent_checkouts ?? 2);
  els.queueStock.textContent = String(data.stock_remaining ?? "—");
  const online = (data.waiting || 0) + (data.active_checkouts || 0);
  els.onlineCount.textContent = String(Math.max(online, online ? online : 1));
  els.onlinePill.classList.toggle("on", online > 0);
}

function renderCrowd(ahead, status) {
  els.crowd.innerHTML = "";
  const n = Math.min(Number(ahead) || 0, 28);
  for (let i = 0; i < n; i += 1) {
    const a = document.createElement("div");
    a.className = "avatar";
    a.textContent = initials(randName());
    a.title = "Shopper ahead";
    els.crowd.appendChild(a);
  }
  const you = document.createElement("div");
  you.className = `avatar you${status === "active" ? " lane" : ""}`;
  you.textContent = "YOU";
  you.title = "You";
  els.crowd.appendChild(you);
}

async function createSale() {
  const now = Date.now();
  const { ok, body } = await api("/flash_sales", {
    method: "POST",
    body: JSON.stringify({
      flash_sale: {
        name: "Aurora Runner Drop",
        starts_at: new Date(now - 60_000).toISOString(),
        ends_at: new Date(now + 60 * 60_000).toISOString(),
        total_stock: 8,
        max_concurrent_checkouts: 2,
      },
    }),
  });
  if (!ok) throw new Error(body?.error || "Could not create drop");
  localStorage.setItem(SALE_KEY, String(body.id));
  return loadSale(body.id);
}

async function loadSale(id) {
  const { ok, body } = await api(`/flash_sales/${id}`);
  if (!ok) return null;
  paintSale(body);
  connectInventory(body.id);
  return body;
}

async function ensureSale() {
  const id = localStorage.getItem(SALE_KEY);
  if (id) {
    const existing = await loadSale(id);
    if (existing?.live) return existing;
  }
  return createSale();
}

async function refreshSale() {
  if (!sale?.id) return;
  const { ok, body } = await api(`/flash_sales/${sale.id}`);
  if (ok) paintSale(body);
}

function cableUrl() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${location.host}/cable`;
}

function disconnectCable() {
  queueSub?.unsubscribe();
  inventorySub?.unsubscribe();
  queueSub = null;
  inventorySub = null;
  consumer?.disconnect();
  consumer = null;
}

function connectInventory(saleId) {
  if (!consumer) {
    consumer = createConsumer(`${cableUrl()}?user_token=${encodeURIComponent(userToken || "spectator")}`);
  }
  inventorySub?.unsubscribe();
  inventorySub = consumer.subscriptions.create(
    { channel: "InventoryChannel", flash_sale_id: saleId },
    {
      received: (data) => {
        paintSale({
          ...(sale || {}),
          stock_remaining: data.stock_remaining,
          waiting: data.waiting,
          active_checkouts: data.active_checkouts,
          live: data.live,
          max_concurrent_checkouts: sale?.max_concurrent_checkouts,
          name: sale?.name,
          total_stock: sale?.total_stock,
        });
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
    { received: (data) => onQueue(data) }
  );
}

function onQueue(data) {
  const ahead = data.people_ahead ?? 0;
  els.aheadNum.textContent = String(ahead);
  els.aheadLabel.textContent = ahead === 1 ? "person ahead of you" : "people ahead of you";
  els.placeNum.textContent = data.position != null ? `#${data.position}` : "—";
  els.statusText.textContent = data.status;
  renderCrowd(ahead, data.status);

  if (data.status === "waiting") {
    els.queueCoach.textContent =
      ahead === 0
        ? "You’re next. As soon as a checkout lane frees, you’re in."
        : "Only 2 lanes are open at a time — that’s how we stop the stampede.";
    show("queue");
  } else if (data.status === "active") {
    if (data.expires_at) {
      els.expiresAt.textContent = `Reserved until ${new Date(data.expires_at).toLocaleTimeString()}`;
    }
    feed("A checkout lane opened for you", "checkout lane opened");
    show("checkout");
  } else if (data.status === "checked_out") {
    els.doneEyebrow.textContent = "Purchase confirmed";
    els.doneTitle.textContent = "You got one — fairly.";
    els.doneCopy.textContent =
      "Stock was locked with an atomic update, so nobody else could take your pair. The waiting room kept checkout from melting down.";
    feed("Purchase complete — no oversell", "Purchase complete");
    stopPolling();
    show("done");
    refreshSale();
  } else if (data.status === "expired") {
    els.doneEyebrow.textContent = "Reservation expired";
    els.doneTitle.textContent = "Your window closed.";
    els.doneCopy.textContent =
      "You didn’t finish in time, so the reserved pair returned to inventory for the next shopper.";
    feed("Reservation expired — stock returned", "expired");
    stopPolling();
    show("done");
    refreshSale();
  }
}

function startPolling(token) {
  stopPolling();
  pollTimer = setInterval(async () => {
    if (!sale) return;
    const { ok, body } = await api(`/flash_sales/${sale.id}/queue/${token}`);
    if (ok) onQueue({ ...body, position: body.position });
    refreshSale();
  }, 2000);
}

function stopPolling() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
}

async function crowd(count = 8, announce = true) {
  await ensureSale();
  const results = await Promise.all(
    Array.from({ length: count }, () => api(`/flash_sales/${sale.id}/queue`, { method: "POST" }))
  );
  const joined = results.filter((r) => r.ok).length;
  await refreshSale();
  if (announce && joined) {
    feed(`${joined} shoppers jumped into line`, `${joined} shoppers`);
    for (let i = 0; i < Math.min(joined, 4); i += 1) {
      feed(`${randName()} joined the waiting room`);
    }
  }
  return joined;
}

async function joinAsMe() {
  els.storeHint.textContent = "";
  els.queueHint.textContent = "";
  busy(els.startBtn, true, "Getting in line…");
  try {
    await ensureSale();
    // Seed a crowd if the room is empty so the problem is visible.
    if ((sale.waiting || 0) < 3) {
      await crowd(7, true);
    }
    const { ok, body, status } = await api(`/flash_sales/${sale.id}/queue`, { method: "POST" });
    if (!ok) {
      els.storeHint.textContent = body?.error || `Could not join (${status})`;
      return;
    }
    userToken = body.user_token;
    localStorage.setItem(TOKEN_KEY, userToken);
    idemKey = null;
    localStorage.removeItem(IDEM_KEY);
    feed("You entered the waiting room", "You entered");
    onQueue(body);
    connectQueue(userToken);
    startPolling(userToken);
    show("queue");
  } catch (e) {
    els.storeHint.textContent = e.message;
  } finally {
    busy(els.startBtn, false, "Join this drop");
  }
}

async function buy({ retry = false } = {}) {
  els.buyHint.textContent = "";
  busy(els.buyBtn, true, retry ? "Retrying…" : "Buying…");
  busy(els.retryBtn, true);
  try {
    if (!retry || !idemKey) {
      idemKey = `${userToken}-buy-${Date.now()}`;
      localStorage.setItem(IDEM_KEY, idemKey);
    }
    const { ok, body, status, headers } = await api(`/flash_sales/${sale.id}/checkout`, {
      method: "POST",
      headers: {
        "Idempotency-Key": idemKey,
        "X-User-Token": userToken,
      },
      body: JSON.stringify({ user_token: userToken }),
    });
    if (!ok) {
      els.buyHint.textContent = body?.error || `Purchase failed (${status})`;
      return;
    }
    if (headers.get("Idempotency-Replayed") === "true") {
      els.buyHint.textContent = "Safe retry: same order returned, no double purchase.";
      feed("Duplicate buy blocked", "Duplicate buy");
    } else {
      feed("You secured a pair", "secured a pair");
    }
    onQueue({ status: "checked_out", people_ahead: 0, position: els.placeNum.textContent.replace("#", "") });
  } catch (e) {
    els.buyHint.textContent = e.message;
  } finally {
    busy(els.buyBtn, false, "Complete purchase");
    busy(els.retryBtn, false, "Retry purchase (safe)");
  }
}

async function resetDrop() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(IDEM_KEY);
  userToken = null;
  idemKey = null;
  stopPolling();
  disconnectCable();
  els.feed.innerHTML = "";
  await createSale();
  feed("New drop opened — 8 pairs available", "New drop");
  show("store");
}

async function autoDemo() {
  if (demoRunning) return;
  demoRunning = true;
  busy(els.demoBtn, true, "Running demo…");
  busy(els.startBtn, true);
  els.storeHint.textContent = "";
  try {
    await resetDrop();
    feed("Auto-demo: simulating a flash-sale spike", "Auto-demo");
    await crowd(10, true);
    await new Promise((r) => setTimeout(r, 700));
    await joinAsMe();
    // Wait until admitted or timeout
    const started = Date.now();
    while (Date.now() - started < 25000) {
      const status = els.statusText.textContent;
      if (status === "active") break;
      if (status === "checked_out" || status === "expired") break;
      await new Promise((r) => setTimeout(r, 800));
    }
    if (els.statusText.textContent === "active") {
      await new Promise((r) => setTimeout(r, 600));
      await buy({ retry: false });
    }
  } catch (e) {
    els.storeHint.textContent = e.message;
  } finally {
    demoRunning = false;
    busy(els.demoBtn, false, "Watch a 20s auto-demo");
    busy(els.startBtn, false, "Join this drop");
  }
}

els.engToggle.addEventListener("click", () => {
  const on = els.engToggle.getAttribute("aria-pressed") !== "true";
  els.engToggle.setAttribute("aria-pressed", String(on));
  els.engPanel.hidden = !on;
});

els.startBtn.addEventListener("click", joinAsMe);
els.demoBtn.addEventListener("click", autoDemo);
els.addCrowdBtn.addEventListener("click", async () => {
  busy(els.addCrowdBtn, true, "Adding…");
  await crowd(5, true);
  busy(els.addCrowdBtn, false, "Add more shoppers");
});
els.buyBtn.addEventListener("click", () => buy({ retry: false }));
els.retryBtn.addEventListener("click", () => buy({ retry: true }));
els.againBtn.addEventListener("click", resetDrop);

(async function boot() {
  try {
    await ensureSale();
    boardTimer = setInterval(refreshSale, 4000);
    feed("Drop is live — limited to 8 pairs", "Drop is live");

    if (userToken && sale) {
      const { ok, body } = await api(`/flash_sales/${sale.id}/queue/${userToken}`);
      if (ok && (body.status === "waiting" || body.status === "active")) {
        onQueue(body);
        connectQueue(userToken);
        startPolling(userToken);
        show(body.status === "active" ? "checkout" : "queue");
        return;
      }
    }
    show("store");
  } catch (e) {
    els.storeHint.textContent = e.message;
    show("store");
  }
})();
