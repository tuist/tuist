defmodule Tuist.Kura.Rollouts.NotifierTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Rollouts.Notifier

  setup :set_mimic_from_context

  setup do
    test_pid = self()
    stub(Tuist.Environment, :ops_slack_webhook_url, fn -> "https://hooks.slack.test/kura" end)
    stub(Tuist.Environment, :env, fn -> :production end)

    stub(Req, :post, fn _url, opts ->
      send(test_pid, {:slack, opts[:json][:text]})
      {:ok, %Req.Response{status: 200}}
    end)

    %{rollout: %Rollout{image_tag: "0.55.0", current_wave: 1}}
  end

  test "names the servers held by paused StatefulSets", %{rollout: rollout} do
    Notifier.notify(:paused, rollout, %{
      wave: 1,
      signal: :statefulset_update_paused,
      servers: [
        %{
          server_id: "server-a",
          region: "eu-east",
          strategy: "updateStrategy OnDelete",
          held_pods: ["kura-a-0", "kura-a-1"]
        },
        %{server_id: "server-b", region: "eu-east", strategy: "rollingUpdate.partition=1", held_pods: ["kura-b-0"]}
      ]
    })

    assert_receive {:slack, text}, 2_000
    assert text =~ "Kura rollout paused: `0.55.0` at wave 1 in production (signal statefulset_update_paused)"
    assert text =~ "Replace the held pods or restore RollingUpdate, then resume."
    assert text =~ "server server-a (eu-east): updateStrategy OnDelete holds kura-a-0, kura-a-1"
    assert text =~ "server server-b (eu-east): rollingUpdate.partition=1 holds kura-b-0"
  end

  test "keeps the generic pause message for other signals", %{rollout: rollout} do
    Notifier.notify(:paused, rollout, %{wave: 1, signal: :wave_deadline_exceeded})

    assert_receive {:slack, text}, 2_000
    assert text == "Kura rollout paused: `0.55.0` at wave 1 in production (signal wave_deadline_exceeded)"
  end
end
