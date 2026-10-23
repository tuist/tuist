defmodule TuistWeb.Noora.NooraLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

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
