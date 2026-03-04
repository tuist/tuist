defmodule TuistWeb.ProjectBundleSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Bundles
  alias Tuist.Repo

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: selected_project, current_user: current_user}} = socket) do
    if Authorization.authorize(:project_update, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Bundles")} · #{selected_project.name} · Tuist")
      |> assign_threshold_defaults(selected_project)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_create_threshold_modal", _params, socket) do
    socket =
      socket
      |> assign(create_form_name: "")
      |> assign(create_form_metric: :install_size)
      |> assign(create_form_deviation: 5.0)
      |> assign(create_form_baseline_branch: "main")
      |> assign(create_form_bundle_name: "")

    {:noreply, socket}
  end

  def handle_event("update_create_form_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, create_form_name: name)}
  end

  def handle_event("update_create_form_metric", %{"metric" => metric}, socket) do
    {:noreply, assign(socket, create_form_metric: String.to_existing_atom(metric))}
  end

  def handle_event("update_create_form_deviation", %{"value" => deviation_str}, socket) do
    case Float.parse(deviation_str) do
      {deviation, _} -> {:noreply, assign(socket, create_form_deviation: deviation)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("update_create_form_baseline_branch", %{"value" => branch}, socket) do
    {:noreply, assign(socket, create_form_baseline_branch: branch)}
  end

  def handle_event("update_create_form_bundle_name", %{"value" => bundle_name}, socket) do
    {:noreply, assign(socket, create_form_bundle_name: bundle_name)}
  end

  def handle_event("create_threshold", _params, %{assigns: assigns} = socket) do
    attrs = %{
      project_id: assigns.selected_project.id,
      name: assigns.create_form_name,
      metric: assigns.create_form_metric,
      deviation_percentage: assigns.create_form_deviation,
      baseline_branch: assigns.create_form_baseline_branch,
      bundle_name: if(assigns.create_form_bundle_name == "", do: nil, else: assigns.create_form_bundle_name)
    }

    {:ok, _threshold} = Bundles.create_bundle_threshold(attrs)

    socket =
      socket
      |> assign_threshold_defaults(assigns.selected_project)
      |> push_event("close-modal", %{id: "create-threshold-modal"})

    {:noreply, socket}
  end

  def handle_event("update_edit_form_name", %{"id" => id, "value" => name}, socket) do
    {:noreply, update_edit_form(socket, id, :name, name)}
  end

  def handle_event("update_edit_form_metric", %{"id" => id, "metric" => metric}, socket) do
    {:noreply, update_edit_form(socket, id, :metric, String.to_existing_atom(metric))}
  end

  def handle_event("update_edit_form_deviation", %{"id" => id, "value" => deviation_str}, socket) do
    case Float.parse(deviation_str) do
      {deviation, _} -> {:noreply, update_edit_form(socket, id, :deviation, deviation)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("update_edit_form_baseline_branch", %{"id" => id, "value" => branch}, socket) do
    {:noreply, update_edit_form(socket, id, :baseline_branch, branch)}
  end

  def handle_event("update_edit_form_bundle_name", %{"id" => id, "value" => bundle_name}, socket) do
    {:noreply, update_edit_form(socket, id, :bundle_name, bundle_name)}
  end

  def handle_event("update_threshold", %{"id" => id}, %{assigns: assigns} = socket) do
    {:ok, threshold} = Bundles.get_bundle_threshold(id)
    threshold = Repo.preload(threshold, :project)

    if Authorization.authorize(:project_update, assigns.current_user, threshold.project) == :ok do
      form = Map.get(assigns.edit_threshold_forms, id, %{})

      attrs = %{
        name: form[:name] || threshold.name,
        metric: form[:metric] || threshold.metric,
        deviation_percentage: form[:deviation] || threshold.deviation_percentage,
        baseline_branch: form[:baseline_branch] || threshold.baseline_branch,
        bundle_name:
          case Map.get(form, :bundle_name) do
            nil -> threshold.bundle_name
            "" -> nil
            val -> val
          end
      }

      {:ok, _threshold} = Bundles.update_bundle_threshold(threshold, attrs)

      socket =
        socket
        |> assign_threshold_defaults(assigns.selected_project)
        |> push_event("close-modal", %{id: "update-threshold-modal-#{id}"})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_threshold", %{"threshold_id" => threshold_id}, socket) do
    current_user = socket.assigns.current_user
    selected_project = socket.assigns.selected_project
    {:ok, threshold} = Bundles.get_bundle_threshold(threshold_id)
    threshold = Repo.preload(threshold, :project)

    if Authorization.authorize(:project_update, current_user, threshold.project) == :ok do
      {:ok, _} = Bundles.delete_bundle_threshold(threshold)
      {:noreply, assign_threshold_defaults(socket, selected_project)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_create_threshold_modal", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "create-threshold-modal"})
      |> assign_threshold_defaults(selected_project)

    {:noreply, socket}
  end

  def handle_event(
        "close_edit_threshold_modal",
        %{"id" => id},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    socket =
      socket
      |> push_event("close-modal", %{id: "update-threshold-modal-#{id}"})
      |> assign_threshold_defaults(selected_project)

    {:noreply, socket}
  end

  defp assign_threshold_defaults(socket, project) do
    thresholds = Bundles.get_project_bundle_thresholds(project)

    edit_forms =
      Map.new(thresholds, fn t ->
        {t.id,
         %{
           name: t.name,
           metric: t.metric,
           deviation: t.deviation_percentage,
           baseline_branch: t.baseline_branch,
           bundle_name: t.bundle_name || ""
         }}
      end)

    socket
    |> assign(thresholds: thresholds)
    |> assign(edit_threshold_forms: edit_forms)
    |> assign(create_form_name: "")
    |> assign(create_form_metric: :install_size)
    |> assign(create_form_deviation: 5.0)
    |> assign(create_form_baseline_branch: "main")
    |> assign(create_form_bundle_name: "")
  end

  defp update_edit_form(socket, id, key, value) do
    forms = socket.assigns.edit_threshold_forms
    form = Map.get(forms, id, %{})
    updated_form = Map.put(form, key, value)
    assign(socket, edit_threshold_forms: Map.put(forms, id, updated_form))
  end

  defp metric_label(:install_size), do: dgettext("dashboard_projects", "Install size")
  defp metric_label(:download_size), do: dgettext("dashboard_projects", "Download size")
end
