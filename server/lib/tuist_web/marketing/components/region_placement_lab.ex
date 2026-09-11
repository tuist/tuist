defmodule TuistWeb.Marketing.Components.RegionPlacementLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".RegionPlacement">
      const NS = "http://www.w3.org/2000/svg"

      const EXPAND = 0.62
      const RETIRE = 0.34

      // Each region's traffic is a slow wave with its own period and phase, so the
      // three lanes cross the thresholds at different moments: one stays busy, one
      // grows into a second instance, one goes quiet and is retired.
      const REGIONS = [
        { label: "us-east", base: 0.72, amplitude: 0.11, rate: 0.34, phase: 0 },
        { label: "eu-central", base: 0.44, amplitude: 0.33, rate: 0.21, phase: -1.2 },
        { label: "ap-northeast", base: 0.50, amplitude: 0.37, rate: 0.16, phase: 2.4 },
      ]

      const CHART_X = 96
      const CHART_RIGHT = 624
      const LANE_TOP = 26
      const LANE_HEIGHT = 74
      const LANE_GAP = 34
      const WINDOW_SECONDS = 26
      const STEP_PX = 4

      function el(name, attrs, text) {
        const node = document.createElementNS(NS, name)
        Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value))
        if (text !== undefined) node.textContent = text
        return node
      }

      function traffic(region, seconds) {
        const wave = Math.sin(seconds * region.rate + region.phase)
        const drift = Math.sin(seconds * region.rate * 0.37 + region.phase * 1.7) * 0.05
        return Math.max(0.04, Math.min(0.98, region.base + region.amplitude * wave + drift))
      }

      export default {
        mounted() {
          this.svg = this.el
          this.root = this.el.closest(".region-placement-lab")
          this.toggle = this.root.querySelector("[data-toggle]")
          this.stats = {
            live: this.root.querySelector("[data-stat-live]"),
            provisioned: this.root.querySelector("[data-stat-provisioned]"),
            retired: this.root.querySelector("[data-stat-retired]"),
          }

          this.running = !window.matchMedia("(prefers-reduced-motion: reduce)").matches
          this.seconds = 0
          this.provisioned = 0
          this.retired = 0
          this.animating = true
          this.lanes = REGIONS.map((region) => ({
            live: traffic(region, 0) >= EXPAND,
          }))

          this.onToggle = () => {
            this.running = !this.running
            this.syncToggle()
          }
          this.toggle.addEventListener("click", this.onToggle)

          this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
          this.onReducedMotionChange = () => this.syncMotion()
          this.reducedMotion.addEventListener("change", this.onReducedMotionChange)

          this.visibilityObserver = new IntersectionObserver(
            ([entry]) => {
              this.isVisible = entry.isIntersecting
              this.syncMotion()
            },
            { threshold: 0.15 },
          )
          this.visibilityObserver.observe(this.el)

          this.build()
          this.syncToggle()
          this.refresh()
          this.draw()

          this.lastTick = performance.now()
          this.frame = window.requestAnimationFrame((now) => this.loop(now))
        },

        destroyed() {
          window.cancelAnimationFrame(this.frame)
          this.visibilityObserver?.disconnect()
          this.reducedMotion?.removeEventListener("change", this.onReducedMotionChange)
          this.toggle?.removeEventListener("click", this.onToggle)
        },

        syncToggle() {
          this.toggle.textContent = this.running ? "Pause" : "Play"
          this.toggle.setAttribute("aria-pressed", String(!this.running))
        },

        syncMotion() {
          this.animating = this.isVisible !== false && !this.reducedMotion.matches
          this.lastTick = performance.now()
        },

        laneTop(index) {
          return LANE_TOP + index * (LANE_HEIGHT + LANE_GAP)
        },

        valueY(index, value) {
          return this.laneTop(index) + LANE_HEIGHT - value * LANE_HEIGHT
        },

        build() {
          this.svg.replaceChildren()
          this.paths = []
          this.badges = []
          this.dots = []

          REGIONS.forEach((region, index) => {
            const top = this.laneTop(index)

            const area = el("path", { class: "region-placement-lab__area" })
            this.svg.append(area)
            this.paths.push(area)

            this.svg.append(el("rect", {
              class: "region-placement-lab__gap",
              x: CHART_X,
              y: this.valueY(index, EXPAND),
              width: CHART_RIGHT - CHART_X,
              height: this.valueY(index, RETIRE) - this.valueY(index, EXPAND),
            }))

            ;[["expand", EXPAND], ["retire", RETIRE]].forEach(([kind, value]) => {
              this.svg.append(el("line", {
                class: `region-placement-lab__threshold region-placement-lab__threshold--${kind}`,
                x1: CHART_X, x2: CHART_RIGHT,
                y1: this.valueY(index, value), y2: this.valueY(index, value),
              }))
              this.svg.append(el("text", {
                class: "region-placement-lab__threshold-label",
                x: CHART_RIGHT + 8,
                y: this.valueY(index, value) + 3,
              }, kind))
            })

            const dot = el("circle", { class: "region-placement-lab__dot", cx: 16, cy: top + 18, r: 4 })
            this.svg.append(dot)
            this.dots.push(dot)

            this.svg.append(el("text", {
              class: "region-placement-lab__region",
              x: 28, y: top + 22,
            }, region.label))

            const badge = el("text", { class: "region-placement-lab__badge", x: 28, y: top + 40 })
            this.svg.append(badge)
            this.badges.push(badge)
          })
        },

        draw() {
          const pxPerSecond = (CHART_RIGHT - CHART_X) / WINDOW_SECONDS

          REGIONS.forEach((region, index) => {
            const points = []
            for (let x = CHART_X; x <= CHART_RIGHT; x += STEP_PX) {
              const at = this.seconds - (CHART_RIGHT - x) / pxPerSecond
              points.push(`${x},${this.valueY(index, traffic(region, at)).toFixed(2)}`)
            }

            const base = this.laneTop(index) + LANE_HEIGHT
            this.paths[index].setAttribute(
              "d",
              `M ${CHART_X},${base} L ${points.join(" L ")} L ${CHART_RIGHT},${base} Z`,
            )

            const live = this.lanes[index].live
            this.dots[index].setAttribute("data-live", String(live))
            this.badges[index].textContent = live ? "instance live" : "no instance"
            this.badges[index].setAttribute("data-live", String(live))
          })
        },

        step(delta) {
          this.seconds += delta / 1000

          REGIONS.forEach((region, index) => {
            const value = traffic(region, this.seconds)
            const lane = this.lanes[index]

            if (!lane.live && value >= EXPAND) {
              lane.live = true
              this.provisioned += 1
              this.refresh()
            } else if (lane.live && value <= RETIRE) {
              lane.live = false
              this.retired += 1
              this.refresh()
            }
          })
        },

        refresh() {
          this.stats.live.textContent = String(this.lanes.filter((lane) => lane.live).length)
          this.stats.provisioned.textContent = String(this.provisioned)
          this.stats.retired.textContent = String(this.retired)
        },

        loop(now) {
          const delta = Math.min(64, now - this.lastTick)
          this.lastTick = now

          if (this.animating && this.running) {
            this.step(delta)
            this.draw()
          }

          this.frame = window.requestAnimationFrame((next) => this.loop(next))
        },
      }
    </script>

    <style :type={TuistWeb.ColocatedCSS}>
      .region-placement-lab {
        margin: var(--noora-spacing-7) 0;
      }

      .region-placement-lab__header {
        display: flex;
        justify-content: flex-end;
        margin-bottom: var(--noora-spacing-4);
      }

      .region-placement-lab__toggle {
        cursor: pointer;
        border: 1px solid var(--noora-surface-border-secondary);
        border-radius: var(--noora-radius-2);
        background: transparent;
        padding: var(--noora-spacing-2) var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .region-placement-lab__toggle:hover {
        color: var(--noora-surface-label-primary);
      }

      .region-placement-lab__chart {
        display: block;
        width: 100%;
        height: auto;
      }

      .region-placement-lab__gap {
        fill: var(--noora-neutral-light-400);
        fill-opacity: 0.28;
      }

      .region-placement-lab__area {
        fill: var(--noora-purple-100);
        stroke: var(--noora-button-primary-background);
        stroke-width: 1.5;
      }

      .region-placement-lab__threshold {
        stroke: var(--noora-surface-border-secondary);
        stroke-width: 1;
        stroke-dasharray: 3 3;
      }

      .region-placement-lab__threshold-label,
      .region-placement-lab__badge {
        fill: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
        font-size: 0.625rem;
      }

      .region-placement-lab__badge[data-live="true"] {
        fill: var(--noora-button-primary-background);
        font-weight: var(--noora-font-weight-semibold);
      }

      .region-placement-lab__region {
        fill: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
        font-size: 0.75rem;
      }

      .region-placement-lab__dot {
        fill: var(--noora-neutral-light-400);
        transition: fill 0.3s ease;
      }

      .region-placement-lab__dot[data-live="true"] {
        fill: var(--noora-button-primary-background);
      }

      .region-placement-lab__legend {
        display: flex;
        flex-wrap: wrap;
        gap: var(--noora-spacing-2) var(--noora-spacing-5);
        margin-top: var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .region-placement-lab__stats {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--noora-spacing-4);
        margin-top: var(--noora-spacing-5);
      }

      .region-placement-lab__stat {
        display: grid;
        gap: var(--noora-spacing-1);
      }

      .region-placement-lab__stat dt {
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .region-placement-lab__stat dd {
        margin: 0;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
      }

      .region-placement-lab__explanation {
        margin-top: var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      @media (width < 48rem) {
        .region-placement-lab__stats {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    </style>

    <section id={@id} class="region-placement-lab" data-part="region-placement-lab">
      <.card icon="world" title="Where an account's instances live">
        <.card_section>
          <div class="region-placement-lab__header">
            <button type="button" class="region-placement-lab__toggle" data-toggle aria-pressed="false">
              Pause
            </button>
          </div>

          <svg
            id={@id <> "-chart"}
            class="region-placement-lab__chart"
            viewBox="0 0 700 350"
            role="img"
            aria-label="One account's cache traffic in three regions over time. An instance is provisioned when traffic rises above the expand threshold and retired when it falls below the retire threshold."
            data-chart
            phx-hook=".RegionPlacement"
            phx-update="ignore"
          >
          </svg>

          <div class="region-placement-lab__legend">
            <span>The shaded band is the gap between the two thresholds. Traffic can wander inside it without anything happening.</span>
          </div>

          <dl class="region-placement-lab__stats">
            <div class="region-placement-lab__stat">
              <dt>Instances live</dt>
              <dd data-stat-live>0</dd>
            </div>
            <div class="region-placement-lab__stat">
              <dt>Provisioned</dt>
              <dd data-stat-provisioned>0</dd>
            </div>
            <div class="region-placement-lab__stat">
              <dt>Retired</dt>
              <dd data-stat-retired>0</dd>
            </div>
          </dl>

          <p class="region-placement-lab__explanation">
            A region earns an instance when the account's traffic there clears the upper
            threshold, and loses it when traffic falls under the much lower one. Setting them
            apart is what stops an account on the boundary from being provisioned and retired
            over and over, and it is why a quiet fortnight is not enough on its own to take a
            region away.
          </p>
        </.card_section>
      </.card>
    </section>
    """
  end
end
