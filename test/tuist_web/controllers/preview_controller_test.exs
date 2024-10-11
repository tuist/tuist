defmodule TuistWeb.PreviewControllerTest do
  use TuistWeb.ConnCase, async: true
  use Mimic

  alias Tuist.Storage
  alias Tuist.Previews
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    conn =
      conn
      |> log_in_user(user)

    %{conn: conn, user: user}
  end

  describe "preview/2" do
    test "renders a download button", %{conn: conn} do
      # Given
      preview =
        Previews.create_preview(%{
          project: ProjectsFixtures.project_fixture(),
          type: :app_bundle,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        })

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}")

      # Then
      response = html_response(conn, 200)

      assert response =~
               "Don't have the Tuist app installed? <a style=\"display: inline;\" href=\"/download\">Click here to download it.</a>"

      refute response =~
               "mobile_preview"
    end

    test "renders mobile preview when the preview is an archive", %{conn: conn} do
      # Given
      preview =
        Previews.create_preview(%{
          project: ProjectsFixtures.project_fixture(),
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        })

      # When
      conn =
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}")

      # Then
      response = html_response(conn, 200)

      assert response =~
               "mobile_preview"
    end

    test "raises not found error when the preview does not exist", %{conn: conn} do
      # When / Then
      assert_raise TuistWeb.Errors.NotFoundError, fn ->
        conn
        |> get(~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9")
      end
    end
  end

  describe "manifest/2" do
    test "returns manifest.plist", %{conn: conn} do
      # Given
      preview =
        Previews.create_preview(%{
          project: ProjectsFixtures.project_fixture(),
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        })

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
        Previews.create_preview(%{
          project: ProjectsFixtures.project_fixture(),
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        })

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
end
