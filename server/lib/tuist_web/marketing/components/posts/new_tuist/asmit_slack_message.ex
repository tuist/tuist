defmodule TuistWeb.Marketing.Components.Posts.NewTuist.AsmitSlackMessage do
  @moduledoc """
  Renders a stylised Slack message reproducing the note Asmit sent in
  #general on 2026-04-07 that sparked the Tuist rebrand. The purple-heart
  reaction is interactive: readers can toggle their own reaction, which
  updates the count in place.
  """
  use TuistWeb, :live_component

  @base_reactions 5

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:reacted, fn -> false end)
      |> assign_new(:base_reactions, fn -> @base_reactions end)

    {:ok, socket}
  end

  def handle_event("toggle_heart", _params, socket) do
    {:noreply, update(socket, :reacted, &(!&1))}
  end

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      [data-part="asmit-slack-message"] {
        margin: var(--noora-spacing-7) 0;
        border-radius: var(--noora-radius-3);
        border: 1px solid light-dark(#e6e6e6, #3d3f42);
        background: light-dark(#ffffff, #1a1d21);
        color: light-dark(#1d1c1d, #d1d2d3);
        padding: var(--noora-spacing-5) var(--noora-spacing-6);
        font-family: "Lato", "Slack-Lato", -apple-system, system-ui, sans-serif;
        line-height: 1.46;

        & [data-part="row"] {
          display: flex;
          gap: 12px;
          align-items: flex-start;
        }

        & [data-part="avatar"] {
          flex-shrink: 0;
          display: block;
          width: 36px;
          height: 36px;
          border-radius: 6px;
          background-color: light-dark(#ebeaeb, #ababad);
          background-repeat: no-repeat;
          background-size: 42px 52px;
          background-position: center 45%;
        }

        & [data-part="content"] {
          flex: 1;
          min-width: 0;
        }

        & [data-part="header"] {
          display: flex;
          align-items: baseline;
          gap: 8px;
          margin: 0 0 2px;
        }

        & [data-part="name"] {
          color: light-dark(#1d1c1d, #d1d2d3);
          font-weight: 900;
          font-size: 15px;
          letter-spacing: -0.1px;
        }

        & [data-part="timestamp"] {
          color: light-dark(#616061, #ababad);
          font-size: 12px;
        }

        & [data-part="body"] {
          color: light-dark(#1d1c1d, #d1d2d3);
          font-size: 15px;
        }

        & [data-part="body"] p,
        [data-part="asmit-slack-message"] & [data-part="body"] p {
          margin: 0;
          padding: 0;
        }

        & [data-part="body"] p + p,
        [data-part="asmit-slack-message"] & [data-part="body"] p + p {
          margin-top: 6px;
        }

        & [data-part="reactions"] {
          display: flex;
          gap: 6px;
          margin-top: 10px;
          flex-wrap: wrap;
        }

        & [data-part="reaction"] {
          display: inline-flex;
          align-items: center;
          gap: 6px;
          padding: 3px 8px 3px 6px;
          border-radius: 12px;
          border: 1px solid light-dark(#dcdcdc, #565856);
          background: light-dark(#f4f4f5, #222529);
          color: light-dark(#616061, #ababad);
          font-size: 13px;
          font-weight: 700;
          cursor: pointer;
          transition: background 120ms ease, border-color 120ms ease, color 120ms ease;
          user-select: none;
          font-family: inherit;
        }

        & [data-part="reaction"]:hover {
          background: light-dark(#eeeef0, #35373b);
          border-color: light-dark(#cfcfd1, #ababad);
        }

        & [data-part="reaction"][data-reacted="true"] {
          background: light-dark(rgba(138, 99, 210, 0.12), rgba(167, 139, 250, 0.18));
          border-color: light-dark(rgba(138, 99, 210, 0.55), rgba(167, 139, 250, 0.65));
          color: light-dark(#6b3fbf, #c4b5fd);
        }

        & [data-part="reaction"] {
          position: relative;
        }

        & [data-part="reaction"] [data-part="emoji"] {
          display: inline-block;
          font-size: 16px;
          line-height: 1;
          transform-origin: center;
          transition: transform 140ms cubic-bezier(0.34, 1.56, 0.64, 1);
        }

        & [data-part="reaction"][data-pulse="true"] [data-part="emoji"] {
          transform: scale(1.35);
        }

        & [data-part="reaction"][data-burst="true"] [data-part="emoji"] {
          animation: asmit-heart-pop 520ms cubic-bezier(0.34, 1.56, 0.64, 1);
        }

        & [data-part="burst-layer"] {
          position: absolute;
          left: 0;
          top: 0;
          width: 0;
          height: 0;
          pointer-events: none;
        }

        & [data-part="burst-layer"] > span {
          position: absolute;
          left: 0;
          top: 0;
          font-size: 12px;
          line-height: 1;
          transform: translate(-50%, -50%) scale(0.4);
          opacity: 0;
          will-change: transform, opacity;
        }

        @keyframes asmit-heart-pop {
          0% { transform: scale(1); }
          40% { transform: scale(1.55); }
          70% { transform: scale(0.9); }
          100% { transform: scale(1); }
        }

        & [data-part="add-reaction"] {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 30px;
          height: 24px;
          border-radius: 12px;
          border: 1px solid light-dark(#dcdcdc, #565856);
          background: transparent;
          color: light-dark(#616061, #ababad);
          cursor: not-allowed;
          font-family: inherit;
        }
      }
    </style>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".AsmitReactionIntro">
      const PARTICLE_COUNT = 10;
      const STEP_DELAY_MS = 220;
      const PULSE_MS = 160;

      export default {
        mounted() {
          this.button = this.el.querySelector('[data-part="reaction"]');
          this.count = this.el.querySelector('[data-part="count"]');
          this.timers = [];
          this.played = false;

          if (!this.button || !this.count) return;

          this.target = parseInt(this.count.textContent, 10) || 0;
          if (this.target < 1) return;

          // Show zero until the intro fires so the count-up starts from 0.
          this.count.textContent = "0";

          if (typeof IntersectionObserver !== "function") {
            this.play();
            return;
          }

          this.observer = new IntersectionObserver((entries) => {
            for (const entry of entries) {
              if (entry.isIntersecting && !this.played) {
                this.played = true;
                this.observer.disconnect();
                this.play();
              }
            }
          }, { threshold: 0.45 });
          this.observer.observe(this.el);
        },

        destroyed() {
          this.observer?.disconnect();
          this.timers.forEach(clearTimeout);
        },

        play() {
          for (let i = 1; i <= this.target; i++) {
            const t = setTimeout(() => {
              this.count.textContent = String(i);
              this.pulse();
              if (i === this.target) {
                this.timers.push(setTimeout(() => this.burst(), 120));
              }
            }, i * STEP_DELAY_MS);
            this.timers.push(t);
          }
        },

        pulse() {
          this.button.setAttribute("data-pulse", "true");
          this.timers.push(setTimeout(() => {
            this.button.removeAttribute("data-pulse");
          }, PULSE_MS));
        },

        burst() {
          this.button.setAttribute("data-burst", "true");
          this.timers.push(setTimeout(() => {
            this.button.removeAttribute("data-burst");
          }, 560));

          const emoji = this.button.querySelector('[data-part="emoji"]');
          if (!emoji) return;
          const buttonRect = this.button.getBoundingClientRect();
          const emojiRect = emoji.getBoundingClientRect();

          const layer = document.createElement("div");
          layer.setAttribute("data-part", "burst-layer");
          layer.style.left = (emojiRect.left - buttonRect.left + emojiRect.width / 2) + "px";
          layer.style.top = (emojiRect.top - buttonRect.top + emojiRect.height / 2) + "px";
          this.button.appendChild(layer);

          for (let i = 0; i < PARTICLE_COUNT; i++) {
            const angle = (i / PARTICLE_COUNT) * Math.PI * 2 + (Math.random() - 0.5) * 0.35;
            const distance = 26 + Math.random() * 16;
            const drift = -4 - Math.random() * 8;
            const p = document.createElement("span");
            p.textContent = "💜";
            p.style.transition = "transform 720ms cubic-bezier(0.16, 1, 0.3, 1), opacity 720ms ease-out";
            layer.appendChild(p);
            requestAnimationFrame(() => {
              requestAnimationFrame(() => {
                const tx = Math.cos(angle) * distance;
                const ty = Math.sin(angle) * distance + drift;
                p.style.transform = `translate(calc(-50% + ${tx}px), calc(-50% + ${ty}px)) scale(1)`;
                p.style.opacity = "1";
              });
            });
            this.timers.push(setTimeout(() => {
              p.style.opacity = "0";
            }, 260));
          }
          this.timers.push(setTimeout(() => layer.remove(), 900));
        },
      };
    </script>

    <div
      id={@id}
      data-part="asmit-slack-message"
      phx-hook=".AsmitReactionIntro"
      aria-label="Slack message from Asmit Malakannawar in #general"
    >
      <div data-part="row">
        <span
          data-part="avatar"
          role="img"
          aria-label="Asmit Malakannawar"
          style="background-image: url('/marketing/images/about/team/asmit.svg');"
        ></span><div data-part="content">
          <div data-part="header">
            <span data-part="name">Asmit Malakannawar</span><span data-part="timestamp">10:00 AM</span>
          </div><div data-part="body">
            <p>
              Over the weekend, I spent some time thinking about Tuist as a brand, our identity and how we present our products, and ended up going down a bit of a rabbit hole with a few observations:
            </p><p>
              Starting with the logo, it currently gives the impression that we only support iOS/macOS apps. While the product has evolved significantly over time, the design hasn't fully evolved alongside it. As we continue to grow and expand our ecosystem, it feels like the right time to revisit our branding.
            </p><p>
              With that in mind, I'd like to explore a rebrand, defining a clearer product identity and making our visual assets more adaptable and accessible. This wouldn't drastically change the Noora design system, aside from some updates to colors and shadows, but I'm aiming to work on something more foundational and impactful.
            </p><p>Would love to hear your thoughts.</p>
          </div><div data-part="reactions">
            <button
              type="button"
              data-part="reaction"
              data-reacted={to_string(@reacted)}
              phx-click="toggle_heart"
              phx-target={@myself}
              aria-pressed={to_string(@reacted)}
              aria-label={
                if @reacted,
                  do: "Remove your purple heart reaction",
                  else: "React with a purple heart"
              }
            ><span data-part="emoji">💜</span><span data-part="count">{@base_reactions +
              if @reacted, do: 1, else: 0}</span></button><span
              data-part="add-reaction"
              aria-hidden="true"
            >+</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
