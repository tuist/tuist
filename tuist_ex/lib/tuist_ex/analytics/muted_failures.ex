defmodule TuistEx.Analytics.MutedFailures do
  @moduledoc false

  # Keeps a muted test's failure out of the failure count `mix test` decides
  # the run's exit status with. A run whose only failures are muted tests
  # then ends as a passing run would, and `mix test` still applies
  # `--warnings-as-errors` to it: Mix fails a run for the warnings of the
  # test files it loaded only when it counted no failure, and it does not
  # say whether there were any when it raises for a failure, so no status
  # rewritten after the run can account for them.
  #
  # ExUnit counts the run's failures in `ExUnit.RunnerStats`, the handler
  # the runner adds to every run and reads the totals from. `install/1`
  # swaps it for a proxy (see `ExUnitPatch`) whose `handle_cast/2` takes a
  # muted test's failure back off the count once the original counted it.
  # The failure stays in the failures manifest, so `--failed` reruns the
  # test, and the formatters still see it fail. A test is muted when the
  # identity the formatter reports it with is, so the two agree.
  #
  # The runner's separate counter for `--max-failures` still counts muted
  # failures: a run that stopped early is failed by the task.
  #
  # The swap is refused, and the task falls back to the `--raise` path
  # retries use, unless the runner reads `ExUnit.RunnerStats.stats/1` and
  # the original counts a failed test as the Elixir versions read for this
  # (1.18 to 1.20) do.

  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistEx.Analytics.ExUnitPatch
  alias TuistEx.Analytics.Quarantine

  @stats ExUnit.RunnerStats
  @original ExUnit.RunnerStats.TuistEx.Original
  @compile {:no_warn_undefined, @original}
  @policy {__MODULE__, :policy}

  @doc """
  Leaves the failures of the policy's muted tests out of the failure count
  of the runs that start from now on. Returns `:ok`, or `{:error, reason}`
  when ExUnit could not be patched.
  """
  def install(%Quarantine{} = policy) do
    :persistent_term.put(@policy, policy)

    case swap() do
      :ok ->
        :ok

      {:error, reason} ->
        :persistent_term.erase(@policy)
        {:error, reason}
    end
  end

  @doc """
  Puts ExUnit's own `ExUnit.RunnerStats` back.
  """
  def uninstall do
    :persistent_term.erase(@policy)
    ExUnitPatch.restore(@stats, @original)
  end

  def installed?, do: ExUnitPatch.installed?(@stats)

  @doc false
  def handle_cast({:test_finished, %ExUnit.Test{state: {kind, _}} = test} = event, state)
      when kind in [:failed, :invalid] do
    case @original.handle_cast(event, state) do
      {:noreply, %{failures: failures} = counted} when failures > 0 ->
        if muted?(test),
          do: {:noreply, %{counted | failures: failures - 1}},
          else: {:noreply, counted}

      other ->
        other
    end
  end

  def handle_cast(event, state), do: @original.handle_cast(event, state)

  defp muted?(test) do
    Quarantine.muted?(:persistent_term.get(@policy, nil), ExUnitFormatter.identity(test))
  end

  defp swap do
    with :ok <- check_version(),
         {:module, @stats} <- Code.ensure_loaded(@stats),
         false <- installed?(),
         :ok <- check_runner() do
      ExUnitPatch.swap(@stats, @original, {__MODULE__, [handle_cast: 2]}, &check_count/0)
    else
      true -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp check_version do
    if Version.match?(System.version(), "~> 1.18"),
      do: :ok,
      else: {:error, {:unsupported_elixir, System.version()}}
  end

  defp check_runner do
    if ExUnitPatch.runner_calls?({@stats, :stats, 1}),
      do: :ok,
      else: {:error, :runner_does_not_read_stats}
  end

  # A failed test counts once in the `:failures` the stats report.
  defp check_count do
    test = %ExUnit.Test{
      name: :"test check",
      module: __MODULE__,
      state: {:failed, []},
      tags: %{file: "check_test.exs"}
    }

    with {:ok, state} <- @original.init([]),
         {:noreply, %{failures: 1} = state} <-
           @original.handle_cast({:test_finished, test}, state),
         {:reply, %{failures: 1}, _state} <-
           @original.handle_call(:stats, {self(), make_ref()}, state) do
      :ok
    else
      _ -> {:error, :unexpected_runner_stats}
    end
  rescue
    _ -> {:error, :unexpected_runner_stats}
  end
end
