defmodule Tuist.GitHub.ReleasesTest do
  use ExUnit.Case, async: false
  setup :set_mimic_global

  use Mimic
  alias Tuist.GitHub.Releases

  describe "get_latest_cli_release/0" do
    test "returns a release if the response is successful" do
      published_at = Timex.now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "v2.0.0",
        "html_url" => "https://github.com/release"
      }

      latest_cli_release_url = Releases.latest_cli_release_url()

      Req
      |> stub(
        :get,
        fn ^latest_cli_release_url ->
          {:ok, %Req.Response{status: 200, body: release}}
        end
      )

      {:ok, pid} = Releases.start_link([])

      release = Releases.get_latest_cli_release(pid)
      assert release.name == "v2.0.0"
      assert release.html_url == "https://github.com/release"
    end
  end
end
