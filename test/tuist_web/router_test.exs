defmodule TuistWeb.RouterTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "marketing pages are indexable and followable",
       %{conn: conn} do
    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tags") == ["index, follow"]
    end
  end

  test "app routes are non-indexable and non-followable",
       %{conn: conn} do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])

    %{account: organization_account} =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        customer_id: "customer_id",
        creator: user,
        preload: [:account]
      )

    # When
    conn = conn |> log_in_user(user)

    # Then
    assert conn
           |> get(~p"/#{organization_account.name}/projects")
           |> get_resp_header("x-robots-tags") == [
             "noindex, nofollow"
           ]
  end
end
