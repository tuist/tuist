defmodule Tuist.Repo.Migrations.BackfillProtectedMacosProfile do
  use Ecto.Migration

  # One-shot backfill: every existing account gets the protected
  # `macos` profile that `Accounts.create_user` /
  # `Accounts.create_organization` now auto-bootstrap. Mirrors the
  # earlier `BackfillProtectedLinuxProfile` migration.
  #
  # Shape + Xcode values are inlined for the same reason the Linux
  # backfill inlined them: migrations run with a slim application
  # boot and the catalog reads its values from runtime env vars
  # that aren't guaranteed to be set at this point. The 6 vCPU /
  # 14 GB M2-L shape is the default macOS shape, and `26.5` is the
  # current default in `runner_macos_xcode_versions`. Re-shaping or
  # re-versioning later is just an `update` from the UI.

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    INSERT INTO runner_profiles (account_id, name, platform, vcpus, memory_gb, xcode_version, protected, inserted_at, updated_at)
    SELECT a.id, 'macos', 'macos', 6, 14, '26.5', true, NOW(), NOW()
      FROM accounts a
     WHERE NOT EXISTS (
       SELECT 1 FROM runner_profiles p
        WHERE p.account_id = a.id AND p.name = 'macos'
     )
    """)
  end

  def down do
    # Only roll back rows this migration could have inserted —
    # never touch a `macos` profile the customer might have
    # subsequently edited or re-created themselves.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    DELETE FROM runner_profiles
     WHERE name = 'macos' AND platform = 'macos' AND protected = true
    """)
  end
end
