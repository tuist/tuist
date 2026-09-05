defmodule TuistWeb.Components.ModuleInvalidationsTable do
  @moduledoc """
  Shared table of modules ranked by cache misses, used both on the Module Cache
  dashboard card and the standalone "all modules" page. Each row shows the
  module, its miss count, its cache hit rate, and how many modules depend on it.
  """
  use Phoenix.Component
  use Gettext, backend: TuistWeb.Gettext
  use Noora

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_navigate, :any, default: nil, doc: "fn module -> path end for row navigation"
  attr :sort_by, :string, default: nil, doc: "Column the rows are ordered by"
  attr :sort_order, :string, default: nil, doc: ~s("asc" or "desc")

  attr :sort_patch, :any,
    default: nil,
    doc: "fn column -> patch end. Without it the headers are not sortable."

  def module_invalidations_table(assigns) do
    # The table keys each row off `:id`; without one every row lands on the same
    # DOM id and LiveView cannot tell them apart when patching.
    assigns = update(assigns, :rows, fn rows -> Enum.map(rows, &Map.put(&1, :id, &1.name)) end)

    ~H"""
    <.table id={@id} rows={@rows} row_navigate={@row_navigate}>
      <:col :let={module} label={dgettext("dashboard_cache", "Module")}>
        <.text_cell label={module.name} />
      </:col>
      <:col
        :let={module}
        label={dgettext("dashboard_cache", "Misses")}
        patch={sort_patch(assigns, "invalidations")}
        sort_order={@sort_by == "invalidations" && @sort_order}
      >
        <.text_cell label={Integer.to_string(module.invalidations)} />
      </:col>
      <:col
        :let={module}
        label={dgettext("dashboard_cache", "Cache hit rate")}
        patch={sort_patch(assigns, "hit_rate")}
        sort_order={@sort_by == "hit_rate" && @sort_order}
      >
        <.text_cell label={"#{module.hit_rate}%"} />
      </:col>
      <:col
        :let={module}
        label={dgettext("dashboard_cache", "Dependents")}
        patch={sort_patch(assigns, "blast_radius")}
        sort_order={@sort_by == "blast_radius" && @sort_order}
      >
        <.text_cell label={Integer.to_string(module.blast_radius || 0)} />
      </:col>
    </.table>
    """
  end

  # Only the column already being sorted is clickable; the sort dropdown is what
  # picks a different one, matching the build run and cache run tables.
  defp sort_patch(%{sort_by: column, sort_patch: patch}, column) when is_function(patch, 1), do: patch.(column)
  defp sort_patch(_assigns, _column), do: nil
end
