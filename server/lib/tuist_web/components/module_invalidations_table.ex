defmodule TuistWeb.Components.ModuleInvalidationsTable do
  @moduledoc """
  Shared table of modules ranked by cache invalidations, used both on the Module
  Cache dashboard card and the standalone "all modules" page. Each row shows the
  module, its invalidation count and rate, a self-change vs dependency-induced
  split, and the downstream blast radius.
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
      <:col :let={module} label={dgettext("dashboard_cache", "Invalidations")}>
        <.text_and_description_cell
          label={"#{module.invalidations}"}
          description={
            dgettext("dashboard_cache", "%{rate}% of %{appearances} builds",
              rate: module.invalidation_rate,
              appearances: module.appearances
            )
          }
        />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Why")}>
        <.why_split module={module} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Blast radius")}>
        <.text_and_description_cell
          :if={module.blast_radius}
          label={blast_radius_label(module.blast_radius)}
          description={dgettext("dashboard_cache", "invalidated downstream")}
        />
        <.text_cell :if={is_nil(module.blast_radius)} sublabel="—" />
      </:col>
    </.table>
    """
  end

  attr :module, :map, required: true

  @doc """
  Renders the self-change vs dependency-induced split bar with labelled badges.
  Styled inline so it renders identically on any page.
  """
  def why_split(assigns) do
    ~H"""
    <div style="display: flex; flex-direction: column; gap: var(--noora-spacing-2); min-width: 140px;">
      <div style="display: flex; height: 6px; border-radius: 3px; overflow: hidden; background: var(--noora-chart-lines);">
        <span style={"width: #{segment_width(@module.self_changes, @module.invalidations)}; background: var(--noora-chart-primary);"}>
        </span>
        <span style={"width: #{segment_width(@module.dependency_induced, @module.invalidations)}; background: var(--noora-chart-secondary);"}>
        </span>
      </div>
      <div style="display: flex; flex-direction: row; gap: var(--noora-spacing-3);">
        <.badge
          label={dgettext("dashboard_cache", "%{count} self", count: @module.self_changes)}
          color="primary"
          size="small"
          dot
        />
        <.badge
          label={dgettext("dashboard_cache", "%{count} deps", count: @module.dependency_induced)}
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

  def blast_radius_label(1), do: dgettext("dashboard_cache", "1 module")
  def blast_radius_label(count), do: dgettext("dashboard_cache", "%{count} modules", count: count)
end
