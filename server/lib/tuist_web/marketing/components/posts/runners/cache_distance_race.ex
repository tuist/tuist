defmodule TuistWeb.Marketing.Components.Posts.Runners.CacheDistanceRace do
  @moduledoc """
  Races the same set of cache downloads from three distances, from the in-rack
  cache node to another continent, for the Tuist Runners announcement.
  """
  use TuistWeb, :live_component
  use Noora

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CacheDistanceRace">
      const IN_FLIGHT = 16;
      const ANIMATION_MS = 4000;
      const WORKLOADS = {
        xcode: { label: "requests", sizeMB: 0.04, min: 1000, max: 20000, step: 500, value: 5000 },
        module: { label: "binaries", sizeMB: 20, min: 10, max: 300, step: 10, value: 80 },
      };
      const ORIGINS = { rack: { rtt: 0.3, mbps: 1000 }, region: { rtt: 20, mbps: 100 }, remote: { rtt: 120, mbps: 25 } };

      const formatDuration = (ms) => {
        if (ms < 1000) return `${Math.round(ms)} ms`;
        if (ms < 60000) return `${(ms / 1000).toFixed(1)} s`;
        const minutes = Math.floor(ms / 60000);
        return `${minutes} min ${Math.round((ms % 60000) / 1000)} s`;
      };

      export default {
        mounted() {
          this.workload = "xcode";
          this.count = this.el.querySelector("[data-count]");
          this.countValue = this.el.querySelector("[data-count-value]");
          this.lanes = [...this.el.querySelectorAll("[data-origin]")];
          this.onInput = () => { this.stop(); this.draw(1); };
          this.onClick = (event) => {
            const workload = event.target.closest("[data-workload]");
            if (workload) this.setWorkload(workload.dataset.workload);
            if (event.target.closest("[data-play]")) this.play();
          };
          this.count.addEventListener("input", this.onInput);
          this.el.addEventListener("click", this.onClick);
          this.setWorkload("xcode");
        },

        destroyed() {
          this.stop();
          this.count.removeEventListener("input", this.onInput);
          this.el.removeEventListener("click", this.onClick);
        },

        setWorkload(key) {
          const workload = WORKLOADS[key];
          this.workload = key;
          this.stop();
          this.el.querySelectorAll("[data-workload]").forEach((button) => {
            button.setAttribute("aria-pressed", button.dataset.workload === key ? "true" : "false");
          });
          Object.assign(this.count, { min: workload.min, max: workload.max, step: workload.step });
          this.count.value = workload.value;
          this.draw(1);
        },

        totals() {
          const workload = WORKLOADS[this.workload];
          const count = Number(this.count.value);
          return Object.fromEntries(Object.entries(ORIGINS).map(([key, origin]) => {
            const waiting = Math.ceil(count / IN_FLIGHT) * origin.rtt;
            const transferring = (count * workload.sizeMB) / origin.mbps * 1000;
            return [key, waiting + transferring];
          }));
        },

        draw(progress) {
          const workload = WORKLOADS[this.workload];
          const count = Number(this.count.value);
          const totals = this.totals();
          const slowest = Math.max(...Object.values(totals));
          const elapsed = slowest * progress;
          const sizeLabel = workload.sizeMB < 1 ? `${workload.sizeMB * 1000} KB` : `${workload.sizeMB} MB`;
          this.countValue.textContent =
            `${count.toLocaleString("en-US")} ${workload.label} · ${sizeLabel} each`;
          this.count.setAttribute("aria-valuetext", this.countValue.textContent);

          this.lanes.forEach((lane) => {
            const total = totals[lane.dataset.origin];
            const shown = Math.min(elapsed, total);
            const done = elapsed >= total;
            lane.querySelector("[data-fill]").style.width = `${(shown / slowest) * 100}%`;
            lane.toggleAttribute("data-done", done);
            lane.querySelector("[data-time]").textContent = formatDuration(shown);
            const ratio = total / totals.rack;
            lane.querySelector("[data-ratio]").textContent =
              lane.dataset.origin === "rack" ? "" : done ? `${Math.round(ratio)}× slower than the rack` : "";
          });
        },

        play() {
          this.stop();
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            this.draw(1);
            return;
          }
          const start = performance.now();
          const frame = (now) => {
            const progress = Math.min((now - start) / ANIMATION_MS, 1);
            this.draw(progress);
            if (progress < 1) this.frame = requestAnimationFrame(frame);
          };
          this.frame = requestAnimationFrame(frame);
        },

        stop() {
          cancelAnimationFrame(this.frame);
        },
      };
    </script>

    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="cache-distance-race"] {
        margin: var(--noora-spacing-7) 0;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);

        & [data-part="controls"] {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: var(--noora-spacing-5);
          margin-bottom: var(--noora-spacing-6);
        }

        & [data-part="workloads"] {
          display: flex;
          flex-wrap: wrap;
          gap: var(--noora-spacing-3);
        }

        & button {
          padding: var(--noora-spacing-3) var(--noora-spacing-5);
          border: 1px solid var(--marketing-stroke-default);
          border-radius: var(--noora-radius-3);
          background: var(--noora-surface-background-primary);
          color: var(--noora-surface-label-primary);
          font: var(--noora-font-weight-medium) var(--noora-font-body-small);
          cursor: pointer;
        }

        & button[aria-pressed="true"] {
          border-color: var(--noora-button-primary-background);
          color: var(--noora-button-primary-background);
        }

        & [data-play] {
          border-color: var(--noora-button-primary-background);
          background: var(--noora-button-primary-background);
          color: var(--noora-button-primary-label);
        }

        & [data-part="count"] {
          display: flex;
          flex-direction: column;
          gap: var(--noora-spacing-3);
          margin-bottom: var(--noora-spacing-7);
        }

        & input[type="range"] {
          width: 100%;
          margin: 0;
          accent-color: var(--noora-button-primary-background);
        }

        & output { color: var(--noora-surface-label-secondary); }

        & [data-origin] + [data-origin] { margin-top: var(--noora-spacing-6); }

        & [data-part="heading"] {
          display: flex;
          flex-wrap: wrap;
          justify-content: space-between;
          gap: var(--noora-spacing-2);
          margin-bottom: var(--noora-spacing-3);
        }

        & [data-part="where"] { color: var(--noora-surface-label-secondary); }

        & [data-part="bar"] {
          height: 22px;
          border-radius: var(--noora-radius-2);
          background: var(--noora-surface-background-secondary);
          overflow: hidden;
        }

        & [data-fill] {
          height: 100%;
          min-width: 3px;
          background: var(--noora-surface-label-secondary);
        }

        & [data-origin="rack"] [data-fill] { background: var(--noora-button-primary-background); }

        & [data-time] { font-variant-numeric: tabular-nums; }

        & [data-ratio] {
          min-height: 1.4em;
          margin-top: var(--noora-spacing-2);
          color: var(--noora-surface-label-secondary);
        }

        & [data-part="note"] {
          margin-top: var(--noora-spacing-6);
          color: var(--noora-surface-label-tertiary);
        }
      }
    </style>

    <div id={@id} data-part="cache-distance-race" phx-hook=".CacheDistanceRace" phx-update="ignore">
      <.card icon="database" title="Where the cache lives">
        <.card_section>
          <div data-part="controls">
            <div data-part="workloads" role="group" aria-label="Workload">
              <button type="button" data-workload="xcode" aria-pressed="true">
                Xcode compilation cache
              </button>
              <button type="button" data-workload="module" aria-pressed="false">
                Module cache
              </button>
            </div>
            <button type="button" data-play>Play</button>
          </div>

          <div data-part="count">
            <label for={@id <> "-count"}>How much the build downloads</label>
            <input
              id={@id <> "-count"}
              data-count
              type="range"
              min="1000"
              max="20000"
              step="500"
              value="5000"
            />
            <output for={@id <> "-count"} data-count-value>5,000 requests · 40 KB each</output>
          </div>

          <div data-origin="rack">
            <div data-part="heading">
              <span>
                <strong>In the rack</strong>
                <span data-part="where">· 0.3 ms round trip, 1 GB/s</span>
              </span>
              <span data-time></span>
            </div>
            <div data-part="bar" aria-hidden="true">
              <div data-fill></div>
            </div>
            <div data-ratio></div>
          </div>

          <div data-origin="region">
            <div data-part="heading">
              <span>
                <strong>A nearby region, over the internet</strong>
                <span data-part="where">· 20 ms round trip, 100 MB/s</span>
              </span>
              <span data-time></span>
            </div>
            <div data-part="bar" aria-hidden="true">
              <div data-fill></div>
            </div>
            <div data-ratio></div>
          </div>

          <div data-origin="remote">
            <div data-part="heading">
              <span>
                <strong>Another continent</strong>
                <span data-part="where">· 120 ms round trip, 25 MB/s</span>
              </span>
              <span data-time></span>
            </div>
            <div data-part="bar" aria-hidden="true">
              <div data-fill></div>
            </div>
            <div data-ratio></div>
          </div>

          <div data-part="note">
            Illustrative values: 16 requests in flight at a time, connections already established,
            and every request a cache hit. Disk and server processing time are excluded.
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end
end
