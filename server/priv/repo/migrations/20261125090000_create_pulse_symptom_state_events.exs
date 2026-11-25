defmodule Tuist.Repo.Migrations.CreatePulseSymptomStateEvents do
  @moduledoc """
  An append-only record of every ack, mute and outcome change with the person
  who made it. `pulse_symptom_acks`, `pulse_symptom_mutes` and
  `pulse_symptom_outcomes` keep only the latest state, overwriting `user_id`,
  so without this a member could silence paging for 30 days without a trace.
  A trigger refuses UPDATE and DELETE except the cascade from deleting the
  account. `symptom_id` and `user_id` carry no foreign key, so pruning a
  symptom or deleting a user neither blocks on nor rewrites the trail.
  """
  use Ecto.Migration

  def up do
    create table(:pulse_symptom_state_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      # No foreign keys: the trail outlives the symptom and the user.
      add :symptom_id, :uuid, null: false
      add :kind, :string, null: false
      add :user_id, :bigint
      add :change_seq, :bigint, null: false
      add :details, :jsonb, null: false, default: "{}"
      add :inserted_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_state_events, [:account_id, :symptom_id, :change_seq])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:pulse_symptom_state_events, [:user_id])

    # Rows are never changed. Deleting is allowed only as part of deleting the
    # account (the FK cascade), which removes the account row in the same
    # statement; any other DELETE or UPDATE fails.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE FUNCTION pulse_symptom_state_events_append_only() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN
        RETURN OLD;
      END IF;
      RAISE EXCEPTION 'pulse_symptom_state_events is append-only';
    END;
    $$ LANGUAGE plpgsql
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TRIGGER pulse_symptom_state_events_append_only
    BEFORE UPDATE OR DELETE ON pulse_symptom_state_events
    FOR EACH ROW EXECUTE FUNCTION pulse_symptom_state_events_append_only()
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:pulse_symptom_state_events)
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP FUNCTION pulse_symptom_state_events_append_only()"
  end
end
