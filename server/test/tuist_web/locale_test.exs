defmodule TuistWeb.LocaleTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  alias Phoenix.LiveView
  alias TuistWeb.Gettext, as: GettextBackend
  alias TuistWeb.Locale
  alias TuistWeb.Plugs.LocalePlug

  describe "normalize_locale/1" do
    test "normalizes language and region locales" do
      assert Locale.normalize_locale("es-ES") == "es"
      assert Locale.normalize_locale("ru-RU") == "ru"
    end

    test "normalizes chinese script variants" do
      assert Locale.normalize_locale("zh-CN") == "zh_Hans"
      assert Locale.normalize_locale("zh-Hant-TW") == "zh_Hant"
    end

    test "normalizes cantonese locales into the supported script locale" do
      assert Locale.normalize_locale("yue-HK") == "yue_Hant"
    end

    test "returns nil for unsupported locales" do
      assert Locale.normalize_locale("fr-FR") == nil
      assert Locale.normalize_locale("pt-BR") == nil
    end
  end

  describe "locale_from_accept_language/1" do
    test "returns the first supported locale from the browser preference list" do
      assert Locale.locale_from_accept_language("fr-FR,zh-CN;q=0.8,es-ES;q=0.7") == "zh_Hans"
    end
  end

  describe "on_mount :assign_locale" do
    test "assigns locale from the session when available" do
      {:cont, updated_socket} = Locale.on_mount(:assign_locale, %{}, %{"locale" => "es"}, %LiveView.Socket{})

      assert updated_socket.assigns.locale == "es"
      assert Gettext.get_locale(GettextBackend) == "es"
    end

    test "assigns locale from connect params when the session has no locale" do
      stub(LiveView, :get_connect_params, fn _socket ->
        %{"user_locale" => "zh-CN,es-ES;q=0.8"}
      end)

      {:cont, updated_socket} = Locale.on_mount(:assign_locale, %{}, %{}, %LiveView.Socket{})

      assert updated_socket.assigns.locale == "zh_Hans"
      assert Gettext.get_locale(GettextBackend) == "zh_Hans"
    end
  end

  describe "LocalePlug" do
    test "stores the normalized locale from the request headers in the session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_req_header("accept-language", "es-ES,es;q=0.9,en;q=0.8")
        |> LocalePlug.call([])

      assert get_session(conn, :locale) == "es"
      assert Gettext.get_locale(GettextBackend) == "es"
    end

    test "falls back to the existing session locale when headers are not present", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{locale: "ja"})
        |> LocalePlug.call([])

      assert get_session(conn, :locale) == "ja"
      assert Gettext.get_locale(GettextBackend) == "ja"
    end
  end
end
