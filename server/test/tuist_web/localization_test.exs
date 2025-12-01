defmodule TuistWeb.Marketing.LocalizationTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  # alias TuistWeb.Marketing.Localization

  # describe "plug put_locale" do
  #   test "returns the same connection if the assigns has no locale", %{conn: conn} do
  #     # Given
  #     plug_opts = Localization.init(:put_locale)

  #     # When
  #     got = Localization.call(conn, plug_opts)

  #     # Then
  #     assert got == conn
  #   end

  #   test "sets the locale in the session and configures Gettext with it", %{conn: conn} do
  #     # Given
  #     plug_opts = Localization.init(:put_locale)
  #     conn = conn |> Phoenix.ConnTest.init_test_session(%{}) |> put_private(:locale, "ja")

  #     # When
  #     conn = Localization.call(conn, plug_opts)

  #     # Then
  #     assert Gettext.get_locale() == "ja"
  #     assert get_session(conn, :locale) == "ja"
  #   end
  # end

  # describe "plug redirect_to_localized_route" do
  #   test "doesn't redirect to the localized route based on the accept-language header when the disable_locale_redirect=true query param is present",
  #        %{conn: conn} do
  #     # Given
  #     plug_opts = Localization.init(:redirect_to_localized_route)

  #     conn =
  #       conn
  #       |> put_private(:locale, "en")
  #       |> put_req_header("accept-language", "ja")

  #     conn = %{conn | query_params: %{"disable_locale_redirect" => "true"}}

  #     # When
  #     got = Localization.call(conn, plug_opts)

  #     # Then
  #     assert got == conn
  #   end

  #   test "redirects to the localized route based on the accept-language header when on English pages",
  #        %{conn: conn} do
  #     # Given
  #     plug_opts = Localization.init(:redirect_to_localized_route)

  #     conn =
  #       conn
  #       |> put_private(:locale, "en")
  #       |> put_req_header("accept-language", "ja")

  #     # When
  #     got = Localization.call(conn, plug_opts)

  #     # Then
  #     assert redirected_to(got, 301) =~ Path.join("/ja", conn.request_path)
  #   end

  #   test "doesn't redirect to English when accessing a localized route from a browser with English as a language",
  #        %{
  #          conn: conn
  #        } do
  #     # Given
  #     plug_opts = Localization.init(:redirect_to_localized_route)

  #     conn =
  #       conn
  #       |> put_private(:locale, "ja")
  #       |> put_req_header("accept-language", "en")

  #     # When
  #     got = Localization.call(conn, plug_opts)

  #     # Then
  #     assert got == conn
  #   end

  #   test "doesn't redirect if the accept-language locale matches the page locale", %{conn: conn} do
  #     # Given
  #     plug_opts = Localization.init(:redirect_to_localized_route)

  #     conn =
  #       conn
  #       |> put_private(:locale, "en")
  #       |> put_req_header("accept-language", "en")

  #     # When
  #     got = Localization.call(conn, plug_opts)

  #     # Then
  #     assert got == conn
  #   end

  #   test "doesn't redirect when on non-English localized pages even if browser language differs",
  #        %{conn: conn} do
  #     # Given
  #     plug_opts = Localization.init(:redirect_to_localized_route)

  #     conn =
  #       conn
  #       |> put_private(:locale, "ja")
  #       |> put_req_header("accept-language", "ko")

  #     # When
  #     got = Localization.call(conn, plug_opts)

  #     # Then
  #     assert got == conn
  #   end
  # end

  # describe "on_mount" do
  #   test "puts the session's locale in Gettext" do
  #     # Given
  #     params = %{}
  #     session = %{"locale" => "ja"}
  #     socket = %{}

  #     # When/Then
  #     assert Localization.on_mount(:default, params, session, socket) == {:cont, socket}
  #     assert Gettext.get_locale() == "ja"
  #   end
  # end

  # describe "localized_href" do
  #   test "localizes docs.tuist.dev URLs with current locale" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/guides/features/projects")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ko/guides/features/projects"
  #   end

  #   test "replaces existing locale in docs.tuist.dev URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ja")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/ko/guides/features/projects")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ja/guides/features/projects"
  #   end

  #   test "handles docs.tuist.dev URLs with English locale" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/en/guides/features/projects")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ko/guides/features/projects"
  #   end

  #   test "handles docs.tuist.dev root path" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ja")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ja/"
  #   end

  #   test "localizes relative marketing URLs for non-English locales" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("/pricing")

  #     # Then
  #     assert result == "/ko/pricing"
  #   end

  #   test "does not localize relative marketing URLs for English locale" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "en")

  #     # When
  #     result = Localization.localized_href("/pricing")

  #     # Then
  #     assert result == "/pricing"
  #   end

  #   test "returns external URLs as-is" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("https://slack.tuist.dev")

  #     # Then
  #     assert result == "https://slack.tuist.dev"
  #   end

  #   test "returns mailto links as-is" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ja")

  #     # When
  #     result = Localization.localized_href("mailto:contact@tuist.dev")

  #     # Then
  #     assert result == "mailto:contact@tuist.dev"
  #   end

  #   test "preserves query strings in docs URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/guides?section=features")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ko/guides?section=features"
  #   end

  #   test "preserves fragments in docs URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ja")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/guides#features")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ja/guides#features"
  #   end
  # end

  # describe "localized_href/2 with target locale" do
  #   test "localizes to target locale for docs URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "en")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/guides/features", "ko")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ko/guides/features"
  #   end

  #   test "switches locale in docs URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ja")

  #     # When
  #     result = Localization.localized_href("https://docs.tuist.dev/ja/guides/features", "ko")

  #     # Then
  #     assert result == "https://docs.tuist.dev/ko/guides/features"
  #   end

  #   test "localizes current page to target locale for relative URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "en")

  #     # When
  #     result = Localization.localized_href("/pricing", "ja")

  #     # Then
  #     assert result == "/ja/pricing"
  #   end

  #   test "switches locale for already localized relative URLs" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("/ko/pricing", "ja")

  #     # Then
  #     assert result == "/ja/pricing"
  #   end

  #   test "removes locale prefix when switching to English" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ja")

  #     # When
  #     result = Localization.localized_href("/ja/pricing", "en")

  #     # Then
  #     assert result == "/pricing"
  #   end

  #   test "handles root path switching to non-English locale" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "en")

  #     # When
  #     result = Localization.localized_href("/", "ko")

  #     # Then
  #     assert result == "/ko"
  #   end

  #   test "handles localized root path switching to English" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "ko")

  #     # When
  #     result = Localization.localized_href("/ko", "en")

  #     # Then
  #     assert result == "/"
  #   end

  #   test "preserves query strings when switching locales" do
  #     # Given
  #     Gettext.put_locale(TuistWeb.Gettext, "en")

  #     # When
  #     result = Localization.localized_href("/pricing?plan=pro", "ja")

  #     # Then
  #     assert result == "/ja/pricing?plan=pro"
  #   end
  # end

  # describe "current_path" do
  #   test "returns current_path from assigns" do
  #     # Given
  #     assigns = %{current_path: "/pricing"}

  #     # When
  #     result = Localization.current_path(assigns)

  #     # Then
  #     assert result == "/pricing"
  #   end

  #   test "returns default path when current_path not in assigns" do
  #     # Given
  #     assigns = %{}

  #     # When
  #     result = Localization.current_path(assigns)

  #     # Then
  #     assert result == "/"
  #   end
  # end
end
