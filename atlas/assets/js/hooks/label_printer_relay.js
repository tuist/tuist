export default {
  async mounted() {
    this.stopped = false;
    const id = this.el.dataset.sessionId;
    let token;
    const capability = this.el.querySelector("#capability");
    try {
      const storageKey = `atlas-label-relay:${id}`;
      const params = new URLSearchParams(location.hash.slice(1));
      token = params.get("token") || localStorage.getItem(storageKey);
      if (params.has("token")) {
        localStorage.setItem(storageKey, token);
        history.replaceState(null, "", location.pathname);
      }
      if (!token)
        throw new Error(
          "Reopen the full private connection link from your agent.",
        );
    } catch (error) {
      capability.textContent = `Relay not started: ${error.message}`;
      return;
    }
    const api = async (tail = "", method = "GET", body) => {
      const response = await fetch(`/api/labels/relay/sessions/${id}${tail}`, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      if (!response.ok)
        throw new Error(
          (await response.json()).error || `HTTP ${response.status}`,
        );
      return response;
    };
    let sdk,
      connecting = false,
      ready = false,
      message = "Waiting for connection.";
    const connect = this.el.querySelector("#connect");
    const disconnect = this.el.querySelector("#disconnect");
    const attempted = new Set();
    let clientId;
    try {
      clientId = sessionStorage.getItem("m211-client") || crypto.randomUUID();
      sessionStorage.setItem("m211-client", clientId);
    } catch {
      capability.textContent =
        "Browser storage is required to preserve the relay identity. No output will be sent.";
      return;
    }
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
      cutReady: typeof sdk?.cut === "function",
    });
    const publish = () => api("/relay", "POST", report());
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
      zonesKey(sdk.zoneDimensions) === zonesKey(job.zoneDimensions);
    const dispatch = async (job) => {
      if (this.stopped || attempted.has(job.id) || !sdk?.isConnected()) return;
      if (!sameSupply(job))
        throw new Error("Printer or supply changed. Output blocked.");
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
        // Exclusive, durable server-side consumption must succeed before any SDK output.
        await api(`/jobs/${job.id}/claim`, "POST", { clientId });
        let success = false;
        try {
          if (this.stopped || !sdk.isConnected() || !sameSupply(job))
            throw new Error("Printer or supply changed");
          if (job.action === "cut") success = (await sdk.cut()) === true;
          else {
            sdk.setCopies(1);
            sdk.setCutOption(2); // Never cut as part of printing.
            success = (await sdk.printBitmap(image)) === true;
          }
          message = success
            ? "Brady SDK confirmed operation. Check the physical label."
            : "Outcome uncertain. Inspect printer; never retry automatically.";
        } catch (error) {
          message = `Outcome uncertain: ${error.message}. No retry.`;
        }
        await api(`/jobs/${job.id}/result`, "POST", {
          clientId,
          success,
          message,
        });
      } finally {
        if (url) URL.revokeObjectURL(url);
      }
    };
    const poll = async () => {
      if (this.stopped) return;
      try {
        await publish();
        const state = await (await api()).json();
        const job = state.jobs.find((j) => j.state === "queued");
        if (job) await dispatch(job);
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
