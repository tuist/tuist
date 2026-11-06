defmodule TuistWeb.ProjectBundleSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Bundles
  alias Tuist.Bundles.BundleThreshold
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistWeb.Helpers.OpenGraph

  @approval_policies [:everyone, :selected]

  @impl true
  def mount(_params, _uri, %{assigns: %{selected_project: selected_project, current_user: current_user}} = socket) do
    if Authorization.authorize(:project_update, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    project = Repo.preload(selected_project, vcs_connection: :github_app_installation)
    has_vcs_connection = Projects.has_vcs_connection?(project)

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Bundles")} · #{selected_project.name} · Tuist")
      |> assign(
        OpenGraph.project_image_assigns(selected_project,
          title: dgettext("dashboard_projects", "Bundles"),
          subtitle: dgettext("dashboard_projects", "Project settings")
        )
      )
      |> assign(:has_vcs_connection, has_vcs_connection)
      |> assign(:approval_policies, @approval_policies)
      |> assign_threshold_defaults(selected_project)
      |> assign_approval_defaults(selected_project)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_create_threshold_modal", _params, socket) do
    socket =
      socket
      |> assign(create_form_name: "", create_form_error: nil)
      |> assign(create_form_metric: :install_size)
      |> assign(create_form_deviation: "5.0", create_form_unit: "percentage")
      |> assign(create_form_baseline_branch: "main")
      |> assign(create_form_bundle_name: "")

    {:noreply, socket}
  end

  def handle_event("update_create_form_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, create_form_name: name, create_form_error: nil)}
  end

  def handle_event("update_create_form_metric", %{"metric" => metric}, socket) do
    {:noreply, assign(socket, create_form_metric: String.to_existing_atom(metric), create_form_error: nil)}
  end

  def handle_event("update_create_form_unit", %{"unit" => unit}, socket) when unit in ["percentage", "megabytes"] do
    socket =
      if unit == socket.assigns.create_form_unit do
        socket
      else
        assign(socket, create_form_unit: unit, create_form_deviation: "", create_form_error: nil)
      end

    {:noreply, socket}
  end

  def handle_event("update_create_form_deviation", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_form_deviation: if(is_binary(value), do: value, else: ""), create_form_error: nil)}
  end

  def handle_event("update_create_form_baseline_branch", %{"value" => branch}, socket) do
    {:noreply, assign(socket, create_form_baseline_branch: branch, create_form_error: nil)}
  end

  def handle_event("update_create_form_bundle_name", %{"value" => bundle_name}, socket) do
    {:noreply, assign(socket, create_form_bundle_name: bundle_name, create_form_error: nil)}
  end

  def handle_event("create_threshold", _params, %{assigns: assigns} = socket) do
    attrs = %{
      project_id: assigns.selected_project.id,
      name: assigns.create_form_name,
      metric: assigns.create_form_metric,
      baseline_branch: assigns.create_form_baseline_branch,
      bundle_name: if(assigns.create_form_bundle_name == "", do: nil, else: assigns.create_form_bundle_name)
    }

    with {:ok, limit} <- limit_attrs(assigns.create_form_unit, assigns.create_form_deviation),
         {:ok, _threshold} <- Bundles.create_bundle_threshold(Map.merge(attrs, limit)) do
      socket =
        socket
        |> assign_threshold_defaults(assigns.selected_project)
        |> push_event("close-modal", %{id: "create-threshold-modal"})

      {:noreply, socket}
    else
      error -> {:noreply, assign(socket, create_form_error: threshold_error_message(error))}
    end
  end

  def handle_event("update_edit_form_name", %{"id" => id, "value" => name}, socket) do
    {:noreply, update_edit_form(socket, id, :name, name)}
  end

  def handle_event("update_edit_form_metric", %{"id" => id, "metric" => metric}, socket) do
    {:noreply, update_edit_form(socket, id, :metric, String.to_existing_atom(metric))}
  end

  def handle_event("update_edit_form_unit", %{"id" => id, "unit" => unit}, socket)
      when unit in ["percentage", "megabytes"] do
    form = Map.get(socket.assigns.edit_threshold_forms, id, %{})

    socket =
      if form[:unit] == unit do
        socket
      else
        socket |> update_edit_form(id, :unit, unit) |> update_edit_form(id, :deviation, "")
      end

    {:noreply, socket}
  end

  def handle_event("update_edit_form_deviation", %{"id" => id, "value" => value}, socket) do
    {:noreply, update_edit_form(socket, id, :deviation, if(is_binary(value), do: value, else: ""))}
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
        name: Map.get(form, :name, threshold.name),
        metric: Map.get(form, :metric, threshold.metric),
        baseline_branch: Map.get(form, :baseline_branch, threshold.baseline_branch),
        bundle_name:
          case Map.get(form, :bundle_name) do
            nil -> threshold.bundle_name
            "" -> nil
            val -> val
          end
      }

      with {:ok, limit} <-
             limit_attrs(
               Map.get(form, :unit, threshold_unit(threshold)),
               Map.get(form, :deviation, threshold_value(threshold))
             ),
           {:ok, _threshold} <- Bundles.update_bundle_threshold(threshold, Map.merge(attrs, limit)) do
        socket =
          socket
          |> assign_threshold_defaults(assigns.selected_project)
          |> push_event("close-modal", %{id: "update-threshold-modal-#{id}"})

        {:noreply, socket}
      else
        error -> {:noreply, update_edit_form(socket, id, :error, threshold_error_message(error))}
      end
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

  def handle_event("select_approval_policy", %{"policy" => policy}, %{assigns: assigns} = socket) do
    policy = String.to_existing_atom(policy)

    if policy in @approval_policies do
      {:ok, project} = Projects.update_project(assigns.selected_project, %{bundle_size_approval_policy: policy})

      {:noreply,
       socket
       |> assign(:selected_project, project)
       |> assign_approval_defaults(project)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_add_approver_modal", _params, socket) do
    {:noreply, assign(socket, approver_handle: "", approver_error: nil)}
  end

  def handle_event("close_add_approver_modal", _params, socket) do
    socket =
      socket
      |> assign(approver_handle: "", approver_error: nil)
      |> push_event("close-modal", %{id: "add-approver-modal"})

    {:noreply, socket}
  end

  def handle_event("update_approver_handle", %{"value" => handle}, socket) do
    {:noreply, assign(socket, approver_handle: handle, approver_error: nil)}
  end

  def handle_event("add_approver", _params, %{assigns: assigns} = socket) do
    case Bundles.add_bundle_size_approver(assigns.selected_project, assigns.approver_handle) do
      {:ok, _approver} ->
        socket =
          socket
          |> assign_approval_defaults(assigns.selected_project)
          |> push_event("close-modal", %{id: "add-approver-modal"})

        {:noreply, socket}

      # Keeps the modal open so the message lands next to the field it is about.
      {:error, reason} ->
        {:noreply, assign(socket, approver_error: approver_error_message(reason))}
    end
  end

  def handle_event("delete_approver", %{"approver_id" => approver_id}, %{assigns: assigns} = socket) do
    with {:ok, approver} <- Bundles.get_bundle_size_approver(assigns.selected_project, approver_id),
         {:ok, _} <- Bundles.delete_bundle_size_approver(approver) do
      {:noreply, assign_approval_defaults(socket, assigns.selected_project)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp assign_approval_defaults(socket, project) do
    socket
    |> assign(approvers: Bundles.list_bundle_size_approvers(project))
    |> assign(approver_handle: "")
    |> assign(approver_error: nil)
  end

  defp approver_error_message(:no_vcs_connection) do
    dgettext(
      "dashboard_projects",
      "Connect the Tuist GitHub App to this project first, so the username can be checked against GitHub."
    )
  end

  defp approver_error_message(:github_user_not_found) do
    dgettext("dashboard_projects", "No GitHub user with that username.")
  end

  defp approver_error_message(:invalid_github_handle) do
    dgettext("dashboard_projects", "That is not a valid GitHub username.")
  end

  defp approver_error_message(:github_unavailable) do
    dgettext("dashboard_projects", "Couldn't reach GitHub to check that username. Try again in a moment.")
  end

  defp approver_error_message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :github_handle) do
      dgettext("dashboard_projects", "Enter a valid GitHub username that isn't already on the list.")
    else
      dgettext("dashboard_projects", "The approver could not be added.")
    end
  end

  defp approver_error_message(_reason) do
    dgettext("dashboard_projects", "The approver could not be added.")
  end

  defp approval_policy_label(:everyone), do: dgettext("dashboard_projects", "Anyone")
  defp approval_policy_label(:selected), do: dgettext("dashboard_projects", "Selected GitHub users")

  defp approval_policy_description(:everyone) do
    dgettext("dashboard_projects", "Anyone with write access to the repository.")
  end

  defp approval_policy_description(:selected) do
    dgettext("dashboard_projects", "Only the GitHub usernames you add below.")
  end

  defp assign_threshold_defaults(socket, project) do
    thresholds = Bundles.get_project_bundle_thresholds(project)

    edit_forms =
      Map.new(thresholds, fn t ->
        {t.id,
         %{
           name: t.name,
           metric: t.metric,
           deviation: threshold_value(t),
           unit: threshold_unit(t),
           baseline_branch: t.baseline_branch,
           bundle_name: t.bundle_name || ""
         }}
      end)

    socket
    |> assign(thresholds: thresholds)
    |> assign(edit_threshold_forms: edit_forms)
    |> assign(create_form_name: "", create_form_error: nil)
    |> assign(create_form_metric: :install_size)
    |> assign(create_form_deviation: "5.0", create_form_unit: "percentage")
    |> assign(create_form_baseline_branch: "main")
    |> assign(create_form_bundle_name: "")
  end

  defp update_edit_form(socket, id, key, value) do
    forms = socket.assigns.edit_threshold_forms
    form = Map.get(forms, id, %{})
    updated_form = form |> Map.delete(:error) |> Map.put(key, value)
    assign(socket, edit_threshold_forms: Map.put(forms, id, updated_form))
  end

  defp metric_label(:install_size), do: dgettext("dashboard_projects", "Install size")
  defp metric_label(:download_size), do: dgettext("dashboard_projects", "Download size")

  defp threshold_error_message(:error), do: dgettext("dashboard_projects", "Enter a valid size threshold.")

  defp threshold_error_message({:error, _changeset}) do
    dgettext("dashboard_projects", "The size threshold could not be saved. Check the name and baseline branch.")
  end

  defp threshold_unit(%{deviation_bytes: bytes}) when is_integer(bytes), do: "megabytes"
  defp threshold_unit(_threshold), do: "percentage"

  defp threshold_value(%{deviation_bytes: bytes}) when is_integer(bytes), do: BundleThreshold.megabytes(bytes)
  defp threshold_value(threshold), do: to_string(threshold.deviation_percentage)

  defp unit_label("percentage"), do: dgettext("dashboard_projects", "Percentage (%)")
  defp unit_label("megabytes"), do: dgettext("dashboard_projects", "Absolute size (MB)")

  defp deviation_label("percentage"), do: dgettext("dashboard_projects", "Deviation %")
  defp deviation_label("megabytes"), do: dgettext("dashboard_projects", "Deviation (MB)")

  defp deviation_hint("megabytes"), do: dgettext("dashboard_projects", "1 MB = 1,000,000 bytes")
  defp deviation_hint(_unit), do: nil

  defp valid_limit?(unit, value), do: match?({:ok, _}, limit_attrs(unit, value))

  defp limit_attrs("percentage", value) do
    case Float.parse(value) do
      {percentage, ""} when percentage > 0 -> {:ok, %{deviation_percentage: percentage, deviation_bytes: nil}}
      _ -> :error
    end
  end

  defp limit_attrs("megabytes", value) when byte_size(value) <= 100 do
    with {%Decimal{coef: coef} = megabytes, ""} when is_integer(coef) <- Decimal.parse(value),
         %Decimal{sign: 1, exp: exponent} = megabytes <- Decimal.normalize(megabytes),
         true <- exponent >= -6 && exponent <= 13,
         bytes = Decimal.mult(megabytes, 1_000_000),
         true <- Decimal.compare(bytes, 0) == :gt,
         true <- Decimal.compare(bytes, 9_223_372_036_854_775_807) != :gt,
         true <- Decimal.equal?(bytes, Decimal.round(bytes, 0)) do
      {:ok, %{deviation_percentage: nil, deviation_bytes: Decimal.to_integer(bytes)}}
    else
      _ -> :error
    end
  end

  defp limit_attrs(_unit, _value), do: :error

  defp threshold_description(metric, deviation, unit, baseline_branch, bundle_name) do
    deviation = escape_description(deviation <> if(unit == "megabytes", do: " MB", else: "%"))
    baseline_branch = escape_description(baseline_branch)
    bundle_name = if bundle_name, do: escape_description(bundle_name)
    size_label = escape_description(metric_label(metric))

    text =
      if bundle_name == "" or is_nil(bundle_name) do
        dgettext(
          "dashboard_projects",
          "Block PRs when the <strong>%{size_label}</strong> increases by more than <strong>%{deviation}</strong> compared to the latest bundle on <strong>%{baseline_branch}</strong>.",
          size_label: size_label,
          deviation: deviation,
          baseline_branch: baseline_branch
        )
      else
        dgettext(
          "dashboard_projects",
          "Block PRs when the <strong>%{size_label}</strong> of <strong>%{bundle_name}</strong> increases by more than <strong>%{deviation}</strong> compared to the latest bundle on <strong>%{baseline_branch}</strong>.",
          size_label: size_label,
          bundle_name: bundle_name,
          deviation: deviation,
          baseline_branch: baseline_branch
        )
      end

    raw(text)
  end

  defp escape_description(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
