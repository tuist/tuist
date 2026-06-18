defmodule TuistOps.Repo.Migrations.CreatePreviewRequests do
  use Ecto.Migration

  def change do
    create table(:preview_requests) do
      add :slug, :string, null: false
      add :action, :string, null: false
      add :status, :string, null: false, default: "requested"
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
      add :failed_at, :utc_datetime
      add :failure_reason, :text

      timestamps(type: :utc_datetime)
    end

    create index(:preview_requests, [:slug, :inserted_at])
    create index(:preview_requests, [:status])
    create index(:preview_requests, [:expires_at])

    # Stop two concurrent `/preview create <slug>` calls from both racing
    # past insert and dispatching workflows for the same namespace. Scoped
    # to *create* requests because the GitHub Actions workflow has no
    # completion callback into tuist-ops yet — the first successful create
    # leaves a row at `provisioning` indefinitely, and a wider index (one
    # that also blocked subsequent deletes / updates / re-creates) would
    # break the documented lifecycle after the first dispatch. Drops to
    # tuist-ops, not Postgres, get to evolve the lifecycle further (mutable
    # row per slug, completion callbacks, etc.) without re-shaping the
    # index.
    create unique_index(
             :preview_requests,
             [:slug],
             where: "action = 'create' AND status IN ('requested', 'provisioning')",
             name: :preview_requests_active_create_slug_index
           )
  end
end
