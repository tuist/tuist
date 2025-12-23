defmodule TuistWeb.ProjectSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Slack.Client, as: SlackClient
  alias Tuist.Slack.Reports, as: SlackReports

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

    selected_account = Tuist.Repo.preload(selected_account, [:slack_installation])
    slack_installation = selected_account.slack_installation

    rename_project_form = to_form(Project.update_changeset(selected_project, %{}))
    delete_project_form = to_form(%{"name" => ""})
    slack_form = to_form(Project.update_changeset(selected_project, %{}), as: :slack)

    socket =
      socket
      |> assign(rename_project_form: rename_project_form)
      |> assign(delete_project_form: delete_project_form)
      |> assign(slack_form: slack_form)
      |> assign(slack_installation: slack_installation)
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Settings")} · #{selected_project.name} · Tuist")
      |> assign_slack_channels(slack_installation)

    {:ok, socket}
  end

  defp assign_slack_channels(socket, nil) do
    assign(socket, slack_channels: %{ok?: true, result: [], loading: false})
  end

  defp assign_slack_channels(socket, slack_installation) do
    assign_async(socket, :slack_channels, fn ->
      case SlackClient.list_channels(slack_installation.access_token) do
        {:ok, channels, _cursor} -> {:ok, %{slack_channels: channels}}
        {:error, _} -> {:ok, %{slack_channels: []}}
      end
    end)
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "rename_project",
        %{"project" => %{"name" => name}} = _params,
        %{assigns: %{selected_project: selected_project, selected_account: selected_account}} = socket
      ) do
    case Projects.update_project(selected_project, %{name: name}) do
      {:ok, project} ->
        socket =
          socket
          |> push_event("close-modal", %{id: "rename-project-modal"})
          |> push_navigate(to: ~p"/#{selected_account.name}/#{project.name}/settings")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, rename_project_form: to_form(changeset))}
    end
  end

  def handle_event("close_rename_project_modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "rename-project-modal"})
      |> assign(rename_project_form: to_form(Project.update_changeset(socket.assigns.selected_project, %{})))

    {:noreply, socket}
  end

  def handle_event(
        "delete_project",
        %{"name" => name} = _params,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    socket =
      if name == project.name do
        Projects.delete_project(project)

        socket
        |> push_event("close-modal", %{id: "delete-project-modal"})
        |> push_navigate(to: ~p"/#{account.name}")
      else
        assign(socket, delete_project_form: to_form(%{"name" => ""}))
      end

    {:noreply, socket}
  end

  def handle_event("close_delete_project_modal", _params, socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "delete-project-modal"})
      |> assign(delete_project_form: to_form(%{"name" => ""}))

    {:noreply, socket}
  end

  def handle_event(
        "update_preview_access",
        %{"visibility" => visibility},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, updated_project} =
      Projects.update_project(selected_project, %{default_previews_visibility: String.to_existing_atom(visibility)})

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event(
        "update_slack_channel",
        %{"channel_id" => channel_id, "channel_name" => channel_name},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, updated_project} =
      Projects.update_project(selected_project, %{
        slack_channel_id: channel_id,
        slack_channel_name: channel_name
      })

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event(
        "update_slack_frequency",
        %{"frequency" => frequency},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, updated_project} =
      Projects.update_project(selected_project, %{
        slack_report_frequency: String.to_existing_atom(frequency)
      })

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event("toggle_slack_day", %{"day" => day_str}, %{assigns: %{selected_project: selected_project}} = socket) do
    day = String.to_integer(day_str)
    current_days = selected_project.slack_report_days_of_week || []

    new_days =
      if day in current_days do
        Enum.reject(current_days, &(&1 == day))
      else
        Enum.sort([day | current_days])
      end

    {:ok, updated_project} =
      Projects.update_project(selected_project, %{slack_report_days_of_week: new_days})

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event(
        "update_slack_schedule_time",
        %{"hour" => hour_str},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    hour = String.to_integer(hour_str)
    schedule_time = DateTime.new!(~D[2000-01-01], Time.new!(hour, 0, 0), "Etc/UTC")

    {:ok, updated_project} =
      Projects.update_project(selected_project, %{slack_report_schedule_time: schedule_time})

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event("toggle_slack_reports", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    new_enabled = not (selected_project.slack_report_enabled || false)

    {:ok, updated_project} =
      Projects.update_project(selected_project, %{slack_report_enabled: new_enabled})

    socket = assign(socket, selected_project: updated_project)
    {:noreply, socket}
  end

  def handle_event(
        "send_test_slack_report",
        _params,
        %{assigns: %{selected_project: selected_project, slack_installation: slack_installation}} = socket
      )
      when not is_nil(slack_installation) do
    frequency = selected_project.slack_report_frequency || :daily
    report = SlackReports.generate_report(selected_project, frequency)
    blocks = SlackReports.format_report_blocks(report)

    case SlackClient.post_message(slack_installation.access_token, selected_project.slack_channel_id, blocks) do
      :ok ->
        socket = put_flash(socket, :info, dgettext("dashboard_projects", "Test report sent successfully"))
        {:noreply, socket}

      {:error, reason} ->
        require Logger
        Logger.error("Failed to send Slack test report: #{inspect(reason)}")
        socket = put_flash(socket, :error, dgettext("dashboard_projects", "Failed to send test report"))
        {:noreply, socket}
    end
  rescue
    e ->
      require Logger
      Logger.error("Exception sending Slack test report: #{inspect(e)}")
      socket = put_flash(socket, :error, dgettext("dashboard_projects", "Failed to send test report"))
      {:noreply, socket}
  end

  def handle_event("send_test_slack_report", _params, socket) do
    socket = put_flash(socket, :error, dgettext("dashboard_projects", "Slack is not configured"))
    {:noreply, socket}
  end

  defp get_slack_channels(%{slack_channels: slack_channels_async}) do
    if slack_channels_async.ok? do
      slack_channels_async.result
    else
      []
    end
  end

  defp day_name(1), do: dgettext("dashboard_projects", "Mon")
  defp day_name(2), do: dgettext("dashboard_projects", "Tue")
  defp day_name(3), do: dgettext("dashboard_projects", "Wed")
  defp day_name(4), do: dgettext("dashboard_projects", "Thu")
  defp day_name(5), do: dgettext("dashboard_projects", "Fri")
  defp day_name(6), do: dgettext("dashboard_projects", "Sat")
  defp day_name(7), do: dgettext("dashboard_projects", "Sun")
end
