Code.require_file("../../../priv/repo/migrations/20260922170000_preserve_kura_account_identity.exs", __DIR__)

defmodule Tuist.Kura.IdentityMigrationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Repo.Migrations.PreserveKuraAccountIdentity

  setup do
    Repo.query!("CREATE TEMP TABLE accounts (id bigint PRIMARY KEY, name citext, kura_tenant_id citext) ON COMMIT DROP")

    Repo.query!(
      "CREATE TEMP TABLE kura_servers (account_id bigint, provisioner_node_ref text, status integer) ON COMMIT DROP"
    )

    :ok
  end

  test "backfills the original identity after a rename and ignores destroyed workloads" do
    Repo.query!("INSERT INTO accounts VALUES (1, 'renamed', NULL), (2, 'fresh', NULL)")

    Repo.query!(
      "INSERT INTO kura_servers VALUES (1, 'kura-original-ap-southeast-1', 1), (1, 'kura-original-eu-west-1-m', 7), (1, 'legacy-destroyed', 4)"
    )

    backfill()
    assert Repo.query!("SELECT kura_tenant_id FROM accounts ORDER BY id").rows == [["original"], ["fresh"]]
  end

  test "refuses unknown workload names instead of guessing a storage namespace" do
    Repo.query!("INSERT INTO accounts VALUES (1, 'renamed', NULL)")
    Repo.query!("INSERT INTO kura_servers VALUES (1, 'unknown-instance', 1)")
    assert_raise Postgrex.Error, ~r/requires an audit/, &backfill/0
  end

  test "refuses conflicting identities across regions" do
    Repo.query!("INSERT INTO accounts VALUES (1, 'renamed', NULL)")
    Repo.query!("INSERT INTO kura_servers VALUES (1, 'kura-original-eu-west-1', 1), (1, 'kura-renamed-us-east-1', 1)")
    assert_raise Postgrex.Error, ~r/requires an audit/, &backfill/0
  end

  defp backfill do
    Enum.each(PreserveKuraAccountIdentity.backfill_statements(), &Repo.query!/1)
  end
end
