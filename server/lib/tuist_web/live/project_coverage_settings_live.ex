defmodule TuistWeb.ProjectCoverageSettingsLive do
  @moduledoc """
  The project's code coverage settings: gates, patch coverage on partial
  runs, the Git history window with its provider fallback and tracked files,
  and the paths left out of every figure.
  """
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
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

  @modals %{
    "gates" => "coverage-gates-modal",
    "excluded_paths" => "coverage-excluded-paths-modal",
    "git_history" => "coverage-git-history-modal",
    "tracked_files" => "coverage-tracked-files-modal"
  }

  @impl true
  def handle_event("toggle_setting", %{"setting" => setting}, socket) when setting in @toggles do
    key = String.to_existing_atom(setting)
    current = Map.get(socket.assigns.selected_project, key) || false

    case update_project(socket, %{key => not current}) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("update_form", %{"form" => form} = params, socket) when is_map_key(@modals, form) do
    {:noreply, update(socket, :forms, &Map.put(&1, form, Map.drop(params, ["form", "_target"])))}
  end

  def handle_event("close_modal", %{"form" => form}, socket) when is_map_key(@modals, form) do
    {:noreply, socket |> assign_forms() |> push_event("close-modal", %{id: @modals[form]})}
  end

  def handle_event("save_form", %{"form" => form}, socket) when is_map_key(@modals, form) do
    case update_project(socket, attrs(form, socket.assigns.forms[form])) do
      {:ok, socket} -> {:noreply, push_event(socket, "close-modal", %{id: @modals[form]})}
      {:error, socket} -> {:noreply, socket}
    end
  end

  defp attrs("gates", form) do
    %{
      coverage_gate_min_patch_coverage: number_or_nil(form["min_patch_coverage"]),
      coverage_gate_max_total_drop: number_or_nil(form["max_total_drop"])
    }
  end

  defp attrs("excluded_paths", form), do: %{coverage_excluded_path_globs: globs_or_nil(form["globs"])}

  defp attrs("git_history", form) do
    %{
      git_history_window_days: integer_or_nil(form["window_days"]),
      git_history_window_commits: integer_or_nil(form["window_commits"])
    }
  end

  defp attrs("tracked_files", form), do: %{tracked_file_globs: globs_or_nil(form["globs"])}

  defp update_project(%{assigns: %{selected_project: project}} = socket, attrs) do
    case Projects.update_project(project, attrs) do
      {:ok, updated} ->
        # The published totals of past runs were computed with the previous
        # exclusions; the runs' pages and comparisons read the new ones at once.
        if ExcludedPaths.globs(updated) != ExcludedPaths.globs(project) do
          RecomputeTotalsWorker.enqueue(updated.id)
        end

        {:ok,
         socket
         |> assign(:selected_project, updated)
         |> assign_settings()
         |> put_flash(:info, dgettext("dashboard_projects", "Coverage settings saved."))}

      {:error, changeset} ->
        {:error,
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
    |> assign(:excluded_path_globs, ExcludedPaths.globs(project))
    |> assign(:git_history, GitHistory.settings(project))
    |> assign(:git_history_defaults, GitHistory.settings(nil))
    |> assign_forms()
  end

  # What each modal starts from: the project's own values, so an empty field
  # stays empty where the server default applies.
  defp assign_forms(%{assigns: %{selected_project: project}} = socket) do
    assign(socket, :forms, %{
      "gates" => %{
        "min_patch_coverage" => to_field(project.coverage_gate_min_patch_coverage),
        "max_total_drop" => to_field(project.coverage_gate_max_total_drop)
      },
      "excluded_paths" => %{"globs" => Enum.join(project.coverage_excluded_path_globs || [], "\n")},
      "git_history" => %{
        "window_days" => to_field(project.git_history_window_days),
        "window_commits" => to_field(project.git_history_window_commits)
      },
      "tracked_files" => %{"globs" => Enum.join(project.tracked_file_globs || [], "\n")}
    })
  end

  defp to_field(nil), do: ""
  defp to_field(value), do: to_string(value)

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
