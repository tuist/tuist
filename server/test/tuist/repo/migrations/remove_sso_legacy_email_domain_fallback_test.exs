# SQL only targets a connection-local temporary table inside a sandbox transaction.
# excellent_migrations:safety-assured-for-this-file operation_query operation_config
Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261027150000_remove_sso_legacy_email_domain_fallback.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.RemoveSsoLegacyEmailDomainFallbackTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Ecto.Migration.Runner
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.RemoveSsoLegacyEmailDomainFallback

  test "drops the flag without changing policies or verification, and rolls back with compatibility disabled" do
    Repo.query!("""
    CREATE TEMP TABLE organizations (
      id integer PRIMARY KEY,
      sso_legacy_email_domain_fallback boolean NOT NULL DEFAULT false,
      sso_login_domain_verified_at timestamptz,
      sso_login_domain_last_verified_at timestamptz,
      sso_automatic_enrollment boolean,
      sso_enforced boolean
    )
    """)

    Repo.query!("""
    INSERT INTO pg_temp.organizations VALUES
      (1, true, NULL, NULL, true, true),
      (2, false, '2026-09-01 00:00:00Z', NULL, true, true),
      (3, false, '2026-10-01 00:00:00Z', '2026-10-27 00:00:00Z', false, false)
    """)

    before = policy_rows()
    migrate(:up)

    assert policy_rows() == before

    assert Repo.query!("""
           SELECT attname FROM pg_attribute
           WHERE attrelid = 'pg_temp.organizations'::regclass
             AND attname = 'sso_legacy_email_domain_fallback' AND NOT attisdropped
           """).rows == []

    migrate(:down)

    assert policy_rows() == before

    assert Repo.query!("SELECT sso_legacy_email_domain_fallback FROM pg_temp.organizations ORDER BY id").rows ==
             [[false], [false], [false]]

    migrate(:up)
    assert policy_rows() == before
  end

  defp policy_rows do
    Repo.query!("""
    SELECT id, sso_login_domain_verified_at, sso_login_domain_last_verified_at,
           sso_automatic_enrollment, sso_enforced
    FROM pg_temp.organizations ORDER BY id
    """).rows
  end

  defp migrate(direction) do
    Runner.run(
      Repo,
      Repo.config(),
      20_261_027_150_000,
      RemoveSsoLegacyEmailDomainFallback,
      :forward,
      direction,
      direction,
      prefix: "pg_temp",
      log: false
    )
  end
end
