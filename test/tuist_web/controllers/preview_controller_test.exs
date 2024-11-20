defmodule TuistWeb.PreviewControllerTest do
  use TuistWeb.ConnCase, async: true
  use Mimic

  alias Tuist.PreviewsFixtures
  alias Tuist.Storage
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn =
      conn
      |> log_in_user(user)

    %{conn: conn, user: user}
  end

  describe "download_qr_code_svg/2" do
    test "renders a QR code", %{conn: conn} do
      # Given
      preview =
        PreviewsFixtures.preview_fixture(type: :ipa)

      QRCode
      |> stub(:create, fn _ ->
        "qr-code"
      end)

      QRCode
      |> stub(:render, fn _ ->
        {:ok, "<svg></svg>"}
      end)

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/qr-code.svg")

      # Then
      assert response(conn, 200) =~ "<svg"
    end
  end

  describe "download_qr_code_png/2" do
    test "renders a QR code", %{conn: conn} do
      # Given
      preview =
        PreviewsFixtures.preview_fixture(type: :ipa)

      QRCode
      |> stub(:create, fn _ ->
        "qr-code"
      end)

      QRCode
      |> stub(:render, fn _, _ ->
        {:ok, "base64png"}
      end)

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/qr-code.png")

      # Then
      assert response(conn, 200) =~ "base64png"
    end
  end

  describe "download_preview/2" do
    test "redirects to presigned preview download url", %{conn: conn} do
      # Given
      preview =
        PreviewsFixtures.preview_fixture()

      Storage
      |> stub(:generate_download_url, fn _, _ -> "https://download-url.com" end)

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/download")

      # Then
      assert redirected_to(conn) == "https://download-url.com"
    end
  end

  describe "manifest/2" do
    test "returns manifest.plist", %{conn: conn} do
      # Given
      preview =
        PreviewsFixtures.preview_fixture(
          project: ProjectsFixtures.project_fixture(),
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        )

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/manifest.plist")

      # Then
      plist_response = response(conn, 200)

      assert plist_response =~ "<string>com.tuist.app</string>"
      assert plist_response =~ "<string>1.0.0</string>"
    end

    test "raises not found error when the preview does not exist", %{conn: conn} do
      # When / Then
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        conn
        |> get(
          ~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9/manifest.plist"
        )
      end
    end
  end

  describe "download_archive/2" do
    test "returns archive object", %{conn: conn} do
      # Given
      preview =
        PreviewsFixtures.preview_fixture(
          project: ProjectsFixtures.project_fixture(),
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        )

      Storage
      |> stub(:get_object_as_string, fn _ -> "ipa-contents" end)

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/app.ipa")

      # Then
      assert response(conn, 200) =~ "ipa-contents"
    end
  end

  describe "download_icon/2" do
    test "streams the icon image", %{conn: conn} do
      # Given
      preview =
        PreviewsFixtures.preview_fixture(type: :ipa)

      icon_content = "icon-content"

      Storage
      |> stub(:stream_object, fn _ ->
        Stream.map([icon_content], fn chunk -> chunk end)
      end)

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}/icon.png")

      # Then
      assert response(conn, 200) =~ icon_content
      assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
    end

    test "raises not found error when the preview does not exist", %{conn: conn} do
      # When / Then
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        conn
        |> get(
          ~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9/icon.png"
        )
      end
    end
  end
end
