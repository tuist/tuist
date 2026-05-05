defmodule TuistWeb.ProjectAutomationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Authorization
  alias Tuist.Automations
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
    if Authorization.authorize(:automation_alert_read, current_user, selected_project) != :ok do
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
        :automation_channel_selection_url,
        SlackOAuthController.alert_channel_selection_url(selected_account.id)
      )
      |> assign_automations(selected_project)
      |> assign_create_automation_form_defaults()

    {:ok, socket}
  end

  defp assign_automations(socket, project) do
    automations = Automations.list_alerts(project.id)
    edit_forms = Map.new(automations, fn a -> {a.id, automation_to_form(a)} end)

    socket
    |> assign(automations: automations)
    |> assign(edit_automation_forms: edit_forms)
  end

  defp assign_create_automation_form_defaults(socket) do
    # Trigger defaults to "mark as flaky" (label-only) so a brand-new automation
    # is non-destructive out of the box — matches the seeded default alert on
    # project creation. Quarantining is an explicit opt-in via "Add action".
    socket
    |> assign(editing_automation_id: nil)
    |> assign(create_automation_form_name: "")
    |> assign(create_automation_form_metric: "flakiness_rate")
    |> assign(create_automation_form_direction: "above")
    |> assign(create_automation_form_threshold: "10")
    |> assign(create_automation_form_window: "30d")
    |> assign(create_automation_form_trigger_actions: [default_add_label_action()])
    |> assign(create_automation_form_recovery_enabled: false)
    |> assign(create_automation_form_recovery_window: "14d")
    |> assign(create_automation_form_recovery_actions: [default_remove_label_action()])
  end

  # Splits the persisted `monitor_type` into the two UI dimensions: the metric
  # being measured and the comparison direction. Keeping the persisted shape
  # parallel (`*_below` suffix) avoids a schema migration; the form just
  # composes/decomposes it on the way in and out.
  defp split_monitor_type("flakiness_rate"), do: {"flakiness_rate", "above"}
  defp split_monitor_type("flakiness_rate_below"), do: {"flakiness_rate", "below"}
  defp split_monitor_type("flaky_run_count"), do: {"flaky_run_count", "above"}
  defp split_monitor_type("flaky_run_count_below"), do: {"flaky_run_count", "below"}
  defp split_monitor_type(_), do: {"flakiness_rate", "above"}

  defp compose_monitor_type("flakiness_rate", "above"), do: "flakiness_rate"
  defp compose_monitor_type("flakiness_rate", "below"), do: "flakiness_rate_below"
  defp compose_monitor_type("flaky_run_count", "above"), do: "flaky_run_count"
  defp compose_monitor_type("flaky_run_count", "below"), do: "flaky_run_count_below"

  defp default_threshold("flakiness_rate", "above"), do: "10"
  defp default_threshold("flakiness_rate", "below"), do: "5"
  defp default_threshold("flaky_run_count", "above"), do: "3"
  defp default_threshold("flaky_run_count", "below"), do: "1"

  defp default_change_state_action(state), do: %{"type" => "change_state", "state" => state}
  defp default_add_label_action, do: %{"type" => "add_label", "label" => "flaky"}
  defp default_remove_label_action, do: %{"type" => "remove_label", "label" => "flaky"}

  @default_trigger_slack_message ":warning: *{{test_case.name}}* in module `{{test_case.module_name}}` has been detected as flaky by automation *{{automation.name}}*.\n\n<{{test_case.url}}|View test case>"
  @default_recovery_slack_message ":white_check_mark: *{{test_case.name}}* in module `{{test_case.module_name}}` has recovered.\n\n<{{test_case.url}}|View test case>"

  defp default_send_slack_action(:trigger),
    do: %{"type" => "send_slack", "channel" => "", "channel_name" => "", "message" => @default_trigger_slack_message}

  defp default_send_slack_action(:recovery),
    do: %{"type" => "send_slack", "channel" => "", "channel_name" => "", "message" => @default_recovery_slack_message}

  defp automation_to_form(automation) do
    %{
      name: automation.name,
      monitor_type: automation.monitor_type,
      threshold: to_string(automation.trigger_config["threshold"] || ""),
      window: automation.trigger_config["window"] || "30d",
      trigger_actions: automation.trigger_actions,
      recovery_enabled: automation.recovery_enabled,
      recovery_window:
        automation.recovery_config["window"] ||
          (automation.recovery_config["days_without_trigger"] && "#{automation.recovery_config["days_without_trigger"]}d") ||
          "14d",
      recovery_actions: automation.recovery_actions,
      enabled: automation.enabled
    }
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

  # Automation create form handlers

  def handle_event("open_create_automation_modal", _params, socket) do
    {:noreply, assign_create_automation_form_defaults(socket)}
  end

  def handle_event("edit_automation", %{"id" => id}, %{assigns: %{selected_project: project}} = socket) do
    with {:ok, automation} <- Automations.get_alert(id),
         true <- automation.project_id == project.id do
      form = automation_to_form(automation)
      {metric, direction} = split_monitor_type(form.monitor_type)

      socket =
        socket
        |> assign(editing_automation_id: automation.id)
        |> assign(create_automation_form_name: form.name)
        |> assign(create_automation_form_metric: metric)
        |> assign(create_automation_form_direction: direction)
        |> assign(create_automation_form_threshold: form.threshold)
        |> assign(create_automation_form_window: form.window)
        |> assign(create_automation_form_trigger_actions: form.trigger_actions)
        |> assign(create_automation_form_recovery_enabled: form.recovery_enabled)
        |> assign(create_automation_form_recovery_window: form.recovery_window)
        |> assign(create_automation_form_recovery_actions: form.recovery_actions)
        |> push_event("open-modal", %{id: "create-automation-modal"})

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_create_automation_modal", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "create-automation-modal"})}
  end

  def handle_event("update_create_automation_form_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, create_automation_form_name: name)}
  end

  def handle_event("update_create_automation_form_metric", %{"data" => metric}, socket) do
    threshold = default_threshold(metric, socket.assigns.create_automation_form_direction)

    {:noreply,
     socket
     |> assign(create_automation_form_metric: metric)
     |> assign(create_automation_form_threshold: threshold)}
  end

  def handle_event("update_create_automation_form_direction", %{"data" => direction}, socket) do
    threshold = default_threshold(socket.assigns.create_automation_form_metric, direction)

    # `below` automations exist to *unmark* tests, so flip the default trigger
    # action when the user switches direction. Only swap if the form is still
    # in its single-default state — preserve any custom actions the user has
    # already added.
    trigger_actions =
      case {direction, socket.assigns.create_automation_form_trigger_actions} do
        {"below", [%{"type" => "add_label", "label" => "flaky"}]} ->
          [default_remove_label_action()]

        {"above", [%{"type" => "remove_label", "label" => "flaky"}]} ->
          [default_add_label_action()]

        {_, current} ->
          current
      end

    {:noreply,
     socket
     |> assign(create_automation_form_direction: direction)
     |> assign(create_automation_form_threshold: threshold)
     |> assign(create_automation_form_trigger_actions: trigger_actions)}
  end

  def handle_event("update_create_automation_form_threshold", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_threshold: value)}
  end

  def handle_event("update_create_automation_form_window", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_window: value)}
  end

  def handle_event("add_create_automation_form_trigger_action", %{"data" => type}, socket) do
    actions = socket.assigns.create_automation_form_trigger_actions ++ [new_action(type, :trigger)]
    {:noreply, assign(socket, create_automation_form_trigger_actions: actions)}
  end

  def handle_event("delete_create_automation_form_trigger_action", %{"index" => index}, socket) do
    index = String.to_integer(index)
    actions = List.delete_at(socket.assigns.create_automation_form_trigger_actions, index)
    {:noreply, assign(socket, create_automation_form_trigger_actions: actions)}
  end

  def handle_event("update_create_automation_form_trigger_action_state", %{"data" => state, "index" => index}, socket) do
    index = String.to_integer(index)

    actions =
      update_action_at(socket.assigns.create_automation_form_trigger_actions, index, fn action ->
        Map.put(action, "state", state)
      end)

    {:noreply, assign(socket, create_automation_form_trigger_actions: actions)}
  end

  def handle_event(
        "trigger_action_channel_selected",
        %{"id" => index, "channel_id" => channel_id, "channel_name" => channel_name},
        socket
      ) do
    index = String.to_integer(index)

    actions =
      update_action_at(socket.assigns.create_automation_form_trigger_actions, index, fn action ->
        action |> Map.put("channel", channel_id) |> Map.put("channel_name", channel_name)
      end)

    {:noreply, assign(socket, create_automation_form_trigger_actions: actions)}
  end

  def handle_event("trigger_action_channel_selected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "update_create_automation_form_trigger_action_message",
        %{"value" => message, "index" => index},
        socket
      ) do
    index = String.to_integer(index)

    actions =
      update_action_at(socket.assigns.create_automation_form_trigger_actions, index, fn action ->
        Map.put(action, "message", message)
      end)

    {:noreply, assign(socket, create_automation_form_trigger_actions: actions)}
  end

  def handle_event("toggle_create_automation_form_recovery", _params, socket) do
    {:noreply,
     assign(socket, create_automation_form_recovery_enabled: not socket.assigns.create_automation_form_recovery_enabled)}
  end

  def handle_event("update_create_automation_form_recovery_window", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_recovery_window: value)}
  end

  def handle_event("add_create_automation_form_recovery_action", %{"data" => type}, socket) do
    actions = socket.assigns.create_automation_form_recovery_actions ++ [new_action(type, :recovery)]
    {:noreply, assign(socket, create_automation_form_recovery_actions: actions)}
  end

  def handle_event("delete_create_automation_form_recovery_action", %{"index" => index}, socket) do
    index = String.to_integer(index)
    actions = List.delete_at(socket.assigns.create_automation_form_recovery_actions, index)
    {:noreply, assign(socket, create_automation_form_recovery_actions: actions)}
  end

  def handle_event("update_create_automation_form_recovery_action_state", %{"data" => state, "index" => index}, socket) do
    index = String.to_integer(index)

    actions =
      update_action_at(socket.assigns.create_automation_form_recovery_actions, index, fn action ->
        Map.put(action, "state", state)
      end)

    {:noreply, assign(socket, create_automation_form_recovery_actions: actions)}
  end

  def handle_event(
        "recovery_action_channel_selected",
        %{"id" => index, "channel_id" => channel_id, "channel_name" => channel_name},
        socket
      ) do
    index = String.to_integer(index)

    actions =
      update_action_at(socket.assigns.create_automation_form_recovery_actions, index, fn action ->
        action |> Map.put("channel", channel_id) |> Map.put("channel_name", channel_name)
      end)

    {:noreply, assign(socket, create_automation_form_recovery_actions: actions)}
  end

  def handle_event("recovery_action_channel_selected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "update_create_automation_form_recovery_action_message",
        %{"value" => message, "index" => index},
        socket
      ) do
    index = String.to_integer(index)

    actions =
      update_action_at(socket.assigns.create_automation_form_recovery_actions, index, fn action ->
        Map.put(action, "message", message)
      end)

    {:noreply, assign(socket, create_automation_form_recovery_actions: actions)}
  end

  def handle_event("save_automation", _params, %{assigns: assigns} = socket) do
    attrs = build_automation_attrs(assigns.selected_project.id, assigns)

    result =
      case assigns.editing_automation_id do
        nil ->
          Automations.create_alert(attrs)

        id ->
          with {:ok, automation} <- Automations.get_alert(id) do
            Automations.update_alert(automation, attrs)
          end
      end

    case result do
      {:ok, _automation} ->
        socket =
          socket
          |> assign_automations(assigns.selected_project)
          |> assign_create_automation_form_defaults()
          |> push_event("close-modal", %{id: "create-automation-modal"})

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_automation_enabled", %{"id" => id}, %{assigns: %{selected_project: project}} = socket) do
    with {:ok, automation} <- Automations.get_alert(id),
         true <- automation.project_id == project.id,
         {:ok, _} <- Automations.update_alert(automation, %{enabled: not automation.enabled}) do
      {:noreply, assign_automations(socket, project)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_automation", %{"id" => id}, %{assigns: %{selected_project: project}} = socket) do
    with {:ok, automation} <- Automations.get_alert(id),
         true <- automation.project_id == project.id,
         {:ok, _} <- Automations.delete_alert(automation) do
      {:noreply, assign_automations(socket, project)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp new_action("change_state", :trigger), do: default_change_state_action("muted")
  defp new_action("change_state", :recovery), do: default_change_state_action("enabled")
  defp new_action("send_slack", context), do: default_send_slack_action(context)
  defp new_action("add_label_flaky", _context), do: %{"type" => "add_label", "label" => "flaky"}
  defp new_action("remove_label_flaky", _context), do: %{"type" => "remove_label", "label" => "flaky"}
  defp new_action(_, :recovery), do: default_change_state_action("enabled")
  defp new_action(_, _), do: default_change_state_action("muted")

  defp update_action_at(actions, index, fun) do
    case Enum.at(actions, index) do
      nil -> actions
      action -> List.replace_at(actions, index, fun.(action))
    end
  end

  defp build_automation_attrs(project_id, assigns) do
    monitor_type =
      compose_monitor_type(assigns.create_automation_form_metric, assigns.create_automation_form_direction)

    threshold = parse_threshold(assigns.create_automation_form_metric, assigns.create_automation_form_threshold)

    base = %{
      "project_id" => project_id,
      "name" => assigns.create_automation_form_name,
      "monitor_type" => monitor_type,
      "trigger_config" => %{
        "threshold" => threshold,
        "window" => assigns.create_automation_form_window
      },
      "trigger_actions" => assigns.create_automation_form_trigger_actions,
      "recovery_enabled" => assigns.create_automation_form_recovery_enabled
    }

    if assigns.create_automation_form_recovery_enabled do
      base
      |> Map.put("recovery_config", %{
        "window" => assigns.create_automation_form_recovery_window
      })
      |> Map.put("recovery_actions", assigns.create_automation_form_recovery_actions)
    else
      base
    end
  end

  defp parse_threshold("flakiness_rate", value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> 10.0
    end
  end

  defp parse_threshold(_metric, value) do
    parse_int(value, 1)
  end

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      :error -> default
    end
  end

  def metric_label("flakiness_rate"), do: dgettext("dashboard_projects", "Flakiness rate")
  def metric_label("flaky_run_count"), do: dgettext("dashboard_projects", "Flaky runs")
  def metric_label(_), do: dgettext("dashboard_projects", "Unknown")

  def direction_label("above"), do: dgettext("dashboard_projects", "Is greater than or equal to")
  def direction_label("below"), do: dgettext("dashboard_projects", "Is less than")
  def direction_label(_), do: dgettext("dashboard_projects", "Unknown")

  def threshold_unit("flakiness_rate"), do: dgettext("dashboard_projects", "%")
  def threshold_unit("flaky_run_count"), do: dgettext("dashboard_projects", "count")
  def threshold_unit(_), do: ""

  def state_action_label("muted"), do: dgettext("dashboard_projects", "Mute")
  def state_action_label("skipped"), do: dgettext("dashboard_projects", "Skip")
  def state_action_label("enabled"), do: dgettext("dashboard_projects", "Enable")
  def state_action_label(_), do: dgettext("dashboard_projects", "Unknown")

  def trigger_action_label("muted"), do: dgettext("dashboard_projects", "Muted")
  def trigger_action_label("skipped"), do: dgettext("dashboard_projects", "Skipped")
  def trigger_action_label("enabled"), do: dgettext("dashboard_projects", "Enabled")
  def trigger_action_label(_), do: dgettext("dashboard_projects", "Unknown")

  def action_type_label("change_state"), do: dgettext("dashboard_projects", "Change state")
  def action_type_label("send_slack"), do: dgettext("dashboard_projects", "Send Slack notification")
  def action_type_label("add_label"), do: dgettext("dashboard_projects", "Add label")
  def action_type_label("remove_label"), do: dgettext("dashboard_projects", "Remove label")
  def action_type_label(_), do: dgettext("dashboard_projects", "Unknown")

  def has_action_type?(actions, type) do
    Enum.any?(actions, fn action -> action["type"] == type end)
  end

  def has_label_action?(actions, type, label) do
    Enum.any?(actions, fn action -> action["type"] == type and action["label"] == label end)
  end

  def has_change_state_action?(actions), do: has_action_type?(actions, "change_state")

  def action_row_summary(%{"type" => "change_state", "state" => state}), do: trigger_action_label(state)

  def action_row_summary(%{"type" => "send_slack", "channel" => channel}) when channel != "", do: "Slack: #{channel}"

  def action_row_summary(%{"type" => "send_slack"}), do: dgettext("dashboard_projects", "Slack: not configured")

  def action_row_summary(%{"type" => "add_label", "label" => label}),
    do: dgettext("dashboard_projects", "Add label: %{label}", label: label)

  def action_row_summary(%{"type" => "remove_label", "label" => label}),
    do: dgettext("dashboard_projects", "Remove label: %{label}", label: label)

  def action_row_summary(_), do: ""

  def automation_summary(%{monitor_type: "flakiness_rate", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    window = trigger_config["window"] || "30d"

    dgettext("dashboard_projects", "When flakiness rate ≥ %{threshold}% over %{window}",
      threshold: threshold,
      window: window
    )
  end

  def automation_summary(%{monitor_type: "flakiness_rate_below", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    window = trigger_config["window"] || "30d"

    dgettext(
      "dashboard_projects",
      "When a flaky-marked test's flakiness rate < %{threshold}% over %{window}",
      threshold: threshold,
      window: window
    )
  end

  def automation_summary(%{monitor_type: "flaky_run_count", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    window = trigger_config["window"] || "30d"
    dgettext("dashboard_projects", "When flaky runs ≥ %{threshold} over %{window}", threshold: threshold, window: window)
  end

  def automation_summary(%{monitor_type: "flaky_run_count_below", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    window = trigger_config["window"] || "30d"

    dgettext(
      "dashboard_projects",
      "When a flaky-marked test's flaky runs < %{threshold} over %{window}",
      threshold: threshold,
      window: window
    )
  end

  def automation_summary(_), do: ""

  defp format_threshold(n) when is_float(n) and trunc(n) == n, do: trunc(n)
  defp format_threshold(n), do: n
end
