defmodule TuistWeb.Components.ModuleInvalidationsTable do
  @moduledoc """
  Shared table of modules ranked by cache misses, used both on the Module Cache
  dashboard card and the standalone "all modules" page. Each row shows the
  module, its miss count, its cache hit rate, whether those misses came from its
  own content changing or from an upstream dependency, and how many modules
  depend on it.
  """
  use Phoenix.Component
  use Gettext, backend: TuistWeb.Gettext
  use Noora

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_navigate, :any, default: nil, doc: "fn module -> path end for row navigation"

  def module_invalidations_table(assigns) do
    ~H"""
    <.table id={@id} rows={@rows} row_navigate={@row_navigate}>
      <:col :let={module} label={dgettext("dashboard_cache", "Module")}>
        <.text_and_description_cell
          label={module.name}
          description={if module.product != "", do: module.product}
        />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Misses")}>
        <.text_and_description_cell
          label={"#{module.invalidations}"}
          description={
            dgettext("dashboard_cache", "of %{appearances} builds", appearances: module.appearances)
          }
        />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Cache hit rate")}>
        <.text_cell label={"#{module.hit_rate}%"} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Why")}>
        <.why_split module={module} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Dependents")}>
        <.text_cell label={Integer.to_string(module.blast_radius || 0)} />
      </:col>
    </.table>
    """
  end

  attr :module, :map, required: true

  @doc """
  Renders the self-change vs dependency-induced split bar with labelled badges.
  """
  def why_split(assigns) do
    ~H"""
    <div class="module-invalidations-why">
      <div data-part="bar">
        <span
          data-part="changed"
          style={"width: #{segment_width(@module.self_changes, @module.invalidations)}"}
        ></span>
        <span
          data-part="upstream"
          style={"width: #{segment_width(@module.dependency_induced, @module.invalidations)}"}
        ></span>
      </div>
      <div data-part="badges">
        <.badge
          label={dgettext("dashboard_cache", "%{count} changed", count: @module.self_changes)}
          color="primary"
          size="small"
          dot
        />
        <.badge
          label={dgettext("dashboard_cache", "%{count} upstream", count: @module.dependency_induced)}
          color="secondary"
          size="small"
          dot
        />
      </div>
    </div>
    """
  end

  def segment_width(_count, total) when total in [0, nil], do: "0%"
  def segment_width(count, total), do: "#{Float.round(count / total * 100, 1)}%"
end
