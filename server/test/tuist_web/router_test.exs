defmodule TuistWeb.RouterTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "marketing pages are non-indexable and non-followable when a production and on-premise environment",
       %{conn: conn} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
    stub(Tuist.Environment, :prod?, fn -> true end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "marketing pages are non-indexable and non-followable when a non-production environment",
       %{conn: conn} do
    stub(Tuist.Environment, :prod?, fn -> false end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "marketing pages are indexable and followable when a production and non on-premise environment",
       %{conn: conn} do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Environment, :prod?, fn -> true end)

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
    conn = log_in_user(conn, user)

    # Then
    assert conn
           |> get(~p"/#{organization_account.name}/projects")
           |> get_resp_header("x-robots-tag") == [
             "noindex, nofollow"
           ]
  end

  test "legacy docs routes redirect to the locale-first docs routes", %{conn: conn} do
    conn = get(conn, "/docs/en/guides/install-tuist?utm_source=test")

    assert redirected_to(conn, 301) == "/en/docs/guides/install-tuist?utm_source=test"
  end

  test "locale-first docs routes render documentation pages", %{conn: conn} do
    assert conn
           |> get("/en/docs/guides/install-tuist")
           |> html_response(200) =~ "Install Tuist"
  end
end
