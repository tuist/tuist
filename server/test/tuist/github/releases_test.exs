defmodule Tuist.GitHub.ReleasesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.GitHub.Releases

  setup do
    stub(Tuist.KeyValueStore, :get_or_update, fn _, _, func -> func.() end)
    :ok
  end

  describe "get_latest_cli_release/0" do
    test "returns a release if the response is successful" do
      # Given
      published_at = DateTime.utc_now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "v2.0.0",
        "html_url" => "https://github.com/release",
        "assets" => []
      }

      releases_url = Releases.releases_url()

      stub(
        Req,
        :get,
        fn ^releases_url, _opts ->
          {:ok, %Req.Response{status: 200, body: [release]}}
        end
      )

      # When
      release = Releases.get_latest_cli_release()

      # Then
      assert release.name == "v2.0.0"
      assert release.html_url == "https://github.com/release"
    end

    test "returns the latest CLI release if the latest release is an App release" do
      # Given
      published_at = DateTime.utc_now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "v2.0.0",
        "html_url" => "https://github.com/release",
        "assets" => [
          %{
            "name" => "tuist.zip",
            "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/app.dmg"
          }
        ]
      }

      releases_url = Releases.releases_url()

      stub(
        Req,
        :get,
        fn ^releases_url, _opts ->
          {:ok,
           %Req.Response{
             status: 200,
             body: [
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "app@2.0.0",
                 "html_url" => "https://github.com/release",
                 "assets" => []
               },
               release
             ]
           }}
        end
      )

      # When
      release = Releases.get_latest_cli_release()

      # Then
      assert release.name == "v2.0.0"
      assert release.html_url == "https://github.com/release"
    end
  end

  test "returns nil when the status is in the range 500..599" do
    # Given
    releases_url = Releases.releases_url()

    stub(
      Req,
      :get,
      fn ^releases_url, _opts ->
        {:ok, %Req.Response{status: 502}}
      end
    )

    # When
    release = Releases.get_latest_cli_release()

    # Then
    assert release == nil
  end

  describe "get_latest_app_release/0" do
    test "returns latest release if the response is successful" do
      # Given
      published_at = DateTime.utc_now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "app@0.1.0",
        "html_url" => "https://github.com/release",
        "assets" => [
          %{
            "name" => "SHASUMS512.txt",
            "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/SHASUMS512.txt"
          },
          %{
            "name" => "Tuist.dmg",
            "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/Tuist.dmg"
          }
        ]
      }

      releases_url = Releases.releases_url()

      stub(
        Req,
        :get,
        fn ^releases_url, _opts ->
          {:ok, %Req.Response{status: 200, body: [release]}}
        end
      )

      # When
      release = Releases.get_latest_app_release()

      # Then
      assert release.name == "app@0.1.0"
      assert release.html_url == "https://github.com/release"
    end

    test "returns the latest App release if the latest release is a CLI release" do
      # Given
      published_at = DateTime.utc_now()
      releases_url = Releases.releases_url()

      stub(
        Req,
        :get,
        fn ^releases_url, _opts ->
          {:ok,
           %Req.Response{
             status: 200,
             body: [
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "0.1.0",
                 "html_url" => "https://github.com/release",
                 "assets" => []
               },
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "app@0.1.0",
                 "html_url" => "https://github.com/release",
                 "assets" => [
                   %{
                     "name" => "SHASUMS512.txt",
                     "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/SHASUMS512.txt"
                   },
                   %{
                     "name" => "Tuist.dmg",
                     "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/Tuist.dmg"
                   }
                 ]
               }
             ]
           }}
        end
      )

      # When
      release = Releases.get_latest_app_release()

      # Then
      assert release.name == "app@0.1.0"
    end

    test "returns the latest App release with a DMG asset" do
      # Given
      published_at = DateTime.utc_now()
      releases_url = Releases.releases_url()

      stub(
        Req,
        :get,
        fn ^releases_url, _opts ->
          {:ok,
           %Req.Response{
             status: 200,
             body: [
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "app@0.2.0",
                 "html_url" => "https://github.com/release",
                 "assets" => [
                   %{
                     "name" => "SHASUMS512.txt",
                     "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.2.0/SHASUMS512.txt"
                   }
                 ]
               },
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "app@0.1.0",
                 "html_url" => "https://github.com/release",
                 "assets" => [
                   %{
                     "name" => "SHASUMS512.txt",
                     "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/SHASUMS512.txt"
                   },
                   %{
                     "name" => "Tuist.dmg",
                     "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.1.0/Tuist.dmg"
                   }
                 ]
               }
             ]
           }}
        end
      )

      # When
      release = Releases.get_latest_app_release()

      # Then
      assert release.name == "app@0.1.0"
      assert release.html_url == "https://github.com/release"
    end

    test "returns app release when it's only available in the second page" do
      # Given
      published_at = DateTime.utc_now()
      releases_url = Releases.releases_url()

      cli_releases = [
        %{
          "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
          "name" => "v1.0.0",
          "html_url" => "https://github.com/release-1",
          "assets" => []
        }
      ]

      app_release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "app@1.0.0",
        "html_url" => "https://github.com/app-release",
        "assets" => [
          %{
            "name" => "Tuist.dmg",
            "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@1.0.0/Tuist.dmg"
          }
        ]
      }

      stub(
        Req,
        :get,
        fn url, _opts ->
          cond do
            url == releases_url ->
              {:ok,
               %Req.Response{
                 status: 200,
                 body: cli_releases,
                 headers: %{
                   "link" => [
                     "<https://api.github.com/repos/tuist/tuist/releases?page=2>; rel=\"next\""
                   ]
                 }
               }}

            url == "https://api.github.com/repos/tuist/tuist/releases?page=2" ->
              {:ok,
               %Req.Response{
                 status: 200,
                 body: [app_release],
                 headers: []
               }}
          end
        end
      )

      # When
      release = Releases.get_latest_app_release()

      # Then
      assert release.name == "app@1.0.0"
      assert release.html_url == "https://github.com/app-release"
    end
  end
end
