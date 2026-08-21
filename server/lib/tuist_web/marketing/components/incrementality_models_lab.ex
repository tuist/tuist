defmodule TuistWeb.Marketing.Components.IncrementalityModelsLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="incrementality-models-lab"
      phx-hook="IncrementalityModelsDiagram"
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
