import Ecto.Query

alias Tuist.Accounts
alias Tuist.Automations
alias Tuist.Automations.Alerts.Alert
alias Tuist.Automations.Alerts.Revision
alias Tuist.Projects
alias Tuist.Repo

password = "tuistrocks"

owner =
  case Accounts.get_user_by_email("tuistrocks@tuist.dev") do
    {:ok, owner} ->
      owner

    {:error, :not_found} ->
      {:ok, _account} =
        Accounts.create_user("tuistrocks@tuist.dev",
          password: password,
          confirmed_at: NaiveDateTime.utc_now(),
          setup_billing: false
        )

      {:ok, owner} = Accounts.get_user_by_email("tuistrocks@tuist.dev")
      owner
  end

owner
|> Tuist.Accounts.User.password_changeset(%{
  password: password,
  password_confirmation: password
})
|> Repo.update!()

organization =
  case Accounts.get_organization_by_handle("tuist") do
    nil ->
      {:ok, organization} =
        Accounts.create_organization(%{name: "tuist", creator: owner}, setup_billing: false)

      organization

    organization ->
      organization
  end

project =
  case Projects.get_project_by_slug("tuist/tuist") do
    {:ok, project} ->
      project

    {:error, :not_found} ->
      Projects.create_project!(
        %{name: "tuist", account: %{id: organization.account.id}},
        vcs_repository_full_handle: "tuist/tuist",
        vcs_provider: :github
      )
  end

trigger_actions = [
  %{"type" => "change_state", "state" => "muted"},
  %{
    "type" => "send_slack",
    "channel" => "test-infra",
    "channel_name" => "test-infra",
    "message" => "A flaky test was quarantined by {{automation.name}}."
  }
]

alert_attrs = %{
  project_id: project.id,
  name: "Auto-quarantine flaky tests",
  enabled: true,
  monitor_type: "flakiness_rate",
  trigger_config: %{
    "threshold" => 15.0,
    "comparison" => "gte",
    "window_type" => "rolling",
    "rolling_window_size" => 50
  },
  cadence: "5m",
  trigger_actions: trigger_actions,
  recovery_enabled: false,
  recovery_config: %{"window_type" => "rolling", "rolling_window_size" => 50},
  recovery_actions: [%{"type" => "change_state", "state" => "enabled"}]
}

alert =
  case Enum.find(Automations.list_alerts(project.id), &(&1.name == alert_attrs.name)) do
    nil -> %Alert{} |> Alert.changeset(alert_attrs) |> Repo.insert!()
    alert -> alert |> Alert.changeset(alert_attrs) |> Repo.update!()
  end

initial_snapshot = %{
  "name" => "Quarantine flaky tests",
  "enabled" => true,
  "monitor_type" => "flakiness_rate",
  "trigger_config" => %{
    "threshold" => 20.0,
    "comparison" => "gte",
    "window_type" => "rolling",
    "rolling_window_size" => 100
  },
  "cadence" => "5m",
  "trigger_actions" => [%{"type" => "change_state", "state" => "muted"}],
  "recovery_enabled" => true,
  "recovery_config" => %{"window_type" => "rolling", "rolling_window_size" => 50},
  "recovery_actions" => [%{"type" => "change_state", "state" => "enabled"}]
}

renamed_snapshot = Map.put(initial_snapshot, "name", "Auto-quarantine flaky tests")
condition_snapshot = Map.put(renamed_snapshot, "trigger_config", alert_attrs.trigger_config)
actions_snapshot = Map.put(condition_snapshot, "trigger_actions", trigger_actions)
current_snapshot = Map.put(actions_snapshot, "recovery_enabled", false)

now = DateTime.utc_now(:second)

revisions = [
  %{
    event: "updated",
    changes: %{"recovery_enabled" => %{"from" => true, "to" => false}},
    snapshot: current_snapshot,
    inserted_at: DateTime.add(now, -6, :hour)
  },
  %{
    event: "updated",
    changes: %{
      "trigger_actions" => %{
        "from" => initial_snapshot["trigger_actions"],
        "to" => trigger_actions
      }
    },
    snapshot: actions_snapshot,
    inserted_at: DateTime.add(now, -2, :day)
  },
  %{
    event: "updated",
    changes: %{
      "trigger_config" => %{
        "from" => initial_snapshot["trigger_config"],
        "to" => alert_attrs.trigger_config
      }
    },
    snapshot: condition_snapshot,
    inserted_at: DateTime.add(now, -4, :day)
  },
  %{
    event: "updated",
    changes: %{
      "name" => %{
        "from" => initial_snapshot["name"],
        "to" => renamed_snapshot["name"]
      }
    },
    snapshot: renamed_snapshot,
    inserted_at: DateTime.add(now, -8, :day)
  },
  %{
    event: "created",
    changes: %{},
    snapshot: initial_snapshot,
    inserted_at: DateTime.add(now, -14, :day)
  }
]

Repo.delete_all(from(revision in Revision, where: revision.automation_alert_id == ^alert.id))

Enum.each(revisions, fn revision ->
  %Revision{}
  |> Revision.changeset(
    Map.merge(revision, %{
      automation_alert_id: alert.id,
      actor_id: owner.id,
      source: "dashboard"
    })
  )
  |> Repo.insert!()
end)

IO.puts("Seeded automation edit history for tuist/tuist")
