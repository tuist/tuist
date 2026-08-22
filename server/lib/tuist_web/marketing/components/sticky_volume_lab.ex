defmodule TuistWeb.Marketing.Components.StickyVolumeLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def render(assigns) do
    ~H"""
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
