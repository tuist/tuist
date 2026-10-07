defmodule TuistWeb.BuildHealth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Tuist.BuildMetrics

  def assign_health(socket, mode \\ :cache)

  def assign_health(%{assigns: %{selected_project: %{build_system: system}}} = socket, mode)
      when system in [:gradle, :xcode, :bazel, :once] do
    project_id = socket.assigns.selected_project.id
    opts = health_opts(socket.assigns, system)
    key = {project_id, mode, period_key(socket.assigns), Keyword.drop(opts, [:start_datetime, :end_datetime])}

    if reusable?(socket.assigns, key) do
      socket
    else
      socket
      |> assign(:build_health_key, key)
      |> assign_async(:build_health, fn ->
        {:ok, %{build_health: query_health(project_id, opts, mode)}}
      end)
    end
  end

  def assign_health(socket, _mode), do: assign(socket, :build_health, nil)

  defp health_opts(assigns, :xcode) do
    assigns |> TuistWeb.XcodeBuildsLive.analytics_opts() |> Keyword.put(:build_system, "xcode")
  end

  defp health_opts(assigns, system) do
    {start_at, end_at} = assigns.analytics_period
    opts = [build_system: to_string(system), start_datetime: start_at, end_datetime: end_at]

    opts =
      case assigns.analytics_environment do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    source_opts(opts, system)
  end

  defp source_opts(opts, :bazel), do: Keyword.put(opts, :command, "build")
  defp source_opts(opts, :once), do: Keyword.put(opts, :kind, "build")
  defp source_opts(opts, _system), do: opts

  defp period_key(%{analytics_preset: "custom", analytics_period: period}), do: period
  defp period_key(assigns), do: assigns.analytics_preset

  defp reusable?(assigns, key) do
    result = assigns[:build_health]
    assigns[:build_health_key] == key && result && !result.failed && (result.ok? || result.loading)
  end

  defp query_health(project_id, opts, :cache) do
    BuildMetrics.query(project_id, Keyword.put(opts, :view, "series"))
  end
end
