defmodule Tuist.GitHub.ReleasesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.GitHub.Releases

  setup do
    stub(Tuist.KeyValueStore, :get_or_update, fn _, _, func -> func.() end)
    :ok
  end

  describe "get_latest_cli_release/1" do
    test "returns a release if the response is successful" do
      # Given
      published_at = DateTime.utc_now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "CLI 4.196.0",
        "tag_name" => "4.196.0",
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
      assert release.tag_name == "4.196.0"
      assert release.html_url == "https://github.com/release"
    end

    test "skips component releases (scoped tags) and returns the CLI release" do
      # Given: mirror the real GitHub release shape. Component releases have a
      # human-readable `name` like "Runners Controller 0.9.0" (no "@") and a
      # scoped `tag_name` like "runners-controller@0.9.0". CLI releases have a
      # bare semver `tag_name` like "4.196.0". The filter must look at
      # `tag_name`, not `name`, to skip the components.
      published_at = DateTime.utc_now()

      cli_release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "CLI 4.196.0",
        "tag_name" => "4.196.0",
        "html_url" => "https://github.com/tuist/tuist/releases/tag/4.196.0",
        "assets" => []
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
                 "name" => "Runners Controller 0.11.0",
                 "tag_name" => "runners-controller@0.11.0",
                 "html_url" => "https://github.com/release",
                 "assets" => []
               },
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "Server 1.207.0",
                 "tag_name" => "server@1.207.0",
                 "html_url" => "https://github.com/release",
                 "assets" => []
               },
               cli_release
             ]
           }}
        end
      )

      # When
      release = Releases.get_latest_cli_release()

      # Then
      assert release.tag_name == "4.196.0"
      assert release.name == "CLI 4.196.0"
    end

    test "returns the highest-semver release even when a lower backport was published most recently" do
      # Given: GitHub orders releases by publish date, so a backport patch
      # (4.192.1) cut after a newer minor (4.195.1) is listed first. The latest
      # CLI version must be selected by semver, not by publish recency.
      backport = %{
        "published_at" => Timex.format!(DateTime.utc_now(), "{ISO:Extended}"),
        "name" => "CLI 4.192.1",
        "tag_name" => "4.192.1",
        "html_url" => "https://github.com/tuist/tuist/releases/tag/4.192.1",
        "assets" => []
      }

      newer = %{
        "published_at" => Timex.format!(DateTime.add(DateTime.utc_now(), -7, :day), "{ISO:Extended}"),
        "name" => "CLI 4.195.1",
        "tag_name" => "4.195.1",
        "html_url" => "https://github.com/tuist/tuist/releases/tag/4.195.1",
        "assets" => []
      }

      releases_url = Releases.releases_url()

      stub(Req, :get, fn ^releases_url, _opts ->
        {:ok, %Req.Response{status: 200, body: [backport, newer]}}
      end)

      # When
      release = Releases.get_latest_cli_release()

      # Then
      assert release.tag_name == "4.195.1"
    end

    test "excludes prerelease channels (canary, rc) and returns the highest stable release" do
      # Given: canary and RC tags are published as GitHub prereleases and a bare
      # semver compare would rank a canary (4.201.0-canary.5) above the latest
      # stable (4.200.0). The latest CLI must always be a stable release.
      published_at = DateTime.utc_now()

      stable = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "CLI 4.200.0",
        "tag_name" => "4.200.0",
        "html_url" => "https://github.com/tuist/tuist/releases/tag/4.200.0",
        "assets" => []
      }

      releases_url = Releases.releases_url()

      stub(Req, :get, fn ^releases_url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{
               "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
               "name" => "CLI 4.201.0-canary.5",
               "tag_name" => "4.201.0-canary.5",
               "html_url" => "https://github.com/tuist/tuist/releases/tag/4.201.0-canary.5",
               "assets" => []
             },
             %{
               "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
               "name" => "CLI 4.201.0-rc.1",
               "tag_name" => "4.201.0-rc.1",
               "html_url" => "https://github.com/tuist/tuist/releases/tag/4.201.0-rc.1",
               "assets" => []
             },
             stable
           ]
         }}
      end)

      # When
      release = Releases.get_latest_cli_release()

      # Then
      assert release.tag_name == "4.200.0"
    end

    test "follows pagination to find the latest stable CLI release buried behind canaries" do
      # Given: with a canary published on every commit, the first page can be all
      # canary/component releases and the latest stable lands on a later page. The
      # fetch must paginate via the Link header instead of stopping at page one.
      published_at = DateTime.utc_now()
      releases_url = Releases.releases_url()
      next_url = "https://api.github.com/repos/tuist/tuist/releases?page=2&per_page=100"

      page_one =
        Enum.map(1..3, fn n ->
          %{
            "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
            "name" => "CLI 4.201.0-canary.#{n}",
            "tag_name" => "4.201.0-canary.#{n}",
            "html_url" => "https://github.com/tuist/tuist/releases/tag/4.201.0-canary.#{n}",
            "assets" => []
          }
        end)

      stable = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "CLI 4.200.0",
        "tag_name" => "4.200.0",
        "html_url" => "https://github.com/tuist/tuist/releases/tag/4.200.0",
        "assets" => []
      }

      stub(Req, :get, fn url, _opts ->
        cond do
          url == releases_url ->
            {:ok,
             %Req.Response{
               status: 200,
               body: page_one,
               headers: %{"link" => ["<#{next_url}>; rel=\"next\""]}
             }}

          url == next_url ->
            {:ok, %Req.Response{status: 200, body: [stable], headers: %{}}}
        end
      end)

      # When
      release = Releases.get_latest_cli_release()

      # Then
      assert release.tag_name == "4.200.0"
    end

    test "returns cached release when update: false and cache exists" do
      # Given
      published_at = DateTime.utc_now()

      cached_release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "CLI 4.196.0",
        "tag_name" => "4.196.0",
        "html_url" => "https://github.com/cached-release",
        "assets" => []
      }

      stub(Tuist.KeyValueStore, :get, fn [Releases, "github_releases"] ->
        [cached_release]
      end)

      # When
      release = Releases.get_latest_cli_release(update_if_needed: false)

      # Then
      assert release.tag_name == "4.196.0"
      assert release.html_url == "https://github.com/cached-release"
    end

    test "returns nil when update_if_needed: false and cache is empty" do
      # Given
      stub(Tuist.KeyValueStore, :get, fn [Releases, "github_releases"] ->
        nil
      end)

      # When
      release = Releases.get_latest_cli_release(update_if_needed: false)

      # Then
      assert release == nil
    end

    test "does not call fetch_releases when update_if_needed: false" do
      # Given
      stub(Tuist.KeyValueStore, :get, fn [Releases, "github_releases"] ->
        nil
      end)

      # Req.get should NOT be called when update_if_needed: false
      reject(Req, :get, 2)

      # When
      release = Releases.get_latest_cli_release(update_if_needed: false)

      # Then
      assert release == nil
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
        "tag_name" => "app@0.1.0",
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

    test "returns latest release when the release name uses the new format (App X.Y.Z)" do
      # Given
      # Release names changed from "app@X.Y.Z" to "App X.Y.Z" at some point; the tag_name
      # has always been "app@X.Y.Z" and is what we use to identify app releases.
      published_at = DateTime.utc_now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "App 0.25.0",
        "tag_name" => "app@0.25.0",
        "html_url" => "https://github.com/release",
        "assets" => [
          %{
            "name" => "Tuist.dmg",
            "browser_download_url" => "https://github.com/tuist/tuist/releases/download/app@0.25.0/Tuist.dmg"
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
      assert release.name == "App 0.25.0"
      assert release.tag_name == "app@0.25.0"
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
                 "tag_name" => "0.1.0",
                 "html_url" => "https://github.com/release",
                 "assets" => []
               },
               %{
                 "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
                 "name" => "app@0.1.0",
                 "tag_name" => "app@0.1.0",
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
                 "tag_name" => "app@0.2.0",
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
                 "tag_name" => "app@0.1.0",
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
          "tag_name" => "v1.0.0",
          "html_url" => "https://github.com/release-1",
          "assets" => []
        }
      ]

      app_release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "app@1.0.0",
        "tag_name" => "app@1.0.0",
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

    test "returns nil when GitHub returns a non-200 response" do
      releases_url = Releases.releases_url()

      stub(Req, :get, fn ^releases_url, _opts ->
        {:ok, %Req.Response{status: 429, body: %{}, headers: []}}
      end)

      assert Releases.get_latest_app_release() == nil
    end
  end
end
