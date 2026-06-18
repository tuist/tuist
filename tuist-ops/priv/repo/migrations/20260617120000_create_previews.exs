defmodule TuistOps.Repo.Migrations.CreatePreviews do
  use Ecto.Migration

  def change do
    # One row per preview slug, mutated as state evolves. Modeling create /
    # update / delete as separate request rows for the same slug (the
    # original shape of this table) leaks lifecycle into the schema and
    # forces the partial-unique-index gymnastics Marek called out — see PR
    # #11348. State-table keeps the data model honest: the row is the
    # preview; status describes what we last asked the workflow to do
    # with it.
    create table(:previews) do
      add :slug, :string, null: false
      add :status, :string, null: false, default: "creating"
      add :requester_email, :string, null: false
      add :requester_slack_id, :string, null: false
      add :ref_kind, :string
      add :ref_value, :string
      add :reason, :text, null: false
      add :ttl_seconds, :integer
      add :host, :string
      add :namespace, :string
      add :release, :string
      add :slack_channel_id, :string, null: false
      add :slack_message_ts, :string
      add :workflow_id, :string
      add :workflow_ref, :string
      add :expires_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :failure_reason, :text

      timestamps(type: :utc_datetime)
    end

    # Slug is the natural key — `/preview create demo` and a later
    # `/preview delete demo` should always converge to the same row.
    create unique_index(:previews, [:slug])
    create index(:previews, [:status])
    create index(:previews, [:expires_at])
  end
end
