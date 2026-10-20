defmodule Tuist.Runners.Workers.BuildkitePollWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.Installation
  alias Tuist.Runners.Workers.BuildkitePollWorker

  setup :verify_on_exit!

  defp installation(id), do: %Installation{id: id, account_id: id, stack_key: "stack-#{id}"}

  describe "perform/1 without an installation id" do
    test "fans out one job per pollable installation" do
      stub(Buildkite, :list_pollable_installations, fn -> [installation(1), installation(2)] end)

      assert :ok = BuildkitePollWorker.perform(%Oban.Job{args: %{}})

      assert [1, 2] ==
               Oban.Job
               |> Tuist.Repo.all()
               |> Enum.filter(&(&1.worker == "Tuist.Runners.Workers.BuildkitePollWorker"))
               |> Enum.map(& &1.args["installation_id"])
               |> Enum.sort()
    end

    test "enqueues nothing when no account has connected Buildkite" do
      stub(Buildkite, :list_pollable_installations, fn -> [] end)

      assert :ok = BuildkitePollWorker.perform(%Oban.Job{args: %{}})
      assert Tuist.Repo.aggregate(Oban.Job, :count) == 0
    end
  end

  describe "perform/1 for one installation" do
    test "is a no-op when the installation is gone" do
      stub(Buildkite, :list_pollable_installations, fn -> [] end)
      reject(&Buildkite.poll/1)

      assert :ok = BuildkitePollWorker.perform(%Oban.Job{args: %{"installation_id" => 99}})
    end

    test "stops the run window as soon as the installation errors" do
      installation = installation(1)
      stub(Buildkite, :list_pollable_installations, fn -> [installation] end)

      # One call, not a run window's worth: retrying a revoked token for
      # the rest of the minute would spend the stack's rate-limit budget
      # on calls that cannot succeed.
      expect(Buildkite, :poll, 1, fn ^installation -> {:error, :unauthorized} end)

      expect(Buildkite, :record_poll_result, 1, fn ^installation, {:error, :unauthorized} ->
        {:ok, installation}
      end)

      assert :ok = BuildkitePollWorker.perform(%Oban.Job{args: %{"installation_id" => 1}})
    end
  end
end
