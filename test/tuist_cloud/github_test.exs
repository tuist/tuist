defmodule TuistCloud.GithubTest do
  use ExUnit.Case
  use Mimic
  alias TuistCloud.Github

  describe "get_most_recent_cli_release/0" do
    test "returns a release if the response is successful" do
      # Given
      published_at = Timex.now()

      release = %{
        "published_at" => Timex.format!(published_at, "{ISO:Extended}"),
        "name" => "v2.0.0",
        "html_url" => "https://github.com/release"
      }

      latest_cli_release_url = Github.latest_cli_release_url()

      Memoize.Cache
      |> stub(:get_or_run, fn :get_most_recent_cli_release, func, _opts -> func.() end)

      Req
      |> stub(
        :get,
        fn ^latest_cli_release_url ->
          {:ok, %Req.Response{status: 200, body: release}}
        end
      )

      # When
      got = Github.get_most_recent_cli_release()

      # Then
      assert got == %{
               name: release["name"],
               published_at: published_at,
               html_url: release["html_url"]
             }
    end

    test "doesn't return a release if the response is an error" do
      # Given
      latest_cli_release_url = Github.latest_cli_release_url()

      Req
      |> stub(
        :get,
        fn ^latest_cli_release_url ->
          {:error, %{}}
        end
      )

      Memoize.Cache
      |> stub(:get_or_run, fn :get_most_recent_cli_release, func, _opts -> func.() end)

      # When
      got = Github.get_most_recent_cli_release()

      # Then
      assert got == nil
    end
  end
end
