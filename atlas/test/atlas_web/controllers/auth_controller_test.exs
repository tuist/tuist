defmodule AtlasWeb.AuthControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Repo
  alias Atlas.Users.User

  test "GET /auth/:provider redirects to login when the provider is not configured", %{
    conn: conn
  } do
    conn = get(conn, ~p"/auth/unknown-provider")
    assert redirected_to(conn) == "/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Authentication provider not supported."
  end

  describe "POST /dev/login" do
    setup do
      Application.put_env(:atlas, :dev_routes, true)
      insert_test_user!()
      on_exit(fn -> Application.delete_env(:atlas, :dev_routes) end)
      :ok
    end

    test "redirects to root when no return_to is provided", %{conn: conn} do
      conn = post(conn, ~p"/dev/login", %{})
      assert redirected_to(conn) == "/"
    end

    test "honors a safe local return_to param", %{conn: conn} do
      %Account{id: account_id} =
        %Account{}
        |> Account.changeset(%{
          account_key: "auth-return-to:#{System.unique_integer([:positive])}",
          name: "Return To Customer",
          segment: :customer
        })
        |> Repo.insert!()

      target = "/commercial/sales/accounts/#{account_id}"

      conn = post(conn, ~p"/dev/login", %{"return_to" => target})
      assert redirected_to(conn) == target
    end

    test "refuses to bounce to a non-local return_to", %{conn: conn} do
      conn = post(conn, ~p"/dev/login", %{"return_to" => "//evil.example.com/steal"})
      assert redirected_to(conn) == "/"
    end

    test "refuses a return_to without a leading slash", %{conn: conn} do
      conn = post(conn, ~p"/dev/login", %{"return_to" => "javascript:alert(1)"})
      assert redirected_to(conn) == "/"
    end
  end

  defp insert_test_user! do
    case Repo.get_by(User, email: "test@atlas.dev") do
      nil ->
        %User{}
        |> User.changeset(%{email: "test@atlas.dev", name: "Test User"})
        |> Repo.insert!()

      _existing ->
        :ok
    end
  end
end
