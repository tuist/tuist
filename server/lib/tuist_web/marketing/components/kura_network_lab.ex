defmodule TuistWeb.Marketing.Components.KuraNetworkLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="kura-network-lab"] {
        display: grid;
        gap: var(--noora-spacing-5);
        margin: var(--noora-spacing-7) 0;
        border-block: 1px solid var(--noora-surface-border-primary);
        padding-block: var(--noora-spacing-6);
      }

      [data-part="kura-network-lab"] [data-part="network-header"] {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        align-items: end;
        gap: var(--noora-spacing-4);
      }

      [data-part="kura-network-lab"] [data-part="eyebrow"] {
        margin: 0;
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      [data-part="kura-network-lab"] [data-part="title"] {
        margin: var(--noora-spacing-1) 0 0;
        max-width: calc(var(--noora-spacing-10) * 11);
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-medium);
      }

      [data-part="kura-network-lab"] [data-part="kura-selector"] {
        flex: none;
      }

      [data-part="kura-network-lab"] [data-part="network-content"] {
        display: grid;
        align-items: center;
        gap: var(--noora-spacing-5);
      }

      [data-part="kura-network-lab"] [data-part="globe-surface"] {
        display: grid;
        position: relative;
        place-items: center;
        overflow: hidden;
      }

      [data-part="kura-network-lab"] [data-part="globe"] {
        display: block;
        cursor: grab;
        aspect-ratio: 1;
        width: 100%;
        max-width: calc(var(--noora-spacing-10) * 11);
        touch-action: none;
      }

      [data-part="kura-network-lab"] [data-part="globe"][data-dragging="true"] {
        cursor: grabbing;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] {
        --cobe-visible-us-east-cache: 0;
        --cobe-visible-germany-developer: 0;
        --cobe-visible-japan-developer: 0;
        --cobe-visible-us-east-kura: 0;
        --cobe-visible-eu-central-kura: 0;
        --cobe-visible-ap-northeast-kura: 0;

        pointer-events: none;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] > span {
        display: inline-flex;
        position: absolute;
        align-items: center;
        gap: var(--noora-spacing-1);
        opacity: 0;
        z-index: 1;
        filter: blur(var(--noora-spacing-2));
        transition:
          opacity 150ms var(--ease-out-cubic),
          filter 150ms var(--ease-out-cubic);
        border: 1px solid var(--noora-surface-border-primary);
        border-radius: var(--noora-radius-3);
        background: var(--noora-surface-background-primary);
        padding: var(--noora-spacing-1) var(--noora-spacing-2);
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);
        white-space: nowrap;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] i {
        display: inline-block;
        border-radius: var(--noora-radius-99);
        width: var(--noora-spacing-2);
        height: var(--noora-spacing-2);
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="us-east-cache"] {
        position-anchor: --cobe-us-east-cache;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="us-east-kura"] {
        position-anchor: --cobe-us-east-kura;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="us-east-cache"],
      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="us-east-kura"] {
        bottom: anchor(top);
        left: anchor(center);
        transform: translate(-50%, calc(-1 * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="germany-developer"] {
        position-anchor: --cobe-germany-developer;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="eu-central-kura"] {
        position-anchor: --cobe-eu-central-kura;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="germany-developer"],
      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="eu-central-kura"] {
        top: anchor(center);
        right: anchor(left);
        transform: translate(calc(-1 * var(--noora-spacing-2)), -50%);
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="japan-developer"] {
        position-anchor: --cobe-japan-developer;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="ap-northeast-kura"] {
        position-anchor: --cobe-ap-northeast-kura;
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="japan-developer"],
      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="ap-northeast-kura"] {
        top: anchor(center);
        left: anchor(right);
        transform: translate(var(--noora-spacing-2), -50%);
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="us-east-cache"] {
        opacity: var(--cobe-visible-us-east-cache);
        filter: blur(calc((1 - var(--cobe-visible-us-east-cache)) * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="germany-developer"] {
        opacity: var(--cobe-visible-germany-developer);
        filter: blur(calc((1 - var(--cobe-visible-germany-developer)) * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="japan-developer"] {
        opacity: var(--cobe-visible-japan-developer);
        filter: blur(calc((1 - var(--cobe-visible-japan-developer)) * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="us-east-kura"] {
        opacity: var(--cobe-visible-us-east-kura);
        filter: blur(calc((1 - var(--cobe-visible-us-east-kura)) * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="eu-central-kura"] {
        opacity: var(--cobe-visible-eu-central-kura);
        filter: blur(calc((1 - var(--cobe-visible-eu-central-kura)) * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"] [data-part="globe-labels"] [data-label-for="ap-northeast-kura"] {
        opacity: var(--cobe-visible-ap-northeast-kura);
        filter: blur(calc((1 - var(--cobe-visible-ap-northeast-kura)) * var(--noora-spacing-2)));
      }

      [data-part="kura-network-lab"][data-scenario="us-east-only"] [data-scenario-label="global-mesh"],
      [data-part="kura-network-lab"][data-scenario="global-mesh"] [data-scenario-label="us-east-only"] {
        display: none;
      }

      [data-part="kura-network-lab"] [data-part="scenario-copy"] {
        display: grid;
        gap: var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      [data-part="kura-network-lab"] [data-part="scenario-copy"] > div {
        display: grid;
        gap: var(--noora-spacing-2);
      }

      [data-part="kura-network-lab"] [data-part="scenario-copy"] strong {
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-medium);
      }

      [data-part="kura-network-lab"] [data-part="scenario-copy"] p {
        margin: 0;
      }

      [data-part="kura-network-lab"] [data-part="scenario-copy"] code {
        font: var(--noora-font-weight-medium) var(--noora-font-code-small);
      }

      [data-part="kura-network-lab"][data-scenario="us-east-only"] [data-scenario-copy="global-mesh"],
      [data-part="kura-network-lab"][data-scenario="global-mesh"] [data-scenario-copy="us-east-only"] {
        display: none;
      }

      [data-part="kura-network-lab"] [data-part="network-key"] {
        display: grid;
        margin: 0;
        border-top: 1px solid var(--noora-surface-border-primary);
        padding: 0;
        padding-top: var(--noora-spacing-4);
        list-style: none;
      }

      [data-part="kura-network-lab"] [data-part="network-key"] li {
        display: flex;
        align-items: baseline;
        gap: var(--noora-spacing-2);
      }

      [data-part="kura-network-lab"] [data-part="network-key"] strong {
        display: inline-flex;
        align-items: center;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      [data-part="kura-network-lab"] [data-part="network-key"] span {
        color: var(--noora-surface-label-secondary);
      }

      [data-part="kura-network-lab"] [data-part="network-key"] i {
        display: inline-block;
        border-radius: var(--noora-radius-99);
        width: var(--noora-spacing-2);
        height: var(--noora-spacing-2);
      }

      [data-part="kura-network-lab"] [data-part="cache-marker"] {
        background: var(--noora-button-primary-background);
      }

      [data-part="kura-network-lab"] [data-part="client-marker"] {
        background: var(--noora-surface-label-primary);
      }

      @media (width >= 48rem) {
        [data-part="kura-network-lab"] [data-part="network-content"] {
          grid-template-columns: minmax(0, 1.2fr) minmax(0, 0.8fr);
        }
      }

      @media (width < 48rem) {
        [data-part="kura-network-lab"] [data-part="kura-selector"] {
          width: 100%;
        }

        [data-part="kura-network-lab"] [data-part="kura-selector"] > * {
          flex: 1;
        }
      }
    </style>

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
            <strong>One short cache trip per environment</strong>
            <p>
              Continuous integration reads from <code>us-east</code>. Germany reads from <code>eu-central</code>, and Japan reads from <code>ap-northeast</code>. The
              short purple arcs show those local reads while the mesh keeps results shared.
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
                to: [38.8, -77.05],
                id: "us-east-local-read",
              },
              {
                from: [52.52, 13.405],
                to: [50.1109, 8.6821],
                id: "germany-local-read",
              },
              {
                from: [35.6762, 139.6503],
                to: [34.6937, 135.5023],
                id: "japan-local-read",
              },
            ],
            markers: [
              {
                id: "us-east-kura",
                location: [38.8, -77.05],
                kind: "cache",
              },
              {
                id: "germany-developer",
                location: [52.52, 13.405],
                kind: "client",
              },
              {
                id: "eu-central-kura",
                location: [50.1109, 8.6821],
                kind: "cache",
              },
              {
                id: "japan-developer",
                location: [35.6762, 139.6503],
                kind: "client",
              },
              {
                id: "ap-northeast-kura",
                location: [34.6937, 135.5023],
                kind: "cache",
              },
            ],
            arcHeight: 0.14,
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
