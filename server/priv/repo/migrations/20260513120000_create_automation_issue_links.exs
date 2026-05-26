defmodule Tuist.Repo.Migrations.CreateAutomationIssueLinks do
  use Ecto.Migration

  def change do
    create table(:automation_issue_links, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :alert_id, references(:automation_alerts, type: :uuid, on_delete: :delete_all),
        null: false

      add :test_case_id, :uuid, null: false

      add :github_app_installation_id,
          references(:github_app_installations, type: :uuid, on_delete: :nilify_all)

      add :github_repository_full_handle, :string, null: false
      add :github_issue_number, :integer, null: false
      add :github_issue_node_id, :string

      add :state, :string, null: false, default: "open"

      add :opened_at, :timestamptz, null: false
      add :resolved_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:automation_issue_links, [:project_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:automation_issue_links, [:alert_id])

    # One open issue per (alert, test_case): the create_github_issue action
    # reads this index to no-op when a link already exists, so duplicate
    # issues can't be created on repeated fires of the same alert.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_issue_links, [:alert_id, :test_case_id],
             where: "state = 'open'",
             name: :automation_issue_links_open_per_alert_test_case_index
           )

    # Webhook lookups arrive with (installation_id, repo, issue_number) and
    # need a single matching row.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :automation_issue_links,
             [:github_app_installation_id, :github_repository_full_handle, :github_issue_number],
             name: :automation_issue_links_installation_repo_issue_index
           )
  end
end
