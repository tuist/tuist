defmodule TuistWeb.Marketing.Components.Posts.Runners.RackElevation do
  @moduledoc """
  A simplified, clickable front view of the Berlin rack for the Tuist Runners
  announcement. Each part of the rack explains its role.
  """
  use TuistWeb, :live_component
  use Noora

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".RackElevation">
      const UNITS = {
        tor: {
          title: "Top-of-rack switches",
          role: "Network",
          body: "Two switches, A and B, linked to each other. Every Mac mini plugs into one of them over 10 Gb/s copper, and the edge and storage nodes connect over 25 Gb/s. The switches also carry the uplink and the rack's management traffic, so there is no separate management switch: a device's management port sits on the switch opposite its data link, and losing one switch never takes out both.",
          facts: ["10 Gb/s to every Mac mini, 25 Gb/s to every Linux node", "Configured from the open-source site definition"],
        },
        edge: {
          title: "Edge nodes",
          role: "Linux · active and standby",
          body: "Two 1U x86 servers that share floating addresses, one active and one on standby, each with a 25 Gb/s link to both switches. They terminate the uplink, announce our own IP range over BGP, and serve the DHCP and network boot that let a new machine join the cluster without anyone touching it. Each one also holds the console of one of the switches.",
          facts: ["Failover without dropping the uplink", "Zero-touch install of new hosts", "Their own BMCs for out-of-band access"],
        },
        store: {
          title: "Storage and cache nodes",
          role: "Linux · the rack's cache",
          body: "Two x86 servers, one on each switch over 25 Gb/s, that run the rack's own Kura cache region, replicating with the rest of the Kura mesh, and store the cache volumes the runners attach to. Each Mac mini shares a switch with one of them, so a cache request never leaves the rack.",
          facts: ["Kura cache region for the rack", "Cache volumes for every runner", "One node per switch, so losing a switch never takes out both"],
        },
        minis: {
          title: "Mac minis",
          role: "Runners",
          body: "M5 Pro Mac minis with 64 GB of memory and 10 Gb/s Ethernet. Each one runs macOS virtual machines, and every job gets a fresh VM, so nothing leaks from one job to the next. Half of them are on switch A and power chain A, the other half on B, and the switches have room for more.",
          facts: ["A fresh macOS VM for every job", "Warm cache volumes attached on start"],
        },
        power: {
          title: "Power",
          role: "Two feeds, two chains",
          body: "Two independent power feeds go into two automatic transfer switches, which keep the rack running when a feed fails. Each one feeds a switched PDU for one half of the Mac minis, whose outlets we can meter and power-cycle remotely. That is how we reboot a Mac mini that stopped responding. The switches and Linux nodes have two power supplies and take a feed each.",
          facts: ["Every outlet metered", "Remote power-cycle per Mac mini"],
        },
      };

      export default {
        mounted() {
          this.title = this.el.querySelector("[data-detail-title]");
          this.role = this.el.querySelector("[data-detail-role]");
          this.body = this.el.querySelector("[data-detail-body]");
          this.facts = this.el.querySelector("[data-detail-facts]");
          this.onClick = (event) => {
            const unit = event.target.closest("[data-unit]");
            if (unit) this.select(unit.dataset.unit);
          };
          this.el.addEventListener("click", this.onClick);
          this.select("store");
        },

        destroyed() {
          this.el.removeEventListener("click", this.onClick);
        },

        select(key) {
          const unit = UNITS[key];
          if (!unit) return;
          this.el.querySelectorAll("[data-unit]").forEach((element) => {
            const selected = element.dataset.unit === key;
            element.toggleAttribute("data-selected", selected);
            element.setAttribute("aria-pressed", selected ? "true" : "false");
          });
          this.title.textContent = unit.title;
          this.role.textContent = unit.role;
          this.body.textContent = unit.body;
          this.facts.replaceChildren(...unit.facts.map((fact) => {
            const item = document.createElement("li");
            item.textContent = fact;
            return item;
          }));
        },
      };
    </script>

    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="rack-elevation"] {
        --rack-frame: #2a2a31;
        --rack-unit: #1b1b20;
        --rack-unit-edge: #34343c;
        --rack-port: #0b0b0e;
        --rack-led: #4ade80;
        --rack-mini: #c9cacf;
        --rack-label: #d9d8de;
        --rack-accent: var(--noora-button-primary-background);
        margin: var(--noora-spacing-7) 0;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);

        & [data-part="layout"] {
          display: grid;
          grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr);
          gap: var(--noora-spacing-7);
          align-items: start;
        }

        & [data-part="frame"] {
          display: flex;
          flex-direction: column;
          gap: 3px;
          padding: 10px 18px;
          border-radius: 10px;
          background: var(--rack-frame);
          box-shadow: inset 0 0 0 1px #3c3c46;
        }

        & [data-part="row"] {
          display: flex;
          gap: 3px;
        }

        & [data-unit] {
          position: relative;
          display: flex;
          flex: 1;
          align-items: center;
          gap: 6px;
          min-height: 22px;
          padding: 3px 8px;
          border: 1px solid var(--rack-unit-edge);
          border-radius: 3px;
          background: var(--rack-unit);
          color: var(--rack-label);
          font: var(--noora-font-weight-medium) 0.625rem/1 var(--noora-font-family-body, inherit);
          letter-spacing: 0.02em;
          text-align: left;
          cursor: pointer;
          transition: border-color 0.2s, box-shadow 0.2s, background 0.2s;
        }

        & [data-unit]:hover { border-color: #6b6b78; }
        & [data-unit]:focus-visible { outline: 2px solid var(--rack-accent); outline-offset: 1px; }
        & [data-unit][data-selected] {
          border-color: var(--rack-accent);
          box-shadow: 0 0 0 1px var(--rack-accent);
        }

        & [data-unit="store"][data-variant="cache"] {
          background: color-mix(in srgb, var(--rack-accent) 32%, var(--rack-unit));
        }

        & [data-part="label"] { white-space: nowrap; }

        & [data-part="ports"] {
          display: flex;
          flex: 1;
          justify-content: flex-end;
          gap: 2px;
        }

        & [data-part="ports"] i {
          display: block;
          width: 5px;
          height: 7px;
          border-radius: 1px;
          background: var(--rack-port);
          box-shadow: inset 0 -2px 0 #2b2b33;
        }

        & [data-part="led"] {
          width: 4px;
          height: 4px;
          border-radius: 50%;
          background: var(--rack-led);
          box-shadow: 0 0 4px var(--rack-led);
          flex: none;
        }

        & [data-unit="minis"] {
          min-height: 30px;
          justify-content: space-between;
        }

        & [data-part="tray"] {
          display: flex;
          gap: 6px;
        }

        & [data-part="mini"] {
          display: block;
          width: 38px;
          height: 16px;
          border-radius: 4px;
          background: linear-gradient(180deg, #e3e4e8, var(--rack-mini));
          box-shadow: inset 0 -2px 0 #9a9ba1;
        }

        & [data-part="details"] {
          display: flex;
          flex-direction: column;
          gap: var(--noora-spacing-3);
          padding: var(--noora-spacing-6);
          border: 1px solid var(--marketing-stroke-default);
          border-radius: var(--noora-radius-4, 8px);
          background: var(--noora-surface-background-secondary);
        }

        & [data-detail-title] {
          margin: 0;
          font: var(--noora-font-weight-semibold) var(--noora-font-body-large);
        }

        & [data-detail-role] {
          color: var(--rack-accent);
          font: var(--noora-font-weight-medium) var(--noora-font-body-small);
        }

        & [data-detail-body] {
          margin: 0;
          color: var(--noora-surface-label-secondary);
          font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
        }

        & [data-detail-facts] {
          margin: 0;
          padding-left: var(--noora-spacing-6);
          color: var(--noora-surface-label-primary);
        }

        & [data-part="note"] {
          margin-top: var(--noora-spacing-6);
          color: var(--noora-surface-label-tertiary);
        }

        @media (max-width: 640px) {
          & [data-part="layout"] { grid-template-columns: 1fr; }
          & [data-part="frame"] { padding: 8px 10px; }
          & [data-part="mini"] { width: 30px; }
        }

        @media (prefers-reduced-motion: reduce) {
          & * { transition: none !important; }
        }
      }
    </style>

    <div id={@id} data-part="rack-elevation" phx-hook=".RackElevation" phx-update="ignore">
      <.card icon="server" title="Our rack">
        <.card_section>
          <div data-part="layout">
            <div>
              <div data-part="frame" aria-label="Rack front view">
                <button type="button" data-unit="tor">
                  <span data-part="led"></span>
                  <span data-part="label">Switch A</span>
                  <span data-part="ports" aria-hidden="true">
                    <i :for={_ <- 1..16}></i>
                  </span>
                </button>
                <button type="button" data-unit="tor">
                  <span data-part="led"></span>
                  <span data-part="label">Switch B</span>
                  <span data-part="ports" aria-hidden="true">
                    <i :for={_ <- 1..16}></i>
                  </span>
                </button>
                <div data-part="row">
                  <button type="button" data-unit="edge">
                    <span data-part="led"></span>
                    <span data-part="label">Edge A</span>
                  </button>
                  <button type="button" data-unit="edge">
                    <span data-part="led"></span>
                    <span data-part="label">Edge B</span>
                  </button>
                </div>
                <div data-part="row">
                  <button type="button" data-unit="store" data-variant="cache">
                    <span data-part="led"></span>
                    <span data-part="label">Storage A</span>
                  </button>
                  <button type="button" data-unit="store" data-variant="cache">
                    <span data-part="led"></span>
                    <span data-part="label">Storage B</span>
                  </button>
                </div>
                <button
                  :for={{count, index} <- Enum.with_index([3, 2, 3, 2])}
                  type="button"
                  data-unit="minis"
                >
                  <span data-part="label">Tray {index + 1}</span>
                  <span data-part="tray" aria-hidden="true">
                    <span :for={_ <- 1..count} data-part="mini"></span>
                  </span>
                </button>
                <div data-part="row">
                  <button type="button" data-unit="power">
                    <span data-part="led"></span>
                    <span data-part="label">PDU A</span>
                  </button>
                  <button type="button" data-unit="power">
                    <span data-part="led"></span>
                    <span data-part="label">PDU B</span>
                  </button>
                </div>
                <div data-part="row">
                  <button type="button" data-unit="power">
                    <span data-part="led"></span>
                    <span data-part="label">Transfer switch A</span>
                  </button>
                  <button type="button" data-unit="power">
                    <span data-part="led"></span>
                    <span data-part="label">Transfer switch B</span>
                  </button>
                </div>
              </div>
            </div>

            <div data-part="details" aria-live="polite">
              <span data-detail-role></span>
              <h4 data-detail-title></h4>
              <p data-detail-body></p>
              <ul data-detail-facts></ul>
            </div>
          </div>

          <div data-part="note">
            A simplified front view. Positions are illustrative; the devices and how they connect
            come from the rack's open-source site definition.
          </div>
        </.card_section>
      </.card>
    </div>
    """
  end
end
