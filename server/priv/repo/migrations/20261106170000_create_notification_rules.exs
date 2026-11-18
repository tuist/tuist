defmodule Tuist.Repo.Migrations.CreateNotificationRules do
  use Ecto.Migration

  def change do
    # A user's own notification rule (`Tuist.Notifications`): when `event`
    # happens in one of the rule's projects (or any project the user can
    # subscribe to, when it lists none) and the event matches `conditions`,
    # run `actions`. Conditions and actions are validated per event type.
    create table(:notification_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :conditions, :map, null: false, default: %{}
      add :actions, {:array, :map}, null: false, default: []
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:notification_rules, [:user_id, :event])

    create table(:notification_rule_projects, primary_key: false) do
      add :rule_id, references(:notification_rules, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :project_id, references(:projects, on_delete: :delete_all),
        null: false,
        primary_key: true
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:notification_rule_projects, [:project_id])
  end
end
