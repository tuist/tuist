defmodule TuistWeb.ProjectCoverageSettingsLive do
  @moduledoc """
  The project's code coverage settings: gates, patch coverage on partial
  runs, the paths left out of every figure, the Git history window and its
  provider fallback, the tracked files, and the retention in effect.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.GitHistory
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage.ExcludedPaths
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.Workers.RecomputeTotalsWorker
  alias TuistWeb.Errors.NotFoundError

  @toggles ~w(coverage_gates_enabled coverage_patch_partial_runs git_history_provider_fallback)

  @impl true
  def mount(
        _params,
        _uri,
        %{assigns: %{selected_project: project, selected_account: account, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:project_update, current_user, project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    if !(Project.xcode_project?(project) and FeatureFlags.xcode_coverage_enabled?(account)) do
      raise NotFoundError, dgettext("dashboard_projects", "Code coverage is not enabled for this project.")
    end

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard_projects", "Code coverage")} · #{project.name} · Tuist")
     |> assign_settings()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save_settings", params, socket) do
    update_settings(socket, %{
      coverage_gate_min_patch_coverage: number_or_nil(params["min_patch_coverage"]),
      coverage_gate_max_total_drop: number_or_nil(params["max_total_drop"]),
      coverage_excluded_path_globs: globs_or_nil(params["excluded_path_globs"]),
      git_history_window_days: integer_or_nil(params["git_history_window_days"]),
      git_history_window_commits: integer_or_nil(params["git_history_window_commits"]),
      tracked_file_globs: globs_or_nil(params["tracked_file_globs"])
    })
  end

  def handle_event("toggle_setting", %{"setting" => setting}, socket) when setting in @toggles do
    key = String.to_existing_atom(setting)
    current = Map.get(socket.assigns.selected_project, key) || false
    update_settings(socket, %{key => not current})
  end

  defp update_settings(%{assigns: %{selected_project: project}} = socket, attrs) do
    case Projects.update_project(project, attrs) do
      {:ok, updated} ->
        # The published totals of past runs were computed with the previous
        # exclusions; the runs' pages and comparisons read the new ones at once.
        if ExcludedPaths.globs(updated) != ExcludedPaths.globs(project) do
          RecomputeTotalsWorker.enqueue(updated.id)
        end

        {:noreply,
         socket
         |> assign(:selected_project, updated)
         |> assign_settings()
         |> put_flash(:info, dgettext("dashboard_projects", "Coverage settings saved."))}

      {:error, changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_projects", "Could not save the coverage settings: %{errors}", errors: errors(changeset))
         )}
    end
  end

  defp assign_settings(%{assigns: %{selected_project: project}} = socket) do
    socket
    |> assign(:gates, Gates.settings(project))
    |> assign(:git_history, GitHistory.settings(project))
    |> assign(:git_history_defaults, GitHistory.settings(nil))
    |> assign(:retention, Environment.coverage_retention_days())
  end

  defp number_or_nil(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp number_or_nil(_value), do: nil

  defp integer_or_nil(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer_or_nil(_value), do: nil

  # One glob per line; an empty field clears the setting.
  defp globs_or_nil(value) when is_binary(value) do
    case value |> String.split(~r/\R/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [] -> nil
      globs -> globs
    end
  end

  defp globs_or_nil(_value), do: nil

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
