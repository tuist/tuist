defmodule TuistWeb.Helpers.BuildEntityLabels do
  @moduledoc false

  use Gettext, backend: TuistWeb.Gettext

  def plural(:gradle, "task"), do: dgettext("dashboard_builds", "Tasks")
  def plural(:xcode, "module"), do: dgettext("dashboard_builds", "Modules")
  def plural(:once, "action"), do: dgettext("dashboard_builds", "Actions")
  def plural(:mix, "file"), do: dgettext("dashboard_builds", "Files")
  def plural(:mix, "module"), do: dgettext("dashboard_builds", "Modules")

  def singular(:gradle, "task"), do: dgettext("dashboard_builds", "Task")
  def singular(:xcode, "module"), do: dgettext("dashboard_builds", "Module")
  def singular(:once, "action"), do: dgettext("dashboard_builds", "Action")
  def singular(:mix, "file"), do: dgettext("dashboard_builds", "File")
  def singular(:mix, "module"), do: dgettext("dashboard_builds", "Module")

  def inventory_fields(:gradle, "task"), do: ~w(root_project_name build_path task_type)
  def inventory_fields(:xcode, "module"), do: ~w(project)
  def inventory_fields(:once, "action"), do: ~w(target_id capability action_index)
  def inventory_fields(_system, _kind), do: []

  def identity_value(%{"build_path" => ":"}, "build_path"), do: dgettext("dashboard_builds", "Root build")

  def identity_value(identity, field) do
    case Map.get(identity, field) do
      value when value in [nil, ""] -> dgettext("dashboard_builds", "Not reported")
      value -> value
    end
  end

  def inventory_sublabel(system, kind, row) do
    value = Map.get(row.identity, primary_field(system, kind))
    if value in [nil, "", row.name], do: nil, else: value
  end

  defp primary_field(:gradle, "task"), do: "task_path"
  defp primary_field(:xcode, "module"), do: "target"
  defp primary_field(:mix, "file"), do: "path"
  defp primary_field(:mix, "module"), do: "module"
  defp primary_field(_system, _kind), do: nil

  def history(:xcode, "module"), do: dgettext("dashboard_builds", "Cache history")
  def history(:mix, _kind), do: dgettext("dashboard_builds", "Compilation history")
  def history(_system, _kind), do: dgettext("dashboard_builds", "Execution history")

  def parent(:gradle, _kind), do: dgettext("dashboard_builds", "Project")
  def parent(:once, _kind), do: dgettext("dashboard_builds", "Run")
  def parent(_system, _kind), do: dgettext("dashboard_builds", "Command")

  def duration(:mix, "module"), do: dgettext("dashboard_builds", "File compilation duration")
  def duration(:mix, "file"), do: dgettext("dashboard_builds", "Compilation duration")
  def duration(_system, _kind), do: dgettext("dashboard_builds", "Duration")

  def environment("ci"), do: dgettext("dashboard_builds", "CI")
  def environment("local"), do: dgettext("dashboard_builds", "Local")
  def environment(_), do: dgettext("dashboard_builds", "Any")

  def status("success"), do: dgettext("dashboard_builds", "Succeeded")
  def status("failure"), do: dgettext("dashboard_builds", "Failed")
  def status("cancelled"), do: dgettext("dashboard_builds", "Cancelled")
  def status("hit_remote"), do: dgettext("dashboard_builds", "Remote hit")
  def status("hit_local"), do: dgettext("dashboard_builds", "Local hit")
  def status("hit"), do: dgettext("dashboard_builds", "Hit")
  def status("miss"), do: dgettext("dashboard_builds", "Miss")
  def status("write"), do: dgettext("dashboard_builds", "Write")
  def status("up_to_date"), do: dgettext("dashboard_builds", "Up-to-date")
  def status("skipped"), do: dgettext("dashboard_builds", "Skipped")
  def status("no_source"), do: dgettext("dashboard_builds", "No source")
  def status(_), do: dgettext("dashboard_builds", "Unknown")

  def status_color("success"), do: "success"
  def status_color("failure"), do: "destructive"
  def status_color(status) when status in ~w(hit_remote hit_local hit), do: "primary"
  def status_color("up_to_date"), do: "secondary"
  def status_color(_), do: "neutral"
end
