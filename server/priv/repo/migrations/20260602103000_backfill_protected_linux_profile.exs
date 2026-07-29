defmodule Tuist.Repo.Migrations.BackfillProtectedLinuxProfile do
  use Ecto.Migration

  # One-shot backfill: every existing account gets the protected
  # `linux` profile that `Accounts.create_user` /
  # `Accounts.create_organization` now auto-bootstrap. Accounts that
  # already have a row named `linux` (the staging operator created
  # one by hand before this lands) are left untouched.
  #
  # Shape values are inlined instead of read through
  # `Tuist.Runners.Catalog.default/0`: migrations run with a slim
  # application boot, the catalog reads `TUIST_RUNNER_LINUX_SHAPES`
  # via `runtime.exs` which isn't guaranteed at this point, and the
  # 4 vCPU / 16 GB default has been the same on every managed env
  # since the shape catalog landed. Re-shaping later is just an
  # `update` from the UI.

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    INSERT INTO runner_profiles (account_id, name, vcpus, memory_gb, protected, inserted_at, updated_at)
    SELECT a.id, 'linux', 4, 16, true, NOW(), NOW()
      FROM accounts a
     WHERE NOT EXISTS (
       SELECT 1 FROM runner_profiles p
        WHERE p.account_id = a.id AND p.name = 'linux'
     )
    """)
  end

  def down do
    # Only roll back rows this migration could have inserted —
    # never touch a `linux` profile the customer might have
    # subsequently edited or re-created themselves.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    DELETE FROM runner_profiles
     WHERE name = 'linux' AND protected = true
    """)
  end
end
