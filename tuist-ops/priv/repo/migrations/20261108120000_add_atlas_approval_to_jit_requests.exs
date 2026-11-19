defmodule TuistOps.Repo.Migrations.AddAtlasApprovalToJitRequests do
  use Ecto.Migration

  # Orb thread elevations can be approved in Atlas instead of Slack
  # (`TuistOps.JIT.Approvals.grant_atlas_approved/1`). Those requests
  # have no Slack requester or card, and carry the Atlas approval they
  # spent instead. The unique index keeps one approval to one grant.
  def change do
    alter table(:tailscale_jit_requests) do
      modify :requester_slack_id, :string, null: true, from: {:string, null: false}
      modify :slack_channel_id, :string, null: true, from: {:string, null: false}
      add :atlas_approval_id, :string
    end

    create unique_index(:tailscale_jit_requests, [:atlas_approval_id])
  end
end
