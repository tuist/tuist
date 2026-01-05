defmodule TuistWeb.ProjectSettingsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias Tuist.Slack.Reports

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
      |> assign_schedule_form_defaults(selected_project)
      |> assign_alert_defaults(selected_project)

    {:ok, socket}
  end

  defp assign_alert_defaults(socket, project) do
    socket
    |> assign(alerts: Slack.list_project_alerts(project.id))
    |> assign(editing_alert: nil)
    |> assign(alert_form_category: :build_run_duration)
    |> assign(alert_form_metric: :p99)
    |> assign(alert_form_threshold: 20.0)
    |> assign(alert_form_sample_size: 100)
    |> assign(alert_form_channel_id: nil)
    |> assign(alert_form_channel_name: nil)
  end

  defp assign_schedule_form_defaults(socket, project) do
    user_timezone = socket.assigns[:user_timezone] || "Etc/UTC"

    frequency = project.slack_report_frequency

    days = if project.slack_report_days_of_week == [], do: [1, 2, 3, 4, 5], else: project.slack_report_days_of_week

    # Get local hour from UTC time
    hour = get_local_hour(project.slack_report_schedule_time, user_timezone) || 9

    socket
    |> assign(schedule_form_channel_id: project.slack_channel_id)
    |> assign(schedule_form_channel_name: project.slack_channel_name)
    |> assign(schedule_form_frequency: frequency)
    |> assign(schedule_form_days: days)
    |> assign(schedule_form_hour: hour)
  end

  defp assign_slack_channels(socket, nil) do
    socket
    |> assign(slack_channels: %{ok?: true, result: [], loading: false})
    |> assign(channel_search_query: "")
  end

  defp assign_slack_channels(socket, slack_installation) do
    socket
    |> assign_async(:slack_channels, fn ->
      case Slack.get_installation_channels(slack_installation) do
        {:ok, channels} -> {:ok, %{slack_channels: channels}}
        {:error, _} -> {:ok, %{slack_channels: []}}
      end
    end)
    |> assign(channel_search_query: "")
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
        "send_test_slack_report",
        _params,
        %{assigns: %{selected_project: selected_project, slack_installation: slack_installation}} = socket
      ) do
    blocks = Reports.report(selected_project)

    :ok = SlackClient.post_message(slack_installation.access_token, selected_project.slack_channel_id, blocks)
    {:noreply, socket}
  end

  def handle_event("update_schedule_form_frequency", %{"frequency" => frequency}, socket) do
    new_frequency = String.to_existing_atom(frequency)
    current_frequency = socket.assigns.schedule_form_frequency

    socket =
      if current_frequency == :never && new_frequency == :daily do
        assign(socket, schedule_form_days: [1, 2, 3, 4, 5])
      else
        socket
      end

    {:noreply, assign(socket, schedule_form_frequency: new_frequency)}
  end

  def handle_event("toggle_schedule_form_day", %{"day" => day_str}, socket) do
    day = String.to_integer(day_str)
    current_days = socket.assigns.schedule_form_days

    new_days =
      if day in current_days do
        remaining = Enum.reject(current_days, &(&1 == day))
        if remaining == [], do: current_days, else: remaining
      else
        Enum.sort([day | current_days])
      end

    {:noreply, assign(socket, schedule_form_days: new_days)}
  end

  def handle_event("update_schedule_form_hour", %{"hour" => hour_str}, socket) do
    {:noreply, assign(socket, schedule_form_hour: String.to_integer(hour_str))}
  end

  def handle_event("update_schedule_form_channel", %{"channel_id" => channel_id, "channel_name" => channel_name}, socket) do
    socket =
      socket
      |> assign(schedule_form_channel_id: channel_id)
      |> assign(schedule_form_channel_name: channel_name)
      |> push_event("close-dropdown", %{id: "slack-channel-dropdown"})

    {:noreply, socket}
  end

  def handle_event("update_channel_search", %{"value" => query}, socket) do
    {:noreply, assign(socket, channel_search_query: query)}
  end

  def handle_event("close_slack_schedule_modal", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "slack-schedule-modal"})
      |> assign_schedule_form_defaults(selected_project)
      |> assign(channel_search_query: "")

    {:noreply, socket}
  end

  def handle_event(
        "save_slack_schedule",
        _params,
        %{assigns: %{selected_project: selected_project, user_timezone: user_timezone} = assigns} = socket
      ) do
    frequency = assigns.schedule_form_frequency
    days = assigns.schedule_form_days
    hour = assigns.schedule_form_hour
    channel_id = assigns.schedule_form_channel_id
    channel_name = assigns.schedule_form_channel_name
    timezone = user_timezone || "Etc/UTC"

    updates =
      if frequency == :never do
        %{
          slack_report_frequency: :never,
          slack_channel_id: channel_id,
          slack_channel_name: channel_name
        }
      else
        utc_time = local_hour_to_utc(hour, timezone)

        %{
          slack_report_frequency: frequency,
          slack_report_days_of_week: days,
          slack_report_schedule_time: utc_time,
          slack_report_timezone: timezone,
          slack_channel_id: channel_id,
          slack_channel_name: channel_name
        }
      end

    {:ok, updated_project} = Projects.update_project(selected_project, updates)

    socket =
      socket
      |> assign(selected_project: updated_project)
      |> assign(channel_search_query: "")
      |> push_event("close-modal", %{id: "slack-schedule-modal"})

    {:noreply, socket}
  end

  # Alert event handlers

  def handle_event("open_create_alert_modal", _params, socket) do
    socket =
      socket
      |> assign(editing_alert: nil)
      |> assign(alert_form_category: :build_run_duration)
      |> assign(alert_form_metric: :p99)
      |> assign(alert_form_threshold: 20.0)
      |> assign(alert_form_sample_size: 100)
      |> assign(alert_form_channel_id: nil)
      |> assign(alert_form_channel_name: nil)

    {:noreply, socket}
  end

  def handle_event("open_edit_alert_modal", %{"alert_id" => alert_id}, socket) do
    case Slack.get_alert(alert_id) do
      {:ok, alert} ->
        socket =
          socket
          |> assign(editing_alert: alert)
          |> assign(alert_form_category: alert.category)
          |> assign(alert_form_metric: alert.metric)
          |> assign(alert_form_threshold: alert.threshold_percentage)
          |> assign(alert_form_sample_size: alert.sample_size)
          |> assign(alert_form_channel_id: alert.slack_channel_id)
          |> assign(alert_form_channel_name: alert.slack_channel_name)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("update_alert_form_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, alert_form_category: String.to_existing_atom(category))}
  end

  def handle_event("update_alert_form_metric", %{"metric" => metric}, socket) do
    {:noreply, assign(socket, alert_form_metric: String.to_existing_atom(metric))}
  end

  def handle_event("update_alert_form_threshold", %{"value" => threshold_str}, socket) do
    case Float.parse(threshold_str) do
      {threshold, _} -> {:noreply, assign(socket, alert_form_threshold: threshold)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("update_alert_form_sample_size", %{"value" => size_str}, socket) do
    case Integer.parse(size_str) do
      {size, _} -> {:noreply, assign(socket, alert_form_sample_size: size)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("update_alert_form_channel", %{"channel_id" => channel_id, "channel_name" => channel_name}, socket) do
    socket =
      socket
      |> assign(alert_form_channel_id: channel_id)
      |> assign(alert_form_channel_name: channel_name)
      |> push_event("close-dropdown", %{id: "alert-channel-dropdown"})

    {:noreply, socket}
  end

  def handle_event("save_alert", _params, %{assigns: assigns} = socket) do
    attrs = %{
      project_id: assigns.selected_project.id,
      category: assigns.alert_form_category,
      metric: assigns.alert_form_metric,
      threshold_percentage: assigns.alert_form_threshold,
      sample_size: assigns.alert_form_sample_size,
      slack_channel_id: assigns.alert_form_channel_id,
      slack_channel_name: assigns.alert_form_channel_name
    }

    result =
      case assigns.editing_alert do
        nil -> Slack.create_alert(attrs)
        alert -> Slack.update_alert(alert, attrs)
      end

    case result do
      {:ok, _alert} ->
        socket =
          socket
          |> assign(alerts: Slack.list_project_alerts(assigns.selected_project.id))
          |> assign(editing_alert: nil)
          |> push_event("close-modal", %{id: "alert-modal"})

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_alert_enabled", %{"alert_id" => alert_id}, socket) do
    case Slack.get_alert(alert_id) do
      {:ok, alert} ->
        {:ok, _} = Slack.update_alert(alert, %{enabled: !alert.enabled})
        {:noreply, assign(socket, alerts: Slack.list_project_alerts(socket.assigns.selected_project.id))}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_alert", %{"alert_id" => alert_id}, socket) do
    case Slack.get_alert(alert_id) do
      {:ok, alert} ->
        {:ok, _} = Slack.delete_alert(alert)
        {:noreply, assign(socket, alerts: Slack.list_project_alerts(socket.assigns.selected_project.id))}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("close_alert_modal", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "alert-modal"})
      |> assign_alert_defaults(selected_project)

    {:noreply, socket}
  end

  defp get_slack_channels(%{slack_channels: slack_channels_async, channel_search_query: query}) do
    channels =
      if slack_channels_async.ok? do
        slack_channels_async.result
      else
        []
      end

    channels
    |> filter_channels_by_query(query)
    |> Enum.sort_by(& &1.name)
  end

  defp filter_channels_by_query(channels, nil), do: channels
  defp filter_channels_by_query(channels, ""), do: channels

  defp filter_channels_by_query(channels, query) do
    query_downcase = String.downcase(query)
    Enum.filter(channels, fn channel -> String.contains?(String.downcase(channel.name), query_downcase) end)
  end

  defp format_hour(hour) do
    hour
    |> Time.new!(0, 0)
    |> Timex.format!("{h12} {AM}")
  end

  defp format_days_range(days) do
    days
    |> Enum.sort()
    |> Enum.chunk_while(
      [],
      fn day, acc ->
        case acc do
          [] -> {:cont, [day]}
          [prev | _] when day == prev + 1 -> {:cont, [day | acc]}
          _ -> {:cont, Enum.reverse(acc), [day]}
        end
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
    |> Enum.map_join(", ", &format_day_group/1)
  end

  defp format_day_group([single]), do: Timex.day_shortname(single)
  defp format_day_group([first, last]), do: "#{Timex.day_shortname(first)}, #{Timex.day_shortname(last)}"
  defp format_day_group([first | rest]), do: "#{Timex.day_shortname(first)}-#{Timex.day_shortname(List.last(rest))}"

  defp format_selected_days([]), do: dgettext("dashboard_projects", "Select days")

  defp format_selected_days(days) when length(days) == 7, do: dgettext("dashboard_projects", "All days")

  defp format_selected_days(days) do
    days
    |> Enum.sort()
    |> Enum.map_join(", ", &Timex.day_shortname/1)
  end

  defp format_slack_reports_tag(%{selected_project: project, user_timezone: user_timezone}) do
    channel_str = "##{project.slack_channel_name}"
    days = project.slack_report_days_of_week
    hour = get_local_hour(project.slack_report_schedule_time, user_timezone)
    time_str = if hour, do: format_hour(hour), else: ""
    day_str = format_days_range(days)

    "#{channel_str} • #{day_str} • #{time_str}"
  end

  defp local_hour_to_utc(local_hour, timezone) do
    today = Date.utc_today()
    local_datetime = DateTime.new!(today, Time.new!(local_hour, 0, 0), timezone)
    DateTime.shift_zone!(local_datetime, "Etc/UTC")
  end

  defp get_local_hour(nil, _timezone), do: nil

  defp get_local_hour(utc_datetime, timezone) when is_binary(timezone) do
    local_datetime = Timex.Timezone.convert(utc_datetime, timezone)
    local_datetime.hour
  end

  defp get_local_hour(utc_datetime, _timezone), do: utc_datetime.hour

  # Alert helper functions

  defp category_label(:build_run_duration), do: dgettext("dashboard_projects", "Build duration")
  defp category_label(:test_run_duration), do: dgettext("dashboard_projects", "Test duration")
  defp category_label(:cache_hit_rate), do: dgettext("dashboard_projects", "Cache hit rate")

  defp metric_label(:p50), do: "P50"
  defp metric_label(:p90), do: "P90"
  defp metric_label(:p99), do: "P99"
  defp metric_label(:average), do: dgettext("dashboard_projects", "Average")
  defp metric_label(nil), do: ""

  defp format_alert_summary(alert) do
    category = category_label(alert.category)
    metric = " #{metric_label(alert.metric)}"
    threshold = "#{alert.threshold_percentage}%"

    "#{category}#{metric} +#{threshold} / #{alert.sample_size} runs"
  end

  defp format_alert_explanation(assigns) do
    category = assigns.alert_form_category
    metric = String.downcase(metric_label(assigns.alert_form_metric))
    threshold = "#{assigns.alert_form_threshold}%"
    window = assigns.alert_form_sample_size

    case category do
      :build_run_duration ->
        dgettext(
          "dashboard_projects",
          "Alert when the %{metric} build time of the last %{window} builds has increased by %{threshold} compared to the previous %{window} builds.",
          metric: metric,
          window: window,
          threshold: threshold
        )

      :test_run_duration ->
        dgettext(
          "dashboard_projects",
          "Alert when the %{metric} test time of the last %{window} test runs has increased by %{threshold} compared to the previous %{window} test runs.",
          metric: metric,
          window: window,
          threshold: threshold
        )

      :cache_hit_rate ->
        dgettext(
          "dashboard_projects",
          "Alert when the %{metric} cache hit rate of the last %{window} builds has decreased by %{threshold} compared to the previous %{window} builds.",
          metric: metric,
          window: window,
          threshold: threshold
        )
    end
  end
end
