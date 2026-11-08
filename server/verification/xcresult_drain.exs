# Run in an isolated VM with server dependencies and disposable PostgreSQL:
# elixir ... verification/xcresult_drain.exs SOCKET_DIRECTORY PORT.
defmodule DrainVerificationRepo do
  use Ecto.Repo, otp_app: :drain_verification, adapter: Ecto.Adapters.Postgres
end

defmodule DrainVerificationMigration do
  @moduledoc false
  use Ecto.Migration

  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end

defmodule DrainVerificationWorker do
  @moduledoc false
  use Oban.Worker, queue: :process_xcresult

  @impl true
  def perform(job) do
    send(Process.whereis(:drain_verification_owner), {:started, job.id, self()})

    receive do
      :finish -> :ok
    after
      30_000 -> {:error, :verification_timed_out}
    end
  end
end

defmodule DrainVerification do
  @moduledoc false
  alias DrainVerificationRepo, as: Repo
  alias Tuist.XcresultDrain

  def run(socket, port) do
    Application.ensure_all_started(:postgrex)
    Application.ensure_all_started(:ecto_sql)
    Application.ensure_all_started(:oban)
    Process.register(self(), :drain_verification_owner)
    {:ok, _} = Repo.start_link(database: "tuist_drain_verification", socket_dir: socket, port: port, pool_size: 4)
    :ok = Ecto.Migrator.up(Repo, 1, DrainVerificationMigration, log: false)
    directory = Path.join(socket, "drain-share")
    File.mkdir_p!(directory)
    {:ok, oban} = start_oban(true)
    {:ok, drain} = XcresultDrain.start_link(directory: directory)
    {:ok, first} = Oban.insert(DrainVerificationWorker.new(%{}))
    worker = receive_started(first.id)
    uid = "b1abef64-43be-40c8-b78d-49d18c261fed\n"
    File.write!(Path.join(directory, "drain-request"), uid)
    wait(fn -> match?(%{paused: true, running: [_]}, Oban.check_queue(queue: :process_xcresult)) end)
    {:ok, second} = Oban.insert(DrainVerificationWorker.new(%{}))
    false = File.exists?(Path.join(directory, "drain-complete"))
    send(worker, :finish)
    wait(fn -> File.read(Path.join(directory, "drain-complete")) == {:ok, uid} end)
    "completed" = Repo.get!(Oban.Job, first.id).state
    "available" = Repo.get!(Oban.Job, second.id).state
    nil = Oban.Registry.whereis(Oban, {:queue, "process_xcresult"})
    Supervisor.stop(oban)
    {:ok, restarted} = start_oban(XcresultDrain.requested?(directory))
    wait(fn -> match?(%{paused: true, running: []}, Oban.check_queue(queue: :process_xcresult)) end)
    "available" = Repo.get!(Oban.Job, second.id).state

    receive do
      {:started, _, _} -> raise "a paused or restarted processor fetched another job"
    after
      250 -> :ok
    end

    GenServer.stop(drain)
    {:ok, restarted_drain} = XcresultDrain.start_link(directory: directory)
    Process.sleep(250)
    "available" = Repo.get!(Oban.Job, second.id).state
    GenServer.stop(restarted_drain)
    Supervisor.stop(restarted)
    IO.puts("PASS: real PG notifier drained the running job, retained queued work, and restarted paused")
  end

  defp start_oban(paused) do
    Oban.start_link(
      repo: Repo,
      notifier: Oban.Notifiers.PG,
      peer: false,
      plugins: false,
      queues: [process_xcresult: [limit: 1, paused: paused]]
    )
  end

  defp receive_started(id) do
    receive do
      {:started, ^id, worker} -> worker
    after
      10_000 -> raise "verification worker did not start"
    end
  end

  defp wait(check, attempts \\ 100)
  defp wait(_check, 0), do: raise("timed out waiting for the drain")

  defp wait(check, attempts) do
    if check.() do
      :ok
    else
      Process.sleep(100)
      wait(check, attempts - 1)
    end
  end
end

[socket, port] = System.argv()
DrainVerification.run(socket, String.to_integer(port))
