defmodule TuistEx.Analytics.Evidence do
  @moduledoc false

  # Which lines each test executed, the per-test coverage evidence
  # coverage-based test selection decides from (`coverage_evidence`).
  #
  # The runtime's native line counters belong to a module, not to a process,
  # so what a test executed is the change in the counters while it ran. ExUnit
  # tells formatters about tests asynchronously, after the fact, so the
  # counters are read where ExUnit itself is at a test's boundaries:
  # `ExUnit.OnExitHandler.register/1`, which every test process calls first,
  # before its `setup`, and `ExUnit.OnExitHandler.run/2`, which the module's
  # runner calls once the test process ended and its `on_exit` callbacks ran.
  # `start/1` wraps the two, keeping ExUnit's own code under another name.
  #
  # A test's change is its own only when nothing else ran meanwhile: no other
  # test and no `setup_all`. ExUnit runs `async: true` modules alongside each
  # other, so their tests mostly overlap one another. One counter of events
  # and one of what is running, updated together, tell: a test that started
  # alone and saw no event before it ended ran alone. The others are
  # `overlapped`, have no evidence of their own, and selection always runs
  # them. The counters are read only for a test that starts alone.
  #
  # What a module's `setup_all` ran, from its start to its first test, and
  # what its tests ran are the module's `target` evidence, with the files the
  # application and the test helper ran before any test, which every test
  # depends on. A `setup_all` that overlapped something leaves its tests
  # without evidence of their own: what they depend on is unknown.
  #
  # Nothing here may fail a test: a hook that raises turns collection off,
  # and the run reports its evidence as `failed`.

  alias TuistEx.Analytics.ExUnitPatch

  @table __MODULE__
  @results Module.concat(__MODULE__, Results)
  @modules {__MODULE__, :modules}
  @handler ExUnit.OnExitHandler
  @original Module.concat(__MODULE__, OriginalOnExitHandler)

  @doc """
  Starts collecting for the suite about to run, reading the counters of
  `modules`. Returns whether it could: the hooks need ExUnit's handler as
  this module knows it.
  """
  def start(modules) do
    stop()

    case install() do
      :ok ->
        :persistent_term.put(@modules, modules)
        :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
        :ets.new(@results, [:duplicate_bag, :public, :named_table, write_concurrency: true])
        :ets.insert(@table, {:state, 0, 0})
        :ets.insert(@results, {:boot, executed(read(), [])})
        true

      _ ->
        false
    end
  rescue
    _ -> false
  end

  @doc """
  What the suite recorded, as module-level evidence, and stops collecting:
  `tests` maps `{module, test_name}` (the atoms ExUnit names a test by) to
  the lines it executed by counting module, `targets` maps each test module
  to what it and its `setup_all` executed, `boot` is what ran before any
  test, `overlapped` the tests without evidence of their own, and `failed`
  whether a hook failed. Nil when nothing was collecting.
  """
  def collect do
    if :ets.whereis(@results) != :undefined do
      rows = :ets.tab2list(@results)
      stop()

      unknown_setup = for {{:setup_unknown, module}} <- rows, into: MapSet.new(), do: module

      {tests, overlapped} =
        Enum.reduce(rows, {%{}, MapSet.new()}, fn
          {{:test, module, name}, lines}, {tests, overlapped} ->
            if MapSet.member?(unknown_setup, module),
              do: {tests, MapSet.put(overlapped, {module, name})},
              else: {Map.put(tests, {module, name}, lines), overlapped}

          {{:overlapped, module, name}}, {tests, overlapped} ->
            {tests, MapSet.put(overlapped, {module, name})}

          _row, acc ->
            acc
        end)

      %{
        tests: tests,
        overlapped: overlapped,
        targets:
          Enum.reduce(rows, %{}, fn
            {{:target, module}, lines}, acc -> Map.update(acc, module, lines, &merge(&1, lines))
            _row, acc -> acc
          end),
        boot: Enum.find_value(rows, %{}, &match_boot/1),
        failed: Enum.any?(rows, &(&1 == {:failed}))
      }
    end
  end

  defp match_boot({:boot, lines}), do: lines
  defp match_boot(_row), do: nil

  defp stop do
    for table <- [@table, @results], :ets.whereis(table) != :undefined, do: :ets.delete(table)
    :persistent_term.erase(@modules)
    :ok
  end

  @doc false
  # Called by the wrapped `register/1`, in the process that registers: a
  # test's, labelled `{module, name}`, or a module's `setup_all` process.
  def started(pid) do
    if :ets.whereis(@table) != :undefined, do: guard(fn -> do_started(pid) end)
    :ok
  end

  @doc false
  # Called by the wrapped `run/2`, in the module's runner, once the process
  # `pid` ended and its `on_exit` callbacks ran.
  def finished(pid) do
    if :ets.whereis(@table) != :undefined, do: guard(fn -> do_finished(pid) end)
    :ok
  end

  defp guard(fun) do
    fun.()
  rescue
    _ -> fail()
  catch
    _kind, _reason -> fail()
  end

  defp fail do
    if :ets.whereis(@results) != :undefined, do: :ets.insert(@results, {{:failed}})
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
  end

  defp do_started(pid) do
    runner = parent(pid)

    # `Process.set_label/1` keeps the label there on every Elixir this
    # package supports; `Process.get_label/0` only exists from 1.20.
    case Process.get(:"$process_label") do
      {module, name} when is_atom(module) and is_atom(name) ->
        # The module's tests run after its `setup_all`, in the runner that
        # spawned both: the first one ends the `setup_all`'s window.
        close_setup(runner, module)
        open(pid, {:test, module, name})

      _label ->
        open(pid, :setup)
        :ets.insert(@table, {{:setup, runner}, pid})
    end
  end

  defp do_finished(pid) do
    case :ets.take(@table, {:start, pid}) do
      [{_key, {:test, module, name}, seq, snapshot}] ->
        case close(seq, snapshot) do
          {:alone, lines} ->
            :ets.insert(@results, [{{:test, module, name}, lines}, {{:target, module}, lines}])

          :overlapped ->
            :ets.insert(@results, {{:overlapped, module, name}})
        end

      # A `setup_all` none of whose tests ran.
      [{_key, :setup, seq, snapshot}] ->
        :ets.delete(@table, {:setup, self()})
        close(seq, snapshot)

      [] ->
        :ok
    end
  end

  defp close_setup(runner, module) do
    with [{_key, pid}] <- :ets.take(@table, {:setup, runner}),
         [{_key, :setup, seq, snapshot}] <- :ets.take(@table, {:start, pid}) do
      case close(seq, snapshot) do
        {:alone, lines} -> :ets.insert(@results, {{:target, module}, lines})
        :overlapped -> :ets.insert(@results, {{:setup_unknown, module}})
      end
    end
  end

  # One event more, and one more running. Alone when nothing else runs; the
  # counters are read after the update, so whatever starts after it is an
  # event the end sees.
  defp open(pid, what) do
    [seq, running] = :ets.update_counter(@table, :state, [{2, 1}, {3, 1}])
    snapshot = if running == 1, do: read()
    :ets.insert(@table, {{:start, pid}, what, seq, snapshot})
  end

  # Read before the update, so whatever started before it was an event.
  defp close(seq, snapshot) do
    now = if snapshot, do: read()
    [end_seq, _running] = :ets.update_counter(@table, :state, [{2, 1}, {3, -1}])

    if snapshot != nil and end_seq == seq + 1,
      do: {:alone, executed(now, snapshot)},
      else: :overlapped
  end

  defp parent(pid) do
    case Process.info(pid, :parent) do
      {:parent, parent} -> parent
      _ -> nil
    end
  end

  # Every counting module's counters. A module unloaded since the suite
  # started is left out.
  defp read do
    for module <- :persistent_term.get(@modules, []),
        lines = counters(module),
        lines != nil,
        do: {module, lines}
  end

  defp counters(module) do
    :code.get_coverage(:line, module)
  rescue
    _ -> nil
  end

  @doc """
  The lines whose counters `now` holds higher than `before`, by module, as
  sorted lists. Line 0 stands for code without a line and is left out.
  """
  def executed(now, before) do
    before = Map.new(before)

    for {module, lines} <- now,
        lines != Map.get(before, module),
        old = Map.new(Map.get(before, module, [])),
        ran = for({line, count} <- lines, line > 0, count > Map.get(old, line, 0), do: line),
        ran != [],
        into: %{},
        do: {module, ran |> Enum.uniq() |> Enum.sort()}
  end

  defp merge(a, b), do: Map.merge(a, b, fn _module, x, y -> Enum.sort(Enum.uniq(x ++ y)) end)

  @doc """
  The `coverage_evidence` block for what `collect/0` returned. `identities`
  names each test that ran, `{module, name}` to the
  `{module, suite, name}` the run reports it by; `sources` maps each counting
  module to its source file, and `relative` turns one into a path in the
  repository, nil outside it.
  """
  def payload(collected, identities, sources, relative) do
    files = fn lines ->
      lines
      |> Enum.flat_map(fn {module, lines} ->
        sources
        |> Map.get(module)
        |> then(&(&1 && relative.(&1)))
        |> case do
          nil -> []
          path -> [{path, lines}]
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {path, lines} ->
        {path, lines |> Enum.concat() |> Enum.uniq() |> Enum.sort()}
      end)
    end

    boot = files.(collected.boot)

    test_scopes =
      for {key, lines} <- collected.tests,
          {module, suite, name} <- [Map.get(identities, key)],
          by_path = files.(lines),
          by_path != %{},
          do: {%{kind: "test", module: module, suite: suite, name: name}, by_path}

    modules = identities |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    targets =
      Map.new(collected.targets, fn {module, lines} -> {inspect(module), files.(lines)} end)

    target_scopes =
      for module <- modules,
          by_path = merge(boot, Map.get(targets, module, %{})),
          by_path != %{},
          do: {%{kind: "target", module: module, suite: "", name: ""}, by_path}

    scopes = test_scopes ++ target_scopes

    paths =
      scopes
      |> Enum.flat_map(fn {_scope, by_path} -> Map.keys(by_path) end)
      |> Enum.uniq()
      |> Enum.sort()

    index = paths |> Enum.with_index() |> Map.new()

    %{
      paths: paths,
      scopes:
        Enum.map(scopes, fn {scope, by_path} ->
          by_path = Enum.sort(by_path)

          scope
          |> Map.put(:files, Enum.map(by_path, &Map.fetch!(index, elem(&1, 0))))
          |> Map.put(:lines, Enum.map(by_path, &ranges(elem(&1, 1))))
        end),
      overlapped_tests:
        for(
          key <- Enum.sort(collected.overlapped),
          {module, suite, name} <- [Map.get(identities, key)],
          do: %{module: module, suite: suite, name: name}
        ),
      status: if(collected.failed, do: "failed", else: "collected")
    }
  end

  @doc "Sorted lines as inclusive ranges, flattened: `[3, 4, 5, 9]` is `[3, 5, 9, 9]`."
  def ranges([]), do: []

  def ranges([first | rest]) do
    {ranges, start, last} =
      Enum.reduce(rest, {[], first, first}, fn
        line, {ranges, start, last} when line == last + 1 -> {ranges, start, line}
        line, {ranges, start, last} -> {[last, start | ranges], line, line}
      end)

    Enum.reverse([last, start | ranges])
  end

  # ExUnit's handler is kept under another name and replaced by one that
  # calls it and the hooks (`ExUnitPatch`).
  defp install do
    ExUnitPatch.wrap(
      @handler,
      @original,
      :__tuist_ex_evidence__,
      [register: 1, run: 2],
      quote do
        def register(pid) do
          result = unquote(@original).register(pid)
          unquote(__MODULE__).started(pid)
          result
        end

        def run(pid, timeout) do
          result = unquote(@original).run(pid, timeout)
          unquote(__MODULE__).finished(pid)
          result
        end
      end
    )
  end
end
