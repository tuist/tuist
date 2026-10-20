defmodule Atlas.FeatureUsage.UsageNotifierTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Account
  alias Atlas.FeatureUsage.Snapshot
  alias Atlas.FeatureUsage.UsageNotifier

  defp account, do: %Account{id: Ecto.UUID.generate(), name: "Acme"}

  defp stop_snapshot do
    %Snapshot{
      feature: "cache",
      active: false,
      active_previous: true,
      events_last_24h: 0,
      events_last_7d: 0,
      events_prior_7d: 6,
      last_used_at: ~U[2026-07-20 10:00:00Z]
    }
  end

  defp start_snapshot do
    %Snapshot{
      feature: "cache",
      active: true,
      active_previous: false,
      events_last_24h: 3,
      events_last_7d: 8,
      events_prior_7d: 0,
      last_used_at: ~U[2026-07-20 10:00:00Z]
    }
  end

  describe "notify/4 for :stopped" do
    test "posts a Block Kit alert to the configured channel" do
      parent = self()

      poster = fn app_key, channel, text, blocks ->
        send(parent, {:posted, app_key, channel, text, blocks})
        {:ok, %{"channel" => channel, "ts" => "123.456"}}
      end

      assert {:ok, %{channel_id: "C123", ts: "123.456"}} =
               UsageNotifier.notify(account(), stop_snapshot(), :stopped, channel_id: "C123", poster: poster)

      assert_received {:posted, :company, "C123", text, blocks}
      assert text =~ "Cache"
      assert text =~ "stopped"
      assert is_list(blocks)
      assert Enum.any?(blocks, &(&1["type"] == "header"))
    end

    test "describes a configuration feature as turned off rather than gone quiet" do
      snapshot = %Snapshot{
        feature: "automations",
        active: false,
        active_previous: true,
        events_last_24h: 4,
        events_last_7d: 0,
        events_prior_7d: 0,
        last_used_at: ~U[2026-07-20 10:00:00Z]
      }

      blocks = UsageNotifier.build_blocks(account(), snapshot, :stopped)
      text = blocks |> Enum.map(&get_in(&1, ["text", "text"])) |> Enum.reject(&is_nil/1) |> Enum.join("\n")

      assert text =~ "stopped using *Automations*"
      assert text =~ "Nothing is enabled in their projects anymore, out of 4 configured."
      refute text =~ "event(s) the week before"
    end

    test "describes an account-level configuration feature as removed from the account" do
      snapshot = %Snapshot{
        feature: "single_sign_on",
        active: false,
        active_previous: true,
        events_last_24h: 0,
        events_last_7d: 0,
        events_prior_7d: 0,
        last_used_at: ~U[2026-07-20 10:00:00Z]
      }

      text =
        account()
        |> UsageNotifier.build_blocks(snapshot, :stopped)
        |> Enum.map(&get_in(&1, ["text", "text"]))
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      assert text =~ "stopped using *Single sign-on*"
      assert text =~ "It is no longer configured for their account."
    end

    test "labels the configuration context line with the last change and total" do
      snapshot = %Snapshot{
        feature: "automations",
        active: false,
        active_previous: true,
        events_last_24h: 4,
        events_last_7d: 0,
        events_prior_7d: 0,
        last_used_at: ~U[2026-07-20 10:00:00Z]
      }

      context_text =
        account()
        |> UsageNotifier.build_blocks(snapshot, :stopped)
        |> Enum.filter(&(&1["type"] == "context"))
        |> List.last()
        |> Map.fetch!("elements")
        |> Enum.map_join("\n", & &1["text"])

      assert context_text =~ "Last changed July 20, 2026"
      assert context_text =~ "Configured in total: 4"
    end

    test "returns an error when no channel is configured" do
      poster = fn _app, _channel, _text, _blocks -> flunk("should not post without a channel") end

      assert {:error, :missing_alert_slack_channel_id} =
               UsageNotifier.notify(account(), stop_snapshot(), :stopped, feature_usage_config: [], poster: poster)
    end
  end

  describe "notify/4 for :started" do
    test "posts a Block Kit adoption message to the configured channel" do
      parent = self()

      poster = fn app_key, channel, text, blocks ->
        send(parent, {:posted, app_key, channel, text, blocks})
        {:ok, %{"channel" => channel, "ts" => "789.012"}}
      end

      assert {:ok, %{channel_id: "C123", ts: "789.012"}} =
               UsageNotifier.notify(account(), start_snapshot(), :started, channel_id: "C123", poster: poster)

      assert_received {:posted, :company, "C123", text, blocks}
      assert text == "Acme started using Cache."
      assert Enum.any?(blocks, &(&1["type"] == "header"))

      body =
        blocks
        |> Enum.map(&get_in(&1, ["text", "text"]))
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      assert body =~ "started using *Cache*"
      assert body =~ "8 event(s) in the last 7 days after no activity the week before."
    end

    test "describes a configuration feature adoption as new setup rather than events" do
      snapshot = %Snapshot{
        feature: "automations",
        active: true,
        active_previous: false,
        events_last_24h: 3,
        events_last_7d: 2,
        events_prior_7d: 0,
        last_used_at: ~U[2026-07-20 10:00:00Z]
      }

      text =
        account()
        |> UsageNotifier.build_blocks(snapshot, :started)
        |> Enum.map(&get_in(&1, ["text", "text"]))
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      assert text =~ "started using *Automations*"
      assert text =~ "They now have 2 enabled in their projects, out of 3 configured."
      refute text =~ "event(s) in the last 7 days after no activity"
    end

    test "describes an account-level configuration feature adoption as freshly configured" do
      snapshot = %Snapshot{
        feature: "single_sign_on",
        active: true,
        active_previous: false,
        events_last_24h: 1,
        events_last_7d: 1,
        events_prior_7d: 0,
        last_used_at: ~U[2026-07-20 10:00:00Z]
      }

      text =
        account()
        |> UsageNotifier.build_blocks(snapshot, :started)
        |> Enum.map(&get_in(&1, ["text", "text"]))
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      assert text =~ "started using *Single sign-on*"
      assert text =~ "It has just been configured for their account."
    end

    test "header reads 'Feature usage started' for adoption" do
      header =
        account()
        |> UsageNotifier.build_blocks(start_snapshot(), :started)
        |> Enum.find(&(&1["type"] == "header"))

      assert get_in(header, ["text", "text"]) == "Feature usage started"
    end

    test "header reads 'Feature usage dropped' for churn" do
      header =
        account()
        |> UsageNotifier.build_blocks(stop_snapshot(), :stopped)
        |> Enum.find(&(&1["type"] == "header"))

      assert get_in(header, ["text", "text"]) == "Feature usage dropped"
    end
  end
end
