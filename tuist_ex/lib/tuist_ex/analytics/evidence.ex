defmodule TuistEx.Analytics.Evidence do
  @moduledoc false

  # Which lines each test executed, the per-test coverage evidence
  # coverage-based test selection decides from and carried coverage reads
  # (`coverage_evidence`).
  #
  # The runtime's native line counters belong to a module, not to a process,
  # so what a test executed is the change in the counters while it ran. ExUnit
  # tells formatters about tests asynchronously, after the fact, so the
  # counters are read where ExUnit itself is at a test's boundaries:
  # `ExUnit.OnExitHandler.register/1`, which every test process calls first,
  # before its `setup`, and `ExUnit.OnExitHandler.run/2`, which the module's
  # runner calls once the test process ended and its `on_exit` callbacks ran,
  # and once a module with `setup_all` ended. `start/1` wraps the two,
  # keeping ExUnit's own code under another name.
  #
  # A test's change is its own only when nothing else ran meanwhile, which is
  # why `mix tuist.test` runs a suite that records evidence one module at a
  # time (`--max-cases 1`). One counter of events and one of what is running,
  # updated together, still tell: a test that started alone and saw no event
  # before it ended ran alone. Any other is `overlapped`, has no evidence of
  # its own, and selection always runs it.
  #
  # Reading every module's counters costs milliseconds and megabytes, so a
  # test reads them once, as it ends, in its module's runner: the reading
  # the same runner took as the previous event, the previous test's end, is
  # where the next test starts, kept in the runner's process dictionary.
  # What the runner does between two tests counts for the second.
  #
  # What a module's `setup_all` ran, from its start to its first test, what
  # its tests ran, and what the `setup_all`'s `on_exit` callbacks ran are the
  # module's `target` evidence, with what the application and the test
  # helper ran before any test, which every test depends on. A `setup_all`
  # that overlapped something leaves its tests without evidence of their own.
  #
  # Each window's lines go to a file as it ends, not to memory, and
  # `write/6` turns the file into the `coverage_evidence` JSON one record at
  # a time, so neither the run nor its report holds every test's lines.
  #
  # Nothing here may fail a test: a hook that raises turns collection off,
  # and the run reports its evidence as `failed`.

  alias TuistEx.Analytics.ExUnitPatch
  alias TuistEx.Analytics.TempDir

  @table __MODULE__
  @info Module.concat(__MODULE__, Info)
  @modules {__MODULE__, :modules}
  @last {__MODULE__, :last}
  @handler ExUnit.OnExitHandler
  @original Module.concat(__MODULE__, OriginalOnExitHandler)

  @doc """
  Whether the runtime can tell a test's process from its module's: ExUnit
  labels each test process with its test from Elixir 1.19.
  """
  def supported?, do: Version.match?(System.version(), ">= 1.19.0")

  @doc """
  Starts collecting for the suite about to run, reading the counters of
  `modules`, into a private directory of its own. Returns whether it could:
  the hooks need ExUnit's handler as this module knows it.
  """
  def start(modules) do
    stop(true)

    case install() do
      :ok ->
        dir = TempDir.create("tuist-ex-evidence")
        {:ok, device} = File.open(records_path(dir), [:write, :binary])
        :persistent_term.put(@modules, modules)
        :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])
        :ets.new(@info, [:set, :public, :named_table, write_concurrency: true])
        :ets.insert(@table, {:state, 0, 0})
        :ets.insert(@info, [{:device, device}, {:dir, dir}, {:boot, executed(read(), [])}])
        true

      _ ->
        false
    end
  rescue
    _ -> false
  end

  @doc """
  Stops collecting and returns what the suite recorded: `path`, the file
  of records `write/6` reads, in `dir`, the private directory the caller
  removes once it is done with them; `boot`, the lines each module ran
  before any test; `modules`, every counting module some record names; and
  `failed`, whether a hook failed. Nil when nothing was collecting.
  """
  def collect do
    if :ets.whereis(@info) != :undefined do
      rows = :ets.tab2list(@info)
      info = Map.new(for {key, value} <- rows, not match?({:seen, _}, key), do: {key, value})
      File.close(info.device)
      stop(false)

      %{
        path: records_path(info.dir),
        dir: info.dir,
        boot: info.boot,
        modules: Enum.uniq(Map.keys(info.boot) ++ for({{:seen, module}, _} <- rows, do: module)),
        failed: Map.has_key?(info, :failed)
      }
    end
  end

  defp records_path(dir), do: Path.join(dir, "records")

  # A suite that started collecting and never collected leaves its directory
  # to the next start.
  defp stop(remove?) do
    if remove? and :ets.whereis(@info) != :undefined do
      for {key, value} <- :ets.tab2list(@info) do
        case key do
          :device -> File.close(value)
          :dir -> File.rm_rf(value)
          _key -> :ok
        end
      end
    end

    for table <- [@table, @info], :ets.whereis(table) != :undefined, do: :ets.delete(table)
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
    if :ets.whereis(@info) != :undefined, do: :ets.insert(@info, {:failed, true})
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
        setup_end = close_setup(runner, module)
        open(pid, runner, {:test, module, name}, setup_end)

      _label ->
        open(pid, runner, :setup, nil)
        :ets.insert(@table, {{:setup, runner}, pid})
    end
  end

  defp do_finished(pid) do
    case :ets.take(@table, {:start, pid}) do
      [{_key, {:test, module, name}, seq, start}] ->
        case close(seq, start) do
          {:alone, lines} -> record({:test, {module, name}, lines})
          :overlapped -> record({:overlapped, {module, name}})
        end

      # A `setup_all` none of whose tests ran.
      [{_key, :setup, seq, start}] ->
        :ets.delete(@table, {:setup, self()})
        close(seq, start)

      [] ->
        close_module(pid)
    end
  end

  # One event more, and one more running. Alone when nothing else runs; the
  # counters are read after the update, so whatever starts after it is an
  # event the end sees. A test needn't read them when the previous event
  # did: its module's `setup_all` ending, read in this process, or the
  # previous test ending in the runner that will end this one (`:chained`).
  defp open(pid, runner, what, setup_end) do
    [seq, running] = :ets.update_counter(@table, :state, [{2, 1}, {3, 1}])

    start =
      cond do
        running != 1 -> nil
        what == :setup -> read()
        match?({_seq, _now}, setup_end) and elem(setup_end, 0) == seq - 1 -> elem(setup_end, 1)
        chained?(runner, seq) -> :chained
        true -> read()
      end

    :ets.insert(@table, {{:start, pid}, what, seq, start})
  end

  defp chained?(runner, seq) do
    case :ets.lookup(@table, :chain) do
      [{:chain, ^runner, chain_seq}] -> chain_seq == seq - 1
      _ -> false
    end
  end

  # Read before the update, so whatever started before it was an event. In
  # the runner, where the reading is also where its next test starts.
  defp close(seq, start) do
    now = if start, do: read()
    [end_seq, _running] = :ets.update_counter(@table, :state, [{2, 1}, {3, -1}])
    before = if start == :chained, do: Process.get(@last), else: start

    if now do
      Process.put(@last, now)
      :ets.insert(@table, {:chain, self(), end_seq})
    end

    if before != nil and end_seq == seq + 1,
      do: {:alone, executed(now, before)},
      else: :overlapped
  end

  # In the first test's process, which then starts where the `setup_all`
  # ended.
  defp close_setup(runner, module) do
    with [{_key, pid}] <- :ets.take(@table, {:setup, runner}),
         [{_key, :setup, seq, start}] <- :ets.take(@table, {:start, pid}) do
      :ets.insert(@table, {{:module, pid}, module})
      now = if start, do: read()
      [end_seq, _running] = :ets.update_counter(@table, :state, [{2, 1}, {3, -1}])

      if start != nil and end_seq == seq + 1,
        do: record({:target, module, executed(now, start)}),
        else: record({:setup_unknown, module})

      if now, do: {end_seq, now}
    else
      _ -> nil
    end
  end

  # A module with `setup_all` ended, in its runner, once the `setup_all`'s
  # `on_exit` callbacks ran: what they ran since the module's last test is
  # the module's too. It's no event, so the next test starts from here.
  defp close_module(pid) do
    runner = self()

    with [{_key, module}] <- :ets.take(@table, {:module, pid}),
         [{:state, seq, 0}] <- :ets.lookup(@table, :state),
         [{:chain, ^runner, ^seq}] <- :ets.lookup(@table, :chain),
         before when before != nil <- Process.get(@last) do
      now = read()
      Process.put(@last, now)
      record({:target, module, executed(now, before)})
    end
  end

  defp parent(pid) do
    case Process.info(pid, :parent) do
      {:parent, parent} -> parent
      _ -> nil
    end
  end

  # One record: its lines as ranges, framed by its size.
  defp record(term) do
    term =
      case term do
        {kind, key, lines} when kind in [:test, :target] ->
          :ets.insert(@info, for(module <- Map.keys(lines), do: {{:seen, module}, true}))
          {kind, key, Map.new(lines, fn {module, lines} -> {module, ranges(lines)} end)}

        term ->
          term
      end

    binary = :erlang.term_to_binary(term, compressed: 1)
    [{:device, device}] = :ets.lookup(@info, :device)
    IO.binwrite(device, [<<byte_size(binary)::32>>, binary])
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
  Counters are compared by position: a line can hold several, such as one
  per clause a `def` with default arguments generates. A module whose
  counters changed shape, such as one loaded again, counts every line that
  ran at all.
  """
  def executed(now, before) do
    before = Map.new(before)

    for {module, counts} <- now,
        old = Map.get(before, module, []),
        counts != old,
        ran = ran(counts, old),
        ran != [],
        into: %{},
        do: {module, ran |> Enum.uniq() |> Enum.sort()}
  end

  defp ran(counts, old) when length(counts) == length(old) do
    for {{line, count}, {_line, was}} <- Enum.zip(counts, old), line > 0, count > was, do: line
  end

  defp ran(counts, _old), do: for({line, count} <- counts, line > 0, count > 0, do: line)

  @doc """
  Writes the `coverage_evidence` JSON for what `collect/0` returned to
  `out`, a record at a time. `identities` names each test that ran,
  `{module, name}` to the `{module, suite, name}` the run reports it by;
  `sources` maps each counting module to its source file, and `relative`
  turns one into a path in the repository, nil outside it. With `lines:
  false`, scopes name their files without lines.
  """
  def write(collected, identities, sources, relative, out, options \\ []) do
    lines? = Keyword.get(options, :lines, true)

    paths =
      for {module, source} <- sources,
          path = relative.(source),
          path != nil,
          into: %{},
          do: {module, path}

    boot = by_path(collected.boot, paths)
    test_modules = identities |> Map.values() |> MapSet.new(&elem(&1, 0))

    # Where each module's last record is, to write its target once it's
    # complete: one module at a time, its records are next to each other.
    {last, unknown_setup, overlapped, _count} =
      fold_records(collected.path, {%{}, MapSet.new(), [], 0}, fn
        {kind, key, _lines}, {last, unknown, overlapped, i} when kind in [:test, :target] ->
          module = if kind == :test, do: elem(key, 0), else: key
          {Map.put(last, module, i), unknown, overlapped, i + 1}

        {:setup_unknown, module}, {last, unknown, overlapped, i} ->
          {last, MapSet.put(unknown, module), overlapped, i + 1}

        {:overlapped, key}, {last, unknown, overlapped, i} ->
          {last, unknown, [key | overlapped], i + 1}
      end)

    {:ok, file} = :file.open(out, [:write, :binary, :raw, {:delayed_write, 1_048_576, 2_000}])

    try do
      :ok = :file.write(file, ~s({"scopes":[))
      state = %{file: file, lines?: lines?, index: %{}, paths: [], first?: true}

      {state, _acc, overlapped, _i} =
        fold_records(collected.path, {state, %{}, overlapped, 0}, fn record,
                                                                     {state, acc, ov, i} ->
          {state, acc, ov, module} =
            case record do
              {:test, {module, _name} = key, lines} ->
                identity = Map.get(identities, key)

                cond do
                  MapSet.member?(unknown_setup, module) ->
                    {state, accumulate(acc, module, by_path(lines, paths, true)), [key | ov],
                     module}

                  identity == nil ->
                    {state, acc, ov, module}

                  true ->
                    by_path = by_path(lines, paths, true)
                    {state, acc} = test_scope(state, acc, identity, module, by_path)
                    {state, acc, ov, module}
                end

              {:target, module, lines} ->
                {state, accumulate(acc, module, by_path(lines, paths, true)), ov, module}

              _record ->
                {state, acc, ov, nil}
            end

          {state, acc} =
            if module != nil and Map.get(last, module) == i,
              do: target_scope(state, acc, module, boot, test_modules),
              else: {state, acc}

          {state, acc, ov, i + 1}
        end)

      # Modules none of whose windows was recorded still depend on the boot.
      written = MapSet.new(Map.keys(last), &inspect/1)

      state =
        test_modules
        |> Enum.reject(&MapSet.member?(written, &1))
        |> Enum.sort()
        |> Enum.reduce(state, &scope(&2, target_head(&1), boot))

      overlapped_tests =
        for key <- overlapped |> Enum.uniq() |> Enum.sort(),
            {module, suite, name} <- [Map.get(identities, key)],
            do: %{module: module, suite: suite, name: name}

      :ok =
        :file.write(file, [
          ~s(],"paths":),
          JSON.encode_to_iodata!(Enum.reverse(state.paths)),
          ~s(,"overlapped_tests":),
          JSON.encode_to_iodata!(overlapped_tests),
          ~s(,"status":),
          JSON.encode_to_iodata!(if(collected.failed, do: "failed", else: "collected")),
          "}"
        ])
    after
      :file.close(file)
    end
  end

  # A test's scope; what it ran is also its module's.
  defp test_scope(state, acc, {module, suite, name}, test_module, by_path) do
    head = [
      ~s("kind":"test","module":),
      JSON.encode_to_iodata!(module),
      ~s(,"suite":),
      JSON.encode_to_iodata!(suite),
      ~s(,"name":),
      JSON.encode_to_iodata!(name)
    ]

    {scope(state, head, by_path), accumulate(acc, test_module, by_path)}
  end

  defp target_head(module),
    do: [~s("kind":"target","module":), JSON.encode_to_iodata!(module), ~s(,"suite":"","name":"")]

  # A module's target, once its last record was written: what its windows
  # ran and what ran before any test.
  defp target_scope(state, acc, module, boot, test_modules) do
    {lines, acc} = Map.pop(acc, module, %{})
    name = inspect(module)

    if MapSet.member?(test_modules, name),
      do: {scope(state, target_head(name), merge(boot, lines)), acc},
      else: {state, acc}
  end

  defp accumulate(acc, module, by_path), do: Map.update(acc, module, by_path, &merge(&1, by_path))

  # `by_path` maps each path to its sorted lines.
  defp scope(state, _head, by_path) when map_size(by_path) == 0, do: state

  defp scope(state, head, by_path) do
    {state, entries} =
      Enum.reduce(by_path, {state, []}, fn {path, lines}, {state, entries} ->
        case state.index do
          %{^path => index} ->
            {state, [{index, lines} | entries]}

          index_by_path ->
            index = map_size(index_by_path)

            {%{state | index: Map.put(index_by_path, path, index), paths: [path | state.paths]},
             [{index, lines} | entries]}
        end
      end)

    entries = Enum.sort(entries)

    lines =
      if state.lines?,
        do: [~s(,"lines":), JSON.encode_to_iodata!(Enum.map(entries, &ranges(elem(&1, 1))))],
        else: []

    :ok =
      :file.write(state.file, [
        if(state.first?, do: "{", else: ",{"),
        head,
        ~s(,"files":),
        JSON.encode_to_iodata!(Enum.map(entries, &elem(&1, 0))),
        lines,
        "}"
      ])

    %{state | first?: false}
  end

  # A module's lines by the path of its source, merged across the modules
  # of one file. Records hold ranges (`expand?`), the boot sorted lines.
  defp by_path(lines, paths, expand? \\ false) do
    Enum.reduce(lines, %{}, fn {module, lines}, acc ->
      case Map.get(paths, module) do
        nil ->
          acc

        path ->
          lines = if expand?, do: expand(lines), else: lines
          Map.update(acc, path, lines, &:ordsets.union(&1, lines))
      end
    end)
  end

  defp merge(a, b), do: Map.merge(a, b, fn _path, x, y -> :ordsets.union(x, y) end)

  defp expand([first, last | rest]), do: Enum.to_list(first..last//1) ++ expand(rest)
  defp expand([]), do: []

  defp fold_records(path, acc, fun) do
    {:ok, file} = :file.open(path, [:read, :binary, :raw, {:read_ahead, 1_048_576}])

    try do
      do_fold(file, acc, fun)
    after
      :file.close(file)
    end
  end

  defp do_fold(file, acc, fun) do
    case :file.read(file, 4) do
      {:ok, <<size::32>>} ->
        {:ok, <<binary::binary-size(^size)>>} = :file.read(file, size)
        do_fold(file, fun.(:erlang.binary_to_term(binary), acc), fun)

      :eof ->
        acc
    end
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
