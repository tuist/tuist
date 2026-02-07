defmodule TuistWeb.ProjectNotificationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Alerts
  alias Tuist.Authorization
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Client, as: SlackClient
  alias Tuist.Slack.Reports
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
      |> assign(:head_title, "#{dgettext("dashboard_projects", "Notifications")} · #{selected_project.name} · Tuist")
      |> assign(
        :slack_channel_selection_url,
        SlackOAuthController.channel_selection_url(selected_project.id, selected_account.id)
      )
      |> assign_schedule_form_defaults(selected_project)
      |> assign_alert_defaults(selected_project)

    {:ok, socket}
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

  defp assign_alert_defaults(socket, project) do
    alert_rules = Alerts.get_project_alert_rules(project)

    edit_alert_forms =
      Map.new(alert_rules, fn rule ->
        {rule.id, alert_rule_to_form(rule)}
      end)

    socket
    |> assign(alert_rules: alert_rules)
    # Metric alert create form defaults
    |> assign(create_alert_form_name: "")
    |> assign(create_alert_form_category: :build_run_duration)
    |> assign(create_alert_form_metric: :p99)
    |> assign(create_alert_form_deviation: 20.0)
    |> assign(create_alert_form_rolling_window_size: 100)
    |> assign(create_alert_form_channel_id: nil)
    |> assign(create_alert_form_channel_name: nil)
    # Metric alert edit forms - one per alert rule
    |> assign(edit_alert_forms: edit_alert_forms)
  end

  defp alert_rule_to_form(rule) do
    %{
      name: rule.name,
      category: rule.category,
      metric: rule.metric,
      deviation: rule.deviation_percentage,
      rolling_window_size: rule.rolling_window_size,
      channel_id: rule.slack_channel_id,
      channel_name: rule.slack_channel_name
    }
  end

  defp assign_schedule_form_defaults(socket, project) do
    user_timezone = socket.assigns[:user_timezone] || "Etc/UTC"

    frequency = project.report_frequency

    days = if project.report_days_of_week == [], do: [1, 2, 3, 4, 5], else: project.report_days_of_week

    hour = get_local_hour(project.report_schedule_time, user_timezone) || 9

    socket
    |> assign(schedule_form_frequency: frequency)
    |> assign(schedule_form_days: days)
    |> assign(schedule_form_hour: hour)
    |> assign(slack_reports_enabled: project.report_frequency == :daily && project.slack_channel_id != nil)
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
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

  def handle_event("close_schedule_modal", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "schedule-modal"})
      |> assign_schedule_form_defaults(selected_project)

    {:noreply, socket}
  end

  def handle_event(
        "save_schedule",
        _params,
        %{assigns: %{selected_project: selected_project, user_timezone: user_timezone} = assigns} = socket
      ) do
    frequency = assigns.schedule_form_frequency
    days = assigns.schedule_form_days
    hour = assigns.schedule_form_hour
    timezone = user_timezone || "Etc/UTC"

    updates =
      if frequency == :never do
        %{report_frequency: :never}
      else
        utc_time = local_hour_to_utc(hour, timezone)

        %{
          report_frequency: frequency,
          report_days_of_week: days,
          report_schedule_time: utc_time,
          report_timezone: timezone
        }
      end

    {:ok, updated_project} = Projects.update_project(selected_project, updates)

    socket =
      socket
      |> assign(selected_project: updated_project)
      |> assign_schedule_form_defaults(updated_project)
      |> push_event("close-modal", %{id: "schedule-modal"})

    {:noreply, socket}
  end

  def handle_event("toggle_slack_reports", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    current_enabled = selected_project.report_frequency == :daily && selected_project.slack_channel_id != nil

    updates =
      if current_enabled do
        %{report_frequency: :never}
      else
        %{report_frequency: :daily}
      end

    {:ok, updated_project} = Projects.update_project(selected_project, updates)

    socket =
      socket
      |> assign(selected_project: updated_project)
      |> assign_schedule_form_defaults(updated_project)

    {:noreply, socket}
  end

  # Alert event handlers

  def handle_event("open_create_alert_modal", _params, socket) do
    socket =
      socket
      |> assign(create_alert_form_name: "")
      |> assign(create_alert_form_category: :build_run_duration)
      |> assign(create_alert_form_metric: :p99)
      |> assign(create_alert_form_deviation: 20.0)
      |> assign(create_alert_form_rolling_window_size: 100)
      |> assign(create_alert_form_channel_id: nil)
      |> assign(create_alert_form_channel_name: nil)

    {:noreply, socket}
  end

  # Create form handlers
  def handle_event("update_create_alert_form_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, create_alert_form_name: name)}
  end

  def handle_event("update_create_alert_form_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, create_alert_form_category: String.to_existing_atom(category))}
  end

  def handle_event("update_create_alert_form_metric", %{"metric" => metric}, socket) do
    {:noreply, assign(socket, create_alert_form_metric: String.to_existing_atom(metric))}
  end

  def handle_event("update_create_alert_form_deviation", %{"value" => deviation_str}, socket) do
    case Float.parse(deviation_str) do
      {deviation, _} -> {:noreply, assign(socket, create_alert_form_deviation: deviation)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("update_create_alert_form_rolling_window_size", %{"value" => size_str}, socket) do
    case Integer.parse(size_str) do
      {size, _} -> {:noreply, assign(socket, create_alert_form_rolling_window_size: size)}
      :error -> {:noreply, socket}
    end
  end

  # Edit form handlers
  def handle_event("update_edit_alert_form_name", %{"id" => id, "value" => name}, socket) do
    {:noreply, update_edit_alert_form(socket, id, :name, name)}
  end

  def handle_event("update_edit_alert_form_category", %{"id" => id, "category" => category}, socket) do
    {:noreply, update_edit_alert_form(socket, id, :category, String.to_existing_atom(category))}
  end

  def handle_event("update_edit_alert_form_metric", %{"id" => id, "metric" => metric}, socket) do
    {:noreply, update_edit_alert_form(socket, id, :metric, String.to_existing_atom(metric))}
  end

  def handle_event("update_edit_alert_form_deviation", %{"id" => id, "value" => deviation_str}, socket) do
    case Float.parse(deviation_str) do
      {deviation, _} -> {:noreply, update_edit_alert_form(socket, id, :deviation, deviation)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("update_edit_alert_form_rolling_window_size", %{"id" => id, "value" => size_str}, socket) do
    case Integer.parse(size_str) do
      {size, _} -> {:noreply, update_edit_alert_form(socket, id, :rolling_window_size, size)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("create_alert_rule", _params, %{assigns: assigns} = socket) do
    attrs = %{
      project_id: assigns.selected_project.id,
      name: assigns.create_alert_form_name,
      category: assigns.create_alert_form_category,
      metric: assigns.create_alert_form_metric,
      deviation_percentage: assigns.create_alert_form_deviation,
      rolling_window_size: assigns.create_alert_form_rolling_window_size,
      slack_channel_id: assigns.create_alert_form_channel_id,
      slack_channel_name: assigns.create_alert_form_channel_name
    }

    {:ok, _alert_rule} = Alerts.create_alert_rule(attrs)

    socket =
      socket
      |> assign_alert_defaults(assigns.selected_project)
      |> push_event("close-modal", %{id: "create-alert-modal"})

    {:noreply, socket}
  end

  def handle_event("update_alert_rule", %{"id" => id}, %{assigns: assigns} = socket) do
    {:ok, alert_rule} = Alerts.get_alert_rule(id)
    alert_rule = Repo.preload(alert_rule, :project)

    if Authorization.authorize(:project_update, assigns.current_user, alert_rule.project) == :ok do
      form = Map.get(assigns.edit_alert_forms, id)

      attrs = %{
        name: form.name,
        category: form.category,
        metric: form.metric,
        deviation_percentage: form.deviation,
        rolling_window_size: form.rolling_window_size,
        slack_channel_id: form.channel_id,
        slack_channel_name: form.channel_name
      }

      {:ok, _alert_rule} = Alerts.update_alert_rule(alert_rule, attrs)

      socket =
        socket
        |> assign_alert_defaults(assigns.selected_project)
        |> push_event("close-modal", %{id: "update-alert-modal-#{id}"})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_alert_rule", %{"alert_rule_id" => alert_rule_id}, socket) do
    current_user = socket.assigns.current_user
    selected_project = socket.assigns.selected_project
    {:ok, alert_rule} = Alerts.get_alert_rule(alert_rule_id)
    alert_rule = Repo.preload(alert_rule, :project)

    if Authorization.authorize(:project_update, current_user, alert_rule.project) == :ok do
      {:ok, _} = Alerts.delete_alert_rule(alert_rule)
      {:noreply, assign(socket, alert_rules: Alerts.get_project_alert_rules(selected_project))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_create_alert_modal", _params, %{assigns: %{selected_project: selected_project}} = socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "create-alert-modal"})
      |> assign_alert_defaults(selected_project)

    {:noreply, socket}
  end

  def handle_event("close_edit_alert_modal", %{"id" => id}, %{assigns: %{selected_project: selected_project}} = socket) do
    socket =
      socket
      |> push_event("close-modal", %{id: "update-alert-modal-#{id}"})
      |> assign_alert_defaults(selected_project)

    {:noreply, socket}
  end

  def handle_event(
        "oauth_channel_selected",
        %{"channel_id" => channel_id, "channel_name" => channel_name},
        %{assigns: %{selected_project: selected_project}} = socket
      ) do
    {:ok, selected_project} =
      Projects.update_project(selected_project, %{
        slack_channel_id: channel_id,
        slack_channel_name: channel_name,
        report_frequency: :daily
      })

    socket =
      socket
      |> assign(selected_project: selected_project)
      |> assign_schedule_form_defaults(selected_project)

    {:noreply, socket}
  end

  def handle_event(
        "create_alert_form_channel_selected",
        %{"channel_id" => channel_id, "channel_name" => channel_name},
        socket
      ) do
    socket =
      socket
      |> assign(create_alert_form_channel_id: channel_id)
      |> assign(create_alert_form_channel_name: channel_name)

    {:noreply, socket}
  end

  def handle_event("create_alert_form_channel_selected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "edit_alert_form_channel_selected",
        %{"id" => id, "channel_id" => channel_id, "channel_name" => channel_name},
        socket
      ) do
    socket =
      socket
      |> update_edit_alert_form(id, :channel_id, channel_id)
      |> update_edit_alert_form(id, :channel_name, channel_name)

    {:noreply, socket}
  end

  def handle_event("edit_alert_form_channel_selected", _params, socket) do
    {:noreply, socket}
  end

  defp update_edit_alert_form(socket, id, key, value) do
    edit_alert_forms = socket.assigns.edit_alert_forms
    form = Map.get(edit_alert_forms, id, %{})
    updated_form = Map.put(form, key, value)
    assign(socket, edit_alert_forms: Map.put(edit_alert_forms, id, updated_form))
  end

  defp alert_channel_selection_url(account_id) do
    SlackOAuthController.alert_channel_selection_url(account_id)
  end

  defp format_hour(hour) do
    hour
    |> Time.new!(0, 0)
    |> Timex.format!("{h12} {AM}")
  end

  defp format_days_range([]), do: ""

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

  defp format_day_group([]), do: ""
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

  defp format_schedule_summary(%{selected_project: project, user_timezone: user_timezone}) do
    days = project.report_days_of_week
    hour = get_local_hour(project.report_schedule_time, user_timezone)
    time_str = if hour, do: format_hour(hour), else: ""
    day_str = format_days_range(days)

    "#{dgettext("dashboard_projects", "Daily")} • #{day_str} • #{time_str}"
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

  defp metric_label(:p50), do: "p50"
  defp metric_label(:p90), do: "p90"
  defp metric_label(:p99), do: "p99"
  defp metric_label(:average), do: dgettext("dashboard_projects", "Average")
  defp metric_label(nil), do: ""

  defp alert_rule_description(category, metric, deviation, rolling_window_size) do
    metric_category = alert_metric_category_label(category, metric)
    unit = alert_unit_label(category)

    text =
      case category do
        :cache_hit_rate ->
          dgettext(
            "dashboard_projects",
            "Alert when the <strong>%{metric_category}</strong> of the last <strong>%{rolling_window_size} %{unit}</strong> has decreased by <strong>%{deviation}%</strong> compared to the previous <strong>%{rolling_window_size} %{unit}</strong>.",
            metric_category: metric_category,
            rolling_window_size: rolling_window_size,
            unit: unit,
            deviation: deviation
          )

        _ ->
          dgettext(
            "dashboard_projects",
            "Alert when the <strong>%{metric_category}</strong> of the last <strong>%{rolling_window_size} %{unit}</strong> has increased by <strong>%{deviation}%</strong> compared to the previous <strong>%{rolling_window_size} %{unit}</strong>.",
            metric_category: metric_category,
            rolling_window_size: rolling_window_size,
            unit: unit,
            deviation: deviation
          )
      end

    raw(text)
  end

  defp alert_metric_category_label(:build_run_duration, metric),
    do: "#{metric_label_lowercase(metric)} #{dgettext("dashboard_projects", "build time")}"

  defp alert_metric_category_label(:test_run_duration, metric),
    do: "#{metric_label_lowercase(metric)} #{dgettext("dashboard_projects", "test time")}"

  defp alert_metric_category_label(:cache_hit_rate, metric),
    do: "#{metric_label_lowercase(metric)} #{dgettext("dashboard_projects", "cache hit rate")}"

  defp alert_unit_label(:build_run_duration), do: dgettext("dashboard_projects", "builds")
  defp alert_unit_label(:test_run_duration), do: dgettext("dashboard_projects", "tests")
  defp alert_unit_label(:cache_hit_rate), do: dgettext("dashboard_projects", "builds")

  defp metric_label_lowercase(:p50), do: "p50"
  defp metric_label_lowercase(:p90), do: "p90"
  defp metric_label_lowercase(:p99), do: "p99"
  defp metric_label_lowercase(:average), do: dgettext("dashboard_projects", "average")
  defp metric_label_lowercase(nil), do: ""
end
