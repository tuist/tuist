defmodule TuistWeb.ProjectAutomationLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Time

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Automations
  alias TuistWeb.ProjectAutomationsLive

  @impl true
  def mount(
        %{"automation_id" => automation_id},
        _session,
        %{assigns: %{selected_project: selected_project, current_user: current_user}} = socket
      ) do
    if Authorization.authorize(:automation_alert_read, current_user, selected_project) != :ok do
      raise TuistWeb.Errors.UnauthorizedError,
            dgettext("dashboard_projects", "You are not authorized to perform this action.")
    end

    with {:ok, automation} <- Automations.get_alert(automation_id),
         true <- automation.project_id == selected_project.id do
      {:ok,
       socket
       |> assign(:automation, automation)
       |> assign(:revisions, Automations.list_alert_revisions(automation.id))
       |> assign(
         :head_title,
         "#{automation.name} · #{dgettext("dashboard_projects", "Automations")} · #{selected_project.name} · Tuist"
       )}
    else
      _ ->
        raise TuistWeb.Errors.NotFoundError,
              dgettext("dashboard_projects", "Automation not found.")
    end
  end

  def automation_summary(automation), do: ProjectAutomationsLive.automation_summary(automation)

  def automation_actions_summary(%{trigger_actions: actions}), do: actions_summary(actions)

  def recovery_summary(%{recovery_enabled: false}), do: dgettext("dashboard_projects", "Disabled")

  def recovery_summary(%{recovery_config: recovery_config}) do
    dgettext(
      "dashboard_projects",
      "Enabled after %{window}",
      window: window_summary(recovery_config)
    )
  end

  def cadence_summary(%{cadence: cadence}) do
    dgettext("dashboard_projects", "Every %{cadence}", cadence: cadence)
  end

  def revision_title(%{event: "created"}), do: dgettext("dashboard_projects", "Automation created")
  def revision_title(_revision), do: dgettext("dashboard_projects", "Automation updated")

  def revision_description(%{event: "created"} = revision) do
    dgettext(
      "dashboard_projects",
      "%{actor} created this automation from %{source}",
      actor: revision_actor_name(revision),
      source: revision_source_label(revision.source)
    )
  end

  def revision_description(revision) do
    dgettext(
      "dashboard_projects",
      "%{actor} changed this automation from %{source}",
      actor: revision_actor_name(revision),
      source: revision_source_label(revision.source)
    )
  end

  def revision_source_label("dashboard"), do: dgettext("dashboard_projects", "the dashboard")
  def revision_source_label("integration"), do: dgettext("dashboard_projects", "an integration")
  def revision_source_label(_source), do: dgettext("dashboard_projects", "Tuist")

  def revision_actor_name(%{actor: %{account: %{name: name}}}) when not is_nil(name), do: name
  def revision_actor_name(%{actor: %{email: email}}) when not is_nil(email), do: email
  def revision_actor_name(_revision), do: dgettext("dashboard_projects", "Tuist")

  def revision_actor_avatar(%{actor: %User{} = actor}), do: User.gravatar_url(actor)
  def revision_actor_avatar(_revision), do: nil

  def revision_actor_color(%{actor: %{account: account}}) when not is_nil(account) do
    Accounts.avatar_color(account)
  end

  def revision_actor_color(_revision), do: "purple"

  def revision_change_items(%{event: "created"}) do
    [
      %{
        title: dgettext("dashboard_projects", "Initial configuration"),
        before: nil,
        after: dgettext("dashboard_projects", "Automation created"),
        icon: "plus"
      }
    ]
  end

  def revision_change_items(revision) do
    []
    |> maybe_add_simple_change(revision, "name", dgettext("dashboard_projects", "Automation renamed"), "pencil")
    |> maybe_add_enabled_change(revision)
    |> maybe_add_condition_change(revision)
    |> maybe_add_simple_change(revision, "cadence", dgettext("dashboard_projects", "Cadence changed"), "hourglass")
    |> maybe_add_actions_change(
      revision,
      "trigger_actions",
      dgettext("dashboard_projects", "Trigger actions changed")
    )
    |> maybe_add_recovery_enabled_change(revision)
    |> maybe_add_recovery_config_change(revision)
    |> maybe_add_actions_change(
      revision,
      "recovery_actions",
      dgettext("dashboard_projects", "Recovery actions changed")
    )
  end

  defp maybe_add_simple_change(items, revision, field, title, icon) do
    case revision.changes[field] do
      %{"from" => before, "to" => new_value} ->
        items ++ [%{title: title, before: to_string(before), after: to_string(new_value), icon: icon}]

      _ ->
        items
    end
  end

  defp maybe_add_enabled_change(items, revision) do
    case revision.changes["enabled"] do
      %{"from" => before, "to" => new_value} ->
        title =
          if new_value,
            do: dgettext("dashboard_projects", "Automation enabled"),
            else: dgettext("dashboard_projects", "Automation disabled")

        items ++
          [
            %{
              title: title,
              before: enabled_label(before),
              after: enabled_label(new_value),
              icon: if(new_value, do: "player_play", else: "player_pause")
            }
          ]

      _ ->
        items
    end
  end

  defp maybe_add_condition_change(items, revision) do
    if Map.has_key?(revision.changes, "monitor_type") or Map.has_key?(revision.changes, "trigger_config") do
      before =
        condition_summary(
          revision_value(revision, "monitor_type", :before),
          revision_value(revision, "trigger_config", :before)
        )

      updated_summary =
        condition_summary(
          revision_value(revision, "monitor_type", :after),
          revision_value(revision, "trigger_config", :after)
        )

      items ++
        [
          %{
            title: dgettext("dashboard_projects", "Condition changed"),
            before: before,
            after: updated_summary,
            icon: "settings"
          }
        ]
    else
      items
    end
  end

  defp maybe_add_actions_change(items, revision, field, title) do
    case revision.changes[field] do
      %{"from" => before, "to" => new_value} ->
        items ++
          [
            %{
              title: title,
              before: actions_summary(before),
              after: actions_summary(new_value),
              icon: "list_tree"
            }
          ]

      _ ->
        items
    end
  end

  defp maybe_add_recovery_enabled_change(items, revision) do
    case revision.changes["recovery_enabled"] do
      %{"from" => before, "to" => new_value} ->
        title =
          if new_value,
            do: dgettext("dashboard_projects", "Recovery enabled"),
            else: dgettext("dashboard_projects", "Recovery disabled")

        items ++
          [
            %{
              title: title,
              before: enabled_label(before),
              after: enabled_label(new_value),
              icon: "history_toggle"
            }
          ]

      _ ->
        items
    end
  end

  defp maybe_add_recovery_config_change(items, revision) do
    case revision.changes["recovery_config"] do
      %{"from" => before, "to" => new_value} ->
        items ++
          [
            %{
              title: dgettext("dashboard_projects", "Recovery condition changed"),
              before: window_summary(before),
              after: window_summary(new_value),
              icon: "history_toggle"
            }
          ]

      _ ->
        items
    end
  end

  defp revision_value(revision, field, :before) do
    case revision.changes[field] do
      %{"from" => value} -> value
      _ -> revision.snapshot[field]
    end
  end

  defp revision_value(revision, field, :after) do
    case revision.changes[field] do
      %{"to" => value} -> value
      _ -> revision.snapshot[field]
    end
  end

  defp condition_summary(monitor_type, trigger_config) do
    ProjectAutomationsLive.automation_summary(%{
      monitor_type: monitor_type,
      trigger_config: trigger_config || %{}
    })
  end

  defp enabled_label(true), do: dgettext("dashboard_projects", "Enabled")
  defp enabled_label(false), do: dgettext("dashboard_projects", "Disabled")

  defp actions_summary([]), do: dgettext("dashboard_projects", "None")

  defp actions_summary(actions) when is_list(actions) do
    Enum.map_join(actions, ", ", &ProjectAutomationsLive.action_row_summary/1)
  end

  defp actions_summary(_), do: dgettext("dashboard_projects", "None")

  defp window_summary(%{"window_type" => "rolling"} = config) do
    dgettext(
      "dashboard_projects",
      "the last %{size} runs",
      size: config["rolling_window_size"] || 100
    )
  end

  defp window_summary(config) when is_map(config), do: config["window"] || "30d"
  defp window_summary(_config), do: "30d"
end
