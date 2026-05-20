defmodule Tuist.Runners.Workers.DispatchWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Workers.DispatchWorker

  setup :verify_on_exit!

  defp job(args) do
    %Oban.Job{args: args}
  end

  defp args(overrides \\ %{}) do
    Map.merge(
      %{
        "payload" => %{"action" => "queued", "workflow_job" => %{"id" => 1}},
        "installation_id" => 42,
        "delivery_guid" => "guid-1"
      },
      overrides
    )
  end

  describe "perform/1" do
    test "returns :ok and forwards payload + installation_id when Dispatch reports success" do
      args = args()
      payload = args["payload"]

      expect(Dispatch, :handle_webhook, fn ^payload, 42 -> {:ok, :queued} end)

      assert :ok = DispatchWorker.perform(job(args))
    end

    test "treats {:ignored, reason} as terminal success so Oban doesn't retry" do
      # Webhooks GitHub will never re-send (no_matching_pool, runners_disabled,
      # etc.) must NOT come back through Oban — that'd burn cycles on a job
      # we already decided to drop.
      expect(Dispatch, :handle_webhook, fn _payload, _id -> {:ignored, :no_matching_pool} end)

      assert :ok = DispatchWorker.perform(job(args()))
    end

    test "treats the bare :ignored atom as terminal success" do
      expect(Dispatch, :handle_webhook, fn _payload, _id -> :ignored end)

      assert :ok = DispatchWorker.perform(job(args()))
    end

    test "propagates {:error, reason} so Oban retries with backoff" do
      expect(Dispatch, :handle_webhook, fn _payload, _id -> {:error, :transient} end)

      assert {:error, :transient} = DispatchWorker.perform(job(args()))
    end
  end
end
