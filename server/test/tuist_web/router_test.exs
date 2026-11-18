defmodule TuistWeb.RouterTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "verified legacy URLs redirect permanently with their raw query", %{conn: conn} do
    for {old_path, destination} <- [
          {"/es/build-insights", "/es/docs/guides/features/build-insights"},
          {"/ko/flaky-tests", "/ko/tests"},
          {"/zh_Hant/selective-testing", "/zh_Hant/docs/guides/features/selective-testing"},
          {"/blog/2025/11/27/teaching-ai-to-r", "/blog/2025/11/27/teaching-ai-to-read-xcode-builds"},
          {"/pt/docs/guides/features/projects/dependencies", "/en/docs/guides/features/projects/dependencies"},
          {"/pt/docs/guides/features/projects/synthesized-files", "/en/docs/guides/features/projects/synthesized-files"},
          {"/pt/docs/guides/develop/projects/adoption/migrate/swift-package",
           "/en/docs/guides/features/projects/adoption/migrate/swift-package"},
          {"/ar/docs/references/examples/generated_app_with_build_rules",
           "/en/docs/references/examples/generated-projects/generated_app_with_build_rules"}
        ],
        query <- ["", "?utm_source=audit&x=a%2Fb&x=c+d"] do
      assert conn |> get(old_path <> query) |> redirected_to(301) == destination <> query
      assert conn |> head(old_path <> query) |> redirected_to(301) == destination <> query
    end
  end

  test "blog pages allow privacy-enhanced YouTube embeds and fullscreen without enabling unrelated features",
       %{conn: conn} do
    conn = get(conn, ~p"/blog")

    assert [policy] = get_resp_header(conn, "content-security-policy")

    assert policy
           |> String.split(";")
           |> Enum.find(&String.starts_with?(&1, "frame-src "))
           |> String.split()
           |> Enum.member?("https://www.youtube-nocookie.com")

    assert [permissions] = get_resp_header(conn, "permissions-policy")
    permissions = String.split(permissions, ", ")

    assert ~s|fullscreen=(self "https://www.youtube-nocookie.com")| in permissions

    for feature <- ~w(autoplay camera encrypted-media microphone picture-in-picture) do
      assert "#{feature}=()" in permissions
    end
  end

  test "marketing pages are non-indexable and non-followable when a production and on-premise environment",
       %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> false end)
    stub(Environment, :prod?, fn -> true end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "marketing pages are non-indexable and non-followable when a non-production environment",
       %{conn: conn} do
    stub(Environment, :prod?, fn -> false end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      assert conn |> get(route) |> get_resp_header("x-robots-tag") == ["noindex, nofollow"]
    end
  end

  test "marketing pages are indexable and followable when a production and non on-premise environment",
       %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :prod?, fn -> true end)

    for route <- [~p"/blog", ~p"/about", ~p"/pricing", ~p"/terms", ~p"/blog"] do
      response_conn = get(conn, route)
      assert get_resp_header(response_conn, "x-robots-tag") == ["index, follow"]
      assert get_resp_header(response_conn, "x-tuist-public") == ["1"]
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
    query = "?utm_source=test&filter=a%2Fb&filter=c+d"

    for {old_path, destination} <- [
          {"/docs/en/guides/install-tuist", "/en/docs/guides/install-tuist"},
          {"/docs/en/guides/features/bundle-size", "/en/docs/guides/features/bundle-insights"}
        ] do
      assert conn |> get(old_path <> query) |> redirected_to(301) == destination <> query
    end
  end

  test "bare docs routes redirect to the English docs overview", %{conn: conn} do
    assert conn |> get("/docs") |> redirected_to(301) == "/en/docs"
    assert conn |> get("/docs/") |> redirected_to(301) == "/en/docs"
  end

  test "the retired flaky-tests and test-insights pages redirect to the tests page", %{conn: conn} do
    assert conn |> get("/flaky-tests") |> redirected_to(301) == "/tests"
    assert conn |> get("/test-insights?utm_source=test") |> redirected_to(301) == "/tests?utm_source=test"
  end

  test "locale-first docs routes render documentation pages", %{conn: conn} do
    assert conn
           |> get("/en/docs/guides/install-tuist")
           |> html_response(200) =~ "Install Tuist"
  end

  test "FunWithFlags UI assets are served without triggering CSRF cross-origin check",
       %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Tuist.Accounts, :tuist_operator?, fn _ -> true end)

    conn =
      conn
      |> log_in_user(user)
      |> get("/ops/flags/assets/details.js")

    assert conn.status == 200

    assert conn
           |> get_resp_header("content-type")
           |> Enum.any?(&String.starts_with?(&1, ~w(text/javascript application/javascript)))
  end
end
