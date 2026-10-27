defmodule TuistOps.Repo.Migrations.CreateProjectAccessTables do
  use Ecto.Migration

  # Backing tables for operator access to customer projects (the
  # ops.tuist.dev reason form + Slack-approved admin tier). Same
  # two-table shape as the Tailscale JIT tables: a request tracks the
  # approval lifecycle (a request can be denied and never become a
  # grant); a grant is the bounded-time capability the signed token
  # handed back to the customer server is derived from.
  def change do
    create table(:project_access_requests) do
      add :requester_email, :string, null: false
      add :account_handle, :string, null: false
      add :tier, :string, null: false
      add :reason, :text, null: false
      add :return_to, :text, null: false
      add :ttl_seconds, :integer, null: false
      add :status, :string, null: false
      add :slack_channel_id, :string
      add :slack_message_ts, :string
      add :approver_email, :string
      add :approver_slack_id, :string
      add :approved_at, :timestamptz
      add :denied_at, :timestamptz
      add :expires_at, :timestamptz, null: false
      add :failure_reason, :text

      timestamps(type: :timestamptz)
    end

    # The interactive Slack handler and the pending-page poller both
    # resolve a request by id; the status/expiry window query covers
    # the expiry sweep.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:project_access_requests, [:status, :expires_at])

    create table(:project_access_grants) do
      add :request_id, references(:project_access_requests, on_delete: :delete_all), null: false
      add :requester_email, :string, null: false
      add :account_handle, :string, null: false
      add :tier, :string, null: false
      add :reason, :text, null: false
      add :expires_at, :timestamptz, null: false
      add :status, :string, null: false
      add :revoked_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The pending-page poller fetches the active grant for a request.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:project_access_grants, [:requester_email, :account_handle, :status])

    # One grant per request (defence-in-depth alongside the
    # `SELECT ... FOR UPDATE` on the request row in
    # `TuistOps.ProjectAccess.Approvals.approve/2`).
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:project_access_grants, [:request_id])
  end
end
