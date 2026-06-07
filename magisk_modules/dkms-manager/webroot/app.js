const state = {
  moduleDir: "",
  scriptPath: "",
  modules: [],
  taskRunning: false,
  pollTimer: null,
};

const el = {
  stateChip: document.getElementById("stateChip"),
  kernelVersion: document.getElementById("kernelVersion"),
  toolchainName: document.getElementById("toolchainName"),
  moduleCount: document.getElementById("moduleCount"),
  taskMessage: document.getElementById("taskMessage"),
  moduleList: document.getElementById("moduleList"),
  logOutput: document.getElementById("logOutput"),
  refreshBtn: document.getElementById("refreshBtn"),
  buildAllBtn: document.getElementById("buildAllBtn"),
  rebuildAllBtn: document.getElementById("rebuildAllBtn"),
  clearLogBtn: document.getElementById("clearLogBtn"),
};

/* ---- KSU bridge ---- */

function getKsuBridge() {
  return globalThis.ksu || window.ksu || null;
}

function shellQuote(v) {
  return "'" + String(v).replace(/'/g, "'\\''") + "'";
}

function toast(msg) {
  getKsuBridge()?.toast?.(msg);
}

function moduleInfo() {
  var b = getKsuBridge();
  if (!b?.moduleInfo) throw new Error("Not running in KernelSU WebUI");
  var raw = b.moduleInfo();
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

function extractStdout(raw) {
  if (raw == null) return "";
  if (typeof raw === "string") {
    try {
      var obj = JSON.parse(raw);
      if (typeof obj?.stdout === "string") return obj.stdout;
      if (typeof obj?.out === "string") return obj.out;
    } catch {}
    return raw;
  }
  if (typeof raw?.stdout === "string") return raw.stdout;
  if (typeof raw?.out === "string") return raw.out;
  return String(raw);
}

function exec(cmd) {
  var b = getKsuBridge();
  if (!b?.exec) throw new Error("KernelSU exec API unavailable");
  return extractStdout(b.exec(cmd));
}

function runScript() {
  var parts = ["MODDIR=" + shellQuote(state.moduleDir), "sh", shellQuote(state.scriptPath)];
  for (var i = 0; i < arguments.length; i++) {
    var a = arguments[i];
    if (a != null && a !== "") parts.push(shellQuote(String(a)));
  }
  return exec(parts.join(" ")).replace(/\t/g, "\n");
}

function parseKV(output) {
  var kv = {};
  var lines = output.split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line) continue;
    var eq = line.indexOf("=");
    if (eq > 0) kv[line.slice(0, eq)] = line.slice(eq + 1);
  }
  return kv;
}

/* ---- Module list parsing ---- */

function parseModuleList(raw) {
  var modules = [];
  var lines = raw.split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (!line) continue;
    var p = line.split("|");
    switch (p[0]) {
      case "H":
        modules.push({ type: "header", id: p[1], kver: p[2], disabled: p[3] === "yes" });
        break;
      case "T":
        modules.push({ type: "toolchain", id: p[1], tcname: p[2], disabled: p[3] === "yes" });
        break;
      case "K":
        modules.push({
          type: "kmod", id: p[1], name: p[2], version: p[3],
          built: p[4] === "yes", bkver: p[5], loaded: p[6] === "yes",
          autoload: p[7] === "on", disabled: p[8] === "yes",
        });
        break;
    }
  }
  return modules;
}

/* ---- Rendering ---- */

