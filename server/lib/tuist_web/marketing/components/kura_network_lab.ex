defmodule TuistWeb.Marketing.Components.KuraNetworkLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def render(assigns) do
    ~H"""
    <figure
      id={@id}
      data-part="kura-network-lab"
      data-scenario="us-east-only"
      phx-hook=".KuraNetworkGlobe"
      phx-update="ignore"
    >
      <div data-part="network-header">
        <div>
          <p data-part="eyebrow">Cache geography</p>
          <h3 data-part="title">The same cache can be near one build and far from another.</h3>
        </div>

        <.button_group size="small" data-part="kura-selector" aria-label="Kura deployment scenario">
          <.button_group_item
            label="US East only"
            data-scenario-option="us-east-only"
            data-selected
          />
          <.button_group_item label="Global Kura mesh" data-scenario-option="global-mesh" />
        </.button_group>
      </div>

      <div data-part="network-content">
        <div data-part="globe-surface">
          <canvas
            data-part="globe"
            width="480"
            height="480"
            role="img"
            aria-label="A rotating globe showing cache paths for continuous integration and developers in the United States, Germany, and Japan. Drag to rotate the globe."
          >
            A globe showing cache paths between the United States, Germany, and Japan.
          </canvas>

          <div data-part="globe-labels" aria-hidden="true">
            <span data-scenario-label="us-east-only" data-label-for="us-east-cache">
              <i data-part="cache-marker" />us-east cache
            </span>
            <span data-scenario-label="us-east-only" data-label-for="germany-developer">
              <i data-part="client-marker" />Germany dev
            </span>
            <span data-scenario-label="us-east-only" data-label-for="japan-developer">
              <i data-part="client-marker" />Japan dev
            </span>

            <span data-scenario-label="global-mesh" data-label-for="us-east-kura">
              <i data-part="cache-marker" />us-east Kura
            </span>
            <span data-scenario-label="global-mesh" data-label-for="eu-central-kura">
              <i data-part="cache-marker" />eu-central Kura
            </span>
            <span data-scenario-label="global-mesh" data-label-for="ap-northeast-kura">
              <i data-part="cache-marker" />ap-northeast Kura
            </span>
          </div>
        </div>

        <figcaption data-part="scenario-copy" aria-live="polite">
          <div data-scenario-copy="us-east-only">
            <strong>One cache in <code>us-east</code></strong>
            <p>
              Continuous integration stays close to the cache. Developers in Germany and Japan
              make long cache trips over the public internet.
            </p>
          </div>

          <div data-scenario-copy="global-mesh">
            <strong>Three nearby Kura regions</strong>
            <p>
              <code>us-east</code>, <code>eu-central</code>, and <code>ap-northeast</code>
              give each active environment a shorter path while the mesh keeps results shared.
            </p>
          </div>

          <ul data-part="network-key">
            <li>
              <i data-part="cache-marker" aria-hidden="true" />
              <strong>Kura cache</strong>
              <span>serves local reads</span>
            </li>
            <li>
              <i data-part="client-marker" aria-hidden="true" />
              <strong>Build environment</strong>
              <span>looks up a result</span>
            </li>
          </ul>
        </figcaption>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".KuraNetworkGlobe">
        import createGlobe from "cobe"

        const scenarios = {
          "us-east-only": {
            arcs: [
              {
                from: [38.9517, -77.4481],
                to: [52.52, 13.405],
                id: "us-east-to-germany",
              },
              {
                from: [38.9517, -77.4481],
                to: [35.6762, 139.6503],
                id: "us-east-to-japan",
              },
            ],
            markers: [
              {
                id: "us-east-cache",
                location: [38.9517, -77.4481],
                kind: "cache",
              },
              {
                id: "germany-developer",
                location: [52.52, 13.405],
                kind: "client",
              },
              {
                id: "japan-developer",
                location: [35.6762, 139.6503],
                kind: "client",
              },
            ],
            arcHeight: 0.32,
            scale: 0.95,
          },
          "global-mesh": {
            arcs: [
              {
                from: [38.9517, -77.4481],
                to: [50.1109, 8.6821],
                id: "us-east-to-eu-central",
              },
              {
                from: [50.1109, 8.6821],
                to: [35.6762, 139.6503],
                id: "eu-central-to-ap-northeast",
              },
            ],
            markers: [
              {
                id: "us-east-kura",
                location: [38.9517, -77.4481],
                kind: "cache",
              },
              {
                id: "eu-central-kura",
                location: [50.1109, 8.6821],
                kind: "cache",
              },
              {
                id: "ap-northeast-kura",
                location: [35.6762, 139.6503],
                kind: "cache",
              },
            ],
            arcHeight: 0.22,
            scale: 1,
          },
        }

        function tokenColor(element, token) {
          const probe = document.createElement("span")
          probe.style.color = `var(${token})`
          element.append(probe)

          const context = document.createElement("canvas").getContext("2d")
          context.fillStyle = getComputedStyle(probe).color
          context.fillRect(0, 0, 1, 1)

          const [red, green, blue] = context.getImageData(0, 0, 1, 1).data
          probe.remove()

          return [red / 255, green / 255, blue / 255]
        }

        export default {
          mounted() {
            this.canvas = this.el.querySelector('[data-part="globe"]')
            this.labels = this.el.querySelector('[data-part="globe-labels"]')
            this.scenario = "us-east-only"
            this.phi = 0.1
            this.theta = 0.28
            this.isVisible = false

            this.colors = {
              base: tokenColor(this.el, "--noora-purple-100"),
              glow: tokenColor(this.el, "--noora-surface-background-primary"),
              cache: tokenColor(this.el, "--noora-button-primary-background"),
              client: tokenColor(this.el, "--noora-surface-label-primary"),
              route: tokenColor(this.el, "--noora-button-primary-background"),
            }

            this.globe = createGlobe(this.canvas, {
              devicePixelRatio: Math.min(window.devicePixelRatio, 2),
              width: this.canvas.clientWidth * Math.min(window.devicePixelRatio, 2),
              height: this.canvas.clientHeight * Math.min(window.devicePixelRatio, 2),
              phi: this.phi,
              theta: this.theta,
              dark: 0,
              diffuse: 1.2,
              mapSamples: 10_000,
              mapBrightness: 3,
              mapBaseBrightness: 0,
              baseColor: this.colors.base,
              markerColor: this.colors.cache,
              glowColor: this.colors.glow,
              arcColor: this.colors.route,
              arcWidth: 0.65,
              markerElevation: 0.02,
              markers: [],
              arcs: [],
            })

            this.onOptionClick = (event) => this.setScenario(event.currentTarget.dataset.scenarioOption)
            this.el.querySelectorAll("[data-scenario-option]").forEach((option) => {
              option.addEventListener("click", this.onOptionClick)
            })

            this.resizeObserver = new ResizeObserver(() => this.resize())
            this.resizeObserver.observe(this.canvas)

            this.onPointerDown = (event) => this.startDragging(event)
            this.onPointerMove = (event) => this.drag(event)
            this.onPointerUp = (event) => this.stopDragging(event)

            this.canvas.addEventListener("pointerdown", this.onPointerDown)
            this.canvas.addEventListener("pointermove", this.onPointerMove)
            this.canvas.addEventListener("pointerup", this.onPointerUp)
            this.canvas.addEventListener("pointercancel", this.onPointerUp)

            this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
            this.onReducedMotionChange = () => this.updateMotionPreference()
            this.reducedMotion.addEventListener("change", this.onReducedMotionChange)

            this.visibilityObserver = new IntersectionObserver(
              ([entry]) => {
                this.isVisible = entry.isIntersecting
                this.updateMotionPreference()
              },
              { threshold: 0.2 },
            )

            this.visibilityObserver.observe(this.el)
            this.setScenario(this.scenario)
            this.initialRender = window.setTimeout(() => this.setScenario(this.scenario), 250)
          },

          destroyed() {
            window.clearTimeout(this.initialRender)
            window.cancelAnimationFrame(this.frame)
            this.resizeObserver?.disconnect()
            this.visibilityObserver?.disconnect()
            this.reducedMotion?.removeEventListener("change", this.onReducedMotionChange)
            this.canvas?.removeEventListener("pointerdown", this.onPointerDown)
            this.canvas?.removeEventListener("pointermove", this.onPointerMove)
            this.canvas?.removeEventListener("pointerup", this.onPointerUp)
            this.canvas?.removeEventListener("pointercancel", this.onPointerUp)
            this.el.querySelectorAll("[data-scenario-option]").forEach((option) => {
              option.removeEventListener("click", this.onOptionClick)
            })
            this.globe?.destroy()
          },

          resize() {
            const ratio = Math.min(window.devicePixelRatio, 2)
            this.globe?.update({
              width: this.canvas.clientWidth * ratio,
              height: this.canvas.clientHeight * ratio,
            })
            this.render()
          },

          updateMotionPreference() {
            window.cancelAnimationFrame(this.frame)

            if (!this.isVisible || this.reducedMotion.matches) return

            const rotate = () => {
              if (!this.dragState) {
                this.phi += 0.00035
                this.render()
              }

              this.frame = window.requestAnimationFrame(rotate)
            }

            this.frame = window.requestAnimationFrame(rotate)
          },

          startDragging(event) {
            this.dragState = {
              pointerId: event.pointerId,
              x: event.clientX,
              y: event.clientY,
            }

            this.canvas.setPointerCapture(event.pointerId)
            this.canvas.dataset.dragging = "true"
          },

          drag(event) {
            if (!this.dragState || event.pointerId !== this.dragState.pointerId) return

            const horizontalDistance = event.clientX - this.dragState.x
            const verticalDistance = event.clientY - this.dragState.y

            this.dragState = {
              pointerId: event.pointerId,
              x: event.clientX,
              y: event.clientY,
            }
            this.phi += horizontalDistance * 0.005
            this.theta = Math.max(-0.5, Math.min(0.5, this.theta + verticalDistance * 0.005))
            this.render()
          },

          stopDragging(event) {
            if (!this.dragState || event.pointerId !== this.dragState.pointerId) return

            if (this.canvas.hasPointerCapture(event.pointerId)) {
              this.canvas.releasePointerCapture(event.pointerId)
            }

            this.dragState = undefined
            delete this.canvas.dataset.dragging
          },

          render() {
            const scenario = scenarios[this.scenario]

            this.globe?.update({
              phi: this.phi,
              theta: this.theta,
              markers: scenario.markers.map((marker) => ({
                ...marker,
                size: marker.kind === "cache" ? 0.065 : 0.045,
                color: marker.kind === "cache" ? this.colors.cache : this.colors.client,
              })),
              arcs: scenario.arcs.map((arc) => ({ ...arc, color: this.colors.route })),
              arcHeight: scenario.arcHeight,
              scale: scenario.scale,
            })
          },

          setScenario(scenario) {
            this.scenario = scenario
            this.el.dataset.scenario = scenario
            this.el.querySelectorAll("[data-scenario-option]").forEach((option) => {
              option.toggleAttribute("data-selected", option.dataset.scenarioOption === scenario)
            })
            this.render()
            this.moveLabelsAfterAnchors()
          },

          moveLabelsAfterAnchors() {
            this.labels?.parentElement?.append(this.labels)
          },
        }
      </script>
    </figure>
    """
  end
end
