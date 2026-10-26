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
  # for a proxy, the way Mimic swaps a module it copies: the original is
  # compiled again from its debug info under another name, and the proxy
  # delegates every function to it but `eval/4`. For an id it was given, a
  # test the run's own filters would run is skipped instead, as `@tag :skip`
  # skips one: an include filter (`--only`, `path:line`) does not bring it
  # back, and `--only` selecting nothing else still counts as having
  # selected a test. A test the run's own filters leave out keeps their
  # answer.
  #
  # The swap is refused, and the caller falls back to ExUnit's own filters,
  # unless the runner calls `ExUnit.Filters.eval/4` and it answers as the
  # Elixir versions read for this (1.18 to 1.20) do.

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

    if installed?() do
      :code.purge(@filters)
      {:module, @filters} = :code.load_file(@filters)
      :code.purge(@original)
      :code.delete(@original)
      :code.purge(@original)
    end

    :ok
  end

  def installed?, do: function_exported?(@filters, :__tuist_ex_original__, 0)

  @doc false
  def eval(include, exclude, tags, collection) do
    case @original.eval(include, exclude, tags, collection) do
      :ok ->
        ids = :persistent_term.get(@ids, nil)

        if ids != nil and MapSet.member?(ids, {Map.get(tags, :module), Map.get(tags, :test)}),
          do: {:skipped, @reason},
          else: :ok

      answer ->
        answer
    end
  end

  defp swap do
    with :ok <- check_version(),
         {:module, @filters} <- Code.ensure_loaded(@filters),
         false <- installed?(),
         :ok <- check_runner(),
         {@filters, binary, path} <- :code.get_object_code(@filters),
         {:ok, forms} <- forms(binary),
         :ok <- load(@original, path, rename(forms)),
         :ok <- check_eval(),
         :ok <- load(@filters, path, proxy(@original.module_info(:exports))) do
      :ok
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
    with {:module, ExUnit.Runner} <- Code.ensure_loaded(ExUnit.Runner),
         {ExUnit.Runner, binary, _path} <- :code.get_object_code(ExUnit.Runner),
         {:ok, {ExUnit.Runner, [imports: imports]}} <- :beam_lib.chunks(binary, [:imports]),
         true <- {@filters, :eval, 4} in imports do
      :ok
    else
      _ -> {:error, :runner_does_not_call_eval}
    end
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

  defp forms(binary) do
    with {:ok, {@filters, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(binary, [:debug_info]),
         {:ok, forms} <- backend.debug_info(:erlang_v1, @filters, data, []) do
      {:ok, forms}
    else
      _ -> {:error, :no_debug_info}
    end
  end

  defp rename(forms) do
    Enum.map(forms, fn
      {:attribute, anno, :module, @filters} -> {:attribute, anno, :module, @original}
      form -> form
    end)
  end

  defp proxy(exports) do
    anno = :erl_anno.new(0)
    functions = Enum.reject(exports, &(elem(&1, 0) == :module_info))

    delegations =
      for {name, arity} <- functions do
        target = if {name, arity} == {:eval, 4}, do: __MODULE__, else: @original
        args = for index <- 1..arity//1, do: {:var, anno, :"Arg#{index}"}
        call = {:call, anno, {:remote, anno, {:atom, anno, target}, {:atom, anno, name}}, args}
        {:function, anno, name, arity, [{:clause, anno, args, [], [call]}]}
      end

    marker =
      {:function, anno, :__tuist_ex_original__, 0,
       [{:clause, anno, [], [], [{:atom, anno, @original}]}]}

    [
      {:attribute, anno, :module, @filters},
      {:attribute, anno, :export, [{:__tuist_ex_original__, 0} | functions]},
      marker | delegations
    ]
  end

  defp load(module, path, forms) do
    with {:ok, ^module, binary} <- :compile.forms(forms, [:binary, :return_errors]),
         :code.purge(module),
         {:module, ^module} <- :code.load_binary(module, path, binary) do
      :ok
    else
      error -> {:error, {:load, module, error}}
    end
  end
end
