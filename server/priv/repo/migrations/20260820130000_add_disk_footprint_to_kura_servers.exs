defmodule Tuist.Repo.Migrations.AddDiskFootprintToKuraServers do
  use Ecto.Migration

  # Regions whose instances were sized alike until this change, and the
  # footprint they were sized at. Frozen here rather than read from the region
  # catalog: the catalog moves in the same change that adds these columns, and
  # these rows still hold the volumes the old constants carved.
  @sized_alike_regions ["us-east", "us-west", "eu-central", "ca-east"]
  @legacy_claim_size "50Gi"
  @legacy_replicas 2

  # A row in one of these states holds no volume: teardown deleted the
  # StatefulSet and every claim with it. It is pinned when it next has storage
  # to describe, on the cold return or the operator's next install.
  @archived_status 7
  @destroyed_status 4

  # What one instance's data volumes were created as: the claim each replica
  # holds and how many replicas hold one. Both were region-wide constants until
  # now; both become properties of the instance so a region can size new
  # instances from their account's plan without touching volumes that already
  # exist. The local-path storage class cannot expand a claim and retains a
  # scaled-away replica's directory, so neither value may change under a live
  # instance -- it changes when the storage is recreated (cold return or warm
  # handoff), never in place.
  def up do
    # Nullable with no default, so PostgreSQL records both in table metadata
    # without rewriting existing rows.
    alter table(:kura_servers) do
      add :storage_claim_size, :string
      add :storage_replicas, :integer
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE kura_servers
    SET storage_claim_size = '#{@legacy_claim_size}',
        storage_replicas = #{@legacy_replicas},
        updated_at = NOW()
    WHERE region IN ('#{Enum.join(@sized_alike_regions, "', '")}')
      AND status NOT IN (#{@archived_status}, #{@destroyed_status})
    """)
  end

  def down do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :storage_claim_size
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :storage_replicas
    end
  end
end
