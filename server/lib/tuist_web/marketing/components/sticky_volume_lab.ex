defmodule TuistWeb.Marketing.Components.StickyVolumeLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="sticky-volume-lab"] {
        margin: var(--noora-spacing-7) 0;
      }

      [data-part="sticky-volume-lab"] [data-part="story"] {
        display: grid;
        gap: var(--noora-spacing-5);
        margin: 0;
      }

      [data-part="sticky-volume-lab"] [data-part="diagram"] {
        display: block;
        width: 100%;
        height: auto;
        overflow: visible;
      }

      [data-part="sticky-volume-lab"] [data-part="mobile-steps"] {
        display: none;
      }

      [data-part="sticky-volume-lab"] [data-part="lane-label"],
      [data-part="sticky-volume-lab"] [data-part="event-label"],
      [data-part="sticky-volume-lab"] [data-part="volume-label"],
      [data-part="sticky-volume-lab"] [data-part="fork-label"] {
        fill: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-medium);
      }

      [data-part="sticky-volume-lab"] [data-part="commit-label"] {
        fill: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
      }

      [data-part="sticky-volume-lab"] [data-part="annotation"],
      [data-part="sticky-volume-lab"] [data-part="volume-note"],
      [data-part="sticky-volume-lab"] [data-part="time-label"] {
        fill: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      [data-part="sticky-volume-lab"] [data-part="delta-label"] {
        fill: var(--noora-button-primary-label);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
      }

      [data-part="sticky-volume-lab"] [data-part="summary"],
      [data-part="sticky-volume-lab"] [data-part="note"] {
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
      }

      [data-part="sticky-volume-lab"] [data-part="lane-guide"],
      [data-part="sticky-volume-lab"] [data-part="time-axis"] {
        stroke: currentColor;
        stroke-width: 1;
        color: var(--noora-surface-border-primary);
      }

      [data-part="sticky-volume-lab"] [data-part="branch-line"] {
        stroke: currentColor;
        stroke-dasharray: var(--noora-spacing-1) var(--noora-spacing-1);
        stroke-width: 1.5;
        color: var(--noora-surface-label-secondary);
      }

      [data-part="sticky-volume-lab"] [data-part="commit"],
      [data-part="sticky-volume-lab"] [data-part="volume"][data-variant="main"] {
        fill: var(--noora-surface-background-secondary);
        stroke: var(--noora-surface-border-primary);
        stroke-width: 2;
      }

      [data-part="sticky-volume-lab"] [data-part="volume"],
      [data-part="sticky-volume-lab"] [data-part="fork-label-surface"] {
        transform-box: fill-box;
        transform-origin: center;
        transition:
          fill 200ms var(--ease-out-cubic),
          stroke 200ms var(--ease-out-cubic),
          transform 200ms var(--ease-out-cubic),
          opacity 200ms var(--ease-out-cubic);
      }

      [data-part="sticky-volume-lab"] [data-part="result-line"] {
        stroke: currentColor;
        stroke-width: 2;
        color: var(--noora-surface-label-secondary);
      }

      [data-part="sticky-volume-lab"] [data-part="volume"][data-variant="feature"] {
        opacity: 0;
        fill: var(--noora-purple-100);
        stroke: var(--noora-button-primary-background);
        stroke-width: 2;
      }

      [data-part="sticky-volume-lab"] [data-stage="fork"] [data-part="volume-label"],
      [data-part="sticky-volume-lab"] [data-stage="fork"] [data-part="volume-note"] {
        opacity: 0;
        transition: opacity 200ms var(--ease-out-cubic);
      }

      [data-part="sticky-volume-lab"] [data-part="volume-delta"] {
        transform-box: fill-box;
        transform-origin: left center;
        opacity: 0;
        fill: var(--noora-button-primary-background);
      }

      [data-part="sticky-volume-lab"] [data-part="delta-label"] {
        opacity: 0;
        transition: opacity 200ms var(--ease-out-cubic);
        fill: var(--noora-button-primary-label);
      }

      [data-part="sticky-volume-lab"] [data-part="fork-line"] {
        opacity: 0;
        transition: opacity 200ms var(--ease-out-cubic);
        fill: none;
        stroke: currentColor;
        stroke-width: 2;
        color: var(--noora-button-primary-background);
      }

      [data-part="sticky-volume-lab"] [data-part="fork-label-surface"] {
        opacity: 0;
        fill: var(--noora-purple-100);
        stroke: var(--noora-button-primary-background);
        stroke-width: 1;
      }

      [data-part="sticky-volume-lab"] [data-part="fork-label"] {
        opacity: 0;
        transition: opacity 200ms var(--ease-out-cubic);
      }

      [data-part="sticky-volume-lab"] [data-part="flow"] {
        opacity: 0;
        fill: var(--noora-button-primary-background);
      }

      [data-part="sticky-volume-lab"] [data-stage="branch"] [data-part="event-label"] {
        opacity: 0;
        transition: opacity 200ms var(--ease-out-cubic);
      }

      [data-part="sticky-volume-lab"] [data-part="summary"],
      [data-part="sticky-volume-lab"] [data-part="note"] {
        margin: 0;
      }

      [data-part="sticky-volume-lab"] [data-part="note"] {
        border-top: 1px solid var(--noora-surface-border-primary);
        padding-top: var(--noora-spacing-4);
      }

      [data-part="sticky-volume-lab"][data-step="0"] [data-stage="main"] [data-part="volume"] {
        fill: var(--noora-purple-100);
        stroke: var(--noora-button-primary-background);
      }

      [data-part="sticky-volume-lab"][data-step="1"] [data-part="fork-line"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-part="fork-line"],
      [data-part="sticky-volume-lab"][data-step="1"] [data-part="fork-label-surface"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-part="fork-label-surface"],
      [data-part="sticky-volume-lab"][data-step="1"] [data-part="fork-label"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-part="fork-label"],
      [data-part="sticky-volume-lab"][data-step="1"] [data-part="volume"][data-variant="feature"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-part="volume"][data-variant="feature"],
      [data-part="sticky-volume-lab"][data-step="1"] [data-stage="fork"] [data-part="volume-label"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-stage="fork"] [data-part="volume-label"],
      [data-part="sticky-volume-lab"][data-step="1"] [data-stage="fork"] [data-part="volume-note"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-stage="fork"] [data-part="volume-note"] {
        opacity: 1;
      }

      [data-part="sticky-volume-lab"][data-step="2"] [data-part="volume-delta"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-part="delta-label"] {
        opacity: 1;
      }

      [data-part="sticky-volume-lab"][data-step="2"] [data-stage="branch"] [data-part="event-label"] {
        opacity: 1;
      }

      [data-part="sticky-volume-lab"][data-step="0"] [data-part="flow"][data-flow="main"] {
        animation: sticky-volume-lab-main-flow 800ms var(--ease-out-cubic) forwards;
      }

      [data-part="sticky-volume-lab"][data-step="1"] [data-part="flow"][data-flow="fork"] {
        animation: sticky-volume-lab-fork-flow 800ms var(--ease-out-cubic) forwards;
      }

      [data-part="sticky-volume-lab"][data-step="2"] [data-part="volume-delta"] {
        animation: sticky-volume-lab-delta-flow 800ms var(--ease-out-cubic) forwards;
      }

      [data-part="sticky-volume-lab"][data-step="0"] [data-part="mobile-step"][data-stage="main"],
      [data-part="sticky-volume-lab"][data-step="1"] [data-part="mobile-step"][data-stage="fork"],
      [data-part="sticky-volume-lab"][data-step="2"] [data-part="mobile-step"][data-stage="branch"] {
        transform: translateY(calc(0px - var(--noora-spacing-1)));
        border-color: var(--noora-button-primary-background);
        background: var(--noora-purple-100);
      }

      @keyframes sticky-volume-lab-main-flow {
        0% {
          transform: translate(0, 0);
          opacity: 0;
        }

        10%,
        75% {
          opacity: 1;
        }

        100% {
          transform: translate(42px, 0);
          opacity: 0;
        }
      }

      @keyframes sticky-volume-lab-fork-flow {
        0% {
          transform: translate(0, 0);
          opacity: 0;
        }

        10%,
        75% {
          opacity: 1;
        }

        100% {
          transform: translate(20px, 59px);
          opacity: 0;
        }
      }

      @keyframes sticky-volume-lab-delta-flow {
        0% {
          transform: scaleX(0);
          opacity: 0;
        }

        10%,
        75% {
          opacity: 1;
        }

        100% {
          transform: scaleX(1);
          opacity: 1;
        }
      }

      @media (prefers-reduced-motion: reduce) {
        [data-part="sticky-volume-lab"] [data-part="flow"] {
          animation: none !important;
        }

        [data-part="sticky-volume-lab"] [data-part="fork-line"],
        [data-part="sticky-volume-lab"] [data-part="fork-label-surface"],
        [data-part="sticky-volume-lab"] [data-part="fork-label"],
        [data-part="sticky-volume-lab"] [data-part="volume"][data-variant="feature"],
        [data-part="sticky-volume-lab"] [data-part="volume-delta"],
        [data-part="sticky-volume-lab"] [data-part="delta-label"] {
          opacity: 1;
        }
      }

      @media (width < 48rem) {
        [data-part="sticky-volume-lab"] [data-part="diagram"] {
          display: none;
        }

        [data-part="sticky-volume-lab"] [data-part="mobile-steps"] {
          display: grid;
          gap: var(--noora-spacing-3);
          margin: 0;
          padding: 0;
          list-style: none;
        }

        [data-part="sticky-volume-lab"] [data-part="mobile-step"] {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          align-items: start;
          gap: var(--noora-spacing-3);
          transition:
            border-color 200ms var(--ease-out-cubic),
            background 200ms var(--ease-out-cubic),
            transform 200ms var(--ease-out-cubic);
          border: 1px solid var(--noora-surface-border-primary);
          border-radius: var(--noora-radius-3);
          background: var(--noora-surface-background-secondary);
          padding: var(--noora-spacing-3);
        }

        [data-part="sticky-volume-lab"] [data-part="mobile-step-number"] {
          display: grid;
          place-items: center;
          border: 1px solid var(--noora-surface-border-primary);
          border-radius: var(--noora-radius-2);
          background: var(--noora-surface-background-primary);
          width: var(--noora-spacing-6);
          height: var(--noora-spacing-6);
          color: var(--noora-surface-label-secondary);
          font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
        }

        [data-part="sticky-volume-lab"] [data-part="mobile-step"] div {
          display: grid;
          gap: var(--noora-spacing-1);
        }

        [data-part="sticky-volume-lab"] [data-part="mobile-step"] strong {
          color: var(--noora-surface-label-primary);
          font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
        }

        [data-part="sticky-volume-lab"] [data-part="mobile-step"] span:not([data-part="mobile-step-number"]) {
          color: var(--noora-surface-label-secondary);
          font: var(--noora-font-weight-regular) var(--noora-font-body-small);
        }
      }
    </style>

    <section
      id={@id}
      data-part="sticky-volume-lab"
      data-step="0"
      phx-hook=".StickyVolumeTimeline"
      phx-update="ignore"
    >
      <.card icon="git_branch" title="How a sticky volume follows a branch">
        <.card_section>
          <figure data-part="story">
            <svg
              data-part="diagram"
              viewBox="0 0 640 290"
              role="img"
              aria-labelledby={@id <> "-title " <> @id <> "-description"}
            >
              <title id={@id <> "-title"}>A sticky-volume timeline</title>
              <desc id={@id <> "-description"}>
                The main branch builds commit a1 and creates a main volume. The feature branch is
                created at that commit and forks the main volume. Its build at b2 advances only the
                feature volume. The main volume remains unchanged.
              </desc>
              <defs>
                <marker
                  id={@id <> "-arrow"}
                  markerWidth="8"
                  markerHeight="8"
                  refX="7"
                  refY="4"
                  orient="auto"
                >
                  <path d="M 0 0 L 8 4 L 0 8 z" fill="currentColor" />
                </marker>
              </defs>

              <text x="20" y="107" data-part="lane-label">main</text>
              <text x="20" y="213" data-part="lane-label">feature</text>
              <line x1="94" y1="100" x2="590" y2="100" data-part="lane-guide" />
              <line x1="94" y1="207" x2="590" y2="207" data-part="lane-guide" />

              <g data-stage="main">
                <text x="188" y="65" text-anchor="end" data-part="event-label">main@a1 build</text>
                <circle cx="145" cy="100" r="8" data-part="commit" />
                <text x="145" y="126" text-anchor="middle" data-part="commit-label">a1</text>
                <line
                  x1="154"
                  y1="100"
                  x2="200"
                  y2="100"
                  data-part="result-line"
                  marker-end={"url(##{@id}-arrow)"}
                />
                <circle cx="154" cy="100" r="5" data-part="flow" data-flow="main" />
                <rect
                  x="200"
                  y="77"
                  width="370"
                  height="46"
                  rx="8"
                  data-part="volume"
                  data-variant="main"
                />
                <text x="218" y="98" data-part="volume-label">main volume</text>
                <text x="218" y="115" data-part="volume-note">a1 incremental state · unchanged</text>
              </g>

              <g data-stage="branch-origin">
                <line x1="145" y1="109" x2="145" y2="198" data-part="branch-line" />
                <text x="160" y="166" data-part="annotation">branch at a1</text>
                <circle cx="145" cy="207" r="8" data-part="commit" />
                <text x="145" y="233" text-anchor="middle" data-part="commit-label">a1</text>
              </g>

              <g data-stage="fork">
                <path
                  d="M 350 124 C 350 151, 370 161, 370 183"
                  data-part="fork-line"
                  marker-end={"url(##{@id}-arrow)"}
                />
                <circle cx="350" cy="124" r="5" data-part="flow" data-flow="fork" />
                <rect x="376" y="141" width="48" height="28" rx="14" data-part="fork-label-surface" />
                <text x="400" y="160" text-anchor="middle" data-part="fork-label">fork</text>
                <rect
                  x="340"
                  y="184"
                  width="230"
                  height="46"
                  rx="8"
                  data-part="volume"
                  data-variant="feature"
                />
                <text x="356" y="205" data-part="volume-label">feature volume</text>
                <text x="356" y="222" data-part="volume-note">a1 state</text>
              </g>

              <g data-stage="branch">
                <text x="498" y="174" text-anchor="middle" data-part="event-label">b2</text>
                <path
                  d="M 498 184 H 562 Q 570 184, 570 192 V 222 Q 570 230, 562 230 H 498 Z"
                  data-part="volume-delta"
                />
                <text x="534" y="211" text-anchor="middle" data-part="delta-label">b2 delta</text>
              </g>

              <line
                x1="94"
                y1="266"
                x2="590"
                y2="266"
                data-part="time-axis"
                marker-end={"url(##{@id}-arrow)"}
              />
              <text x="94" y="284" data-part="time-label">earlier</text>
              <text x="590" y="284" text-anchor="end" data-part="time-label">later</text>
            </svg>

            <ol data-part="mobile-steps">
              <li data-part="mobile-step" data-stage="main">
                <span data-part="mobile-step-number">1</span>
                <div>
                  <strong>main@a1 builds</strong>
                  <span>It creates a main volume with incremental state.</span>
                </div>
              </li>
              <li data-part="mobile-step" data-stage="fork">
                <span data-part="mobile-step-number">2</span>
                <div>
                  <strong>feature@a1 forks that state</strong>
                  <span>The branch starts with its own copy of the main volume.</span>
                </div>
              </li>
              <li data-part="mobile-step" data-stage="branch">
                <span data-part="mobile-step-number">3</span>
                <div>
                  <strong>feature@b2 builds</strong>
                  <span>Only the branch volume receives the new state.</span>
                </div>
              </li>
            </ol>

            <figcaption data-part="summary">
              The main volume continues unchanged after the fork. The branch starts warm, then its
              next build advances only its own copy.
            </figcaption>
          </figure>

          <p data-part="note">
            This is one possible platform policy. A volume fork is not a property that every build
            system provides.
          </p>
        </.card_section>
      </.card>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".StickyVolumeTimeline">
        export default {
          mounted() {
            this.step = 0
            this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)")
            this.onReducedMotionChange = () => this.updateMotionPreference()
            this.reducedMotion.addEventListener("change", this.onReducedMotionChange)

            this.observer = new IntersectionObserver(
              ([entry]) => {
                this.isVisible = entry.isIntersecting
                this.updateMotionPreference()
              },
              {threshold: 0.35},
            )

            this.observer.observe(this.el)
            this.updateMotionPreference()
          },

          destroyed() {
            this.stop()
            this.observer?.disconnect()
            this.reducedMotion?.removeEventListener("change", this.onReducedMotionChange)
          },

          updateMotionPreference() {
            if (this.reducedMotion.matches) {
              this.stop()
              this.showStep(2)
              return
            }

            if (this.isVisible) {
              this.start()
            } else {
              this.stop()
            }
          },

          start() {
            if (this.timer) return

            this.showStep(this.step)
            this.timer = window.setInterval(() => this.showStep((this.step + 1) % 3), 2800)
          },

          stop() {
            window.clearInterval(this.timer)
            this.timer = undefined
          },

          showStep(step) {
            this.step = step
            this.el.dataset.step = step
          },
        }
      </script>
    </section>
    """
  end
end
