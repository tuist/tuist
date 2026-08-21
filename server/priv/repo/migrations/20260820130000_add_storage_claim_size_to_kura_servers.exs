defmodule Tuist.Repo.Migrations.AddStorageClaimSizeToKuraServers do
  use Ecto.Migration

  # The regions that size per plan from here on, and the claim every instance in
  # them was carved at while they sized alike. Listed rather than read from the
  # region catalog because the catalog moves in the same change that adds this
  # column, and this has to describe volumes as they already are.
  #
  # Restricted to those regions on purpose. Everywhere else an instance is meant
  # to keep tracking the claim its region declares, and pinning one would freeze
  # it against a region that later declares something different.
  @per_plan_regions ["us-east", "us-west", "eu-central", "ca-east"]
  @claim_carved_at "50Gi"

  # A row in one of these states holds no volume: teardown deleted the
  # StatefulSet and every claim with it. It is pinned when it next has storage
  # to describe, on the cold return or the operator's next install.
  @archived_status 7
  @destroyed_status 4

  # The claim one instance's data volumes were created at. It was a region-wide
  # constant until now; it becomes a property of the instance so a region can
  # size new instances from their account's plan without touching volumes that
  # already exist. The local-path storage class cannot expand a claim, so this
  # may not change under a live instance -- it changes when the storage is
  # recreated (cold return or warm handoff), never in place.
  #
  # The backfill does not correct anything: an instance carrying no claim
  # resolves one from its account's plan, and every instance these regions hold
  # today is enterprise, whose claim is the same 50Gi its volumes were carved
  # at. What it does is stop them resolving it again. Left unpinned they would
  # follow their account's plan on every render, so a downgrade would evict a
  # cache no one asked to lose and an upgrade would try to grow a claim the
  # storage class cannot expand, which wedges the instance's reconcile while it
  # goes on serving. Nothing re-pins a live instance, so rows that miss this
  # never get another chance.
  def up do
    # Nullable with no default, so PostgreSQL records it in table metadata
    # without rewriting existing rows.
    alter table(:kura_servers) do
      add :storage_claim_size, :string
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE kura_servers
    SET storage_claim_size = '#{@claim_carved_at}',
        updated_at = NOW()
    WHERE region IN ('#{Enum.join(@per_plan_regions, "', '")}')
      AND status NOT IN (#{@archived_status}, #{@destroyed_status})
    """)
  end

  def down do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :storage_claim_size
    end
  end
end
