defmodule TuistEx.Analytics.ExcludeTestIds do
  @moduledoc false

  # Leaves tests out of an ExUnit run by their exact id, `{module, name}`:
  # the counterpart of ExUnit's `only_test_ids` allowlist, which Elixir has
  # no option for. ExUnit filters match one tag at a time, so no filter can
  # name a test of one module without naming a test of the same full name in
  # another.
  #
  # The runner asks `ExUnit.Filters.eval/4` about each test, with the test's
  # module and name merged into its tags. `install/1` swaps `ExUnit.Filters`
  # for a proxy (see `ExUnitPatch`) that delegates every function to the
  # original but `eval/4`, which answers
  # `{:excluded, "due to Tuist quarantine"}` for an id it was given first.
  # Every filter of the run's own still applies to the other tests, and an
  # include filter (`--only`, `path:line`) does not bring an excluded id
  # back.
  #
  # The swap is refused, and the caller falls back to ExUnit's own filters,
  # unless the runner calls `ExUnit.Filters.eval/4` and it answers as the
  # Elixir versions read for this (1.18 to 1.20) do.

  alias TuistEx.Analytics.ExUnitPatch

  @filters ExUnit.Filters
  @original ExUnit.Filters.TuistEx.Original
  @compile {:no_warn_undefined, @original}
  @ids {__MODULE__, :ids}
  @reason "due to Tuist quarantine"

  def reason, do: @reason

  @doc """
  Leaves the tests with the given `{module, name}` ids out of the runs that
  start from now on. Returns `:ok`, or `{:error, reason}` when ExUnit could
  not be patched.
  """
  def install(ids) do
    :persistent_term.put(@ids, MapSet.new(ids))

    case swap() do
      :ok ->
        :ok

      {:error, reason} ->
        :persistent_term.erase(@ids)
        {:error, reason}
    end
  end

  @doc """
  Puts ExUnit's own `ExUnit.Filters` back.
  """
  def uninstall do
    :persistent_term.erase(@ids)
    ExUnitPatch.restore(@filters, @original)
  end

  def installed?, do: ExUnitPatch.installed?(@filters)

  @doc false
  def eval(include, exclude, tags, collection) when is_map(tags) do
    ids = :persistent_term.get(@ids, nil)

    if ids != nil and MapSet.member?(ids, {Map.get(tags, :module), Map.get(tags, :test)}),
      do: {:excluded, @reason},
      else: @original.eval(include, exclude, tags, collection)
  end

  def eval(include, exclude, tags, collection),
    do: @original.eval(include, exclude, tags, collection)

  defp swap do
    with :ok <- check_version(),
         {:module, @filters} <- Code.ensure_loaded(@filters),
         false <- installed?(),
         :ok <- check_runner() do
      ExUnitPatch.swap(@filters, @original, {__MODULE__, [eval: 4]}, &check_eval/0)
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
    if ExUnitPatch.runner_calls?({@filters, :eval, 4}),
      do: :ok,
      else: {:error, :runner_does_not_call_eval}
  end

  # The answers the runner tells apart: `:ok` runs a test, and any other
  # answer is the state it is reported with.
  defp check_eval do
    if function_exported?(@original, :eval, 4) and
         @original.eval([], [], %{}, []) == :ok and
         match?({:excluded, _}, @original.eval([], [:slow], %{slow: true}, [])) do
      :ok
    else
      {:error, :unexpected_eval}
    end
  end
end
