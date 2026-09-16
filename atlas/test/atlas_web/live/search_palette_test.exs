defmodule AtlasWeb.SearchPaletteTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Repo
  alias Atlas.Users.User

  test "palette renders in the dashboard layout closed by default", %{conn: conn} do
    user = insert_user!()
    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, ~s(#search-palette[data-open="false"]))
    assert has_element?(view, "#search-palette-input")
  end

  test "searching returns matching accounts as result links", %{conn: conn} do
    user = insert_user!()

    delivery_hero =
      insert_account!(%{
        account_key: "search:delivery_hero",
        name: "Acme",
        primary_domain: "deliveryhero.com",
        segment: :customer
      })

    _other =
      insert_account!(%{
        account_key: "search:other",
        name: "Morgan Stanley",
        primary_domain: "morganstanley.com",
        segment: :lead
      })

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/sales")

    view
    |> form("#search-palette-form", search_palette: %{query: "delivery"})
    |> render_change()

    assert has_element?(
             view,
             ~s(#search-palette a[data-result-link][href="/sales/accounts/#{delivery_hero.id}"])
           )

    refute has_element?(view, ~s(#search-palette [data-part="empty"]))
  end

  test "empty query shows the prompt empty state", %{conn: conn} do
    user = insert_user!()
    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/sales")

    assert has_element?(view, ~s(#search-palette [data-part="empty"]), "Type to search")
  end

  defp insert_user!(email \\ "palette@example.com") do
    %User{}
    |> User.changeset(%{email: email, name: "Palette User"})
    |> Repo.insert!()
  end

  defp insert_account!(attrs) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert!()
  end
end
