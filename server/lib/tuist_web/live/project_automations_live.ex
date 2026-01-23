defmodule TuistWeb.ProjectAutomationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Slack
  alias TuistWeb.SlackOAuthController

  @impl true
  def mount(
        _params,
        _uri,
        %{assigns: %{selected_project: selected_project, selected_account: selected_account, current_user: current_user}} =
          socket
      ) do
    if Authorization.authorize(:project_update, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    selected_account = Repo.preload(selected_account, [:slack_installation])
    slack_installation = selected_account.slack_installation

    if connected?(socket) do
      Tuist.PubSub.subscribe(Slack.slack_installation_topic(selected_account.id))
    end

    socket =
      socket
      |> assign(slack_installation: slack_installation)
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Automations")} · #{selected_project.name} · Tuist")
      |> assign(
        :flaky_alert_channel_selection_url,
        SlackOAuthController.flaky_alert_channel_selection_url(selected_project.id, selected_account.id)
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:slack_installation_changed, %{status: status}}, socket) do
    selected_account = socket.assigns.selected_account

    slack_installation =
      case status do
        :connected ->
          selected_account = Repo.preload(selected_account, [:slack_installation], force: true)
          selected_account.slack_installation

        :disconnected ->
          nil
      end

    {:noreply, assign(socket, slack_installation: slack_installation)}
  end

  @impl true
  def handle_event("toggle_auto_quarantine", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    new_value = not selected_project.auto_quarantine_flaky_tests

    {:ok, updated_project} =
      Projects.update_project(selected_project, %{auto_quarantine_flaky_tests: new_value})

    {:noreply, assign(socket, selected_project: updated_project)}
  end

  def handle_event(
        "toggle_flaky_alerts",
        _params,
        %{assigns: %{selected_project: selected_project, slack_installation: slack_installation}} = socket
      ) do
    # Don't allow toggling if no slack installation or no channel configured
    if is_nil(slack_installation) || is_nil(selected_project.flaky_test_alerts_slack_channel_id) do
      {:noreply, socket}
    else
      new_value = not selected_project.flaky_test_alerts_enabled

      {:ok, updated_project} =
        Projects.update_project(selected_project, %{flaky_test_alerts_enabled: new_value})

      {:noreply, assign(socket, selected_project: updated_project)}
    end
  end

  def handle_event(
        "flaky_alert_channel_selected",
        %{"channel_id" => channel_id, "channel_name" => channel_name},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, updated_project} =
      Projects.update_project(selected_project, %{
        flaky_test_alerts_slack_channel_id: channel_id,
        flaky_test_alerts_slack_channel_name: channel_name,
        flaky_test_alerts_enabled: true
      })

    {:noreply, assign(socket, selected_project: updated_project)}
  end

  def handle_event("flaky_alert_channel_selected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_auto_mark_flaky", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    new_value = not selected_project.auto_mark_flaky_tests

    {:ok, updated_project} =
      Projects.update_project(selected_project, %{auto_mark_flaky_tests: new_value})

    {:noreply, assign(socket, selected_project: updated_project)}
  end

  def handle_event(
        "update_auto_mark_flaky_threshold",
        %{"value" => threshold_str},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    case Integer.parse(threshold_str) do
      {threshold, _} when threshold > 0 ->
        {:ok, updated_project} =
          Projects.update_project(selected_project, %{auto_mark_flaky_threshold: threshold})

        {:noreply, assign(socket, selected_project: updated_project)}

      _ ->
        {:noreply, socket}
    end
  end
end
