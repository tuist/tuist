defmodule Tuist.Analytics.PosthogTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Analytics.Posthog
  alias Tuist.Environment

  test "process_event" do
    # Given
    response = %{test: "tuist"}
    entries = [%{event: "event1", properties: %{}}]
    url = "/capture"
    api_key = "api_key"
    body = %{batch: entries, api_key: api_key}

    expect(Req, :post, fn _req, opts ->
      assert Keyword.get(opts, :url) == url
      assert Keyword.get(opts, :json) == body
      assert Keyword.get(opts, :headers) == [{"Content-Type", "application/json"}]
      {:ok, response}
    end)

    expect(Environment, :posthog_api_key, fn -> api_key end)
    expect(Environment, :posthog_url, fn -> "https://posthog.com" end)

    # When
    assert {:ok, ^response} = Posthog.capture_batch(entries)
  end
end
