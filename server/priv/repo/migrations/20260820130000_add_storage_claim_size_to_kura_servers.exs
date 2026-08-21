defmodule Tuist.Repo.Migrations.AddStorageClaimSizeToKuraServers do
  use Ecto.Migration

  # The claim one instance's data volumes were created at. It was a region-wide
  # constant until now; it becomes a property of the instance so a region can
  # size new instances from their account's plan without touching volumes that
  # already exist. The local-path storage class cannot expand a claim, so this
  # may not change under a live instance -- it changes when the storage is
  # recreated (cold return or warm handoff), never in place.
  #
  # Nothing is backfilled. An instance carrying no claim resolves one from its
  # account's plan, and every instance provisioned before this is enterprise,
  # whose claim is the same 50Gi its volumes were carved at, so writing that
  # value would only restate what already renders. What it would additionally do
  # is stop those rows following their plan, and there is nothing to protect
  # them from: enterprise is the top plan, so the only move available to them is
  # a downgrade, which is a shrink, and a shrink leaves the volume alone and
  # lets the ring evict down to its new budget.
  def change do
    # Nullable with no default, so PostgreSQL records it in table metadata
    # without rewriting existing rows.
    alter table(:kura_servers) do
      add :storage_claim_size, :string
    end
  end
end
