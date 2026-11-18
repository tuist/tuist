defmodule TuistWeb.Noora.NooraLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Noora.Pages
  alias TuistWeb.Noora.Tokens

  test "the introduction lists every page and stays out of search indexes", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/noora")

    assert html =~ ~s(<meta name="robots" content="noindex, nofollow")

    for page <- Pages.all() do
      assert has_element?(view, ~s(#noora-docs-nav a[href="#{Pages.path(page)}"]), page.nav_title())
    end
  end

  test "does not redirect to a localized route", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "ko-KR,ko;q=0.9")

    assert {:ok, _view, _html} = live(conn, ~p"/noora/button")
  end

  test "raises a not found error for an unknown page", %{conn: conn} do
    assert_raise NotFoundError, fn -> live(conn, ~p"/noora/unknown") end
  end

  test "redirects the former status badge page to the badge page", %{conn: conn} do
    conn = get(conn, "/noora/status-badge")

    assert redirected_to(conn, 301) == "/noora/badge"
  end

  test "redirects the former inline and button dropdown pages to the dropdown page", %{conn: conn} do
    for path <- ["/noora/inline-dropdown", "/noora/button-dropdown"] do
      assert redirected_to(get(conn, path), 301) == "/noora/dropdown"
    end
  end

  test "redirects the former neutral button page to the button page", %{conn: conn} do
    assert redirected_to(get(conn, "/noora/neutral-button"), 301) == "/noora/button"
  end

  test "documents the ghost button on the button page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/noora/button")

    assert has_element?(view, ".noora-ghost-button[aria-label='Copy command']")
    assert has_element?(view, ".noora-ghost-button[data-with-label]", "Copy link")
  end

  test "documents the spinner, on its own and inside buttons and badges", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/noora/spinner")

    assert has_element?(view, "noora-spinner[role=status][aria-label='Loading']")
    assert has_element?(view, ".noora-button > noora-spinner")
    assert has_element?(view, ".noora-badge [data-part=icon] > noora-spinner")
  end

  test "documents the status badge on the badge page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/noora/badge")

    assert has_element?(view, ".noora-status-badge[data-status=success]", "Passed")
  end

  test "shows each example's source next to its live preview", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/noora/button")

    assert has_element?(view, "#variants [data-part=preview] button.noora-button[data-variant=primary]", "Primary")

    assert view |> element("#variants-code template[data-part=copy-source]") |> render() =~
             ~s(&lt;.button label=&quot;Primary&quot; variant=&quot;primary&quot; /&gt;)
  end

  test "documents the attributes and slots declared by the component", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/noora/button")

    assert has_element?(view, "#api-button-attributes td [data-part=label]", "variant")
    assert has_element?(view, "#api-button-attributes [data-part=values] code", ~s("destructive"))
    assert has_element?(view, "#api-button-slots td [data-part=label]", ":icon_left")
  end

  for page <- Pages.all() do
    @page page

    test "renders #{inspect(page)}", %{conn: conn} do
      {:ok, view, _html} = live(conn, Pages.path(@page))

      assert has_element?(view, "[data-part=page-header] h1", @page.title())

      for example <- @page.examples() do
        assert has_element?(view, "##{example.id} [data-part=preview]")
      end
    end
  end

  test "lists every icon on the icons page" do
    html = render_component(&Pages.Icons.content/1, %{})

    for name <- Noora.Icon.names() do
      assert html =~ ~s(title="#{name}")
    end
  end

  describe "team pages" do
    test "aren't listed, and ask visitors to sign in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/noora")

      refute Pages.Icons in Pages.all()
      refute has_element?(view, ~s(#noora-docs-nav a[href="/noora/icons"]))
      assert has_element?(view, ~s(a[href="/docs/login?return_to=%2Fnoora"]), "Sign in")

      assert {:error, {:redirect, %{to: "/docs/login?return_to=%2Fnoora%2Ficons"}}} =
               live(conn, ~p"/noora/icons")
    end

    test "don't exist for people outside the Tuist team", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      stub(Accounts, :tuist_operator?, fn _user -> false end)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/noora")

      refute has_element?(view, ~s(#noora-docs-nav a[href="/noora/icons"]))
      assert has_element?(view, "#noora-docs-account-dropdown")
      assert_raise NotFoundError, fn -> live(conn, ~p"/noora/icons") end
    end

    test "are listed and open for the Tuist team", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      stub(Accounts, :tuist_operator?, fn _user -> true end)
      conn = log_in_user(conn, user)

      # The credit card input artwork carries its own clip and filter ids, so
      # showing it at every size repeats them.
      {:ok, view, _html} = live(conn, ~p"/noora/icons", on_error: :warn)

      assert has_element?(view, ~s(#noora-docs-nav a[href="/noora/icons"]), "Icons")
      assert has_element?(view, "[data-part=page-header] h1", "Icons")
    end
  end

  describe "tokens" do
    test "reads top-level declarations grouped by their section comment" do
      assert %{name: "--noora-spacing-6", value: "1rem"} =
               Enum.find(Tokens.section("Spacing"), &(&1.name == "--noora-spacing-6"))

      assert Enum.all?(Tokens.section("Radius"), &String.starts_with?(&1.name, "--noora-radius-"))
    end

    test "joins values declared across several lines" do
      token = Enum.find(Tokens.all(), &(&1.name == "--noora-surface-background-primary"))

      assert token.value =~ ~r/^light-dark\(\s*var\(--noora-neutral-light-50\),\s*var\(--noora-neutral-dark-1200\)\s*\)$/
    end
  end
end
