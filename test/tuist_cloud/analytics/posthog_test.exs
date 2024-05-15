defmodule TuistCloud.Analytics.PosthogTest do
  alias TuistCloud.Environment
  alias TuistCloud.Analytics.Posthog
  use ExUnit.Case, async: true
  use Mimic

  test "process_event" do
    # Given
    response = %{test: "tuist"}
    entries = [%{event: "event1", properties: %{}}]
    url = "/capture"
    api_key = "api_key"
    body = %{batch: entries, api_key: api_key}

    Req
    |> expect(:post, fn _req, opts ->
      assert Keyword.get(opts, :url) == url
      assert Keyword.get(opts, :json) == body
      assert Keyword.get(opts, :headers) == [{"Content-Type", "application/json"}]
      {:ok, response}
    end)

    Environment |> expect(:posthog_api_key, fn -> api_key end)
    Environment |> expect(:posthog_url, fn -> "https://posthog.com" end)

    # When
    assert {:ok, ^response} = Posthog.capture_batch(entries)
  end
end
