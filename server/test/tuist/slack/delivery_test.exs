defmodule Tuist.Slack.DeliveryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Slack.Client

  test "429 reschedules one bounded HTTP attempt without retrying inside Req" do
    expect(Req, :post, fn "https://hooks.slack.com/test", opts ->
      assert opts[:retry] == false
      assert opts[:redirect] == false
      assert opts[:receive_timeout] == 10_000
      assert opts[:pool_timeout] == 5_000
      assert opts[:connect_options][:timeout] == 5_000
      {:ok, %Req.Response{status: 429, headers: %{"retry-after" => ["42"]}}}
    end)

    assert {:snooze, 42} = Client.deliver_once({:webhook, "https://hooks.slack.com/test"}, [])
  end

  test "permanent rejection and transient failure are distinct" do
    expect(Req, :post, fn _, _ -> {:ok, %Req.Response{status: 404}} end)
    assert {:discard, :slack_rejected} = Client.deliver_once({:webhook, "https://hooks.slack.com/test"}, [])
    expect(Req, :post, fn _, _ -> {:ok, %Req.Response{status: 503}} end)
    assert {:error, :slack_unavailable} = Client.deliver_once({:webhook, "https://hooks.slack.com/test"}, [])
  end

  test "legacy bot transport checks Slack's application-level errors" do
    expect(Req, :post, fn _, opts ->
      assert opts[:json].channel == "C123"
      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "token_revoked"}}}
    end)

    assert {:discard, :slack_rejected} = Client.deliver_once({:channel, "test-token", "C123"}, [])
  end
end
