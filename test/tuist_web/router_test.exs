defmodule TuistWeb.RouterTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  alias TuistTestSupport.Fixtures.AccountsFixtures
  use Mimic

  test "marketing pages are non-indexable and non-followable when a production and on-premise environment",
       %{conn: conn} do
    Tuist.Environment |> stub(:on_premise?, fn -> true end)
    Tuist.Environment |> stub(:prod?, fn -> true end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "marketing pages are non-indexable and non-followable when a non-production environment",
       %{conn: conn} do
    Tuist.Environment |> stub(:prod?, fn -> false end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "marketing pages are indexable and followable when a production and non on-premise environment",
       %{conn: conn} do
    Tuist.Environment |> stub(:on_premise?, fn -> false end)
    Tuist.Environment |> stub(:prod?, fn -> true end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["index, follow"]
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
           |> get_resp_header("x-robots-tag") == [
             "noindex, nofollow"
           ]
  end
end
