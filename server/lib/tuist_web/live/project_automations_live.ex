defmodule TuistWeb.ProjectAutomationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.CheckboxControl

  alias Tuist.Authorization
  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Environment
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

    socket =
      socket
      |> assign(:slack_configured, Environment.slack_configured?())
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
    |> assign(create_automation_form_window_type: "last_days")
    |> assign(create_automation_form_window: "30d")
    |> assign(create_automation_form_rolling_window_size: "100")
    |> assign(create_automation_form_events: ["marked_flaky"])
    |> assign(create_automation_form_trigger_actions: [default_add_label_action()])
    |> assign(create_automation_form_recovery_enabled: false)
    |> assign(create_automation_form_recovery_window_type: "last_days")
    |> assign(create_automation_form_recovery_window: "14d")
    |> assign(create_automation_form_recovery_rolling_window_size: "100")
    |> assign(create_automation_form_recovery_actions: [default_remove_label_action()])
    |> reset_webhook_action_modal()
  end

  # Webhook action modal — opened from the "Send webhook" entry in either the
  # trigger or recovery action dropdown, or from "Rotate" on an existing row.
  # `context` is `:trigger` or `:recovery`; `editing_index` is non-nil when
  # rotating the secret of an already-added action.
  defp reset_webhook_action_modal(socket) do
    socket
    |> assign(webhook_action_modal_context: nil)
    |> assign(webhook_action_modal_url: "")
    |> assign(webhook_action_modal_url_error: nil)
    |> assign(webhook_action_modal_plaintext_secret: nil)
    |> assign(webhook_action_modal_encrypted_secret: nil)
    |> assign(webhook_action_modal_editing_index: nil)
  end

  @comparisons ~w(gte gt lt lte)
  @window_types ~w(last_days rolling)

  # Only varies by metric — switching comparison keeps whatever the user has
  # typed, since "% < 5" and "% >= 5" are both reasonable starting points and
  # auto-resetting on every dropdown click would clobber their input.
  defp default_threshold("flakiness_rate"), do: "10"
  defp default_threshold("flaky_run_count"), do: "3"
  defp default_threshold(_), do: "1"

  defp default_change_state_action(state), do: %{"type" => "change_state", "state" => state}
  defp default_add_label_action, do: %{"type" => "add_label", "label" => "flaky"}
  defp default_remove_label_action, do: %{"type" => "remove_label", "label" => "flaky"}

  @default_trigger_slack_message ":warning: *{{test_case.name}}* in module `{{test_case.module_name}}` has been detected as flaky by automation *{{automation.name}}*.\n\n<{{test_case.url}}|View test case>"
  @default_recovery_slack_message ":white_check_mark: *{{test_case.name}}* in module `{{test_case.module_name}}` has recovered.\n\n<{{test_case.url}}|View test case>"

  defp default_send_slack_action(:trigger),
    do: %{
      "type" => "send_slack",
      "channel" => "",
      "channel_name" => "",
      "webhook_url_encrypted" => "",
      "message" => @default_trigger_slack_message
    }

  defp default_send_slack_action(:recovery),
    do: %{
      "type" => "send_slack",
      "channel" => "",
      "channel_name" => "",
      "webhook_url_encrypted" => "",
      "message" => @default_recovery_slack_message
    }

  defp automation_to_form(automation) do
    %{
      name: automation.name,
      metric: automation.monitor_type,
      comparison: parse_comparison(automation.trigger_config["comparison"]),
      threshold: to_string(automation.trigger_config["threshold"] || ""),
      window_type: parse_window_type(automation.trigger_config["window_type"]),
      window: automation.trigger_config["window"] || "30d",
      rolling_window_size: to_string(automation.trigger_config["rolling_window_size"] || 100),
      events: parse_events(automation.trigger_config["events"]),
      trigger_actions: automation.trigger_actions,
      recovery_enabled: automation.recovery_enabled,
      recovery_window_type: parse_window_type(automation.recovery_config["window_type"]),
      recovery_window: automation.recovery_config["window"] || "14d",
      recovery_rolling_window_size: to_string(automation.recovery_config["rolling_window_size"] || 100),
      recovery_actions: automation.recovery_actions,
      enabled: automation.enabled
    }
  end

  defp parse_events(events) when is_list(events) do
    Enum.filter(events, &(&1 in Alert.test_updated_events()))
  end

  defp parse_events(_), do: ["marked_flaky"]

  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"

  defp parse_window_type(window_type) when window_type in @window_types, do: window_type
  defp parse_window_type(_), do: "last_days"

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
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
        |> assign(create_automation_form_window_type: form.window_type)
        |> assign(create_automation_form_window: form.window)
        |> assign(create_automation_form_rolling_window_size: form.rolling_window_size)
        |> assign(create_automation_form_events: form.events)
        |> assign(create_automation_form_trigger_actions: form.trigger_actions)
        |> assign(create_automation_form_recovery_enabled: form.recovery_enabled)
        |> assign(create_automation_form_recovery_window_type: form.recovery_window_type)
        |> assign(create_automation_form_recovery_window: form.recovery_window)
        |> assign(create_automation_form_recovery_rolling_window_size: form.recovery_rolling_window_size)
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
    event_driven? = event_driven_monitor_type?(metric)

    trigger_actions = strip_redundant_actions(socket.assigns.create_automation_form_trigger_actions, metric)

    # Event-driven monitors are discrete one-shots — there's no "condition no
    # longer holds" semantic, so we force recovery off when switching to one.
    {recovery_enabled, recovery_actions} =
      if event_driven? do
        {false, socket.assigns.create_automation_form_recovery_actions}
      else
        {socket.assigns.create_automation_form_recovery_enabled, socket.assigns.create_automation_form_recovery_actions}
      end

    {:noreply,
     socket
     |> assign(create_automation_form_metric: metric)
     |> assign(create_automation_form_threshold: default_threshold(metric))
     |> assign(create_automation_form_trigger_actions: trigger_actions)
     |> assign(create_automation_form_recovery_enabled: recovery_enabled)
     |> assign(create_automation_form_recovery_actions: recovery_actions)}
  end

  def handle_event("update_create_automation_form_comparison", %{"data" => comparison}, socket) do
    {:noreply, assign(socket, create_automation_form_comparison: comparison)}
  end

  def handle_event("toggle_create_automation_form_event", %{"data" => event}, socket) do
    current = socket.assigns.create_automation_form_events

    next =
      if event in current do
        List.delete(current, event)
      else
        current ++ [event]
      end

    {:noreply, assign(socket, create_automation_form_events: next)}
  end

  def handle_event("update_create_automation_form_threshold", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_threshold: value)}
  end

  def handle_event("update_create_automation_form_window", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_window: value)}
  end

  def handle_event("update_create_automation_form_window_type", %{"data" => window_type}, socket) do
    if window_type in @window_types do
      {:noreply, assign(socket, create_automation_form_window_type: window_type)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_create_automation_form_rolling_window_size", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_rolling_window_size: value)}
  end

  def handle_event("add_create_automation_form_trigger_action", %{"data" => "send_webhook"}, socket) do
    {:noreply, open_webhook_action_modal(socket, :trigger, nil)}
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

  def handle_event("trigger_action_channel_selected", %{"id" => index, "channel_token" => channel_token}, socket) do
    case verify_and_encrypt(channel_token) do
      {:ok, %{channel_id: channel_id, channel_name: channel_name, encrypted_webhook_url: encrypted}} ->
        index = String.to_integer(index)

        actions =
          update_action_at(socket.assigns.create_automation_form_trigger_actions, index, fn action ->
            action
            |> Map.put("channel", channel_id)
            |> Map.put("channel_name", channel_name)
            |> Map.put("webhook_url_encrypted", encrypted)
          end)

        {:noreply, assign(socket, create_automation_form_trigger_actions: actions)}

      {:error, _reason} ->
        {:noreply, socket}
    end
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

  def handle_event("update_create_automation_form_recovery_window_type", %{"data" => window_type}, socket) do
    if window_type in @window_types do
      {:noreply, assign(socket, create_automation_form_recovery_window_type: window_type)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_create_automation_form_recovery_rolling_window_size", %{"value" => value}, socket) do
    {:noreply, assign(socket, create_automation_form_recovery_rolling_window_size: value)}
  end

  def handle_event("add_create_automation_form_recovery_action", %{"data" => "send_webhook"}, socket) do
    {:noreply, open_webhook_action_modal(socket, :recovery, nil)}
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

  def handle_event("recovery_action_channel_selected", %{"id" => index, "channel_token" => channel_token}, socket) do
    case verify_and_encrypt(channel_token) do
      {:ok, %{channel_id: channel_id, channel_name: channel_name, encrypted_webhook_url: encrypted}} ->
        index = String.to_integer(index)

        actions =
          update_action_at(socket.assigns.create_automation_form_recovery_actions, index, fn action ->
            action
            |> Map.put("channel", channel_id)
            |> Map.put("channel_name", channel_name)
            |> Map.put("webhook_url_encrypted", encrypted)
          end)

        {:noreply, assign(socket, create_automation_form_recovery_actions: actions)}

      {:error, _reason} ->
        {:noreply, socket}
    end
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

  # Webhook action modal handlers

  def handle_event("open_webhook_action_rotate_modal", %{"context" => context, "index" => index}, socket)
      when context in ["trigger", "recovery"] do
    index = String.to_integer(index)
    ctx = String.to_existing_atom(context)
    action = current_webhook_action(socket, ctx, index)

    if action do
      %{plaintext: plaintext, encrypted: encrypted} = Tuist.Webhooks.generate_signing_secret()

      socket =
        socket
        |> assign(webhook_action_modal_context: ctx)
        |> assign(webhook_action_modal_editing_index: index)
        |> assign(webhook_action_modal_url: action["url"] || "")
        |> assign(webhook_action_modal_url_error: nil)
        |> assign(webhook_action_modal_plaintext_secret: plaintext)
        |> assign(webhook_action_modal_encrypted_secret: encrypted)
        |> push_event("open-modal", %{id: "webhook-action-modal"})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_webhook_action_modal_url", %{"value" => url}, socket) do
    {:noreply,
     socket
     |> assign(webhook_action_modal_url: url)
     |> assign(webhook_action_modal_url_error: nil)}
  end

  def handle_event("create_webhook_action", _params, socket) do
    url = String.trim(socket.assigns.webhook_action_modal_url || "")

    if Tuist.Webhooks.valid_webhook_url?(url) do
      %{plaintext: plaintext, encrypted: encrypted} = Tuist.Webhooks.generate_signing_secret()

      {:noreply,
       socket
       |> assign(webhook_action_modal_url: url)
       |> assign(webhook_action_modal_url_error: nil)
       |> assign(webhook_action_modal_plaintext_secret: plaintext)
       |> assign(webhook_action_modal_encrypted_secret: encrypted)}
    else
      {:noreply,
       assign(socket,
         webhook_action_modal_url_error: dgettext("dashboard_projects", "Must be a valid HTTPS URL.")
       )}
    end
  end

  def handle_event("confirm_webhook_action", _params, socket) do
    {:noreply,
     socket
     |> apply_webhook_modal_result()
     |> reset_webhook_action_modal()
     |> push_event("close-modal", %{id: "webhook-action-modal"})}
  end

  def handle_event("cancel_webhook_action", _params, socket) do
    {:noreply,
     socket
     |> reset_webhook_action_modal()
     |> push_event("close-modal", %{id: "webhook-action-modal"})}
  end

  # Catches close-on-Escape and close-on-interact-outside (Zag dialog state),
  # neither of which triggers `on_dismiss`. We reset the modal state so a
  # subsequent open lands on the blank URL form rather than the prior secret.
  def handle_event("webhook_action_modal_open_change", %{"open" => false}, socket) do
    {:noreply, reset_webhook_action_modal(socket)}
  end

  def handle_event("webhook_action_modal_open_change", _params, socket), do: {:noreply, socket}

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

  defp open_webhook_action_modal(socket, context, _opts) do
    socket
    |> reset_webhook_action_modal()
    |> assign(webhook_action_modal_context: context)
    |> push_event("open-modal", %{id: "webhook-action-modal"})
  end

  defp current_webhook_action(socket, :trigger, index),
    do: Enum.at(socket.assigns.create_automation_form_trigger_actions, index)

  defp current_webhook_action(socket, :recovery, index),
    do: Enum.at(socket.assigns.create_automation_form_recovery_actions, index)

  defp build_webhook_action(url, encrypted_secret) do
    %{
      "type" => "send_webhook",
      "url" => url,
      "signing_secret_encrypted" => encrypted_secret
    }
  end

  defp apply_webhook_modal_result(%{assigns: %{webhook_action_modal_encrypted_secret: nil}} = socket), do: socket

  defp apply_webhook_modal_result(socket) do
    ctx = socket.assigns.webhook_action_modal_context
    index = socket.assigns.webhook_action_modal_editing_index
    url = socket.assigns.webhook_action_modal_url
    encrypted = socket.assigns.webhook_action_modal_encrypted_secret

    field = webhook_modal_actions_field(ctx)

    if is_nil(field) do
      socket
    else
      assign(socket, field, apply_webhook_to_actions(Map.fetch!(socket.assigns, field), index, url, encrypted))
    end
  end

  defp webhook_modal_actions_field(:trigger), do: :create_automation_form_trigger_actions
  defp webhook_modal_actions_field(:recovery), do: :create_automation_form_recovery_actions
  defp webhook_modal_actions_field(_), do: nil

  defp apply_webhook_to_actions(actions, nil, url, encrypted) do
    actions ++ [build_webhook_action(url, encrypted)]
  end

  defp apply_webhook_to_actions(actions, index, url, encrypted) do
    update_action_at(actions, index, fn action ->
      action
      |> Map.put("signing_secret_encrypted", encrypted)
      |> Map.put("url", url)
    end)
  end

  defp build_automation_attrs(project_id, assigns) do
    metric = assigns.create_automation_form_metric

    base = %{
      "project_id" => project_id,
      "name" => assigns.create_automation_form_name,
      "monitor_type" => metric,
      "trigger_config" => trigger_config_for(metric, assigns),
      "trigger_actions" => strip_transient_action_fields(assigns.create_automation_form_trigger_actions),
      "recovery_enabled" => assigns.create_automation_form_recovery_enabled
    }

    if assigns.create_automation_form_recovery_enabled do
      base
      |> Map.put("recovery_config", recovery_config_for(metric, assigns))
      |> Map.put("recovery_actions", strip_transient_action_fields(assigns.create_automation_form_recovery_actions))
    else
      base
    end
  end

  # Fields prefixed with `_` are transient form-only state (e.g. the plaintext
  # signing secret shown once after generation) and must never reach the DB.
  defp strip_transient_action_fields(actions) do
    Enum.map(actions, fn action ->
      action
      |> Enum.reject(fn {key, _} -> is_binary(key) and String.starts_with?(key, "_") end)
      |> Map.new()
    end)
  end

  defp trigger_config_for("test_updated", assigns) do
    %{"events" => assigns.create_automation_form_events}
  end

  defp trigger_config_for(metric, assigns) do
    build_trigger_config(
      parse_threshold(metric, assigns.create_automation_form_threshold),
      assigns.create_automation_form_comparison,
      assigns.create_automation_form_window_type,
      assigns.create_automation_form_window,
      assigns.create_automation_form_rolling_window_size
    )
  end

  defp recovery_config_for("test_updated", _assigns), do: %{}

  defp recovery_config_for(_metric, assigns) do
    build_recovery_config(
      assigns.create_automation_form_recovery_window_type,
      assigns.create_automation_form_recovery_window,
      assigns.create_automation_form_recovery_rolling_window_size
    )
  end

  defp build_trigger_config(threshold, comparison, "rolling", _window, rolling_window_size) do
    %{
      "threshold" => threshold,
      "comparison" => comparison,
      "window_type" => "rolling",
      "rolling_window_size" => parse_int(rolling_window_size, 100)
    }
  end

  defp build_trigger_config(threshold, comparison, _window_type, window, _rolling_window_size) do
    %{
      "threshold" => threshold,
      "comparison" => comparison,
      "window_type" => "last_days",
      "window" => window
    }
  end

  defp build_recovery_config("rolling", _window, rolling_window_size) do
    %{
      "window_type" => "rolling",
      "rolling_window_size" => parse_int(rolling_window_size, 100)
    }
  end

  defp build_recovery_config(_window_type, window, _rolling_window_size) do
    %{
      "window_type" => "last_days",
      "window" => window
    }
  end

  # The default `add_label flaky` / `remove_label flaky` trigger actions
  # presume the threshold-monitor mental model. For the event-driven
  # `test_updated` trigger they're a confusing default — the user picks
  # which sub-events to react to (mark / unmark / state change), and a
  # blanket label flip tends to fight at least one of those sub-events.
  # Strip them on switch; the user can opt back in via "Add action".
  defp strip_redundant_actions(actions, "test_updated") do
    Enum.reject(actions, fn action ->
      action["label"] == "flaky" and action["type"] in ["add_label", "remove_label"]
    end)
  end

  defp strip_redundant_actions(actions, _), do: actions

  def event_driven_monitor_type?("test_updated"), do: true
  def event_driven_monitor_type?(_), do: false

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
  def metric_label("test_updated"), do: dgettext("dashboard_projects", "Test updated")
  def metric_label(_), do: dgettext("dashboard_projects", "Unknown")

  def test_updated_event_label("marked_flaky"), do: dgettext("dashboard_projects", "Marked as flaky")
  def test_updated_event_label("unmarked_flaky"), do: dgettext("dashboard_projects", "Unmarked as flaky")

  def test_updated_event_label("state_changed_to_enabled"), do: dgettext("dashboard_projects", "State changed to Enabled")

  def test_updated_event_label("state_changed_to_muted"), do: dgettext("dashboard_projects", "State changed to Muted")

  def test_updated_event_label("state_changed_to_skipped"), do: dgettext("dashboard_projects", "State changed to Skipped")

  def test_updated_event_label(_), do: dgettext("dashboard_projects", "Unknown")

  def test_updated_event_description("marked_flaky"),
    do: dgettext("dashboard_projects", "Fires when a test is manually flagged as flaky.")

  def test_updated_event_description("unmarked_flaky"),
    do: dgettext("dashboard_projects", "Fires when the flaky flag is manually removed.")

  def test_updated_event_description("state_changed_to_enabled"),
    do: dgettext("dashboard_projects", "Fires when a test returns to the default enabled state.")

  def test_updated_event_description("state_changed_to_muted"),
    do: dgettext("dashboard_projects", "Fires when a test is muted (still runs, failures ignored).")

  def test_updated_event_description("state_changed_to_skipped"),
    do: dgettext("dashboard_projects", "Fires when a test is skipped entirely.")

  def test_updated_event_description(_), do: ""

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

  def threshold_label("flakiness_rate"), do: dgettext("dashboard_projects", "Percent")
  def threshold_label("flaky_run_count"), do: dgettext("dashboard_projects", "Count")
  def threshold_label(_), do: dgettext("dashboard_projects", "Threshold")

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
  def action_type_label("send_webhook"), do: dgettext("dashboard_projects", "Send webhook")
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

  def action_row_summary(%{"type" => "send_webhook", "url" => url}) when is_binary(url) and url != "",
    do: "Webhook: #{url}"

  def action_row_summary(%{"type" => "send_webhook"}), do: dgettext("dashboard_projects", "Webhook: not configured")

  def action_row_summary(%{"type" => "add_label", "label" => label}),
    do: dgettext("dashboard_projects", "Add label: %{label}", label: label)

  def action_row_summary(%{"type" => "remove_label", "label" => label}),
    do: dgettext("dashboard_projects", "Remove label: %{label}", label: label)

  def action_row_summary(_), do: ""

  def automation_summary(%{monitor_type: "flakiness_rate", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    symbol = comparison_symbol(parse_comparison(trigger_config["comparison"]))

    dgettext(
      "dashboard_projects",
      "When flakiness rate %{symbol} %{threshold}% over %{window}",
      symbol: symbol,
      threshold: threshold,
      window: window_summary(trigger_config)
    )
  end

  def automation_summary(%{monitor_type: "flaky_run_count", trigger_config: trigger_config}) do
    threshold = format_threshold(trigger_config["threshold"] || 0)
    symbol = comparison_symbol(parse_comparison(trigger_config["comparison"]))

    dgettext(
      "dashboard_projects",
      "When flaky runs %{symbol} %{threshold} over %{window}",
      symbol: symbol,
      threshold: threshold,
      window: window_summary(trigger_config)
    )
  end

  def automation_summary(%{monitor_type: "test_updated", trigger_config: trigger_config}) do
    events = trigger_config["events"] || []

    case events do
      [] ->
        dgettext("dashboard_projects", "When a test is updated")

      _ ->
        labels = Enum.map_join(events, ", ", &test_updated_event_label/1)
        dgettext("dashboard_projects", "When a test is updated: %{events}", events: labels)
    end
  end

  def automation_summary(_), do: ""

  defp window_summary(%{"window_type" => "rolling"} = trigger_config) do
    size = trigger_config["rolling_window_size"] || 100

    dgettext(
      "dashboard_projects",
      "the last %{size} runs",
      size: size
    )
  end

  defp window_summary(trigger_config), do: trigger_config["window"] || "30d"

  defp format_threshold(n) when is_float(n) and trunc(n) == n, do: trunc(n)
  defp format_threshold(n), do: n

  def window_type_label("rolling"), do: dgettext("dashboard_projects", "Rolling window")
  def window_type_label(_), do: dgettext("dashboard_projects", "Last days")

  @doc """
  True when the form's rolling-window inputs are within the schema cap.
  Drives the Save button's disabled state so a too-large value can't be
  submitted silently — the changeset already rejects it server-side, but
  Save dispatches via `phx-click` not a form submit, so the browser's
  `max` attribute doesn't intercept the click.
  """
  def rolling_window_inputs_valid?(assigns) do
    is_nil(
      rolling_size_error(assigns.create_automation_form_window_type, assigns.create_automation_form_rolling_window_size)
    ) and
      (not assigns.create_automation_form_recovery_enabled or
         is_nil(
           rolling_size_error(
             assigns.create_automation_form_recovery_window_type,
             assigns.create_automation_form_recovery_rolling_window_size
           )
         ))
  end

  @doc """
  User-facing error string for a rolling-window size input, or `nil` when
  the value is valid (or the window mode isn't rolling). Wired into the
  `error` attribute on the noora `text_input` so the same constraint that
  disables Save is visible inline on the field.
  """
  def rolling_size_error("rolling", raw_size) do
    max = Alert.max_rolling_window_size()

    case Integer.parse(to_string(raw_size)) do
      {n, ""} when n >= 1 and n <= max -> nil
      _ -> dgettext("dashboard_projects", "1–%{max}", max: max)
    end
  end

  def rolling_size_error(_window_type, _raw_size), do: nil

  # Decode the signed channel-result token, then encrypt the webhook URL so
  # we never store it as plaintext inside the action JSON.
  defp verify_and_encrypt(channel_token) do
    with {:ok, %{channel_id: channel_id, channel_name: channel_name, webhook_url: webhook_url}} <-
           Slack.verify_channel_result(channel_token),
         {:ok, encrypted} <- Slack.encrypt_webhook_url(webhook_url) do
      {:ok, %{channel_id: channel_id, channel_name: channel_name, encrypted_webhook_url: encrypted}}
    end
  end
end
