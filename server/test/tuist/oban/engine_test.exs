defmodule Tuist.Oban.EngineTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Oban.Engines.Basic
  alias Oban.Job
  alias Tuist.Oban.Engine

  @oban_name Module.concat(__MODULE__, "Oban")

  defmodule Worker do
    @moduledoc false
    use Oban.Worker, queue: :engine_integration

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  defmodule RollbackOnceRepo do
    @moduledoc false

    defdelegate config(), to: Tuist.Repo
    defdelegate get_dynamic_repo(), to: Tuist.Repo
    defdelegate in_transaction?(), to: Tuist.Repo
    defdelegate insert(changeset, opts), to: Tuist.Repo
    defdelegate put_dynamic_repo(repo), to: Tuist.Repo
    defdelegate update_all(queryable, updates, opts), to: Tuist.Repo

    def rollback_next_transaction do
      Agent.update(__MODULE__, fn _rollback? -> true end)
    end

    def transaction(function, opts) do
      rollback? = Agent.get_and_update(__MODULE__, fn rollback? -> {rollback?, false} end)

      if rollback? do
        {:error, :rollback}
      else
        Tuist.Repo.transaction(function, opts)
      end
    end
  end

  test "is configured as the Oban engine" do
    assert Oban.config().engine == Engine
  end

  test "retries a rolled-back Oban insertion" do
    changeset = Ecto.Changeset.change(%Job{})
    job = %Job{}
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Mimic.expect(Basic, :insert_job, 2, fn _conf, ^changeset, [] ->
      attempt = Agent.get_and_update(counter, &{&1, &1 + 1})

      case attempt do
        0 -> {:error, :rollback}
        1 -> {:ok, job}
      end
    end)

    assert {:ok, ^job} = Oban.insert(changeset)
  end

  test "returns other insertion errors without retrying" do
    changeset = Ecto.Changeset.change(%Job{})

    Mimic.expect(Basic, :insert_job, 1, fn _conf, ^changeset, [] -> {:error, :invalid} end)

    assert {:error, :invalid} = Engine.insert_job(%Oban.Config{}, changeset, [])
  end

  test "returns a rollback after exhausting retries" do
    changeset = Ecto.Changeset.change(%Job{})

    Mimic.expect(Basic, :insert_job, 4, fn _conf, ^changeset, [] -> {:error, :rollback} end)

    assert {:error, :rollback} = Engine.insert_job(%Oban.Config{}, changeset, [])
  end

  test "implements every callback provided by the basic engine" do
    for {function, arity} <- Oban.Engine.behaviour_info(:callbacks) do
      assert function_exported?(Engine, function, arity) ==
               function_exported?(Basic, function, arity)
    end
  end

  test "executes a job through a supervised queue" do
    start_oban(Tuist.Repo, engine_integration: 1)

    assert Oban.config(@oban_name).engine == Engine
    assert {:ok, job} = Oban.insert(@oban_name, Worker.new(%{}))
    assert_job_completed(job.id)
  end

  test "retries a rolled-back fetch without restarting the queue" do
    start_supervised!(%{
      id: RollbackOnceRepo,
      start: {Agent, :start_link, [fn -> false end, [name: RollbackOnceRepo]]}
    })

    start_oban(RollbackOnceRepo, engine_integration: [limit: 1, paused: true])

    assert {:ok, job} = Oban.insert(@oban_name, Worker.new(%{}))
    RollbackOnceRepo.rollback_next_transaction()

    producer = Oban.Registry.whereis(@oban_name, {:producer, "engine_integration"})

    {_result, log} =
      with_log(fn ->
        assert :ok = Oban.resume_queue(@oban_name, queue: :engine_integration)
        assert_job_completed(job.id)
      end)

    assert log =~ "Oban job fetch transaction rolled back; retrying in one second"
    assert Process.alive?(producer)
    assert producer == Oban.Registry.whereis(@oban_name, {:producer, "engine_integration"})
  end

  defp start_oban(repo, queues) do
    start_supervised!(
      {Oban,
       name: @oban_name,
       engine: Engine,
       repo: repo,
       notifier: Oban.Notifiers.Isolated,
       peer: false,
       plugins: false,
       queues: queues,
       dispatch_cooldown: 1}
    )
  end

  defp assert_job_completed(job_id, attempts \\ 500)

  defp assert_job_completed(job_id, 0) do
    job = Repo.get!(Job, job_id)
    assert job.state == "completed"
  end

  defp assert_job_completed(job_id, attempts) do
    case Repo.get!(Job, job_id) do
      %Job{state: "completed"} ->
        :ok

      %Job{} ->
        Process.sleep(10)
        assert_job_completed(job_id, attempts - 1)
    end
  end
end
