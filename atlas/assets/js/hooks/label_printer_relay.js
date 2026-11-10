export default {
  async mounted() {
    this.stopped = false;
    const id = this.el.dataset.sessionId;
    const storageKey = `atlas-label-relay:${id}`;
    const capability = this.el.querySelector("#capability");
    let token, clientId;
    try {
      clientId = sessionStorage.getItem("m211-client") || crypto.randomUUID();
      sessionStorage.setItem("m211-client", clientId);
      const params = new URLSearchParams(location.hash.slice(1));
      token = params.get("token") || localStorage.getItem(storageKey);
      if (params.has("token")) {
        localStorage.setItem(storageKey, token);
        history.replaceState(null, "", location.pathname);
      }
    } catch {
      capability.textContent =
        "Browser storage is required to preserve the relay identity. No output will be sent.";
      return;
    }
    // The link's #token fragment does not survive every route here (sign-in
    // round trips drop it), so the signed-in owner's page can ask Atlas for a
    // fresh relay capability. Atlas refuses while another relay tab is active.
    const issueToken = () =>
      new Promise((resolve, reject) =>
        this.pushEvent("relay_token", { clientId }, (reply) => {
          if (!reply?.token)
            return reject(new Error(reply?.error || "Relay not started."));
          localStorage.setItem(storageKey, reply.token);
          resolve(reply.token);
        }),
      );
    if (!token) {
      try {
        token = await issueToken();
      } catch (error) {
        capability.textContent = `Relay not started: ${error.message}`;
        return;
      }
    }
    const api = async (tail = "", method = "GET", body, renewed = false) => {
      const response = await fetch(`/api/labels/relay/sessions/${id}${tail}`, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      // A stored capability can be outdated; Atlas did nothing for a 401.
      if (response.status === 401 && !renewed) {
        token = await issueToken();
        return api(tail, method, body, true);
      }
      if (!response.ok)
        throw new Error(
          (await response.json()).error || `HTTP ${response.status}`,
        );
      return response;
    };
    let sdk,
      connecting = false,
      ready = false,
      // Tells Atlas this page has no operation in flight, so anything it still
      // shows as dispatched is uncertain and queued output stops.
      restarted = true,
      message = "Waiting for connection.";
    const connect = this.el.querySelector("#connect");
    const disconnect = this.el.querySelector("#disconnect");
    const attempted = new Set();
    const report = () => ({
      clientId,
      connected: sdk?.isConnected() === true,
      message,
      model: sdk?.printerModel,
      name: sdk?.printerName,
      supply: sdk?.supplyName,
      dimensions: sdk?.supplyDimensions,
      printerStatus: sdk?.status,
      zoneDimensions: sdk?.zoneDimensions,
      supplyWidth: sdk?.supplyWidth,
      supplyHeight: sdk?.supplyHeight,
      mediaIsDieCut: sdk?.mediaIsDieCut,
      cutReady: typeof sdk?.cut === "function",
      restarted,
    });
    const publish = async () => {
      await api("/relay", "POST", report());
      restarted = false;
    };
    const buttons = () => {
      connect.disabled = connecting || !ready || sdk?.isConnected() === true;
      disconnect.disabled = connecting || !sdk?.isConnected();
    };
    // PostgreSQL JSONB reorders object keys; compare content, not SDK key order.
    const zonesKey = (zones) =>
      JSON.stringify(
        zones?.map((zone) =>
          Object.entries(zone).sort(([a], [b]) => a.localeCompare(b)),
        ),
      );
    const sameSupply = (job) =>
      sdk.printerName === job.printer &&
      sdk.supplyName === job.supply &&
      String(sdk.supplyWidth ?? "") === job.supplyWidth &&
      String(sdk.supplyHeight ?? "") === job.supplyHeight &&
      (sdk.mediaIsDieCut ?? null) === job.mediaIsDieCut &&
      zonesKey(sdk.zoneDimensions) === zonesKey(job.zoneDimensions);
    // Returns true only when the next queued label may follow.
    const dispatch = async (job) => {
      if (this.stopped || attempted.has(job.id) || !sdk?.isConnected())
        return false;
      if (!sameSupply(job))
        throw new Error("Printer or supply changed. Output blocked.");
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
        await publish(); // Keep the relay lease fresh during long batches.
        // Exclusive, durable server-side consumption must succeed before any SDK output.
        await api(`/jobs/${job.id}/claim`, "POST", { clientId });
        attempted.add(job.id);
        let success = false;
        let cutSuccess = null;
        let failure;
        try {
          if (this.stopped || !sdk.isConnected() || !sameSupply(job))
            throw new Error("Printer or supply changed");
          if (job.action === "cut") success = (await sdk.cut()) === true;
          else {
            // One label per print call so every label gets its own SDK result.
            // printBitmaps reports one boolean for the whole job.
            sdk.setCopies(1);
            sdk.setCutOption(2); // Never cut inside the print job.
            success = (await sdk.printBitmap(image)) === true;
            if (success && job.cut) {
              cutSuccess = false;
              cutSuccess = (await sdk.cut()) === true;
            }
          }
        } catch (error) {
          failure = error.message;
        }
        const ok =
          success && (job.action === "cut" || !job.cut || cutSuccess === true);
        message = ok
          ? `Brady SDK confirmed ${job.title}. Check the physical label.`
          : `Outcome uncertain for ${job.title}${failure ? `: ${failure}` : ""}. Inspect printer; never retry automatically.`;
        await api(`/jobs/${job.id}/result`, "POST", {
          clientId,
          success,
          cutSuccess,
          message,
        });
        return ok;
      } finally {
        if (url) URL.revokeObjectURL(url);
      }
    };
    const poll = async () => {
      if (this.stopped) return;
      try {
        await publish();
        const state = await (await api()).json();
        const queued = state.jobs
          .filter((j) => j.state === "queued")
          .sort(
            (a, b) => a.queuedAt - b.queuedAt || a.batchIndex - b.batchIndex,
          );
        for (const job of queued) {
          if (!(await dispatch(job))) break;
          capability.textContent = message;
        }
      } catch (error) {
        message = error.message;
      }
      if (!this.stopped) {
        capability.textContent = message;
        buttons();
        this.timer = setTimeout(poll, 5000);
      }
    };
    connect.addEventListener("click", async () => {
      if (!sdk || connecting) return;
      connecting = true;
      buttons();
      message = "Waiting for chooser / connection…";
      capability.textContent = message;
      try {
        // Direct user gesture; no network await before Chrome's Bluetooth chooser.
        const connected = await sdk.showDiscoveredBleDevices();
        message =
          connected && sdk.isConnected()
            ? "Connected through local Bluetooth."
            : sdk.getConnectionErrorMessage() ||
              "Chooser cancelled or printer unavailable.";
      } catch (error) {
        message = error.message;
      } finally {
        connecting = false;
        buttons();
        capability.textContent = message;
        await publish().catch(() => {});
      }
    });
    disconnect.addEventListener("click", async () => {
      if (!sdk?.isConnected()) return;
      connecting = true;
      buttons();
      try {
        if ((await sdk.disconnect()) !== true)
          throw new Error("Disconnect did not complete.");
        message = "Disconnected; printer ownership released.";
      } catch (error) {
        message = error.message;
      } finally {
        connecting = false;
        buttons();
        await publish().catch(() => {});
      }
    });
    if (!isSecureContext || !navigator.bluetooth) {
      message =
        "Web Bluetooth unavailable. Open this private connection link in Google Chrome on the nearby Mac over HTTPS. Zen/Firefox cannot relay Bluetooth.";
    } else {
      capability.textContent = "Loading Brady Web SDK 3.3.3…";
      try {
        const sdkUrl = "/assets/labels-sdk/bundle.js";
        const { default: BradySdk } = await import(sdkUrl);
        if (this.stopped) return;
        // SDK owns localStorage.ownershipID. Discovery returns a boolean, not an ownership ID.
        sdk = new BradySdk(() => {
          if (sdk && !this.stopped) {
            buttons();
            publish().catch(() => {});
          }
        }, false);
        ready = true;
        message = "SDK ready · Web Bluetooth available · analytics disabled";
      } catch (error) {
        message = `SDK failed to load: ${error.message}`;
      }
    }
    buttons();
    poll();
  },
  destroyed() {
    this.stopped = true;
    clearTimeout(this.timer);
  },
};
