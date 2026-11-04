defmodule TuistWeb.Marketing.Components.Posts.NativeEdges.EdgeGraphLab do
  @moduledoc """
  Interactive graph for the native edges post. It compares choosing core
  targets through graph dependencies with compiling the core with per-edge
  flags, and shows which hashes are new (and so must be built) after each change.
  """
  use TuistWeb, :live_component

  @edges [
    %{id: "ios", label: "iOS app", x: 30, deps: ~w(agent), features: "ios"},
    %{id: "android", label: "Android app", x: 200, deps: ~w(agent), features: "android"},
    %{id: "cli", label: "CLI", x: 370, deps: ~w(agent), features: "cli"},
    %{id: "widget", label: "Widget", x: 540, deps: ~w(storage), features: "widget"}
  ]

  @core_targets [
    %{id: "agent", label: "agent", x: 200, y: 140, deps: ~w(network storage)},
    %{id: "network", label: "network", x: 30, y: 250, deps: []},
    %{id: "storage", label: "storage", x: 455, y: 250, deps: []}
  ]

  @node_width 150
  @node_height 54

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if Map.has_key?(socket.assigns, :mode) do
        socket
      else
        socket
        |> assign(:mode, "graph")
        |> assign(:enabled, MapSet.new(~w(ios android cli)))
        |> assign(:revision, 1)
        |> reset_cache()
      end

    {:ok, socket}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in ["graph", "flags"] do
    {:noreply, socket |> assign(:mode, mode) |> reset_cache()}
  end

  def handle_event("toggle_edge", %{"edge" => edge}, socket) do
    enabled =
      if MapSet.member?(socket.assigns.enabled, edge),
        do: MapSet.delete(socket.assigns.enabled, edge),
        else: MapSet.put(socket.assigns.enabled, edge)

    if MapSet.size(enabled) == 0 do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:enabled, enabled) |> build()}
    end
  end

  def handle_event("edit_storage", _params, socket) do
    {:noreply, socket |> update(:revision, &(&1 + 1)) |> build()}
  end

  defp reset_cache(socket) do
    nodes = nodes(socket.assigns)

    socket
    |> assign(:cache, MapSet.new(nodes, & &1.hash))
    |> assign(:nodes, Enum.map(nodes, &Map.put(&1, :built?, false)))
    |> assign(:last_change, nil)
  end

  defp build(socket) do
    nodes = nodes(socket.assigns)
    nodes = Enum.map(nodes, &Map.put(&1, :built?, not MapSet.member?(socket.assigns.cache, &1.hash)))
    built = Enum.filter(nodes, & &1.built?)

    socket
    |> assign(:nodes, nodes)
    |> assign(:cache, Enum.reduce(nodes, socket.assigns.cache, &MapSet.put(&2, &1.hash)))
    |> assign(:last_change, %{
      core: Enum.count(built, &(&1.kind == :core)),
      edges: Enum.count(built, &(&1.kind == :edge))
    })
  end

  # A node's hash covers its own sources and the hashes of what it depends on.
  # Nothing about the nodes that depend on it goes in.
  defp nodes(%{mode: "graph", enabled: enabled, revision: revision}) do
    core =
      Enum.reduce(Enum.reverse(@core_targets), %{}, fn target, hashes ->
        sources = if target.id == "storage", do: revision, else: 1
        hash = hash([target.id, sources | Enum.map(target.deps, &hashes[&1])])
        Map.put(hashes, target.id, hash)
      end)

    core_nodes =
      @core_targets
      |> Enum.filter(fn target -> Enum.any?(enabled_edges(enabled), &(target.id in reachable(&1.deps))) end)
      |> Enum.map(fn target ->
        %{
          id: target.id,
          kind: :core,
          label: target.label,
          detail: nil,
          x: target.x,
          y: target.y,
          hash: core[target.id],
          deps: Enum.map(target.deps, &center(&1))
        }
      end)

    edge_nodes =
      Enum.map(enabled_edges(enabled), fn edge ->
        %{
          id: edge.id,
          kind: :edge,
          label: edge.label,
          detail: nil,
          x: edge.x,
          y: 30,
          hash: hash([edge.id | Enum.map(edge.deps, &core[&1])]),
          deps: Enum.map(edge.deps, &center(&1))
        }
      end)

    edge_nodes ++ core_nodes
  end

  defp nodes(%{mode: "flags", enabled: enabled, revision: revision}) do
    enabled
    |> enabled_edges()
    |> Enum.flat_map(fn edge ->
      core_hash = hash(["core", revision, edge.features])

      [
        %{
          id: edge.id,
          kind: :edge,
          label: edge.label,
          detail: nil,
          x: edge.x,
          y: 30,
          hash: hash([edge.id, core_hash]),
          deps: [{edge.x + @node_width / 2, 150}]
        },
        %{
          id: "core-" <> edge.id,
          kind: :core,
          label: "core",
          detail: "--features " <> edge.features,
          x: edge.x,
          y: 150,
          hash: core_hash,
          deps: []
        }
      ]
    end)
  end

  defp enabled_edges(enabled), do: Enum.filter(@edges, &MapSet.member?(enabled, &1.id))

  defp reachable(ids) do
    Enum.flat_map(ids, fn id ->
      target = Enum.find(@core_targets, &(&1.id == id))
      [id | reachable(target.deps)]
    end)
  end

  defp center(id) do
    target = Enum.find(@core_targets, &(&1.id == id))
    {target.x + @node_width / 2, target.y}
  end

  defp hash(parts) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(parts))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 6)
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:edges, @edges)
      |> assign(:node_width, @node_width)
      |> assign(:node_height, @node_height)
      |> assign(:core_count, Enum.count(assigns.nodes, &(&1.kind == :core)))

    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      .edge-graph-lab {
        display: flex;
        flex-direction: column;
        gap: var(--noora-spacing-5);
        margin: var(--noora-spacing-9) 0;
        width: min(780px, calc(100vw - var(--noora-spacing-12)));

        @media (min-width: 1024px) {
          margin-left: calc((650px - 780px) / 2);
        }
      }

      .edge-graph-lab__controls {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--noora-spacing-4);
      }

      .edge-graph-lab__segmented {
        display: inline-flex;
        padding: 2px;
        border: 1px solid var(--noora-surface-border-primary);
        border-radius: 8px;
      }

      .edge-graph-lab button {
        cursor: pointer;
        padding: var(--noora-spacing-2) var(--noora-spacing-4);
        border: 1px solid transparent;
        border-radius: 6px;
        background: none;
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .edge-graph-lab button[aria-pressed="true"] {
        background: var(--noora-purple-500);
        color: var(--noora-button-primary-label);
      }

      .edge-graph-lab__edges button,
      .edge-graph-lab .edge-graph-lab__edit {
        border-color: var(--noora-surface-border-primary);
      }

      .edge-graph-lab__edges {
        display: inline-flex;
        flex-wrap: wrap;
        gap: var(--noora-spacing-2);
      }

      .edge-graph-lab__edges button[aria-pressed="true"] {
        border-color: var(--noora-purple-500);
        background: none;
        color: var(--noora-surface-label-primary);
      }

      .edge-graph-lab svg {
        display: block;
        width: 100%;
        height: auto;
      }

      .edge-graph-lab__line {
        stroke: var(--marketing-illustration-neutral-6);
        stroke-width: 1.5;
      }

      .edge-graph-lab__node {
        fill: var(--noora-surface-background-primary);
        stroke: var(--marketing-illustration-neutral-7);
        stroke-width: 1.5;
        transition: fill 200ms, stroke 200ms;
      }

      .edge-graph-lab__node[data-built] {
        fill: color-mix(in srgb, var(--noora-purple-500) 16%, var(--noora-surface-background-primary));
        stroke: var(--noora-purple-500);
        stroke-width: 2;
      }

      .edge-graph-lab__label {
        fill: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .edge-graph-lab__hash {
        fill: var(--noora-surface-label-secondary);
        font-family: var(--noora-font-family-mono, ui-monospace, monospace);
        font-size: 11px;
      }

      .edge-graph-lab__row-label {
        fill: var(--noora-surface-label-tertiary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }

      .edge-graph-lab__result {
        margin: 0;
        color: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
      }

      .edge-graph-lab__result strong {
        color: var(--noora-surface-label-primary);
        font-weight: var(--noora-font-weight-semibold);
      }
    </style>

    <section id={@id} class="edge-graph-lab" aria-label="Per-edge build graph">
      <div class="edge-graph-lab__controls">
        <div class="edge-graph-lab__segmented" role="group" aria-label="How edges choose the core">
          <button
            type="button"
            phx-click="set_mode"
            phx-value-mode="graph"
            phx-target={@myself}
            aria-pressed={to_string(@mode == "graph")}
          >
            Choose in the graph
          </button>
          <button
            type="button"
            phx-click="set_mode"
            phx-value-mode="flags"
            phx-target={@myself}
            aria-pressed={to_string(@mode == "flags")}
          >
            Flags per edge
          </button>
        </div>
        <div class="edge-graph-lab__edges" role="group" aria-label="Edges">
          <button
            :for={edge <- @edges}
            type="button"
            phx-click="toggle_edge"
            phx-value-edge={edge.id}
            phx-target={@myself}
            aria-pressed={to_string(MapSet.member?(@enabled, edge.id))}
          >
            {edge.label}
          </button>
        </div>
        <button
          type="button"
          class="edge-graph-lab__edit"
          phx-click="edit_storage"
          phx-target={@myself}
        >
          Edit storage.rs
        </button>
      </div>

      <svg
        viewBox={"0 0 720 #{if @mode == "graph", do: 310, else: 230}"}
        role="img"
        aria-label="Build graph with a hash per node"
      >
        <text x="0" y="22" class="edge-graph-lab__row-label">Edges</text>
        <text x="0" y={if @mode == "graph", do: 132, else: 142} class="edge-graph-lab__row-label">
          Core
        </text>
        <g :for={node <- @nodes}>
          <line
            :for={{x, y} <- node.deps}
            x1={node.x + @node_width / 2}
            y1={node.y + @node_height}
            x2={x}
            y2={y}
            class="edge-graph-lab__line"
          />
        </g>
        <g :for={node <- @nodes} transform={"translate(#{node.x}, #{node.y})"}>
          <rect
            width={@node_width}
            height={if node.detail, do: @node_height + 16, else: @node_height}
            rx="8"
            class="edge-graph-lab__node"
            data-built={node.built?}
          />
          <text x="12" y="22" class="edge-graph-lab__label">{node.label}</text>
          <text :if={node.detail} x="12" y="41" class="edge-graph-lab__hash">{node.detail}</text>
          <text x="12" y={if node.detail, do: 57, else: 41} class="edge-graph-lab__hash">
            #{node.hash}
          </text>
        </g>
      </svg>

      <p class="edge-graph-lab__result">
        <strong>{@core_count} core {if @core_count == 1, do: "build", else: "builds"}</strong>
        to keep warm in the cache.
        <%= if @last_change do %>
          Your last change built
          <strong>{@last_change.core} core {if @last_change.core == 1, do: "target", else: "targets"}</strong>
          and <strong>{@last_change.edges} {if @last_change.edges == 1, do: "edge", else: "edges"}</strong>;
          everything else was already in the cache.
        <% else %>
          Add or remove an edge, or edit a core file, to see what has to be built.
        <% end %>
      </p>
    </section>
    """
  end
end
