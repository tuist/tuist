defmodule TuistWeb.LocaleTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  alias Phoenix.LiveView
  alias Tuist.Accounts
  alias TuistWeb.Gettext, as: GettextBackend
  alias TuistWeb.Locale
  alias TuistWeb.Plugs.LocalePlug
  alias TuistTestSupport.Fixtures.AccountsFixtures

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

    test "returns nil for malformed separator-only locales" do
      assert Locale.normalize_locale("-") == nil
      assert Locale.normalize_locale("_") == nil
    end
  end

  describe "locale_from_accept_language/1" do
    test "returns the first supported locale from the browser preference list" do
      assert Locale.locale_from_accept_language("fr-FR,zh-CN;q=0.8,es-ES;q=0.7") == "zh_Hans"
    end

    test "skips malformed tokens and keeps searching" do
      assert Locale.locale_from_accept_language("-,_,es-ES;q=0.7") == "es"
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

    test "uses user's preferred_locale over session locale" do
      user = AccountsFixtures.user_fixture()
      {:ok, user} = Accounts.update_user_preferred_locale(user, "ja")

      socket =
        %LiveView.Socket{}
        |> Phoenix.Component.assign(:current_user, user)

      {:cont, updated_socket} = Locale.on_mount(:assign_locale, %{}, %{"locale" => "es"}, socket)

      assert updated_socket.assigns.locale == "ja"
      assert Gettext.get_locale(GettextBackend) == "ja"
    end

    test "falls back to session locale when preferred_locale is nil" do
      user = AccountsFixtures.user_fixture()

      socket =
        %LiveView.Socket{}
        |> Phoenix.Component.assign(:current_user, user)

      {:cont, updated_socket} = Locale.on_mount(:assign_locale, %{}, %{"locale" => "ko"}, socket)

      assert updated_socket.assigns.locale == "ko"
      assert Gettext.get_locale(GettextBackend) == "ko"
    end

    test "ignores unsupported preferred_locale and falls back to session" do
      user = AccountsFixtures.user_fixture()
      Tuist.Repo.update!(Ecto.Changeset.change(user, preferred_locale: "xx"))
      user = Accounts.get_user_by_id(user.id)

      socket =
        %LiveView.Socket{}
        |> Phoenix.Component.assign(:current_user, user)

      {:cont, updated_socket} = Locale.on_mount(:assign_locale, %{}, %{"locale" => "ru"}, socket)

      assert updated_socket.assigns.locale == "ru"
      assert Gettext.get_locale(GettextBackend) == "ru"
    end

    test "falls back to session locale when no current_user is assigned" do
      {:cont, updated_socket} = Locale.on_mount(:assign_locale, %{}, %{"locale" => "es"}, %LiveView.Socket{})

      assert updated_socket.assigns.locale == "es"
      assert Gettext.get_locale(GettextBackend) == "es"
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
