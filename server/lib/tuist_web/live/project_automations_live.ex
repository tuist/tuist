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
    |> assign(create_automation_form_comparison: "gte")
    |> assign(create_automation_form_threshold: "10")
    |> assign(create_automation_form_window: "30d")
    |> assign(create_automation_form_trigger_actions: [default_add_label_action()])
    |> assign(create_automation_form_recovery_enabled: false)
    |> assign(create_automation_form_recovery_window: "14d")
    |> assign(create_automation_form_recovery_actions: [default_remove_label_action()])
  end

  @comparisons ~w(gte gt lt lte)
  @below_comparisons ~w(lt lte)

  defp default_threshold("flakiness_rate", comparison) when comparison in @below_comparisons, do: "5"
  defp default_threshold("flakiness_rate", _), do: "10"
  defp default_threshold("flaky_run_count", comparison) when comparison in @below_comparisons, do: "1"
  defp default_threshold("flaky_run_count", _), do: "3"

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
      metric: automation.monitor_type,
      comparison: parse_comparison(automation.trigger_config["comparison"]),
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

  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"

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

      socket =
        socket
        |> assign(editing_automation_id: automation.id)
        |> assign(create_automation_form_name: form.name)
        |> assign(create_automation_form_metric: form.metric)
        |> assign(create_automation_form_comparison: form.comparison)
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
    threshold = default_threshold(metric, socket.assigns.create_automation_form_comparison)

    {:noreply,
     socket
     |> assign(create_automation_form_metric: metric)
     |> assign(create_automation_form_threshold: threshold)}
  end

  def handle_event("update_create_automation_form_comparison", %{"data" => comparison}, socket) do
    threshold = default_threshold(socket.assigns.create_automation_form_metric, comparison)

    # Below comparisons (lt/lte) exist to *unmark* tests, so flip the default
    # trigger action when the user switches direction. Only swap if the form
    # is still in its single-default state — preserve any custom actions the
    # user has already added.
    was_below = socket.assigns.create_automation_form_comparison in @below_comparisons
    is_below = comparison in @below_comparisons

    trigger_actions =
      case {is_below, was_below, socket.assigns.create_automation_form_trigger_actions} do
        {true, false, [%{"type" => "add_label", "label" => "flaky"}]} -> [default_remove_label_action()]
        {false, true, [%{"type" => "remove_label", "label" => "flaky"}]} -> [default_add_label_action()]
        {_, _, current} -> current
      end

    {:noreply,
     socket
     |> assign(create_automation_form_comparison: comparison)
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
    threshold = parse_threshold(assigns.create_automation_form_metric, assigns.create_automation_form_threshold)

    base = %{
      "project_id" => project_id,
      "name" => assigns.create_automation_form_name,
      "monitor_type" => assigns.create_automation_form_metric,
      "trigger_config" => %{
        "threshold" => threshold,
        "window" => assigns.create_automation_form_window,
        "comparison" => assigns.create_automation_form_comparison
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

  def comparison_label("gte"), do: dgettext("dashboard_projects", "Greater or equal")
  def comparison_label("gt"), do: dgettext("dashboard_projects", "Greater than")
  def comparison_label("lt"), do: dgettext("dashboard_projects", "Less than")
  def comparison_label("lte"), do: dgettext("dashboard_projects", "Less or equal")
  def comparison_label(_), do: dgettext("dashboard_projects", "Unknown")

  def comparison_symbol("gte"), do: "≥"
  def comparison_symbol("gt"), do: ">"
  def comparison_symbol("lt"), do: "<"
  def comparison_symbol("lte"), do: "≤"
  def comparison_symbol(_), do: "≥"

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
    symbol = comparison_symbol(parse_comparison(trigger_config["comparison"]))
    scope = scope_phrase(parse_comparison(trigger_config["comparison"]))

    dgettext(
      "dashboard_projects",
      "When %{scope}flakiness rate %{symbol} %{threshold}% over %{window}",
      scope: scope,
      symbol: symbol,
      threshold: threshold,
      window: window
    )
  end

  def automation_summary(%{monitor_type: "flaky_run_count", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    window = trigger_config["window"] || "30d"
    symbol = comparison_symbol(parse_comparison(trigger_config["comparison"]))
    scope = scope_phrase(parse_comparison(trigger_config["comparison"]))

    dgettext(
      "dashboard_projects",
      "When %{scope}flaky runs %{symbol} %{threshold} over %{window}",
      scope: scope,
      symbol: symbol,
      threshold: threshold,
      window: window
    )
  end

  def automation_summary(_), do: ""

  defp scope_phrase(comparison) when comparison in @below_comparisons,
    do: dgettext("dashboard_projects", "a flaky-marked test's ")

  defp scope_phrase(_), do: ""

  defp format_threshold(n) when is_float(n) and trunc(n) == n, do: trunc(n)
  defp format_threshold(n), do: n
end
