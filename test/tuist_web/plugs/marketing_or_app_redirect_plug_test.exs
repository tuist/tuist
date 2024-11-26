defmodule TuistWeb.MarketingOrAppRedirectPlugTest do
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures
  use Plug.Test
  use TuistWeb.ConnCase
  alias TuistWeb.MarketingOrAppRedirectPlug
  alias TuistWeb.Authentication
  use Mimic

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    %{
      current_user: user,
      conn: conn,
      plug_opts: MarketingOrAppRedirectPlug.init(%{})
    }
  end

  describe "/ path, no authenticated user, and on-premise" do
    test "redirects to the login route", %{
      current_user: current_user,
      plug_opts: plug_opts,
      conn: conn
    } do
      # Given
      ProjectsFixtures.project_fixture(account_id: current_user.account.id)
      Tuist.Environment |> stub(:on_premise?, fn -> true end)

      # When
      conn = conn |> MarketingOrAppRedirectPlug.call(plug_opts)

      # Then
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "/ path, authenticated user, and on-premise" do
    test "redirects to the user's account projects page when there are no projects ", %{
      current_user: current_user,
      plug_opts: plug_opts,
      conn: conn
    } do
      # Given
      Tuist.Environment |> stub(:on_premise?, fn -> true end)

      # When
      conn =
        conn
        |> Authentication.put_current_user(current_user)
        |> MarketingOrAppRedirectPlug.call(plug_opts)

      # Then
      assert redirected_to(conn) == "/#{current_user.account.name}/projects"
    end
  end

  describe "/ path, authenticated user, and not on-premise" do
    test "returns the same connection", %{
      current_user: current_user,
      plug_opts: plug_opts,
      conn: conn
    } do
      # Given
      Tuist.Environment |> stub(:on_premise?, fn -> false end)

      conn =
        conn
        |> Authentication.put_current_user(current_user)

      # When
      got =
        conn
        |> MarketingOrAppRedirectPlug.call(plug_opts)

      # Then
      assert got == conn
    end
  end

  describe "/ path, non-authenticated user, and not on-premise" do
    test "returns the same connection", %{
      plug_opts: plug_opts,
      conn: conn
    } do
      # Given
      Tuist.Environment |> stub(:on_premise?, fn -> false end)

      # When
      got =
        conn
        |> MarketingOrAppRedirectPlug.call(plug_opts)

      # Then
      assert got == conn
    end
  end
end
