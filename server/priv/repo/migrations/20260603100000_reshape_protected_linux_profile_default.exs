defmodule Tuist.Repo.Migrations.ReshapeProtectedLinuxProfileDefault do
  use Ecto.Migration

  # The default Linux runner shape moved from 4 vCPU / 16 GB to
  # 2 vCPU / 8 GB. The `20260602103000` backfill seeded every existing
  # account's protected `linux` profile at the old default, so realign
  # those rows. Only the untouched old-default shape is updated
  # (`vcpus = 4 AND memory_gb = 16`); a protected `linux` row at any
  # other shape was deliberately re-sized and is left alone. Safe to run
  # now because the feature has not reached customers yet.
  #
  # Shape values are inlined rather than read through
  # `Tuist.Runners.Catalog.default/0`: migrations run with a slim
  # application boot and must not depend on the runtime catalog.

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_profiles
       SET vcpus = 2, memory_gb = 8, updated_at = NOW()
     WHERE name = 'linux' AND protected = true
       AND vcpus = 4 AND memory_gb = 16
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE runner_profiles
       SET vcpus = 4, memory_gb = 16, updated_at = NOW()
     WHERE name = 'linux' AND protected = true
       AND vcpus = 2 AND memory_gb = 8
    """)
  end
end
