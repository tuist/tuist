defmodule TuistEx.Analytics.CompileProfile do
  @moduledoc false

  # Collects a per-file compilation profile for one `mix compile` run:
  # when each file started and how long it took to compile, the modules it
  # defines, and every wait it sat through (what it waited on, when, and for
  # how long).
  #
  # Two sources feed it:
  #
  #   * The compiler's own `--profile time` lines, which carry the compile
  #     time and one measured wait per module the file blocked on. They are
  #     printed to standard error, so a small proxy device sits in front of
  #     it while the compile runs, records those lines, and forwards
  #     everything else untouched.
  #     Those lines also report the work the compiler does around the files
  #     (type checking each module, writing modules to disk, and so on). A
  #     line is printed when its work finishes, so the moment it arrives is
  #     the end of that work.
  #   * A compilation tracer (`trace/2`), which maps each module to the file
  #     defining it so a wait on a module can be shown as a wait on a file,
  #     and timestamps when each file started and each module became
  #     available so both can be placed on the build's timeline. The compiler
  #     calls it from every file's process, so it only writes to a public
  #     ETS table.

  #   * The same tracer sees every reference a file makes to another module,
  #     which gives the dependency graph between the project's files: which
  #     files a file needs, and how strongly. The kinds follow `mix xref`:
  #     `compile` (the file needs the other module while it compiles: it
  #     calls its macros or uses it in a module body), `export` (it needs the
  #     module's struct or imports it) and `runtime` (it only calls it from
  #     inside functions, so compilation order does not matter).

  # The profile the compiler's tracer writes to. The tracer is a module the
  # compiler calls with no context of ours, so the one profile being collected
  # has to be found from anywhere; everything else takes the profile it works
  # on as an argument.
  @active {__MODULE__, :active}
  @compiling ~r/^\[profile\]\s+(\d+)ms compiling \+\s+(.+)$/
  @wait ~r/(\d+)ms waiting (?:for (\w+) (.+) )?while compiling (.+?)\s*$/
  @type_checked ~r/^\[profile\] Type checked (.+) in (\d+)ms\s*$/
  @finished ~r/^\[profile\] Finished (.+?)(?: of \d+ modules)? in (\d+)ms\s*$/

  @doc """
  Starts an empty profile. `origin` is the monotonic time, in milliseconds,
  that every offset is measured from. The profile lives as long as the
  process that created it.
  """
  def new(origin \\ now()) do
    entries =
      :ets.new(:tuist_ex_compile_profile, [:public, :duplicate_bag, write_concurrency: true])

    :ets.insert(entries, {:origin, origin})

    # References arrive by the million, mostly repeated, so they go to a set
    # that keeps one entry per file, module and kind.
    references = :ets.new(:tuist_ex_compile_references, [:public, :set, write_concurrency: true])

    %{entries: entries, references: references}
  end

  @doc """
  Points the compiler at `profile`: installs the tracer and puts a proxy in
  front of standard error. `show_profile?` keeps the compiler's profile lines
  visible when the user asked for them. Returns what `uninstall/1` needs to
  put everything back.
  """
  def install(profile, show_profile? \\ false) do
    :persistent_term.put(@active, profile)

    previous_tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, Enum.uniq([__MODULE__ | previous_tracers]))

    %{previous_tracers: previous_tracers, proxy: install_proxy(profile, show_profile?)}
  end

  @doc """
  Frees a profile's tables once it has been read.
  """
  def delete(%{entries: entries, references: references}) do
    :ets.delete(entries)
    :ets.delete(references)
    :ok
  end

  @doc """
  Restores the compiler and standard error.
  """
  def uninstall(%{previous_tracers: previous_tracers, proxy: proxy}) do
    Code.put_compiler_option(:tracers, previous_tracers)
    remove_proxy(proxy)
    :persistent_term.erase(@active)
    :ok
  end

  @doc """
  The compiler's tracer callback. It runs inside the compiler's processes.
  """
  def trace(event, env) do
    case :persistent_term.get(@active, nil) do
      nil -> :ok
      profile -> record(profile, event, env)
    end
  end

  @doc """
  Records a tracer event in `profile`. Cheap, and never raises: it runs for
  every reference in every file being compiled.
  """
  def record(profile, event, env, at \\ now())
  def record(profile, :start, env, at), do: put(profile, {:start, file(env)}, at)
  def record(profile, :stop, env, at), do: put(profile, {:stop, file(env)}, at)

  def record(profile, {:on_module, _bytecode, _}, env, at),
    do: put(profile, {:module, file(env)}, {env.module, at})

  def record(profile, {macro, _meta, module, _name, _arity}, env, _at)
      when macro in [:remote_macro, :imported_macro],
      do: reference(profile, env, module, :compile)

  def record(profile, {function, _meta, module, _name, _arity}, env, _at)
      when function in [:remote_function, :imported_function],
      do: reference(profile, env, module, context(env))

  def record(profile, {:alias_reference, _meta, module}, env, _at),
    do: reference(profile, env, module, context(env))

  def record(profile, {:struct_expansion, _meta, module, _keys}, env, _at),
    do: reference(profile, env, module, :export)

  def record(profile, {:import, _meta, module, _opts}, env, _at),
    do: reference(profile, env, module, :export)

  def record(_profile, _event, _env, _at), do: :ok

  # Code in a module body runs while the file compiles; code in a function
  # only runs later.
  defp context(%{function: nil}), do: :compile
  defp context(_env), do: :runtime

  defp reference(_profile, %{module: module}, module, _kind), do: :ok

  defp reference(profile, env, module, kind) do
    :ets.insert(profile.references, {{env.file, module, kind}})
    :ok
  rescue
    # The profile's owner is gone; there is nobody left to report to.
    ArgumentError -> :ok
  end

  @doc """
  Records that a Mix compiler (`:erlang`, `:elixir`, `:app`, ...) finished.
  """
  def compiler_finished(profile, name, at \\ now()), do: put(profile, :compiler, {name, at})

  @doc """
  Records what the compiler's `--profile time` output says in `text`.
  Returns whether `text` was profile output and nothing else.
  """
  def record_profile_output(profile, text, at \\ now()) do
    lines = String.split(text, "\n", trim: true)
    Enum.each(lines, &record_profile_line(profile, &1, at))
    lines != [] and Enum.all?(lines, &String.starts_with?(&1, "[profile]"))
  end

  defp record_profile_line(profile, line, at) do
    case Regex.run(@type_checked, line) do
      [_, module, duration] ->
        put(profile, :type_check, {module, at, String.to_integer(duration)})

      _ ->
        :ok
    end

    case Regex.run(@finished, line) do
      [_, phase, duration] -> put(profile, :phase, {phase, at, String.to_integer(duration)})
      _ -> :ok
    end

    with [_, compiling, rest] <- Regex.run(@compiling, line),
         [_, _, _, _, path] <- Regex.run(@wait, rest) do
      put(profile, {:compiling, path}, String.to_integer(compiling))
    end

    case Regex.run(@wait, line) do
      [_, duration, kind, on, path] when kind != "" ->
        put(profile, {:wait, path}, {kind, on, String.to_integer(duration)})

      _ ->
        :ok
    end
  end

  @doc """
  The files `profile` saw compiled, each with when it started, how long it
  compiled and waited, the modules it defines and the project files it
  depends on. `project_source` resolves a module that was not compiled in
  this run to its source file.
  """
  def files(profile, project_source \\ project_source()) do
    entries = :ets.tab2list(profile.entries)
    dependencies = dependencies(entries, :ets.tab2list(profile.references), project_source)

    origin =
      Enum.find_value(entries, fn entry -> match?({:origin, _}, entry) && elem(entry, 1) end)

    modules = for {{:module, file}, {module, at}} <- entries, do: {file, inspect(module), at}
    module_files = Map.new(modules, fn {file, module, _at} -> {module, file} end)
    modules_available_at = Map.new(modules, fn {_file, module, at} -> {module, at} end)
    modules_by_file = Enum.group_by(modules, &elem(&1, 0), &elem(&1, 1))

    waits_by_file =
      Enum.group_by(
        for({{:wait, file}, wait} <- entries, do: {file, wait}),
        &elem(&1, 0),
        &elem(&1, 1)
      )

    compiling = Map.new(for({{:compiling, file}, duration} <- entries, do: {file, duration}))
    starts = min_by_file(for({{:start, file}, at} <- entries, do: {file, at}), &Enum.min/1)
    stops = min_by_file(for({{:stop, file}, at} <- entries, do: {file, at}), &Enum.max/1)

    (Map.keys(compiling) ++ Map.keys(starts))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn file ->
      started_at = Map.get(starts, file)
      stopped_at = Map.get(stops, file)

      waits =
        waits_by_file
        |> Map.get(file, [])
        |> Enum.map(fn {kind, on, duration} ->
          %{
            kind: kind,
            module: on,
            path: Map.get(module_files, on),
            duration_ms: duration,
            start_offset_ms:
              wait_start_offset(
                origin,
                started_at,
                stopped_at,
                Map.get(modules_available_at, on),
                duration
              )
          }
        end)
        |> Enum.sort_by(&(-&1.duration_ms))

      wait_duration = Enum.sum(Enum.map(waits, & &1.duration_ms))
      elapsed = max((stopped_at || 0) - (started_at || 0), 0)

      %{
        path: file,
        start_offset_ms: offset(origin, started_at),
        compile_duration_ms: Map.get(compiling, file, max(elapsed - wait_duration, 0)),
        wait_duration_ms: wait_duration,
        modules: modules_by_file |> Map.get(file, []) |> Enum.sort(),
        waits: waits,
        dependencies: Map.get(dependencies, file, [])
      }
    end)
  end

  @doc """
  The work of the build other than compiling files, as timeline steps:
  `%{category, title, path, start_offset_ms, duration_ms}`.

    * `"type_check"`: one step per module the compiler type checked.
    * `"write"`: writing the compiled modules to disk.
    * `"compiler"`: every Mix compiler other than Elixir's own, whose work is
      the files and the steps above. A compiler starts when the one before it
      finishes, so the first compiler, whose start is unknown, is left out.
    * `"other"`: the remaining phases the compiler reports.

  Steps that took no measurable time are dropped.
  """
  def steps(profile) do
    entries = :ets.tab2list(profile.entries)

    origin =
      Enum.find_value(entries, fn entry -> match?({:origin, _}, entry) && elem(entry, 1) end)

    module_files =
      Map.new(for {{:module, file}, {module, _at}} <- entries, do: {inspect(module), file})

    type_checks =
      for {:type_check, {module, at, duration}} <- entries do
        step(
          "type_check",
          "Type checking " <> module,
          Map.get(module_files, module),
          origin,
          at - duration,
          duration
        )
      end

    phases =
      for {:phase, {phase, at, duration}} <- entries,
          kind = phase_kind(phase, type_checks != []) do
        {category, title} = kind
        step(category, title, nil, origin, at - duration, duration)
      end

    finished =
      for({:compiler, {name, at}} <- entries, do: {name, at})
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.chunk_every(2, 1, :discard)

    compilers =
      for [{_previous, started_at}, {name, at}] <- finished, name != :elixir do
        step("compiler", "mix compile.#{name}", nil, origin, started_at, at - started_at)
      end

    (type_checks ++ phases ++ compilers)
    |> Enum.filter(&(&1.duration_ms > 0 and is_integer(&1.start_offset_ms)))
    |> Enum.sort_by(&{&1.start_offset_ms, &1.title})
  end

  defp step(category, title, path, origin, started_at, duration) do
    %{
      category: category,
      title: title,
      path: path,
      start_offset_ms: offset(origin, started_at),
      duration_ms: duration
    }
  end

  # The compilation cycle is the files themselves, and the group pass is the
  # sum of the per-module type checks when the compiler reports those.
  defp phase_kind("compilation cycle", _type_checks?), do: nil
  defp phase_kind("group pass check", true), do: nil
  defp phase_kind("group pass check", false), do: {"type_check", "Type checking"}

  defp phase_kind("writing modules to disk", _type_checks?),
    do: {"write", "Writing modules to disk"}

  defp phase_kind(phase, _type_checks?), do: {"other", String.capitalize(phase)}

  @kind_strength %{compile: 3, export: 2, runtime: 1}

  # file => [%{path, kind}]: the project files it references, with the
  # strongest kind when it references a file in more than one way. Modules
  # outside the project (dependencies, the standard library) are left out.
  defp dependencies(entries, references, project_source) do
    defined = Map.new(for {{:module, file}, {module, _at}} <- entries, do: {module, file})

    sources =
      references
      |> Enum.map(fn {{_file, module, _kind}} -> module end)
      |> Enum.uniq()
      |> Map.new(&{&1, Map.get(defined, &1) || project_source.(&1)})

    references
    |> Enum.flat_map(fn {{file, module, kind}} ->
      from = Path.relative_to_cwd(file)

      case Map.fetch!(sources, module) do
        to when is_binary(to) and to != from -> [{from, to, kind}]
        _ -> []
      end
    end)
    |> Enum.group_by(fn {from, to, _kind} -> {from, to} end, fn {_from, _to, kind} -> kind end)
    |> Enum.map(fn {{from, to}, kinds} ->
      {from, %{path: to, kind: kinds |> Enum.max_by(&@kind_strength[&1]) |> Atom.to_string()}}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {from, targets} -> {from, Enum.sort_by(targets, & &1.path)} end)
  end

  # Resolves a module that was not compiled in this run (an incremental
  # compile) to its source file, when it belongs to the project: its compiled
  # file sits in the project's build directory and records where it came from.
  defp project_source do
    compile_path = String.to_charlist(Mix.Project.compile_path())

    fn module ->
      with path when is_list(path) <- :code.which(module),
           true <- List.starts_with?(path, compile_path),
           {:ok, {_module, [compile_info: info]}} <- :beam_lib.chunks(path, [:compile_info]),
           source when is_list(source) <- Keyword.get(info, :source) do
        Path.relative_to_cwd(List.to_string(source))
      else
        _ -> nil
      end
    end
  rescue
    _ -> fn _module -> nil end
  end

  defp offset(origin, at) when is_integer(origin) and is_integer(at), do: max(at - origin, 0)
  defp offset(_origin, _at), do: nil

  # The compiler reports how long a file waited on a module, not when. The
  # wait ends when that module becomes available, so it is placed right
  # before that moment, inside the span the file was being compiled.
  defp wait_start_offset(origin, started_at, stopped_at, available_at, duration)
       when is_integer(origin) and is_integer(started_at) and is_integer(available_at) do
    latest = if is_integer(stopped_at), do: stopped_at - duration, else: available_at - duration
    offset(origin, max(min(available_at - duration, latest), started_at))
  end

  defp wait_start_offset(_origin, _started_at, _stopped_at, _available_at, _duration), do: nil

  defp now, do: System.monotonic_time(:millisecond)

  defp min_by_file(pairs, pick) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {file, values} -> {file, pick.(values)} end)
  end

  defp file(env), do: Path.relative_to_cwd(env.file)

  defp put(profile, key, value) do
    :ets.insert(profile.entries, {key, value})
    :ok
  rescue
    # The profile's owner is gone; there is nobody left to report to.
    ArgumentError -> :ok
  end

  # Standard error proxy

  defp install_proxy(profile, show_profile?) do
    case Process.whereis(:standard_error) do
      nil ->
        nil

      device ->
        proxy = spawn(fn -> proxy_loop(profile, device, show_profile?) end)
        Process.unregister(:standard_error)
        Process.register(proxy, :standard_error)
        %{pid: proxy, device: device}
    end
  end

  defp remove_proxy(nil), do: :ok

  defp remove_proxy(%{pid: proxy, device: device}) do
    if Process.whereis(:standard_error) == proxy do
      Process.unregister(:standard_error)
      Process.register(device, :standard_error)
    end

    send(proxy, :stop)
    :ok
  end

  defp proxy_loop(profile, device, show_profile?) do
    receive do
      :stop ->
        :ok

      {:io_request, from, reply_as, request} = message ->
        if profile_line?(profile, request) and not show_profile? do
          send(from, {:io_reply, reply_as, :ok})
        else
          send(device, message)
        end

        proxy_loop(profile, device, show_profile?)

      message ->
        send(device, message)
        proxy_loop(profile, device, show_profile?)
    end
  end

  defp profile_line?(profile, {:put_chars, _encoding, chars}), do: profile_text?(profile, chars)
  defp profile_line?(profile, {:put_chars, chars}), do: profile_text?(profile, chars)
  defp profile_line?(_profile, _request), do: false

  defp profile_text?(profile, chars) do
    record_profile_output(profile, IO.chardata_to_string(chars))
  rescue
    _ -> false
  end
end
