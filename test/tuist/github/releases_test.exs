defmodule Tuist.GitHub.ReleasesTest do
  use ExUnit.Case, async: false
  setup :set_mimic_global

  use Mimic
  alias Tuist.GitHub.Releases

  describe "get_latest_cli_release/0" do
    test "returns a release if the response is successful" do
      # Given
      published_at = Timex.now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "v2.0.0",
        "html_url" => "https://github.com/release",
        "assets" => []
      }

      releases_url = Releases.releases_url()

      Req
      |> stub(
        :get,
        fn ^releases_url ->
          {:ok, %Req.Response{status: 200, body: [release]}}
        end
      )

      # When
      {:ok, pid} = Releases.start_link([])

      # Then
      release = Releases.get_latest_cli_release(pid)
      assert release.name == "v2.0.0"
      assert release.html_url == "https://github.com/release"
    end

    test "returns the latest CLI release if the latest release is an App release" do
      # Given
      published_at = Timex.now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "v2.0.0",
        "html_url" => "https://github.com/release",
        "assets" => [
          %{
            "name" => "tuist.zip",
            "browser_download_url" =>
              "https://github.com/tuist/tuist/releases/download/app@0.1.0/app.dmg"
          }
        ]
      }

      releases_url = Releases.releases_url()

      Req
      |> stub(
        :get,
        fn ^releases_url ->
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
      {:ok, pid} = Releases.start_link([])

      # Then
      release = Releases.get_latest_cli_release(pid)
      assert release.name == "v2.0.0"
      assert release.html_url == "https://github.com/release"
    end
  end

  test "returns nil when the status is in the range 500..599" do
    # Given
    releases_url = Releases.releases_url()

    Req
    |> stub(
      :get,
      fn ^releases_url ->
        {:ok, %Req.Response{status: 502}}
      end
    )

    # When
    {:ok, pid} = Releases.start_link([])

    # Then
    release = Releases.get_latest_cli_release(pid)
    assert release == nil
  end
end
