defmodule Tuist.GithubTest do
  use ExUnit.Case
  use Mimic
  alias Tuist.Github

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

      # When
      got = Github.get_most_recent_cli_release()

      # Then
      assert got == nil
    end
  end
end
