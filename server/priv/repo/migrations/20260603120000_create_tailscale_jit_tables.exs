defmodule Tuist.Repo.Migrations.CreateTailscaleJitTables do
  use Ecto.Migration

  # Backing tables for the Tailscale JIT elevation Slack bot. Two
  # tables on purpose: requests track the Slack-side approval
  # lifecycle (a request can be denied and never become an
  # elevation); elevations track the runtime grant (active until
  # TTL, revertable early). Drift reconciler queries elevations.
  def change do
    create table(:tailscale_jit_requests) do
      add :requester_email, :string, null: false
      add :requester_slack_id, :string, null: false
      add :target_group, :string, null: false
      add :intent, :text, null: false
      add :ttl_seconds, :integer, null: false
      add :status, :string, null: false
      add :slack_channel_id, :string, null: false
      add :slack_message_ts, :string
      add :approver_email, :string
      add :approver_slack_id, :string
      add :approved_at, :timestamptz
      add :denied_at, :timestamptz
      add :expires_at, :timestamptz, null: false
      add :failure_reason, :text

      timestamps(type: :timestamptz)
    end

    # Fast lookup for the request-approval handler resolving an
    # interactive button click. Pending-only queries are common.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:tailscale_jit_requests, [:status, :expires_at])

    create table(:tailscale_jit_elevations) do
      add :request_id, references(:tailscale_jit_requests, on_delete: :delete_all), null: false
      add :requester_email, :string, null: false
      add :target_group, :string, null: false
      add :expires_at, :timestamptz, null: false
      add :status, :string, null: false
      add :reverted_at, :timestamptz
      add :revert_failure_reason, :text

      timestamps(type: :timestamptz)
    end

    # Drift reconciler scans active elevations to compare DB state
    # against actual ACL membership; covers the (status, expires_at)
    # window query.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:tailscale_jit_elevations, [:status, :expires_at])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:tailscale_jit_elevations, [:request_id])
  end
end
