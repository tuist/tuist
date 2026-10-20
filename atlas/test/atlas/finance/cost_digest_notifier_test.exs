defmodule Atlas.Finance.CostDigestNotifierTest do
  use ExUnit.Case, async: true

  alias Atlas.Finance.CostDigestNotifier

  test "posts agent-generated Slack blocks to the configured cost digest channel" do
    test_pid = self()

    poster = fn app_key, channel, text, blocks ->
      send(test_pid, {:posted, app_key, channel, text, blocks})
      {:ok, %{"ok" => true}}
    end

    assert :ok =
             CostDigestNotifier.maybe_post(digest_fixture(),
               finance_config: [cost_digest_slack_channel_id: "C_LEADERSHIP"],
               poster: poster
             )

    assert_received {:posted, :company, "C_LEADERSHIP", "Daily cost check: no material concerns.", blocks}
    assert hd(blocks)["type"] == "header"

    assert Enum.at(blocks, 1) == %{
             "type" => "section",
             "text" => %{
               "type" => "plain_text",
               "text" => "Daily cost check: no material concerns.",
               "emoji" => false
             }
           }

    assert List.last(blocks)["type"] == "actions"
  end

  test "keeps an agent-generated body without repeating the fallback text" do
    test_pid = self()

    poster = fn _app_key, _channel, _text, blocks ->
      send(test_pid, {:posted, blocks})
      {:ok, %{"ok" => true}}
    end

    digest = %{
      fallback_text: "Daily cost check: no material concerns.",
      blocks: [
        %{
          "type" => "section",
          "text" => %{"type" => "mrkdwn", "text" => "*Summary*\nNo material concerns."}
        }
      ]
    }

    assert :ok =
             CostDigestNotifier.maybe_post(digest,
               channel_id: "C_LEADERSHIP",
               poster: poster
             )

    assert_received {:posted, blocks}

    assert Enum.count(blocks, fn block -> block["type"] == "section" end) == 1
    refute inspect(blocks) =~ digest.fallback_text
  end

  test "falls back to the weekly finance summary channel" do
    test_pid = self()

    poster = fn _app_key, channel, _text, _blocks ->
      send(test_pid, {:posted, channel})
      {:ok, %{"ok" => true}}
    end

    assert :ok =
             CostDigestNotifier.maybe_post(digest_fixture(),
               finance_config: [cost_digest_slack_channel_id: nil, weekly_summary_slack_channel_id: "C_FINANCE"],
               poster: poster
             )

    assert_received {:posted, "C_FINANCE"}
  end

  test "returns an error when no Slack channel is configured" do
    assert {:error, :missing_cost_digest_slack_channel_id} =
             CostDigestNotifier.maybe_post(digest_fixture(), finance_config: [])
  end

  defp digest_fixture do
    %{
      fallback_text: "Daily cost check: no material concerns.",
      blocks: [
        %{
          "type" => "header",
          "text" => %{"type" => "plain_text", "text" => "Daily cost check", "emoji" => true}
        }
      ]
    }
  end
end
