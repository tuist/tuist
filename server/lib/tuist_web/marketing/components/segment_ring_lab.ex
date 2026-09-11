defmodule TuistWeb.Marketing.Components.SegmentRingLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SegmentRing">
      const SEGMENT_COUNT = 10;
      const SLOTS_PER_SEGMENT = 12;
      const OLD_SEGMENTS = 2;
      const NEW_SEGMENTS = 4;
      const TICK_MS = 260;

      function bandFor(index) {
        if (index < NEW_SEGMENTS) return "new";
        if (index < SEGMENT_COUNT - OLD_SEGMENTS) return "current";
        return "old";
      }

      const SegmentRing = {
        mounted() {
          this.running = !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
          this.nextId = 0;
          this.unlinks = 0;
          this.reclaimed = 0;
          this.lastReclaimed = 0;
          this.rotating = false;

          this.segments = Array.from({ length: SEGMENT_COUNT }, (_, index) => ({
            id: this.nextId++,
            filled: index === 0 ? 0 : SLOTS_PER_SEGMENT,
          }));

          this.track = this.el;
          this.root = this.el.closest(".segment-ring-lab");
          this.toggle = this.root.querySelector("[data-toggle]");
          this.stats = {
            unlinks: this.root.querySelector("[data-stat-unlinks]"),
            reclaimed: this.root.querySelector("[data-stat-reclaimed]"),
            last: this.root.querySelector("[data-stat-last]"),
          };

          this.onToggle = () => {
            this.running = !this.running;
            this.syncToggle();
          };
          this.toggle.addEventListener("click", this.onToggle);

          this.build();
          this.syncToggle();
          this.timer = window.setInterval(() => this.tick(), TICK_MS);
        },

        destroyed() {
          window.clearInterval(this.timer);
          this.toggle?.removeEventListener("click", this.onToggle);
        },

        syncToggle() {
          this.toggle.textContent = this.running ? "Pause" : "Play";
          this.toggle.setAttribute("aria-pressed", String(!this.running));
        },

        build() {
          this.track.replaceChildren();
          this.segments.forEach((segment, index) => {
            this.track.append(this.segmentElement(segment, index));
          });
        },

        segmentElement(segment, index) {
          const band = bandFor(index);
          const element = document.createElement("div");
          element.className = `segment-ring-lab__segment segment-ring-lab__segment--${band}`;
          element.dataset.id = String(segment.id);

          const slots = document.createElement("div");
          slots.className = "segment-ring-lab__slots";
          for (let slot = 0; slot < SLOTS_PER_SEGMENT; slot += 1) {
            const cell = document.createElement("span");
            cell.className = "segment-ring-lab__slot";
            if (slot < segment.filled) cell.dataset.filled = "true";
            slots.append(cell);
          }

          const label = document.createElement("span");
          label.className = "segment-ring-lab__band";
          label.textContent = band === "current" ? "current" : band;

          element.append(slots, label);
          return element;
        },

        refresh() {
          this.segments.forEach((segment, index) => {
            const element = this.track.children[index];
            if (!element) return;

            const band = bandFor(index);
            element.className = `segment-ring-lab__segment segment-ring-lab__segment--${band}`;
            element.dataset.id = String(segment.id);
            element.querySelector(".segment-ring-lab__band").textContent =
              band === "current" ? "current" : band;

            const cells = element.querySelectorAll(".segment-ring-lab__slot");
            cells.forEach((cell, slot) => {
              if (slot < segment.filled) {
                cell.dataset.filled = "true";
              } else {
                delete cell.dataset.filled;
              }
            });
          });

          this.stats.unlinks.textContent = String(this.unlinks);
          this.stats.reclaimed.textContent = String(this.reclaimed);
          this.stats.last.textContent = this.lastReclaimed
            ? `${this.lastReclaimed} ${this.lastReclaimed === 1 ? "artifact" : "artifacts"}, 1 operation`
            : "waiting for the head to fill";
        },

        tick() {
          if (!this.running || this.rotating) return;

          const head = this.segments[0];
          head.filled = Math.min(SLOTS_PER_SEGMENT, head.filled + 1 + Math.floor(Math.random() * 2));

          if (head.filled >= SLOTS_PER_SEGMENT) {
            this.rotate();
            return;
          }

          this.refresh();
        },

        rotate() {
          this.rotating = true;

          const tail = this.track.lastElementChild;
          const reclaimed = this.segments[this.segments.length - 1].filled;

          this.unlinks += 1;
          this.reclaimed += reclaimed;
          this.lastReclaimed = reclaimed;

          tail?.setAttribute("data-unlinking", "true");

          window.setTimeout(() => {
            this.segments.pop();
            this.segments.unshift({ id: this.nextId++, filled: 0 });
            this.build();
            this.track.firstElementChild?.setAttribute("data-fresh", "true");
            this.rotating = false;
            this.refresh();
          }, 420);

          this.refresh();
        },
      };

      export { SegmentRing };

      export default SegmentRing;
    </script>

    <style :type={TuistWeb.ColocatedCSS}>
      .segment-ring-lab {
        margin: var(--noora-spacing-7) 0;
      }

      .segment-ring-lab__header {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        gap: var(--noora-spacing-4);
        margin-bottom: var(--noora-spacing-4);
      }

      .segment-ring-lab__title {
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .segment-ring-lab__toggle {
        cursor: pointer;
        border: 1px solid var(--noora-surface-border-secondary);
        border-radius: var(--noora-radius-2);
        background: transparent;
        padding: var(--noora-spacing-2) var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .segment-ring-lab__toggle:hover {
        color: var(--noora-surface-label-primary);
      }

      .segment-ring-lab__flow {
        display: flex;
        justify-content: space-between;
        gap: var(--noora-spacing-3);
        margin-bottom: var(--noora-spacing-2);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .segment-ring-lab__track {
        display: grid;
        grid-auto-flow: column;
        grid-auto-columns: minmax(0, 1fr);
        gap: var(--noora-spacing-2);
      }

      .segment-ring-lab__segment {
        display: grid;
        gap: var(--noora-spacing-2);
        transition: opacity 0.4s ease, transform 0.4s ease;
        border: 1px solid var(--noora-surface-border-secondary);
        border-radius: var(--noora-radius-2);
        padding: var(--noora-spacing-2);
      }

      .segment-ring-lab__segment--new {
        border-color: var(--noora-button-primary-background);
      }

      .segment-ring-lab__segment[data-unlinking] {
        transform: translateY(var(--noora-spacing-4));
        opacity: 0;
      }

      .segment-ring-lab__segment[data-fresh] {
        animation: segment-ring-lab-arrive 0.4s ease;
      }

      @keyframes segment-ring-lab-arrive {
        from {
          transform: translateY(calc(var(--noora-spacing-4) * -1));
          opacity: 0;
        }
      }

      .segment-ring-lab__slots {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 2px;
      }

      .segment-ring-lab__slot {
        border-radius: 1px;
        background: var(--noora-neutral-light-300);
        aspect-ratio: 1;
      }

      .segment-ring-lab__slot[data-filled] {
        background: var(--noora-neutral-light-700);
      }

      .segment-ring-lab__segment--new .segment-ring-lab__slot[data-filled] {
        background: var(--noora-button-primary-background);
      }

      .segment-ring-lab__band {
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
        font-size: 0.6875rem;
        text-align: center;
      }

      .segment-ring-lab__legend {
        display: flex;
        flex-wrap: wrap;
        gap: var(--noora-spacing-2) var(--noora-spacing-5);
        margin-top: var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .segment-ring-lab__legend span {
        display: inline-flex;
        align-items: center;
        gap: var(--noora-spacing-2);
      }

      .segment-ring-lab__key {
        display: inline-block;
        border-radius: 1px;
        width: var(--noora-spacing-3);
        height: var(--noora-spacing-3);
      }

      .segment-ring-lab__key[data-key="written"] {
        background: var(--noora-neutral-light-700);
      }

      .segment-ring-lab__key[data-key="free"] {
        background: var(--noora-neutral-light-300);
      }

      .segment-ring-lab__stats {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--noora-spacing-4);
        margin-top: var(--noora-spacing-5);
      }

      .segment-ring-lab__stat {
        display: grid;
        gap: var(--noora-spacing-1);
      }

      .segment-ring-lab__stat dt {
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .segment-ring-lab__stat dd {
        margin: 0;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
      }

      .segment-ring-lab__explanation {
        margin-top: var(--noora-spacing-4);
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      @media (width < 48rem) {
        .segment-ring-lab__slots {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .segment-ring-lab__band {
          display: none;
        }

        .segment-ring-lab__stats {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    </style>

    <section id={@id} class="segment-ring-lab" data-part="segment-ring-lab">
      <.card icon="database" title="The segment ring">
        <.card_section>
          <div class="segment-ring-lab__header">
            <button type="button" class="segment-ring-lab__toggle" data-toggle aria-pressed="false">
              Pause
            </button>
          </div>

          <div class="segment-ring-lab__flow">
            <span>writes append here</span>
            <span>the oldest segment is unlinked whole</span>
          </div>

          <div
            id={@id <> "-track"}
            class="segment-ring-lab__track"
            data-track
            phx-hook=".SegmentRing"
            phx-update="ignore"
          >
          </div>

          <div class="segment-ring-lab__legend">
            <span><i class="segment-ring-lab__key" data-key="written"></i> artifact body</span>
            <span><i class="segment-ring-lab__key" data-key="free"></i> free space, only ever in the open segment</span>
          </div>

          <dl class="segment-ring-lab__stats">
            <div class="segment-ring-lab__stat">
              <dt>Unlink operations</dt>
              <dd data-stat-unlinks>0</dd>
            </div>
            <div class="segment-ring-lab__stat">
              <dt>Artifacts reclaimed</dt>
              <dd data-stat-reclaimed>0</dd>
            </div>
            <div class="segment-ring-lab__stat">
              <dt>Last reclaim</dt>
              <dd data-stat-last>waiting for the head to fill</dd>
            </div>
          </dl>

          <p class="segment-ring-lab__explanation">
            Artifacts are appended to the newest segment. When it fills, the ring rotates and the
            oldest segment is removed in a single <code>unlink</code>, taking every artifact inside
            it at once. Eviction never visits an individual artifact, which is why its cost does not
            grow with how many the segment happened to hold.
          </p>
        </.card_section>
      </.card>
    </section>
    """
  end
end
