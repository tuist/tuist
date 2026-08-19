defmodule Tuist.Repo.Migrations.CreateKuraLifecycleOperatorActions do
  @moduledoc """
  Audit trail for operator-initiated Kura archive and unarchive.

  The demand-driven lifecycle normally decides on its own, so an operator
  overriding it is a deliberate act on someone else's cache and is recorded
  with who did it and when. Automatic transitions are not written here: this
  table answers "who reclaimed this account's cache", and mixing the sweep's
  own decisions in would bury that.
  """
  use Ecto.Migration

  def change do
    create table(:kura_lifecycle_operator_actions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :service_region, :string, null: false
      add :action, :integer, null: false
      add :performed_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so its constraints and indexes cannot block existing writes.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_lifecycle_operator_actions,
             :kura_lifecycle_operator_actions_action_valid,
             check: "action IN (0, 1)"
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_lifecycle_operator_actions, [:account_id, :inserted_at])
  end
end
