defmodule TuistWeb.OpsDatabaseTableLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    Mimic.stub(Accounts, :tuist_operator?, fn _ -> true end)
    %{conn: log_in_user(conn, user)}
  end

  test "offers only non-credential columns for sorting and filtering", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/ops/db/tables/public/users?sort=encrypted_password")
    document = Floki.parse_document!(html)

    sort_items =
      document |> Floki.find(~s(a[data-part=item][href*="sort="])) |> Enum.flat_map(&Floki.attribute(&1, "data-value"))

    filter_items = document |> Floki.find("span[data-part=item]") |> Enum.flat_map(&Floki.attribute(&1, "data-value"))

    for items <- [sort_items, filter_items] do
      assert "email" in items
      assert "credentials_revoked_at" in items
      refute "encrypted_password" in items
    end

    # The URL's credential sort falls back to the default column.
    selected =
      document
      |> Floki.find(~s(a[data-part=item][data-selected][href*="sort="]))
      |> Enum.flat_map(&Floki.attribute(&1, "data-value"))

    assert selected == ["id"]
  end
end
