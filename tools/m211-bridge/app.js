const $ = (id) => document.getElementById(id);
const relay = location.pathname === "/relay";
const storageKey = relay ? "m211-relay-session" : "m211-control-session";
let config,
  sdk,
  relayMessage = "Waiting for connection.",
  canConnect = false,
  connecting = false,
  previewKey = "",
  urls = [];
const clientId = sessionStorage.getItem("m211-client") || crypto.randomUUID();
sessionStorage.setItem("m211-client", clientId);
const notice = (text = "") => {
  $("notice").textContent = text;
};
const params = new URLSearchParams(location.hash.slice(1));
try {
  if (params.has("session") && params.has("token")) {
    config = {
      id: params.get("session"),
      token: params.get("token"),
      relayToken: params.get("relayToken"),
    };
    localStorage.setItem(storageKey, JSON.stringify(config));
    history.replaceState(null, "", location.pathname);
  } else config = JSON.parse(localStorage.getItem(storageKey) || "null");
} catch {
  notice(
    "Browser storage is unavailable. Allow storage for this page to retain the session and printer ownership.",
  );
}

async function api(tail = "", method = "GET", body) {
  const response = await fetch(`/api/sessions/${config.id}${tail}`, {
    method,
    headers: {
      Authorization: `Bearer ${config.token}`,
      "Content-Type": "application/json",
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (!response.ok) {
    const result = await response.json();
    throw new Error(result.error || `Request failed (${response.status}).`);
  }
  return response;
}
function relayStatus() {
  return {
    clientId,
    connected: sdk?.isConnected() === true,
    message: relayMessage,
    model: sdk?.printerModel,
    name: sdk?.printerName,
    supply: sdk?.supplyName,
    dimensions: sdk?.supplyDimensions,
    printerStatus: sdk?.status,
    zoneDimensions: sdk?.zoneDimensions,
    supplyWidth: sdk?.supplyWidth,
    supplyHeight: sdk?.supplyHeight,
    cutReady: typeof sdk?.cut === "function",
  };
}
async function publish() {
  await api("/relay", "POST", relayStatus());
}
function detail(label, value) {
  if (value === undefined || value === null || value === "") return;
  const dt = document.createElement("dt"),
    dd = document.createElement("dd");
  dt.textContent = label;
  dd.textContent = String(value);
  $("details").append(dt, dd);
}
async function showJobs(jobs) {
  const key = jobs.map((j) => `${j.id}:${j.state}`).join(",");
  if (key === previewKey) return;
  const fragment = document.createDocumentFragment();
  const nextUrls = [];
  try {
    for (const job of jobs) {
      if (job.action === "cut") {
        const article = document.createElement("article"),
          caption = document.createElement("p");
        article.className = "job";
        caption.textContent = `${job.title} · ${job.state}`;
        article.append(caption);
        fragment.append(article);
        continue;
      }
      const response = await api(`/jobs/${job.id}.png`);
      const url = URL.createObjectURL(await response.blob());
      nextUrls.push(url);
      const article = document.createElement("article"),
        img = document.createElement("img"),
        caption = document.createElement("p");
      article.className = "job";
      img.src = url;
      img.alt = job.title;
      caption.textContent = `${job.title} · ${job.state}`;
      article.append(img, caption);
      fragment.append(article);
    }
  } catch (error) {
    nextUrls.forEach(URL.revokeObjectURL);
    throw error;
  }
  urls.forEach(URL.revokeObjectURL);
  urls = nextUrls;
  $("jobs").replaceChildren(fragment);
  previewKey = key;
}
const attempted = new Set();
async function dispatch(job) {
  if (attempted.has(job.id) || !sdk?.isConnected()) return;
  if (sdk.printerName !== job.printer || sdk.supplyName !== job.supply)
    throw new Error("Print blocked: connected printer or cartridge changed.");
  attempted.add(job.id);
  let url;
  try {
    let image;
    if (job.action !== "cut") {
      image = new Image();
      url = URL.createObjectURL(
        await (await api(`/jobs/${job.id}.png`)).blob(),
      );
      image.src = url;
      await image.decode();
    }
    // Claim is non-retriable: server writes a durable single-use marker first.
    await api(`/jobs/${job.id}/claim`, "POST", { clientId });
    let success = false,
      message;
    try {
      if (
        !sdk.isConnected() ||
        sdk.printerName !== job.printer ||
        sdk.supplyName !== job.supply
      )
        throw new Error("Printer or supply changed before dispatch");
      if (job.action === "cut") {
        success = (await sdk.cut()) === true;
        message = success
          ? "Brady SDK confirmed the cut operation. No printing or feeding requested."
          : "Cut outcome uncertain. Inspect printer; no automatic retry.";
      } else {
        sdk.setCopies(1);
        sdk.setCutOption(2); // Never: job option only, no explicit cut/feed/settings call.
        success = (await sdk.printBitmap(image)) === true;
        message = success
          ? "Brady SDK confirmed the print operation. Check the physical label."
          : "SDK did not confirm printing. Inspect printer; do not retry automatically.";
      }
    } catch (error) {
      message = `Operation outcome uncertain: ${error.message}. No retry.`;
    }
    relayMessage = message;
    await api(`/jobs/${job.id}/result`, "POST", { clientId, success, message });
    notice(message);
  } finally {
    if (url) URL.revokeObjectURL(url);
  }
}
async function poll() {
  try {
    if (relay) {
      await publish();
      $("connect").disabled =
        connecting || !canConnect || sdk?.isConnected() === true;
    }
    const state = await (await api()).json();
    const status = state.relay;
    const connected = status?.connected === true;
    $("state").textContent = connected
      ? "Connected"
      : status?.stale
        ? "Relay offline"
        : status
          ? "Not connected"
          : "Waiting for Chrome";
    $("state").classList.toggle("live", connected);
    $("details").replaceChildren();
    if (status) {
      detail("Model", status.model);
      detail("Printer", status.name);
      detail("Supply", status.supply);
      detail("Size", status.dimensions);
      detail("Status", status.printerStatus);
      detail("Message", status.message);
    }
    $("sync").textContent =
      `${status?.stale ? "Last report" : "Synced"} ${new Date().toLocaleTimeString()} · session expires ${new Date(state.expiresAt).toLocaleTimeString()}`;
    $("count").textContent = state.jobs.length;
    $("safety-title").textContent = state.printAuthorization
      ? "One authorized label."
      : "Preview only.";
    $("safety-message").textContent = state.printAuthorization
      ? `CLI may send one copy of ${state.printAuthorization.text}. ${state.cutAuthorized ? "One separate cut is authorized." : "No cutting authorized."} No automatic retries, feeding or printer-setting changes.`
      : "Printing is disabled for this session. There are no feed, cut, reset or configuration controls.";
    $("badge").textContent = state.printAuthorization
      ? "SINGLE-USE PRINT AUTHORIZATION"
      : "PREVIEW ONLY";
    await showJobs(state.jobs);
    if (relay) {
      const job = state.jobs.find((j) => j.state === "queued");
      if (job) await dispatch(job);
    }
  } catch (error) {
    notice(error.message);
    $("state").textContent = "Status unavailable";
    $("state").classList.remove("live");
    $("connect").disabled = true;
  } finally {
    setTimeout(poll, 5000);
  }
}
async function start() {
  $("welcome").hidden = !!config || relay;
  $("workspace").hidden = !config;
  if (!config) {
    if (relay)
      notice(
        "Open the private relay link from the CLI or control page. Do not use the control link in this tab.",
      );
    return;
  }
  $("copy-relay").hidden = relay || !config.relayToken;
  $("composer").hidden = relay;
  if (relay) {
    $("heading").textContent = "Your Mac is the Bluetooth bridge.";
    $("subtitle").textContent =
      "Keep this Chrome tab open. Only an explicitly authorized CLI print job can print; previews never print automatically.";
    $("connection-title").textContent = "Connect the M211";
    $("connection-help").textContent =
      "Select your M211 in the browser chooser. Reconnecting after a refresh reuses the ownership ID stored by Brady’s SDK on this origin.";
    $("connect").hidden = false;
    $("connect").disabled = true;
    $("disconnect").hidden = false;
    if (!isSecureContext || !navigator.bluetooth) {
      relayMessage =
        "Web Bluetooth unavailable. Open this relay link in Google Chrome on your Mac over HTTPS; Zen/Firefox cannot connect.";
      $("capability").textContent = relayMessage;
    } else {
      $("capability").textContent = "Loading Brady Web SDK 3.3.3…";
      try {
        const { default: BradySdk } = await import("/sdk/bundle.js");
        // 3.3.3 reads and writes localStorage.ownershipID internally. Do not overwrite it
        // with the boolean returned by showDiscoveredBleDevices, or clear it on refresh.
        sdk = new BradySdk(() => {
          if (sdk) {
            $("disconnect").disabled = !sdk.isConnected();
            if (!sdk.isConnected())
              relayMessage = "Disconnected. Click Connect M211 to reconnect.";
            publish().catch((error) => notice(error.message));
          }
        }, false);
        canConnect = true;
        $("capability").textContent =
          "SDK ready · Web Bluetooth available · analytics disabled";
      } catch (error) {
        relayMessage = `SDK failed to load: ${error.message}`;
        notice(relayMessage);
      }
    }
  }
  poll();
}
$("create").addEventListener("click", async () => {
  $("create").disabled = true;
  try {
    const response = await fetch("/api/sessions", { method: "POST" });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error);
    config = {
      id: result.id,
      token: result.controlToken,
      relayToken: result.relayToken,
    };
    localStorage.setItem(storageKey, JSON.stringify(config));
    await start();
  } catch (error) {
    notice(error.message);
    $("create").disabled = false;
  }
});
$("copy-relay").addEventListener("click", async () => {
  try {
    const fragment = new URLSearchParams({
      session: config.id,
      token: config.relayToken,
    });
    await navigator.clipboard.writeText(`${location.origin}/relay#${fragment}`);
    notice(
      "Relay link copied. Open it in Chrome on the Mac near the printer. Treat the link as private.",
    );
  } catch {
    notice(
      "Clipboard unavailable. Use the CLI “links” command to obtain the private relay link.",
    );
  }
});
$("label-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("submit-labels").disabled = true;
  try {
    const items = $("labels")
      .value.split(/\r?\n/)
      .filter((s) => s.trim())
      .map((text) => ({ text }));
    await api("/jobs", "POST", {
      items,
      widthMm: Number($("width").value),
      heightMm: Number($("height").value),
    });
    $("labels").value = "";
    notice(
      "Labels queued for preview only. Printing requires a separate authorized CLI command.",
    );
  } catch (error) {
    notice(error.message);
  } finally {
    $("submit-labels").disabled = false;
  }
});
$("connect").addEventListener("click", async () => {
  if (!sdk || !canConnect || connecting) return;
  connecting = true;
  $("connect").disabled = true;
  relayMessage = "Waiting for chooser / connection…";
  notice();
  try {
    // Call directly from this click: no network await before the browser’s user gesture.
    const connected = await sdk.showDiscoveredBleDevices();
    relayMessage =
      connected && sdk.isConnected()
        ? "Connected through local Bluetooth."
        : sdk.getConnectionErrorMessage() ||
          "No connection. Chooser cancelled or printer unavailable.";
    if (!sdk.isConnected()) notice(relayMessage);
    $("disconnect").disabled = !sdk.isConnected();
    await publish();
  } catch (error) {
    relayMessage = `Connection failed: ${error.message}`;
    notice(relayMessage);
  } finally {
    connecting = false;
    $("connect").disabled = sdk.isConnected();
  }
});
$("disconnect").addEventListener("click", async () => {
  if (!sdk?.isConnected()) return;
  try {
    if (!(await sdk.disconnect()))
      throw new Error("Disconnect did not complete.");
    relayMessage =
      "Disconnected and released by request. No printer settings changed.";
    $("disconnect").disabled = true;
    $("connect").disabled = false;
    await publish();
  } catch (error) {
    notice(error.message);
  }
});
start().catch((error) => notice(error.message));
