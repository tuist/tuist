defmodule TuistOps.JIT.SlackClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.JIT.SlackClient

  setup :verify_on_exit!

  test "post_message sends thread_ts when present" do
    stub(Environment, :slack_bot_token, fn -> "token" end)

    expect(Req, :post, fn "https://slack.com/api/chat.postMessage", opts ->
      body = JSON.decode!(opts[:body])

      assert {"Authorization", "Bearer token"} in opts[:headers]
      assert body["channel"] == "C_PREVIEWS"
      assert body["thread_ts"] == "1710000000.000001"
      assert body["text"] == "Preview deployment started"

      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "ts" => "1710000000.000002"}}}
    end)

    assert {:ok, "1710000000.000002"} =
             SlackClient.post_message(
               "C_PREVIEWS",
               [],
               fallback_text: "Preview deployment started",
               thread_ts: "1710000000.000001"
             )
  end
end