function escapeHtml(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function renderSystemInfo() {
  var headers = state.modules.filter(function(m) { return m.type === "header"; });
  var toolchains = state.modules.filter(function(m) { return m.type === "toolchain"; });
  var kmods = state.modules.filter(function(m) { return m.type === "kmod"; });

  el.kernelVersion.textContent = headers.length > 0 ? headers[0].kver : "Not installed";
  el.toolchainName.textContent = toolchains.length > 0 ? toolchains[0].tcname : "Not installed";
  el.moduleCount.textContent = String(kmods.length);

  el.kernelVersion.parentElement.classList.toggle("stat-warn", headers.length === 0);
  el.toolchainName.parentElement.classList.toggle("stat-warn", toolchains.length === 0);
}

function renderModuleList() {
  var kmods = state.modules.filter(function(m) { return m.type === "kmod"; });
  if (kmods.length === 0) {
    el.moduleList.innerHTML = '<p class="empty-text">No kernel modules found</p>';
    return;
  }
  el.moduleList.innerHTML = kmods.map(renderKmodCard).join("");
}

function renderKmodCard(mod) {
  var builtPill, loadedPill;
  if (mod.disabled) {
    builtPill = '<span class="status-pill dim">Disabled</span>';
    loadedPill = "";
  } else {
    builtPill = mod.built
      ? '<span class="status-pill ok">Built (' + escapeHtml(mod.bkver === "-" ? "unknown" : mod.bkver) + ')</span>'
      : '<span class="status-pill bad">Not built</span>';
    loadedPill = mod.loaded
      ? '<span class="status-pill ok">Loaded</span>'
      : '<span class="status-pill">Not loaded</span>';
  }

  var actions = "";
  if (!mod.disabled) {
    actions += '<button class="action-btn" data-action="build">Build</button>';
    actions += '<button class="action-btn" data-action="rebuild">Rebuild</button>';
    if (mod.built && !mod.loaded) {
      actions += '<button class="action-btn action-load" data-action="load">Load</button>';
    }
    if (mod.loaded) {
      actions += '<button class="action-btn action-unload" data-action="unload">Unload</button>';
    }
  }

  var autoloadChecked = mod.autoload ? " checked" : "";
  var autoloadDisabled = mod.disabled ? " disabled" : "";

  return '<div class="module-card' + (mod.disabled ? " module-disabled" : "") + '" data-name="' + escapeHtml(mod.name) + '">'
    + '<div class="module-header">'
    +   '<div class="module-title">'
    +     '<span class="module-name">' + escapeHtml(mod.name) + '</span>'
    +     '<span class="module-version">v' + escapeHtml(mod.version) + '</span>'
    +   '</div>'
    +   '<label class="autoload-toggle">'
    +     '<input type="checkbox" class="autoload-checkbox"' + autoloadChecked + autoloadDisabled + ' />'
    +     '<span class="toggle-slider"></span>'
    +     '<span class="toggle-label">Autoload</span>'
    +   '</label>'
    + '</div>'
    + '<div class="module-id">' + escapeHtml(mod.id) + '</div>'
    + '<div class="module-status">' + builtPill + loadedPill + '</div>'
    + '<div class="module-actions">' + actions + '</div>'
    + '</div>';
}

function updateTaskUI() {
  if (state.taskRunning) {
    el.stateChip.textContent = "Task running";
    el.stateChip.className = "chip chip-warn";
    el.buildAllBtn.disabled = true;
    el.rebuildAllBtn.disabled = true;
  } else {
    el.buildAllBtn.disabled = false;
    el.rebuildAllBtn.disabled = false;
  }
}

/* ---- Actions ---- */

function handleAction(action, name) {
  switch (action) {
    case "build":   startTask("build", name); break;
    case "rebuild": startTask("rebuild", name); break;
    case "load":    doLoad(name); break;
    case "unload":  doUnload(name); break;
  }
}

function startTask(action, name) {
  try {
    var raw = runScript("start", action, name);
    var kv = parseKV(raw);
    if (kv.BUSY === "1") {
      toast("A task is already running");
      return;
    }
    if (kv.STARTED === "1") {
      toast((action === "rebuild" ? "Rebuild" : "Build") + " " + name + " started");
      state.taskRunning = true;
      updateTaskUI();
      schedulePoll(2000);
    } else if (kv.FINISHED) {
      toast("Task finished: " + kv.FINISHED);
      manualRefresh();
    } else {
      toast("Failed to start task");
    }
  } catch (e) {
    toast("Error: " + e.message);
  }
}

function startBuildAll(force) {
  var action = force ? "rebuild-all" : "build-all";
  try {
    var raw = runScript("start", action, "");
    var kv = parseKV(raw);
    if (kv.BUSY === "1") {
      toast("A task is already running");
      return;
    }
    if (kv.STARTED === "1") {
      toast(force ? "Rebuild all started" : "Build all started");
      state.taskRunning = true;
      updateTaskUI();
      schedulePoll(2000);
    } else if (kv.FINISHED) {
      toast("Task finished");
      manualRefresh();
    }
  } catch (e) {
    toast("Error: " + e.message);
  }
}

function doLoad(name) {
  try {
    var raw = runScript("load", name);
    var kv = parseKV(raw);
    switch (kv.RESULT) {
      case "ok":             toast(name + " loaded"); break;
      case "already_loaded": toast(name + " already loaded"); break;
      case "not_built":      toast(name + " not built, build first"); break;
      case "not_found":      toast(name + " not found"); break;
      default:               toast(name + " load failed"); break;
    }
  } catch (e) {
    toast("Error: " + e.message);
  }
  refreshList();
}

function doUnload(name) {
  try {
    var raw = runScript("unload", name);
    var kv = parseKV(raw);
    switch (kv.RESULT) {
      case "ok":         toast(name + " unloaded"); break;
      case "not_loaded": toast(name + " not loaded"); break;
      default:           toast(name + " unload failed (may be in use)"); break;
    }
  } catch (e) {
    toast("Error: " + e.message);
  }
  refreshList();
}

function doAutoloadToggle(name, on) {
  try {
    var raw = runScript("autoload", on ? "on" : "off", name);
    var kv = parseKV(raw);
    if (kv.RESULT === "disabled") {
      toast("Module is disabled, cannot set autoload");
    } else if (kv.RESULT === "ok") {
      toast(name + (on ? " autoload enabled" : " autoload disabled"));
    }
  } catch (e) {
    toast("Error: " + e.message);
  }
  refreshList();
}

/* ---- Polling ---- */

function refreshList() {
  try {
    var raw = runScript("list");
    state.modules = parseModuleList(raw);
    renderSystemInfo();
    renderModuleList();
  } catch (e) {
    el.moduleList.innerHTML = '<p class="empty-text">Failed to load modules: ' + escapeHtml(e.message) + '</p>';
  }
}

function refreshLog() {
  try {
    var log = runScript("tail", "200").trim();
    el.logOutput.textContent = log || "No log output";
    el.logOutput.scrollTop = el.logOutput.scrollHeight;
  } catch (e) {
    el.logOutput.textContent = "Failed to read log: " + e.message;
  }
}

function refreshTaskStatus() {
  try {
    var raw = runScript("task-status");
    var kv = parseKV(raw);
    state.taskRunning = kv.RUNNING === "1";
    var s = kv.STATE || "idle";
    var msg = kv.MESSAGE || "Idle";

    el.taskMessage.textContent = msg;
    el.stateChip.textContent = state.taskRunning ? "Task running" : (s === "idle" ? "Idle" : msg);
    el.stateChip.className = "chip";
    if (s === "success")        el.stateChip.classList.add("chip-success");
    else if (s === "error")     el.stateChip.classList.add("chip-danger");
    else if (state.taskRunning) el.stateChip.classList.add("chip-warn");

    updateTaskUI();
  } catch (e) {
    el.stateChip.textContent = "Status error";
    el.stateChip.className = "chip chip-danger";
  }
}

function poll() {
  refreshTaskStatus();
  if (state.taskRunning) {
    refreshLog();
  } else {
    refreshList();
    refreshLog();
  }
  schedulePoll(state.taskRunning ? 3000 : 8000);
}

function schedulePoll(ms) {
  clearTimeout(state.pollTimer);
  state.pollTimer = setTimeout(poll, ms);
}

function manualRefresh() {
  clearTimeout(state.pollTimer);
  refreshTaskStatus();
  refreshList();
  refreshLog();
  schedulePoll(state.taskRunning ? 3000 : 8000);
}

/* ---- Event delegation ---- */

function setupEvents() {
  el.refreshBtn.addEventListener("click", manualRefresh);

  el.buildAllBtn.addEventListener("click", function() { startBuildAll(false); });
  el.rebuildAllBtn.addEventListener("click", function() { startBuildAll(true); });

  el.clearLogBtn.addEventListener("click", function() {
    try {
      var raw = runScript("clear-log");
      var kv = parseKV(raw);
      if (kv.BUSY === "1") { toast("Task running, cannot clear"); return; }
      toast("Log cleared");
    } catch (e) { toast("Clear failed: " + e.message); }
    manualRefresh();
  });

  el.moduleList.addEventListener("click", function(e) {
    var btn = e.target.closest("[data-action]");
    if (!btn) return;
    var card = btn.closest("[data-name]");
    if (!card) return;
    if (state.taskRunning && (btn.dataset.action === "build" || btn.dataset.action === "rebuild")) {
      toast("A task is already running"); return;
    }
    handleAction(btn.dataset.action, card.dataset.name);
  });

  el.moduleList.addEventListener("change", function(e) {
    if (!e.target.classList.contains("autoload-checkbox")) return;
    var card = e.target.closest("[data-name]");
    if (!card) return;
    doAutoloadToggle(card.dataset.name, e.target.checked);
  });
}

/* ---- Init ---- */

function init() {
  try {
    var info = moduleInfo();
    state.moduleDir = info.moduleDir;
    state.scriptPath = state.moduleDir + "/bin/dkms_android.sh";
  } catch (e) {
    el.stateChip.textContent = "Init failed";
    el.stateChip.className = "chip chip-danger";
    el.taskMessage.textContent = e.message;
    el.moduleList.innerHTML = '<p class="empty-text">' + escapeHtml(e.message) + '</p>';
    el.buildAllBtn.disabled = true;
    el.rebuildAllBtn.disabled = true;
    return;
  }

  setupEvents();
  manualRefresh();
}

init();
