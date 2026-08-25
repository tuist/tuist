defmodule TuistWeb.Marketing.Components.IncrementalityModelsLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".IncrementalityModelsDiagram">
      const IncrementalityModelsDiagram = {
        mounted() {
          this.observer = new IntersectionObserver(
            ([entry]) => {
              this.el.classList.toggle("is-visible", entry.isIntersecting);
            },
            { threshold: 0.35 },
          );

          this.observer.observe(this.el);
        },

        destroyed() {
          this.observer?.disconnect();
        },
      };

      export { IncrementalityModelsDiagram };

      export default IncrementalityModelsDiagram;
    </script>

    <style :type={TuistWeb.ColocatedCSS}>
      .incrementality-models-lab {
        margin: var(--noora-spacing-7) 0;
      }

      .incrementality-models-lab__models {
        display: grid;
        gap: var(--noora-spacing-7);
      }

      .incrementality-models-lab__model {
        display: grid;
        gap: var(--noora-spacing-5);
        margin: 0;
        min-width: 0;
      }

      .incrementality-models-lab__caption {
        display: grid;
        gap: var(--noora-spacing-1);
      }

      .incrementality-models-lab__caption strong {
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-semibold) var(--noora-font-body-small);
      }

      .incrementality-models-lab__caption span {
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .incrementality-models-lab__model svg {
        display: block;
        width: 100%;
        height: auto;
        overflow: visible;
      }

      .incrementality-models-lab__edge {
        stroke: currentColor;
        stroke-width: 2;
        color: var(--noora-surface-label-secondary);
      }

      .incrementality-models-lab__edge--lookup {
        stroke-dasharray: var(--noora-spacing-1) var(--noora-spacing-1);
      }

      .incrementality-models-lab__flow {
        opacity: 0;
        fill: var(--noora-button-primary-background);
      }

      .incrementality-models-lab__node {
        fill: var(--noora-surface-background-primary);
        stroke: var(--noora-surface-border-primary);
        stroke-width: 2;
      }

      .incrementality-models-lab__node--reused {
        fill: var(--noora-purple-100);
        stroke: var(--noora-button-primary-background);
      }

      .incrementality-models-lab__state {
        fill: var(--noora-surface-background-secondary);
        stroke: var(--noora-surface-border-primary);
        stroke-width: 2;
      }

      .incrementality-models-lab__result {
        fill: var(--noora-button-primary-background);
        stroke: var(--noora-button-primary-background);
        stroke-width: 2;
      }

      .incrementality-models-lab__node-label,
      .incrementality-models-lab__result-label,
      .incrementality-models-lab__worktree-label {
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .incrementality-models-lab__node-label,
      .incrementality-models-lab__worktree-label {
        fill: var(--noora-surface-label-primary);
      }

      .incrementality-models-lab__node-secondary-label,
      .incrementality-models-lab__annotation,
      .incrementality-models-lab__result-secondary-label {
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .incrementality-models-lab__node-secondary-label,
      .incrementality-models-lab__annotation {
        fill: var(--noora-surface-label-secondary);
      }

      .incrementality-models-lab__result-label,
      .incrementality-models-lab__result-secondary-label {
        fill: var(--noora-button-primary-label);
      }

      .incrementality-models-lab.is-visible .incrementality-models-lab__flow--location-a {
        animation: incrementality-models-lab-location-flow 1.8s ease-out infinite;
      }

      .incrementality-models-lab.is-visible .incrementality-models-lab__flow--location-b {
        animation: incrementality-models-lab-location-flow 1.8s ease-out 600ms infinite;
      }

      .incrementality-models-lab.is-visible .incrementality-models-lab__flow--identity-produce {
        animation: incrementality-models-lab-identity-produce 1.8s ease-out infinite;
      }

      .incrementality-models-lab.is-visible .incrementality-models-lab__flow--identity-reuse {
        animation: incrementality-models-lab-identity-reuse 1.8s ease-out 600ms infinite;
      }

      @keyframes incrementality-models-lab-location-flow {
        0% {
          transform: translate(0, 0);
          opacity: 0;
        }

        5% {
          opacity: 1;
        }

        25% {
          transform: translate(78px, 0);
          opacity: 1;
        }

        30%,
        100% {
          transform: translate(78px, 0);
          opacity: 0;
        }
      }

      @keyframes incrementality-models-lab-identity-produce {
        0% {
          transform: translate(0, 0);
          opacity: 0;
        }

        5% {
          opacity: 1;
        }

        25% {
          transform: translate(78px, 27px);
          opacity: 1;
        }

        30%,
        100% {
          transform: translate(78px, 27px);
          opacity: 0;
        }
      }

      @keyframes incrementality-models-lab-identity-reuse {
        0% {
          transform: translate(0, 0);
          opacity: 0;
        }

        5% {
          opacity: 1;
        }

        25% {
          transform: translate(78px, -32px);
          opacity: 1;
        }

        30%,
        100% {
          transform: translate(78px, -32px);
          opacity: 0;
        }
      }

      @media (prefers-reduced-motion: reduce) {
        .incrementality-models-lab__flow {
          display: none;
        }
      }

      @media (width >= 48rem) {
        .incrementality-models-lab__models {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    </style>

    <section
      id={@id}
      class="incrementality-models-lab"
      phx-hook=".IncrementalityModelsDiagram"
    >
      <.card icon="git_branch" title="Where prior work lives">
        <.card_section>
          <div class="incrementality-models-lab__models">
            <figure class="incrementality-models-lab__model">
              <figcaption class="incrementality-models-lab__caption">
                <strong>Incrementality by location</strong>
                <span>Each build directory keeps its own state.</span>
              </figcaption>

              <svg
                viewBox="0 0 360 180"
                role="img"
                aria-labelledby={@id <> "-location-title " <> @id <> "-location-description"}
              >
                <title id={@id <> "-location-title"}>Incrementality by location</title>
                <desc id={@id <> "-location-description"}>
                  Two worktrees keep separate build directories, so their local incremental state is not
                  reused across worktrees.
                </desc>
                <defs>
                  <marker
                    id={@id <> "-location-arrow"}
                    markerWidth="8"
                    markerHeight="8"
                    refX="7"
                    refY="4"
                    orient="auto"
                  >
                    <path d="M 0 0 L 8 4 L 0 8 z" fill="currentColor" />
                  </marker>
                </defs>

                <line
                  x1="128"
                  y1="50"
                  x2="211"
                  y2="50"
                  class="incrementality-models-lab__edge"
                  marker-end={"url(##{@id}-location-arrow)"}
                />
                <line
                  x1="128"
                  y1="130"
                  x2="211"
                  y2="130"
                  class="incrementality-models-lab__edge"
                  marker-end={"url(##{@id}-location-arrow)"}
                />
                <circle
                  cx="128"
                  cy="50"
                  r="5"
                  class="incrementality-models-lab__flow incrementality-models-lab__flow--location-a"
                />
                <circle
                  cx="128"
                  cy="130"
                  r="5"
                  class="incrementality-models-lab__flow incrementality-models-lab__flow--location-b"
                />

                <rect
                  x="8"
                  y="27"
                  width="120"
                  height="46"
                  rx="8"
                  class="incrementality-models-lab__node"
                />
                <text x="68" y="55" text-anchor="middle" class="incrementality-models-lab__node-label">
                  worktree A
                </text>

                <rect
                  x="8"
                  y="107"
                  width="120"
                  height="46"
                  rx="8"
                  class="incrementality-models-lab__node"
                />
                <text
                  x="68"
                  y="135"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-label"
                >
                  worktree B
                </text>
                <rect
                  x="211"
                  y="20"
                  width="141"
                  height="60"
                  rx="8"
                  class="incrementality-models-lab__state"
                />
                <text
                  x="281.5"
                  y="45"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-label"
                >
                  build directory A
                </text>
                <text
                  x="281.5"
                  y="66"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-secondary-label"
                >
                  mutable state
                </text>

                <rect
                  x="211"
                  y="100"
                  width="141"
                  height="60"
                  rx="8"
                  class="incrementality-models-lab__state"
                />
                <text
                  x="281.5"
                  y="125"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-label"
                >
                  build directory B
                </text>
                <text
                  x="281.5"
                  y="146"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-secondary-label"
                >
                  rebuilds
                </text>
              </svg>
            </figure>

            <figure class="incrementality-models-lab__model">
              <figcaption class="incrementality-models-lab__caption">
                <strong>Incrementality by identity</strong>
                <span>Tasks look up results by the inputs that produced them.</span>
              </figcaption>

              <svg
                viewBox="0 0 360 180"
                role="img"
                aria-labelledby={@id <> "-identity-title " <> @id <> "-identity-description"}
              >
                <title id={@id <> "-identity-title"}>Incrementality by identity</title>
                <desc id={@id <> "-identity-description"}>
                  A task in worktree A writes a result to a cache. A matching task in worktree B looks
                  up the same identity and gets a cache hit.
                </desc>
                <defs>
                  <marker
                    id={@id <> "-identity-arrow"}
                    markerWidth="8"
                    markerHeight="8"
                    refX="7"
                    refY="4"
                    orient="auto"
                  >
                    <path d="M 0 0 L 8 4 L 0 8 z" fill="currentColor" />
                  </marker>
                </defs>

                <line
                  x1="128"
                  y1="70"
                  x2="213"
                  y2="99"
                  class="incrementality-models-lab__edge"
                  marker-end={"url(##{@id}-identity-arrow)"}
                />
                <line
                  x1="128"
                  y1="155"
                  x2="213"
                  y2="119"
                  class="incrementality-models-lab__edge incrementality-models-lab__edge--lookup"
                  marker-end={"url(##{@id}-identity-arrow)"}
                />
                <circle
                  cx="128"
                  cy="70"
                  r="5"
                  class="incrementality-models-lab__flow incrementality-models-lab__flow--identity-produce"
                />
                <circle
                  cx="128"
                  cy="155"
                  r="5"
                  class="incrementality-models-lab__flow incrementality-models-lab__flow--identity-reuse"
                />

                <text
                  x="54"
                  y="34"
                  text-anchor="middle"
                  class="incrementality-models-lab__worktree-label"
                >
                  worktree A
                </text>
                <rect
                  x="8"
                  y="47"
                  width="120"
                  height="46"
                  rx="8"
                  class="incrementality-models-lab__node"
                />
                <text x="68" y="75" text-anchor="middle" class="incrementality-models-lab__node-label">
                  build task
                </text>

                <rect
                  x="213"
                  y="79"
                  width="139"
                  height="60"
                  rx="8"
                  class="incrementality-models-lab__result"
                />
                <text
                  x="282.5"
                  y="104"
                  text-anchor="middle"
                  class="incrementality-models-lab__result-label"
                >
                  cached result
                </text>
                <text
                  x="282.5"
                  y="125"
                  text-anchor="middle"
                  class="incrementality-models-lab__result-secondary-label"
                >
                  same inputs
                </text>

                <text
                  x="68"
                  y="119"
                  text-anchor="middle"
                  class="incrementality-models-lab__worktree-label"
                >
                  worktree B
                </text>
                <rect
                  x="8"
                  y="132"
                  width="120"
                  height="44"
                  rx="8"
                  class="incrementality-models-lab__node incrementality-models-lab__node--reused"
                />
                <text
                  x="68"
                  y="151"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-label"
                >
                  matching task
                </text>
                <text
                  x="68"
                  y="169"
                  text-anchor="middle"
                  class="incrementality-models-lab__node-secondary-label"
                >
                  cache hit
                </text>
              </svg>
            </figure>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end
end
