defmodule TuistWeb.Components.ModuleInvalidationsTable do
  @moduledoc """
  Shared table of modules ranked by cache misses, used both on the Module Cache
  dashboard card and the standalone "all modules" page. Each row shows the
  module, its miss count split into the three reasons a module misses, its cache
  hit rate, and how many modules depend on it. Changed, Upstream and Cold sum to
  Misses.
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
        <.text_cell label={Integer.to_string(module.invalidations)} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Changed")}>
        <.text_cell label={Integer.to_string(module.self_changes)} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Upstream")}>
        <.text_cell label={Integer.to_string(module.dependency_induced)} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Cold")}>
        <.text_cell label={Integer.to_string(module.unclassified)} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Cache hit rate")}>
        <.text_cell label={"#{module.hit_rate}%"} />
      </:col>
      <:col :let={module} label={dgettext("dashboard_cache", "Dependents")}>
        <.text_cell label={Integer.to_string(module.blast_radius || 0)} />
      </:col>
    </.table>
    """
  end
end
