Code.require_file("../../../priv/repo/migrations/20260922200000_expire_kura_client_aliases.exs", __DIR__)

defmodule Tuist.Kura.ClientAliasExpiryMigrationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Repo.Migrations.ExpireKuraClientAliases

  test "existing historical URLs get 90 days from migration while current names never expire" do
    Repo.query!("CREATE TEMP TABLE accounts (id bigint PRIMARY KEY, name citext) ON COMMIT DROP")

    Repo.query!(
      "CREATE TEMP TABLE account_handle_reservations (name citext, account_id bigint, client_url_expires_at timestamptz) ON COMMIT DROP"
    )

    Repo.query!("INSERT INTO accounts VALUES (1, 'current'), (2, 'Fresh')")

    Repo.query!(
      "INSERT INTO account_handle_reservations (name, account_id) VALUES ('original', 1), ('middle', 1), ('current', 1), ('fresh', 2)"
    )

    Repo.query!(ExpireKuraClientAliases.backfill_statement())

    assert Repo.query!(
             "SELECT name FROM account_handle_reservations WHERE client_url_expires_at = now() + interval '90 days' ORDER BY name"
           ).rows == [["middle"], ["original"]]

    assert Repo.query!("SELECT name FROM account_handle_reservations WHERE client_url_expires_at IS NULL ORDER BY name").rows ==
             [["current"], ["fresh"]]
  end
end
