defmodule AtlasWeb.PostmortemLive.PublicTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Postmortems
  alias Atlas.Repo
  alias Atlas.Users.User

  defp postmortem do
    user =
      %User{}
      |> User.changeset(%{email: "postmortem-public-#{System.unique_integer([:positive])}@tuist.dev", name: "Author"})
      |> Repo.insert!()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(%{"body" => "# Queue outage\n\nThe queue backed up."}, user)

    postmortem
  end

  test "renders a postmortem by number without a login", %{conn: conn} do
    postmortem = postmortem()

    {:ok, _view, html} = live(conn, ~p"/p/postmortems/#{postmortem.number}")

    assert html =~ "Queue outage"
    assert html =~ "The queue backed up."
  end

  test "redirects a legacy share token to the numbered URL", %{conn: conn} do
    postmortem = postmortem()
    token = Ecto.UUID.generate()
    postmortem |> Ecto.Changeset.change(share_token: token) |> Repo.update!()

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/p/postmortems/#{token}")
    assert to == ~p"/p/postmortems/#{postmortem.number}"
  end

  test "renders not found for an unknown postmortem", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/p/postmortems/999999")

    assert html =~ "This postmortem does not exist."
  end

  test "sends anonymous visitors of the dashboard URL to the public page", %{conn: conn} do
    postmortem = postmortem()

    conn = get(conn, ~p"/engineering/postmortems/#{postmortem.number}")

    assert redirected_to(conn) == ~p"/p/postmortems/#{postmortem.number}"
  end

  test "keeps the dashboard page for signed-in users", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    postmortem = postmortem()

    conn = get(conn, ~p"/engineering/postmortems/#{postmortem.number}")

    assert html_response(conn, 200) =~ ~s(id="share-postmortem")
  end
end
