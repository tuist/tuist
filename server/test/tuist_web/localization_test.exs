defmodule TuistWeb.Marketing.LocalizationTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Marketing.Localization

  describe "plug put_locale" do
    test "returns the same connection if the assigns has no locale", %{conn: conn} do
      # Given
      plug_opts = Localization.init(:put_locale)

      # When
      got = Localization.call(conn, plug_opts)

      # Then
      assert got == conn
    end

    test "sets the locale in the session and configures Gettext with it", %{conn: conn} do
      # Given
      plug_opts = Localization.init(:put_locale)
      conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> put_private(:locale, "ja")

      # When
      conn = Localization.call(conn, plug_opts)

      # Then
      assert Gettext.get_locale() == "ja"
      assert get_session(conn, :locale) == "ja"
    end
  end

  describe "plug redirect_to_localized_route" do
    test "doesn't redirect to the localized route based on the accept-language header when the disable_locale_redirect=true query param is present",
         %{conn: conn} do
      # Given
      plug_opts = Localization.init(:redirect_to_localized_route)

      conn =
        conn
        |> put_private(:locale, "en")
        |> put_req_header("accept-language", "ja")

      conn = %{conn | query_params: %{"disable_locale_redirect" => "true"}}

      # When
      got = Localization.call(conn, plug_opts)

      # Then
      assert got == conn
    end

    test "redirects to the localized route based on the accept-language header", %{conn: conn} do
      # Given
      plug_opts = Localization.init(:redirect_to_localized_route)

      conn =
        conn
        |> put_private(:locale, "en")
        |> put_req_header("accept-language", "ja")

      # When
      got = Localization.call(conn, plug_opts)

      # Then
      assert redirected_to(got, 301) =~ Path.join("/ja", conn.request_path)
    end

    test "redirects to English when accessing a localized route from a browser with English as a language",
         %{
           conn: conn
         } do
      # Given
      plug_opts = Localization.init(:redirect_to_localized_route)

      conn =
        conn
        |> put_private(:locale, "ja")
        |> put_req_header("accept-language", "en")

      # When
      got = Localization.call(conn, plug_opts)

      # Then
      assert redirected_to(got, 301) =~ Path.join("/", conn.request_path)
    end

    test "doesn't redirect if the accept-language locale matches the assign", %{conn: conn} do
      # Given
      plug_opts = Localization.init(:redirect_to_localized_route)

      conn =
        conn
        |> put_private(:locale, "en")
        |> put_req_header("accept-language", "en")

      # When
      got = Localization.call(conn, plug_opts)

      # Then
      assert got == conn
    end
  end

  describe "on_mount" do
    test "puts the session's locale in Gettext" do
      # Given
      params = %{}
      session = %{"locale" => "ja"}
      socket = %{}

      # When/Then
      assert Localization.on_mount(:default, params, session, socket) == {:cont, socket}
      assert Gettext.get_locale() == "ja"
    end
  end
end
