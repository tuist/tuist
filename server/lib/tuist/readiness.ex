defmodule Tuist.Readiness do
  @moduledoc """
  Dependency readiness for pod roles that run without a Phoenix listener.

  The xcresult processor runs in a Tart VM and reaches Postgres and the
  in-cluster ClickHouse over the tailnet. Its Pod used to read Ready as soon
  as the VM had an IP, so a guest that could reach none of its dependencies
  looked healthy to every rollout. `Tuist.Readiness.Plug` serves `check/1`
  on `port/0` so tart-kubelet can probe it.

  Every check is bounded by a timeout and runs concurrently, so a probe
  answers within roughly that timeout even when a dependency hangs.
  """

  require Logger

  @port 9092
  @timeout 2_000

  def port, do: @port

  @doc """
  The checks a pod role must pass to be ready. Empty for roles that are not
  probed this way.
  """
  def checks(:xcresult_processor) do
    [:postgres, :clickhouse, {:oban_queue, :process_xcresult}]
  end

  def checks(_mode), do: []

  @doc """
  Runs `checks` concurrently. Returns `{:ok, results}` when every check
  passes and `{:error, results}` otherwise, where `results` maps each check
  to `:ok` or `{:error, reason}`.
  """
  def check(checks, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @timeout)

    results =
      checks
      |> Task.async_stream(&run/1, timeout: timeout, on_timeout: :kill_task, max_concurrency: max(length(checks), 1))
      |> Enum.zip(checks)
      |> Map.new(fn
        {{:ok, result}, check} -> {name(check), result}
        {{:exit, reason}, check} -> {name(check), {:error, reason}}
      end)

    if Enum.all?(results, fn {_name, result} -> result == :ok end) do
      {:ok, results}
    else
      Logger.warning("Readiness check failed: #{inspect(results)}")
      {:error, results}
    end
  end

  def name({:oban_queue, queue}), do: "oban_queue_#{queue}"
  def name(check), do: Atom.to_string(check)

  # A dependency that is not running raises or exits rather than returning an
  # error (an unstarted repository, or Oban before its registry exists). Either
  # is a failed check, and must not take the linked caller down with it.
  defp run(check) do
    run_check(check)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp run_check(:postgres), do: select_one(Tuist.Repo)
  defp run_check(:clickhouse), do: select_one(Tuist.IngestRepo)

  defp run_check({:oban_queue, queue}) do
    case Oban.check_queue(queue: queue) do
      %{paused: false} -> :ok
      %{paused: true} -> {:error, :paused}
    end
  end

  defp select_one(repo) do
    case repo.query("SELECT 1", [], timeout: @timeout, log: false) do
      {:ok, _result} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
