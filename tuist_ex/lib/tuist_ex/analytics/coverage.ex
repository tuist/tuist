defmodule TuistEx.Analytics.Coverage do
  @moduledoc false

  # The line coverage of a `mix tuist.test --cover` run, read from the
  # runtime's native line counters and Erlang's `cover`, and shaped as the
  # server's `coverage` block: one entry per source file of the repository,
  # with the OTP application it belongs to, whether it is test code, and how
  # many times each executable line ran.
  #
  # The counters are read by the formatter when the suite finishes: every test
  # has run, and Mix's own coverage tool has not yet turned them into its
  # report, nor, in an umbrella, restarted `cover` for the next application.

  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Git
  alias TuistEx.HTTP, as: Client

  # What picks tests other than the whole suite. `--include` only adds tests
  # the configuration excluded, and a shard's files are known to the server
  # from the shard plan, so neither makes a run partial.
  @filters ~w(--only --exclude --failed --stale --name-pattern --max-failures)
  # The `mix test` options that take a value, which is not a test file.
  @value_switches ~w(--only --exclude --include --seed --timeout --max-cases --max-failures
                     --max-requires --partitions --formatter --slowest --slowest-modules
                     --name-pattern --export-coverage --exit-status --repeat-until-failure)

  # The native counters of the modules Mimic copied, from before the copy.
  @before_swap {__MODULE__, :before_swap}

  # What limits a run to the tests it names, rather than leaving some out.
  @selectors ~w(--only --failed --stale --name-pattern)

  # The chunk of a module with counters in code compiled into it from another
  # file, as Phoenix and EEx compile `.heex` and `.eex` templates under
  # `@file`: the file, by its number (`included_files/1`, 0 for the module's
  # own source), and the line of each counter, by the counter's ID less one.
  @ids_chunk ~c"TCov"

  def requested?(test_args), do: "--cover" in test_args

  @doc """
  Whether the run's own arguments limit it to the tests they select:
  `--only`, `--failed`, `--stale`, `--name-pattern`, or explicit test files or
  lines. Such a run names the tests it ran; any other partial run names the
  tests it left out.
  """
  def narrowed?(test_args) do
    files?(test_args) or
      Enum.any?(test_args, fn arg ->
        Enum.any?(@selectors, &(arg == &1 or String.starts_with?(arg, &1 <> "=")))
      end)
  end

  @doc """
  The tags the run's own `--exclude` options filter on, as ExUnit names
  them in an exclusion's reason (`"due to <tag> filter"`).
  """
  def excluded_tags(test_args) do
    {options, _rest, _invalid} = OptionParser.parse(test_args, switches: [exclude: :keep])
    for {:exclude, filter} <- options, do: filter |> String.split(":", parts: 2) |> hd()
  end

  @doc """
  Whether the run's own arguments left tests out on purpose: a filter, or
  explicit test files or lines.
  """
  def partial?(test_args) do
    files?(test_args) or
      Enum.any?(test_args, fn arg ->
        Enum.any?(@filters, &(arg == &1 or String.starts_with?(arg, &1 <> "=")))
      end)
  end

  defp files?([switch, _value | rest]) when switch in @value_switches, do: files?(rest)
  defp files?(["-" <> _ | rest]), do: files?(rest)
  defp files?([_file | _rest]), do: true
  defp files?([]), do: false

  @doc """
  The run's line counters, one entry per source file with its lines and its
  functions, or nil when nothing counted. A template compiled into a module
  has an entry of its own, and so has each external resource of a module
  that ran, without lines (`sources/3`). Called in the project the suite
  belongs to, an umbrella's application for its own suite: its test paths say
  what is test code, and its directory finds sources a build compiled
  elsewhere.
  """
  def snapshot(project_dir \\ File.cwd!(), config \\ Mix.Project.config()) do
    with {entries, calls} <- line_entries(config) do
      test_dirs = Enum.map(config[:test_paths] || ["test"], &Path.expand(&1, project_dir))
      default_app = config[:app] && to_string(config[:app])
      ignored = get_in(config, [:test_coverage, :ignore_modules]) || []

      resources = resources(project_dir, config)

      entries
      |> Enum.reject(fn {{_module, line}, _count} -> line == {0, 0} end)
      |> Enum.group_by(fn {{module, _line}, _count} -> module end, fn {{_module, line}, count} ->
        {line, count}
      end)
      |> Enum.map(fn {module, lines} -> {original(module), lines} end)
      |> Enum.reject(fn {module, _lines} -> ignored?(module, ignored) end)
      |> Enum.flat_map(fn {module, lines} ->
        {files, clauses} = module_files(module, project_dir, config)
        app = application(module) || default_app

        counted =
          lines
          |> Enum.group_by(fn {{index, _line}, _count} -> index end, fn {{_index, line}, count} ->
            {line, count}
          end)
          |> Enum.flat_map(fn {index, lines} ->
            # A template's code without a line, as a static one may only
            # have, still says the module counts in it.
            case Map.fetch(files, index) do
              {:ok, path} ->
                clauses = if index == 0, do: clauses, else: []

                [
                  {path, app, Enum.reject(lines, &(elem(&1, 0) == 0)),
                   Enum.map(clauses, fn {head, body, function} ->
                     {head, body, {module, function}}
                   end)}
                ]

              :error ->
                []
            end
          end)

        # A module that ran depends on its external resources, which hold
        # no lines.
        if Enum.any?(lines, fn {_line, count} -> count > 0 end),
          do:
            counted ++
              for(path <- module_resources(resources, module, files), do: {path, app, [], []}),
          else: counted
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(fn {path, modules} ->
        # Several modules can share a file, and a line attributed to more
        # than one keeps its highest count, as excoveralls does. A module
        # Mimic copied is one of them: the counters from before the copy stay
        # under its own name, the later ones under its original's.
        lines =
          Enum.reduce(modules, %{}, fn {_path, _app, lines, _clauses}, acc ->
            Enum.reduce(lines, acc, fn {line, count}, acc ->
              Map.update(acc, line, count, &max(&1, count))
            end)
          end)

        %{
          path: path,
          app: modules |> hd() |> elem(1),
          test?: Enum.any?(test_dirs, &String.starts_with?(path, &1 <> "/")),
          lines: lines,
          functions: functions(Enum.flat_map(modules, &elem(&1, 3)), lines, calls)
        }
      end)
    end
  end

  @doc """
  Whether each executable line of each of the project's modules ran, by
  module, as Mix's coverage tool summarizes them: Mimic's copies count as
  their originals, and the modules the configuration ignores are left out.
  """
  def module_lines(config \\ Mix.Project.config()) do
    ignored = get_in(config, [:test_coverage, :ignore_modules]) || []

    case line_entries(config) do
      nil ->
        %{}

      {entries, _calls} ->
        entries
        # Mix's tool counts no template line, so neither do its summary
        # and threshold.
        |> Enum.reject(fn {{_module, {index, line}}, _count} -> index != 0 or line == 0 end)
        |> Enum.reduce(%{}, fn {{module, {_index, line}}, count}, acc ->
          Map.update(acc, original(module), %{line => count > 0}, fn lines ->
            Map.update(lines, line, count > 0, &(&1 or count > 0))
          end)
        end)
        |> Map.reject(fn {module, _lines} -> ignored?(module, ignored) end)
    end
  end

  # The counters `cover` holds and, in a runtime counting natively, those of
  # the project's modules `cover` did not compile: a build `instrument/1`
  # prepared counts in its own code. Nil when nothing counts.
  defp line_entries(config) do
    cover? = Process.whereis(:cover_server) != nil
    # Without the JIT the runtime has no coverage mode to ask about: asking raises.
    native? = :code.coverage_support() and :code.get_coverage_mode() != :none

    if cover? or native? do
      {cover_entries, compiled, calls} =
        if cover? do
          {:result, entries, _failures} = :cover.analyse(:calls, :line)

          {for({{module, line}, count} <- entries, do: {{module, {0, line}}, count}),
           MapSet.new(:cover.modules(), &original/1), function_calls()}
        else
          {[], MapSet.new(), %{}}
        end

      native_entries = if native?, do: native_lines(config, compiled), else: []
      {cover_entries ++ native_entries, calls}
    end
  end

  # A module the run never loaded still counts its lines, so every module of
  # the build is loaded first. Mimic's copies count as their originals'.
  defp native_lines(config, compiled) do
    project = config |> Mix.Project.compile_path() |> build_modules() |> MapSet.new()

    counted =
      for module <- native_modules(config),
          source = original(module),
          not MapSet.member?(compiled, source),
          {line, count} <- counted_lines(module),
          do: {{source, line}, count}

    before_swap =
      for {{module, _line}, _count} = entry <- :persistent_term.get(@before_swap, []),
          MapSet.member?(project, module) and not MapSet.member?(compiled, module),
          do: entry

    # A copied module's lines add up its calls from before and after the swap.
    (counted ++ before_swap)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {key, counts} -> {key, Enum.sum(counts)} end)
  end

  @doc """
  The loaded modules that count the project's lines natively: every module of
  the build, loaded first, and Mimic's copies of them, less Mimic's proxies,
  which count lines of Mimic's own source.
  """
  def native_modules(config \\ Mix.Project.config()) do
    project = config |> Mix.Project.compile_path() |> build_modules()
    Enum.each(project, &Code.ensure_loaded/1)
    project = MapSet.new(project)

    for {module, _path} <- :code.all_loaded(),
        MapSet.member?(project, original(module)),
        not function_exported?(module, :__mimic_info__, 0),
        :code.get_coverage_mode(module) != :none,
        do: module
  end

  @doc """
  The files each of `modules` counts lines of, found under `project_dir`
  when the build was compiled elsewhere, with Mimic's copies under their
  originals': `files`, by number, the module's source as 0 and the
  templates compiled into it after it; `ids`, the file number and line of
  each of its counters, by ID less one, when it counts by ID
  (`counter_level/1`), nil otherwise; and `resources`, its other external
  resources, which every scope that ran the module depends on. Modules
  without a file in the project are left out.
  """
  def sources(modules, project_dir \\ File.cwd!(), config \\ Mix.Project.config()) do
    resources = resources(project_dir, config)

    for module <- Enum.uniq(modules),
        {files, _clauses} = module_files(original(module), project_dir, config),
        files != %{},
        into: %{},
        do:
          {module,
           %{
             files: files,
             ids: counter_ids(module),
             resources: module_resources(resources, original(module), files)
           }}
  end

  @doc """
  How `:code.get_coverage/2` reads the module's counters: by ID
  (`:cover_id_line`) when `instrument/3` counted code compiled into it from
  another file, whose lines `sources/3`'s `ids` say, and by line otherwise,
  all of them the module's own source's. Mimic's copies, compiled from the
  module's code without that file's counters, count by line.
  """
  def counter_level(module), do: if(counter_ids(module), do: :cover_id_line, else: :line)

  # The module's counters by the file number and line each counts.
  defp counted_lines(module) do
    case counter_ids(module) do
      nil ->
        for {line, count} <- :code.get_coverage(:line, module), do: {{0, line}, count}

      ids ->
        for {id, count} <- :code.get_coverage(:cover_id_line, module),
            do: {elem(ids, id - 1), count}
    end
  end

  @doc """
  The file number and line of each of the module's counters, by ID less
  one, as `instrument/3` wrote them to its build, read from the file it was
  loaded from: nil when it counts by line, as a copy Mimic loaded from
  memory does.
  """
  def counter_ids(module) do
    with path when is_list(path) and path != [] <- :code.which(module),
         {:ok, {_module, [{@ids_chunk, binary}]}} when is_binary(binary) <-
           :beam_lib.chunks(path, [@ids_chunk], [:allow_missing_chunks]) do
      :erlang.binary_to_term(binary)
    else
      _ -> nil
    end
  end

  # The module's files in the project, by number: its source, 0, and the
  # files code was compiled into it from, as `included_files/1` numbers them.
  # An included file outside the project or in its dependencies, such as a
  # library's macro whose code keeps its own location, is left out. With
  # where its own function clauses start.
  defp module_files(module, project_dir, config) do
    {files, clauses} = build_info(module)

    located =
      for {index, file} <- files,
          file != nil,
          path = locate(Path.expand(file, project_dir), project_dir),
          path != nil,
          index == 0 or in_project?(path, project_dir, config),
          into: %{},
          do: {index, path}

    {located, clauses}
  end

  # Whether a file is the project's own, rather than outside it or in its
  # dependencies.
  defp in_project?(path, project_dir, config) do
    deps = Path.expand(config[:deps_path] || "deps", project_dir)
    String.starts_with?(path, project_dir <> "/") and not String.starts_with?(path, deps <> "/")
  end

  # The external resources of a module, less the files it counts lines of.
  defp module_resources(resources, module, files) do
    counted = files |> Map.values() |> MapSet.new()
    resources |> Map.get(module, []) |> Enum.reject(&MapSet.member?(counted, &1))
  end

  @doc """
  The files each of the project's modules names with `@external_resource`,
  such as a Gettext backend's `.po` files, a template or data read at
  compile time, as absolute paths. The BEAM keeps none of them: Mix's
  compile manifest has them, by the source file that names them, which
  holds the modules. A manifest Mix can't read names none.
  """
  def resources(project_dir \\ File.cwd!(), config \\ Mix.Project.config()) do
    manifest = Path.join(Mix.Project.manifest_path(config), "compile.elixir")
    {_modules, sources} = Mix.Compilers.Elixir.read_manifest(manifest)

    # `Mix.Compilers.Elixir`'s private `source` record, the same from Elixir
    # 1.18 to 1.20; another shape names nothing.
    Enum.reduce(sources, %{}, fn
      {_source, {:source, _, _, _, _, _, _, _, external, _, _, modules}}, acc
      when external != [] ->
        paths =
          for entry <- external,
              file = if(is_tuple(entry), do: elem(entry, 0), else: entry),
              is_binary(file),
              path = file |> Path.expand(project_dir) |> resolve_links(),
              File.regular?(path),
              uniq: true,
              do: path

        Enum.reduce(
          module_paths(paths, modules),
          acc,
          fn {module, paths}, acc ->
            Map.update(acc, module, paths, &Enum.uniq(&1 ++ paths))
          end
        )

      _source, acc ->
        acc
    end)
  rescue
    _ -> %{}
  end

  # Each of a source's modules with the resources it depends on: all of them,
  # but a Gettext catalog one of the modules holds (`catalog_owners/2`).
  defp module_paths(paths, modules) do
    owners = catalog_owners(paths, modules)

    for module <- modules,
        do: {module, for(path <- paths, module in Map.get(owners, path, [module]), do: path)}
  end

  # The modules that hold each Gettext catalog among a source's resources. A
  # backend split by locale or domain (`split_module_by:`) compiles each
  # `<locale>/LC_MESSAGES/<domain>.po` into a module of its own,
  # `<Backend>.T_<locale>_<domain>` (`T_<locale>` or `T_<domain>` when split
  # by one), defined from the backend's source; the backend only routes to it.
  # So the catalog is that module's alone, and a test depends on it only when
  # it looked a message up in that locale and domain. A catalog no module of
  # the source holds, as an unsplit backend's, stays every module's.
  defp catalog_owners(paths, modules) do
    names = MapSet.new(modules, &inspect/1)

    split =
      Enum.group_by(
        for(
          module <- modules,
          [_, backend, suffix] <- [Regex.run(~r/^(.+)\.T_([^.]+)$/, inspect(module))],
          MapSet.member?(names, backend),
          do: {suffix, module}
        ),
        &elem(&1, 0),
        &elem(&1, 1)
      )

    for path <- paths,
        [file, "LC_MESSAGES", locale | _] <- [path |> Path.split() |> Enum.reverse()],
        Path.extname(file) == ".po",
        domain = Path.rootname(file, ".po"),
        owners = Enum.flat_map([locale <> "_" <> domain, locale, domain], &Map.get(split, &1, [])),
        owners != [],
        into: %{},
        do: {path, owners}
  end

  # The path with its symbolic links resolved, as Git names the file: a module
  # that reads `Application.app_dir/2` names its resources through the build's
  # `priv` link to the project's `priv`. Gives up after 32 links.
  defp resolve_links(path), do: resolve_links(Path.split(path), [], 32)

  defp resolve_links(rest, resolved, 0), do: Path.join(resolved ++ rest)
  defp resolve_links([], resolved, _budget), do: Path.join(resolved)

  defp resolve_links([part | rest], resolved, budget) do
    current = Path.join(resolved ++ [part])

    case :file.read_link(current) do
      {:ok, target} ->
        target = target |> to_string() |> Path.expand(Path.dirname(current))
        resolve_links(Path.split(target) ++ rest, [], budget - 1)

      {:error, _reason} ->
        resolve_links(rest, resolved ++ [part], budget)
    end
  end

  defp build_modules(ebin) do
    for beam <- Path.wildcard(Path.join(ebin, "*.beam")),
        do: beam |> Path.basename(".beam") |> String.to_atom()
  end

  @doc """
  Recompiles the modules in the build directories `dirs`, the compile path
  and the consolidated protocols', from their debug info with the
  runtime's native line counters, so that a run counting natively
  (`enable_native/1`) compiles nothing for `cover`, which recompiles every
  module at the start of each run. A module that already carries the
  counters is left as it is, so only what a compile wrote since is
  recompiled. The Elixir compiler leaves the counters out even when asked
  for them, which is why this starts from the debug info. The module keeps
  its own debug info, which protocol consolidation reads, and the chunks
  only Elixir writes, such as the docs doctests read. A module without debug
  info stays as it was. Code compiled into a module from another file counts
  only when that file is in the project at `project_dir`, such as a
  template, not a dependency's macro. Returns how many modules were
  instrumented and the ones that could not be.
  """
  def instrument(dirs, project_dir \\ File.cwd!(), config \\ Mix.Project.config()) do
    project_dir = Path.expand(project_dir)
    project? = &in_project?(Path.expand(to_string(&1), project_dir), project_dir, config)

    results =
      dirs
      |> List.wrap()
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.beam")))
      |> Task.async_stream(&{&1, instrument_beam(&1, project?)},
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    {Enum.count(results, &(elem(&1, 1) == :instrumented)),
     for({path, :skipped} <- results, do: Path.basename(path))}
  end

  defp instrument_beam(path, project?) do
    beam = String.to_charlist(path)

    # Decoding Elixir's debug info is the costly part, so a module that
    # already carries the counters is told apart by its compile options first.
    with {:ok, {_module, [compile_info: info]}} <- :beam_lib.chunks(beam, [:compile_info]),
         false <- :line_coverage in (info[:options] || []),
         {:ok, {module, [abstract_code: {:raw_abstract_v1, forms}]}} <-
           :beam_lib.chunks(beam, [:abstract_code]),
         {:ok, ^module, binary, ids} <- compile_native(forms, info, project?),
         {:ok, _module, original} <- :beam_lib.all_chunks(beam),
         {:ok, _module, chunks} <- :beam_lib.all_chunks(binary),
         chunks =
           Enum.map(Enum.reject(chunks, &(elem(&1, 0) == ~c"Dbgi")), &counted_info/1) ++
             if(ids, do: [{@ids_chunk, :erlang.term_to_binary(ids, [:compressed])}], else: []),
         ids = MapSet.new(chunks, &elem(&1, 0)),
         {:ok, binary} <-
           :beam_lib.build_module(
             chunks ++ Enum.reject(original, &MapSet.member?(ids, elem(&1, 0)))
           ) do
      File.write!(path, binary)
      :instrumented
    else
      true -> :already
      _ -> :skipped
    end
  end

  # Erlang counts only the code of a module's own file: none of a template's,
  # which Phoenix and EEx compile into it after a `-file` attribute naming
  # the template. For each such file in the project, the forms go to the
  # instrumentation with its attribute naming the module's own source, and
  # come back with the attribute as it was, so the line table, stack traces,
  # and each counter's line still name the template and its lines. The
  # counters are numbered in order, and the file and line of each, by number
  # less one, are the module's `@ids_chunk`, which `:cover_id_line` reads
  # by. A file outside the project, such as a dependency's macro that keeps
  # its own location, gets no counters, as Erlang has it. Forms the
  # instrumentation can't take back that way are compiled as any other.
  defp compile_native(forms, info, project?) do
    counted =
      for {file, index} <- included_files(forms), project?.(file), into: %{}, do: {file, index}

    with true <- counted != %{},
         [own | _] <- for({:attribute, _anno, :file, {file, _line}} <- forms, do: file),
         {:ok, instrumented} <-
           forms |> Enum.map(&as_own_file(&1, counted, own)) |> :sys_coverage.module([]),
         true <- length(instrumented) == length(forms),
         {restored, {_index, ids}} =
           forms
           |> Enum.zip(instrumented)
           |> Enum.map_reduce({0, %{}}, &restore_file(&1, &2, counted)),
         true <- ids != %{},
         {:ok, module, binary} <- :compile.forms(restored, native_options(info)) do
      ids = List.to_tuple(for id <- 1..Enum.max(Map.keys(ids)), do: Map.get(ids, id, {0, 0}))
      {:ok, module, binary, ids}
    else
      _ -> compile_counted(forms, info)
    end
  rescue
    _ -> compile_counted(forms, info)
  end

  defp compile_counted(forms, info) do
    with {:ok, module, binary} <- :compile.forms(forms, [:line_coverage | native_options(info)]),
         do: {:ok, module, binary, nil}
  end

  defp as_own_file({:attribute, anno, :file, {file, line}}, counted, own)
       when is_map_key(counted, file), do: {:attribute, anno, :file, {own, line}}

  defp as_own_file(form, _counted, _own), do: form

  # A form as it was, and the file number and line of each of its counters,
  # by number, the file being the counted one it's in, or the module's own,
  # 0. The instrumentation keeps the forms one to one.
  defp restore_file(
         {{:attribute, _, :file, {file, _}} = form, _instrumented},
         {_index, ids},
         counted
       ), do: {form, {Map.get(counted, file, 0), ids}}

  defp restore_file({_form, instrumented}, {index, ids}, _counted),
    do: {instrumented, {index, counter_lines(instrumented, index, ids)}}

  defp counter_lines({:executable_line, anno, id}, index, ids),
    do: Map.put(ids, id, {index, :erl_anno.line(anno)})

  defp counter_lines(term, index, ids) when is_tuple(term),
    do: counter_lines(Tuple.to_list(term), index, ids)

  defp counter_lines(list, index, ids) when is_list(list),
    do: Enum.reduce(list, ids, &counter_lines(&1, index, &2))

  defp counter_lines(_term, _index, ids), do: ids

  # Compiled without `:line_coverage`, which would instrument the forms
  # again, a module with a template still says it carries the counters: so
  # `instrument/1` leaves it as it is, and Mimic, which compiles its copies
  # with the module's own options, counts in them.
  defp counted_info({~c"CInf", binary}) do
    info = :erlang.binary_to_term(binary)
    options = Enum.uniq([:line_coverage | :proplists.get_value(:options, info, [])])
    {~c"CInf", :erlang.term_to_binary(List.keystore(info, :options, 0, {:options, options}))}
  end

  defp counted_info(chunk), do: chunk

  # The module's own options, less those that tell the Erlang compiler its
  # input is Elixir's Core Erlang: the counters are added to the abstract code.
  defp native_options(info) do
    options =
      Enum.reject(
        info[:options] || [],
        &(&1 in [:from_core, :no_core_prepare, :binary, :line_coverage])
      )

    [:binary, :debug_info, {:source, info[:source]} | options]
  end

  @doc """
  Switches the runtime to native line counters and loads the modules of the
  build in `ebin` with them, so a run needs no `+JPcover` flag. The mode set
  after boot applies only to code loaded explicitly, not to modules loaded on
  demand, so every module is loaded here, before the application starts; one
  loaded earlier is loaded again, unless a process still runs its previous
  version. False where the runtime cannot count natively, which needs the JIT.
  """
  def enable_native(ebin) do
    if :code.coverage_support() and :code.get_coverage_mode() == :none,
      do: :code.set_coverage_mode(:line_counters)

    if :code.coverage_support() and :code.get_coverage_mode() == :line_counters do
      ebin |> build_modules() |> Enum.each(&load_native/1)
      true
    else
      false
    end
  end

  defp load_native(module) do
    cond do
      :code.is_loaded(module) == false -> :code.load_file(module)
      :code.get_coverage_mode(module) != :none -> :ok
      :code.soft_purge(module) -> :code.load_file(module)
      true -> :ok
    end
  end

  @doc """
  Readies a run of an instrumented build once the test helper has run and
  before any test does: the modules Mimic will copy are swapped for Mimic's
  copies now, and not at their first stub, so no test runs before a swap.
  Mimic compiles each module's original under another name with the
  module's own options, which carry the native counters, so the calls the
  tests make count without `cover`. The calls made before the swap, while
  the application started, are in the counters of the code the swap
  replaces, so they are read first and added to the copy's.
  """
  def prepare_native(config \\ Mix.Project.config()) do
    case mimic_modules(config) do
      [] ->
        :ok

      modules ->
        # Each module's counters are read right before its own swap: the
        # application's processes keep calling it while the others swap.
        before =
          Enum.flat_map(modules, fn module ->
            counts = called_lines(module)
            Mimic.calls(module, :module_info, 0)
            counts
          end)

        :persistent_term.put(@before_swap, before)
    end
  end

  defp called_lines(module) do
    if :code.is_loaded(module) != false and :code.get_coverage_mode(module) != :none do
      for {line, count} <- counted_lines(module),
          count > 0,
          do: {{module, line}, count}
    else
      []
    end
  end

  defp mimic_modules(config) do
    case mimic_coordinator() do
      nil ->
        []

      coordinator ->
        for beam <- config |> Mix.Project.compile_path() |> Path.join("*.beam") |> Path.wildcard(),
            module = beam |> Path.basename(".beam") |> String.to_atom(),
            coordinator.marked_to_copy?(module),
            do: module
    end
  end

  # Mimic 2.4 moved what it marks to copy from `Mimic.Server` to
  # `Mimic.Coordinator`.
  defp mimic_coordinator do
    Enum.find([Mimic.Coordinator, Mimic.Server], fn coordinator ->
      Code.ensure_loaded?(coordinator) and function_exported?(coordinator, :marked_to_copy?, 1) and
        Process.whereis(coordinator) != nil
    end)
  end

  @doc """
  A shard's arguments for `mix test`, exporting its coverage when it is
  measured and nothing exports it yet. Mix's coverage tool would otherwise
  hold a shard, which runs only part of the suite, to the whole project's
  threshold (90% unless configured) and write its report there. Tuist reads
  the counters itself, so what Mix exports, under `cover/shard-<index>`, is
  only for the project's own tools.
  """
  def with_shard_export(test_args, index) do
    exported? =
      Enum.any?(
        test_args,
        &(&1 == "--export-coverage" or String.starts_with?(&1, "--export-coverage="))
      )

    if requested?(test_args) and not exported?,
      do: test_args ++ ["--export-coverage", "shard-#{index}"],
      else: test_args
  end

  @doc """
  The arguments for `mix test` without Mix's own coverage tool, which a run
  counting natively does not need: it would compile every module again.
  """
  def without_cover(["--cover" | rest]), do: without_cover(rest)
  def without_cover(["--export-coverage", _name | rest]), do: without_cover(rest)
  def without_cover(["--export-coverage=" <> _name | rest]), do: without_cover(rest)
  def without_cover([arg | rest]), do: [arg | without_cover(rest)]
  def without_cover([]), do: []

  # The modules the project's coverage configuration leaves out, as Mix's
  # coverage tool reads `ignore_modules`: a module, or a pattern its name
  # matches.
  defp ignored?(module, ignored) do
    Enum.any?(ignored, fn
      %Regex{} = pattern -> Regex.match?(pattern, inspect(module))
      other -> other == module
    end)
  end

  # Mimic, the mocking library most suites use, swaps a copied module for a
  # proxy and keeps the original's code under another name, cover-compiled
  # from its binary when `cover` compiled the original, so the counters a
  # test moves in it are the original module's lines.
  @mimic_original ".Mimic.Original.Module"

  defp original(module) do
    name = Atom.to_string(module)

    if String.ends_with?(name, @mimic_original),
      do: name |> String.replace_suffix(@mimic_original, "") |> String.to_atom(),
      else: module
  end

  # How many times each function was called, keyed by the module it belongs
  # to once Mimic's copies are mapped back to their originals.
  defp function_calls do
    {:result, entries, _failures} = :cover.analyse(:calls, :function)

    Map.new(entries, fn {{module, name, arity}, count} ->
      {{original(module), name, arity}, count}
    end)
  end

  # The module's files, its source as 0 and the files `included_files/1`
  # numbers, and where each of its own function clauses starts, read off its
  # build: a module cover-compiled from a binary, as Mimic's copies are,
  # names no source of its own.
  defp build_info(module) do
    with path when is_list(path) <- :code.where_is_file(~c"#{module}.beam"),
         {:ok, {_module, chunks}} <-
           :beam_lib.chunks(path, [:compile_info, :abstract_code], [:allow_missing_chunks]) do
      source =
        case chunks[:compile_info] do
          info when is_list(info) -> if source = info[:source], do: to_string(source)
          _ -> nil
        end

      forms =
        case chunks[:abstract_code] do
          {:raw_abstract_v1, forms} -> forms
          _ -> []
        end

      included = included_files(forms)
      files = Map.new(included, fn {file, index} -> {index, to_string(file)} end)
      {Map.put(files, 0, source), clause_starts(forms, included)}
    else
      _ -> {%{}, []}
    end
  end

  # Each clause's head line, which is where its function is said to start,
  # and the line of its first expression, which runs once per call that
  # takes the clause. Only the module's own: a template's function has no
  # head line in the template (Phoenix's is generated, EEx's is the line
  # that compiles it), so a template's lines belong to no function.
  defp clause_starts(forms, included) do
    forms
    |> Enum.flat_map_reduce(true, fn
      {:attribute, _anno, :file, {file, _line}}, _own? ->
        {[], not Map.has_key?(included, file)}

      {:function, _anno, name, arity, clauses}, true ->
        starts =
          for {:clause, anno, _args, _guards, [first | _]} <- clauses,
              line = :erl_anno.line(anno),
              line > 0,
              do: {line, :erl_anno.line(elem(first, 1)), {name, arity}}

        {starts, true}

      _form, own? ->
        {[], own?}
    end)
    |> elem(0)
  end

  # The files other than its own a module's forms say code comes from,
  # numbered from 1 in the order they first appear. The first `-file` names
  # the module's own source.
  defp included_files(forms) do
    case for({:attribute, _anno, :file, {file, _line}} <- forms, do: file) do
      [own | files] ->
        files |> Enum.reject(&(&1 == own)) |> Enum.uniq() |> Enum.with_index(1) |> Map.new()

      [] ->
        %{}
    end
  end

  # Each executable line belongs to the function whose clause head starts
  # closest above it, including the anonymous functions inside it, whichever
  # of the file's modules it is in. Functions the compiler generates
  # (`__info__/1`, `__struct__/0`, `module_info/0`) are not listed, but still
  # end the function before them. A function's executions are the runs of its
  # clauses' first expressions, as cover counts calls, or cover's own count
  # when that is higher: the calls a module Mimic copied took before the copy
  # are only in its lines.
  defp functions(clauses, lines, calls) do
    clauses = Enum.uniq(clauses)

    starts =
      clauses |> Enum.map(fn {head, _body, function} -> {head, function} end) |> Enum.sort()

    head_lines =
      clauses
      |> Enum.sort()
      |> Enum.reduce(%{}, fn {head, _body, function}, acc -> Map.put_new(acc, function, head) end)

    # A line two functions' clauses start on, as a default argument's does,
    # counts both, so it says nothing about either.
    shared =
      clauses
      |> Enum.group_by(fn {_head, body, _function} -> body end, fn {_head, _body, function} ->
        function
      end)
      |> Enum.filter(fn {_body, functions} -> functions |> Enum.uniq() |> length() > 1 end)
      |> MapSet.new(fn {body, _functions} -> body end)

    clause_calls =
      Enum.reduce(clauses, %{}, fn {_head, body, function}, acc ->
        count = if MapSet.member?(shared, body), do: 0, else: Map.get(lines, body, 0)
        Map.update(acc, function, count, &(&1 + count))
      end)

    lines
    |> Enum.sort()
    |> Enum.reduce({starts, nil, %{}}, fn {line, count}, {starts, owner, acc} ->
      {starts, owner} = advance(starts, owner, line)
      acc = if owner, do: Map.update(acc, owner, [count], &[count | &1]), else: acc
      {starts, owner, acc}
    end)
    |> elem(2)
    |> Enum.reject(fn {{_module, {name, _arity}}, _counts} -> generated?(name) end)
    |> Enum.map(fn {{module, {name, arity}} = function, counts} ->
      %{
        name: "#{name}/#{arity}",
        line: Map.fetch!(head_lines, function),
        calls: max(Map.get(calls, {module, name, arity}, 0), Map.fetch!(clause_calls, function)),
        covered: Enum.count(counts, &(&1 > 0)),
        executable: length(counts)
      }
    end)
    |> Enum.sort_by(&{&1.line, &1.name})
  end

  defp advance([{start, function} | rest], _owner, line) when start <= line,
    do: advance(rest, function, line)

  defp advance(starts, owner, _line), do: {starts, owner}

  defp generated?(name),
    do: name == :module_info or String.starts_with?(Atom.to_string(name), "__")

  defp application(module) do
    case :application.get_application(module) do
      {:ok, app} -> to_string(app)
      :undefined -> nil
    end
  end

  # A build compiled on another machine, such as a shard's, names its sources
  # by that machine's paths. Its files are found here by the longest suffix
  # that exists under the project.
  defp locate(nil, _project_dir), do: nil

  defp locate(path, project_dir) do
    if File.regular?(path) do
      path
    else
      parts = Path.split(path)

      Enum.find_value(1..max(length(parts) - 1, 1)//1, fn drop ->
        candidate = Path.join([project_dir | Enum.drop(parts, drop)])
        if File.regular?(candidate), do: candidate
      end)
    end
  end

  @doc """
  The `coverage` block for the files a snapshot holds that live in the
  repository at `root`, keyed by their path relative to it, with the blob each
  had in the checkout. Test code keeps its counts but not its lines: the
  server leaves it out of every figure.
  """
  def report(snapshot, root, blob_ids, partial?) do
    files =
      for %{path: path} = file <- snapshot, relative = relative(path, root), relative != nil do
        {line_numbers, execution_counts} =
          file.lines |> Enum.sort() |> Enum.unzip()

        covered = Enum.count(execution_counts, &(&1 > 0))

        %{
          path: relative,
          git_blob_id: Map.get(blob_ids, relative),
          targets: List.wrap(file.app),
          is_test: file.test?,
          covered_lines: covered,
          executable_lines: length(line_numbers),
          line_numbers: if(file.test?, do: [], else: line_numbers),
          execution_counts: if(file.test?, do: [], else: execution_counts),
          functions:
            if(file.test?, do: [], else: Enum.map(Map.get(file, :functions, []), &function_row/1))
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
      end

    %{
      tool: "cover",
      tool_version: "OTP #{Env.otp_version()}/Elixir #{Env.elixir_version()}",
      partial: partial?,
      files: Enum.sort_by(files, & &1.path)
    }
  end

  defp function_row(function) do
    %{
      name: function.name,
      line_number: function.line,
      execution_count: function.calls,
      covered_lines: function.covered,
      executable_lines: function.executable
    }
  end

  defp relative(path, root) do
    if String.starts_with?(path, root <> "/"), do: Path.relative_to(path, root)
  end

  @doc """
  Builds a run's block from the snapshots its formatter took. Reads the
  repository's root and blobs from the checkout at `dir`.
  """
  def build(snapshot, dir, partial?) do
    with {:ok, root} <- Git.toplevel(dir) do
      root = Path.expand(root)
      covered = MapSet.new(snapshot, &relative(&1.path, root))

      blob_ids =
        case Git.blob_ids(root, &MapSet.member?(covered, &1)) do
          {:ok, blob_ids} -> blob_ids
          :error -> %{}
        end

      {:ok, report(snapshot, root, blob_ids, partial?)}
    end
  end

  @doc """
  Puts the block into the run's payload: inline when its uncompressed size is
  within the server's threshold and within `budget`, what the report's body
  limit leaves it, and otherwise uploaded first, compressed, the run naming
  the upload's key. The server holds an inline run to its body limit after
  inflating it, and coverage compresses tenfold or more, so the decision
  reads the uncompressed size. The run's evidence is decided afterwards, from
  what's left.
  """
  def attach(payload, coverage, budget, options) do
    ndjson = Enum.map_join(coverage.files, "\n", &JSON.encode!/1)

    if byte_size(ndjson) <= min(inline_threshold(options), budget) do
      {:ok, Map.put(payload, :coverage, coverage)}
    else
      compressed = deflate(ndjson)

      with {:ok, %{"storage_key" => key, "upload_url" => url}} <-
             HTTP.project_request(
               :post,
               "/tests/coverage/uploads",
               %{test_run_id: payload.id},
               options
             ),
           {:ok, _etag} <- Client.put_binary(url, compressed) do
        {:ok,
         Map.put(payload, :coverage, coverage |> Map.delete(:files) |> Map.put(:storage_key, key))}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_response, other}}
      end
    end
  end

  @doc """
  Uploads the run's per-test evidence, `ndjson` as `Evidence.write/6` wrote
  it with `format: :ndjson`, when its uncompressed size is past the server's
  inline threshold or `budget`, what the report's body limit leaves it once
  the coverage is in (the server holds a deflated body's inflated size to the
  limit), and puts `rest` (`overlapped_tests`, `status`) with the upload's key
  into the payload. `:inline` when it's small enough to send
  inline, or the server predates evidence uploads; `{:error, reason}` when
  the upload failed.
  """
  def attach_evidence(payload, ndjson, rest, budget, options) do
    with true <- File.stat!(ndjson).size > min(inline_threshold(options), budget),
         {:ok, %{"evidence_storage_key" => key, "evidence_upload_url" => url}} <-
           HTTP.project_request(
             :post,
             "/tests/coverage/uploads",
             %{test_run_id: payload.id},
             options
           ),
         compressed = ndjson |> File.stream!(65_536) |> deflate_stream(),
         {:ok, _etag} <- Client.put_binary(url, compressed) do
      {:ok, Map.put(payload, :coverage_evidence, Map.put(rest, :storage_key, key))}
    else
      false -> :inline
      {:ok, %{}} -> :inline
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  defp inline_threshold(options) do
    case HTTP.project_request(:get, "/tests/coverage/settings", nil, options) do
      {:ok, %{"inline_threshold_bytes" => bytes}} when is_integer(bytes) -> bytes
      _ -> 5_000_000
    end
  end

  defp deflate_stream(chunks) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)

    try do
      compressed = Enum.map(chunks, &:zlib.deflate(z, &1))
      IO.iodata_to_binary([compressed, :zlib.deflate(z, [], :finish)])
    after
      :zlib.close(z)
    end
  end

  # Raw DEFLATE, what the server inflates (`PublishCoverageWorker`).
  defp deflate(data) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    compressed = IO.iodata_to_binary(:zlib.deflate(z, data, :finish))
    :zlib.deflateEnd(z)
    :zlib.close(z)
    compressed
  end
end
