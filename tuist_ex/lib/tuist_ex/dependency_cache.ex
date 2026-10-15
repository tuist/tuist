defmodule TuistEx.DependencyCache do
  @moduledoc false

  alias TuistEx.Analytics.CompileProfile
  alias TuistEx.Analytics.CompileReporter
  alias TuistEx.Analytics.Report
  alias TuistEx.Cache.Key
  alias TuistEx.Cache.Reapi
  alias TuistEx.Cache.Store

  @compiler_config [
    :app,
    :version,
    :elixir,
    :compilers,
    :elixirc_paths,
    :elixirc_options,
    :erlc_include_path,
    :xref,
    :build_per_environment,
    :erlc_paths,
    :erlc_options,
    :consolidate_protocols,
    :build_embedded
  ]

  @compiler_environment ~w(ERL_COMPILER_OPTIONS ELIXIR_ERL_OPTIONS ERL_AFLAGS ERL_FLAGS ERL_ZFLAGS SOURCE_DATE_EPOCH ERL_LIBS MIX_PATH MIX_ARCHIVES)

  def prepare(args, reporter, analytics_options \\ []) do
    options =
      Mix.Project.config()
      |> Keyword.get(:tuist, [])
      |> Keyword.get(:cache)
      |> case do
        true -> []
        options when is_list(options) -> options
        _ -> nil
      end

    if not is_nil(options) and not Mix.Project.umbrella?() and
         not Enum.any?(["--no-compile", "--no-deps-check"], &(&1 in args)) do
      Mix.ensure_application!(:crypto)

      Mix.Project.with_build_lock(fn ->
        prepare_dependencies(args, options, reporter, analytics_options)
      end)
    end

    :ok
  end

  defp prepare_dependencies(args, options, reporter, analytics_options) do
    dependencies = Mix.Dep.load_and_cache()

    dependencies =
      if "--no-optional-deps" in args,
        do: Enum.reject(dependencies, & &1.opts[:optional]),
        else: dependencies

    Reapi.with_session(
      options,
      CompileReporter.build_id(reporter),
      analytics_options,
      fn remote ->
        pending =
          Enum.reduce(dependencies, [], fn dependency, pending ->
            dependency = Mix.Dep.check_lock(dependency)

            cond do
              not Mix.Dep.compilable?(dependency) ->
                pending

              selected?(dependency, options) ->
                compile_dependencies(Enum.reverse(pending))
                context = capture_context(options)
                observation = compile(dependency, dependencies, context, options, remote)
                CompileReporter.record_cache(reporter, observation)
                Mix.Dep.load_and_cache()
                []

              local_chain?(dependency, dependencies) ->
                pending

              true ->
                [dependency | pending]
            end
          end)

        compile_dependencies(Enum.reverse(pending))
        Mix.Dep.load_and_cache()
      end
    )
  end

  defp compile(dependency, dependencies, context, options, remote) do
    case action_key(dependency, dependencies, context, options) do
      {:ok, key} ->
        cached_compile(dependency, dependencies, context, options, key, remote)

      {:bypass, "local_dependency"} ->
        # Mix must compile local source dependencies before their fetched dependents.
        # Their SCM status cannot tell us whether the sources changed, so leave the
        # whole unsupported chain to the normal dependency compiler.
        observation(dependency, "bypass", "local_dependency", "", 0, nil)

      {:bypass, reason} ->
        duration = compile_dependency(dependency)
        observation(dependency, "bypass", reason, "", duration, nil)
    end
  end

  defp cached_compile(dependency, dependencies, context, options, key, remote) do
    root = store_root(options)
    started = now()

    case restore(remote, root, key, dependency) do
      {:ok, previous_duration, metrics, outcome} ->
        dependency
        |> observation(outcome, "", key, now() - started, previous_duration)
        |> Map.merge(metrics)

      :miss ->
        duration = compile_dependency(dependency)

        {reason, metrics} =
          if capture_context(options) == context and
               action_key(dependency, dependencies, context, options) == {:ok, key} do
            case Store.publish_with_metrics(
                   root,
                   key,
                   dependency.opts[:build],
                   dependency.opts[:dest],
                   duration,
                   &valid_application?(&1, dependency)
                 ) do
              {:ok, metrics} ->
                metrics =
                  if Keyword.get(options, :upload, true),
                    do: publish_remote(remote, root, key, dependency.app, metrics),
                    else: metrics

                {"", metrics}

              {:error, _} ->
                {"store_failed", %{}}
            end
          else
            {"inputs_changed", %{}}
          end

        dependency
        |> observation("miss", reason, key, duration, nil)
        |> Map.merge(metrics)
    end
  end

  defp restore(remote, root, key, dependency) do
    validate = &valid_application?(&1, dependency)

    case Store.restore_with_metrics(
           root,
           key,
           dependency.opts[:build],
           dependency.opts[:dest],
           validate
         ) do
      {:ok, duration, metrics} ->
        {:ok, duration, metrics, "local_hit"}

      :miss ->
        with {:ok, binary, metrics} <- Reapi.get(remote.(), key, dependency.app),
             {:ok, duration, _local_metrics} <-
               Store.restore_bundle(
                 root,
                 key,
                 binary,
                 dependency.opts[:build],
                 dependency.opts[:dest],
                 validate
               ) do
          {:ok, duration, Map.delete(metrics, :output_digest), "remote_hit"}
        else
          _ -> :miss
        end
    end
  end

  defp valid_application?(staging, dependency) do
    app = dependency.app
    path = Path.join([staging, "ebin", "#{app}.app"])
    version = dependency_config(dependency)[:version]

    with {:ok, [{:application, ^app, properties}]} <- :file.consult(String.to_charlist(path)),
         true <- Keyword.keyword?(properties),
         true <- to_string(Keyword.fetch!(properties, :vsn)) == version,
         modules when is_list(modules) <- Keyword.fetch!(properties, :modules),
         true <- File.regular?(Path.join(staging, ".mix/compile.elixir_scm")) do
      Enum.all?(modules, fn module ->
        is_atom(module) and File.regular?(Path.join([staging, "ebin", "#{module}.beam"]))
      end)
    else
      _ -> false
    end
  end

  defp publish_remote(remote, root, key, dependency, local_metrics) do
    with session when not is_nil(session) <- remote.(),
         {:ok, binary} <- Store.export_bundle(root, key),
         {:ok, metrics} <- Reapi.put(session, key, dependency, binary) do
      Map.delete(metrics, :output_digest)
    else
      _ -> local_metrics
    end
  end

  # Cache I/O must never hide compiler failures. Only input modeling and the
  # store fail open; the call to Mix stays outside those rescue boundaries.
  defp compile_dependency(dependency) do
    started = now()
    compile_dependencies([dependency])
    now() - started
  end

  defp compile_dependencies([]), do: :ok

  defp compile_dependencies(dependencies) do
    paths = :code.get_path()

    try do
      Mix.Tasks.Deps.Compile.compile(dependencies)
    after
      Code.prepend_paths(paths -- :code.get_path())
    end
  end

  defp local_chain?(dependency, dependencies) do
    not dependency.scm.fetchable?() or
      Enum.any?(
        closure(dependency, Map.new(dependencies, &{&1.app, &1}), MapSet.new()),
        &(not &1.scm.fetchable?())
      )
  end

  defp selected?(dependency, options) do
    selected = Keyword.get(options, :dependencies, :all)
    excluded = Keyword.get(options, :exclude, [])
    (selected == :all or dependency.app in selected) and dependency.app not in excluded
  end

  def action_key(dependency, dependencies, context, options) do
    closure = closure(dependency, Map.new(dependencies, &{&1.app, &1}), MapSet.new())

    cond do
      not dependency.scm.fetchable?() or Enum.any?(closure, &(not &1.scm.fetchable?())) ->
        {:bypass, "local_dependency"}

      not selected?(dependency, options) ->
        {:bypass, "not_enabled"}

      Enum.any?([dependency | closure], &(&1.manager != :mix or &1.opts[:compile] != nil)) ->
        {:bypass, "custom_compiler"}

      is_nil(context) ->
        {:bypass, "unmodeled_input"}

      Enum.any?(context.compiler_options[:tracers] || [], &(&1 != CompileProfile)) ->
        {:bypass, "custom_compiler"}

      true ->
        model_key(dependency, closure, context, options)
    end
  rescue
    _ -> {:bypass, "unmodeled_input"}
  catch
    :unmodeled_input -> {:bypass, "unmodeled_input"}
  end

  defp model_key(dependency, closure, context, options) do
    root = Key.canonical_path(store_root(options))

    for dep <- [dependency | closure], input <- [dep.opts[:dest], dep.opts[:build]] do
      if Path.type(Path.relative_to(root, Key.canonical_path(input))) == :relative,
        do: throw(:unmodeled_input)
    end

    config = dependency_config(dependency)
    sources = Key.tree(dependency.opts[:dest])

    upstream_sources = Enum.map(closure, &{&1, Key.tree(&1.opts[:dest])})

    if unsupported_config?(config) or unsupported_sources?(sources) or
         Enum.any?(upstream_sources, fn {dep, tree} ->
           upstream_config = dependency_config(dep)
           unsupported_config?(upstream_config) or unsupported_sources?(tree)
         end) do
      {:bypass, "custom_compiler"}
    else
      upstream =
        upstream_sources
        |> Enum.sort_by(fn {dep, _} -> dep.app end)
        |> Enum.map(fn {dep, tree} ->
          {dep.app, dependency_options(dep), tree, Key.tree(Path.join(dep.opts[:build], "ebin"))}
        end)

      paths =
        if !Keyword.get(options, :portable, false),
          do: {File.cwd!(), dependency.opts[:dest], dependency.opts[:build]}

      inputs =
        {context, dependency.app, dependency_options(dependency), sources,
         Keyword.take(config, @compiler_config), upstream, paths}

      if safe_term?(inputs), do: {:ok, Key.build(inputs)}, else: {:bypass, "unmodeled_input"}
    end
  end

  defp dependency_config(dependency) do
    Mix.Dep.Loader.with_system_env(dependency, fn ->
      Mix.Dep.in_dependency(dependency, fn _ -> Mix.Project.config() end)
    end)
  end

  defp dependency_options(dependency) do
    {dependency.opts[:lock], dependency.opts[:env] || :prod,
     dependency.system_env |> Map.new() |> Enum.sort()}
  end

  defp unsupported_config?(config) do
    compilers = config[:compilers] || Mix.compilers()
    paths = (config[:elixirc_paths] || ["lib"]) ++ (config[:erlc_paths] || ["src"])

    Enum.any?(compilers, &(&1 not in [:yecc, :leex, :erlang, :elixir, :app])) or
      Enum.any?(config[:aliases] || [], fn {name, _} ->
        String.starts_with?(to_string(name), "compile") or
          name in [:loadpaths, :"deps.loadpaths", :loadconfig, :"app.config", :will_recompile]
      end) or
      (config[:elixirc_options] || [])[:tracers] not in [nil, []] or
      Enum.any?(
        paths,
        &(Path.type(&1) != :relative or ".." in Path.split(&1) or
            hd(Path.split(&1)) in [".git", "_build"])
      )
  end

  defp unsupported_sources?(sources) do
    Enum.any?(sources, fn entry ->
      path = elem(entry, 0)

      Path.extname(path) in [
        ".erl",
        ".xrl",
        ".yrl",
        ".c",
        ".cc",
        ".cpp",
        ".rs",
        ".so",
        ".dylib",
        ".dll"
      ] or
        Path.basename(path) in ["Makefile", "makefile", "rebar.config", "CMakeLists.txt"]
    end)
  end

  defp capture_context(options) do
    context(options)
  rescue
    error ->
      Report.debug("tuist cache: cannot model inputs: #{inspect(error)}")
      nil
  catch
    :unmodeled_input -> nil
  end

  defp context(options) do
    # Loading an .app merges defaults into live env. Those defaults are keyed by
    # dependency sources; only explicitly configured keys belong in this context.
    config =
      Mix.Tasks.Loadconfig.read_compile()
      |> Enum.map(fn {app, pairs} ->
        {app,
         Enum.map(pairs, fn {key, value} -> {key, Application.get_env(app, key, value)} end)
         |> Enum.sort()}
      end)
      |> Enum.sort()

    %{
      toolchain: %{
        elixir: System.build_info(),
        otp: otp_version(),
        erts: :erlang.system_info(:system_version),
        architecture: :erlang.system_info(:system_architecture),
        word_size: :erlang.system_info(:wordsize),
        endianness: :erlang.system_info(:endian),
        os: {:os.type(), :os.version()},
        compilers: Enum.map([:compile, :elixir_erl_compiler], &compiler_digest/1)
      },
      compiler_options: Code.compiler_options() |> Enum.sort(),
      env: Mix.env(),
      target: Mix.target(),
      configuration: config,
      environment:
        (@compiler_environment ++ Keyword.get(options, :env, []))
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&{&1, System.get_env(&1)}),
      inputs: options |> Keyword.get(:inputs, []) |> Enum.sort() |> Enum.map(&{&1, Key.tree(&1)}),
      project: Mix.Project.config()[:tuist] |> Keyword.get(:project)
    }
  end

  defp otp_version do
    release = :erlang.system_info(:otp_release) |> to_string()
    path = Path.join([to_string(:code.root_dir()), "releases", release, "OTP_VERSION"])

    case File.read(path) do
      {:ok, version} -> {release, String.trim(version)}
      _ -> {release, nil}
    end
  end

  defp compiler_digest(module) do
    case :code.get_object_code(module) do
      {^module, binary, _path} -> {module, Key.digest(binary)}
      _ -> throw(:unmodeled_input)
    end
  end

  defp closure(dependency, dependencies, seen) do
    {result, _seen} = walk_closure(dependency.deps, dependencies, seen)
    result
  end

  defp walk_closure(children, dependencies, seen) do
    Enum.reduce(children, {[], seen}, fn child, {result, seen} ->
      if MapSet.member?(seen, child.app) do
        {result, seen}
      else
        child = Map.get(dependencies, child.app, child)
        {descendants, seen} = walk_closure(child.deps, dependencies, MapSet.put(seen, child.app))
        {[child | descendants] ++ result, seen}
      end
    end)
  end

  defp safe_term?(term)
       when is_pid(term) or is_reference(term) or is_function(term) or is_port(term), do: false

  defp safe_term?(term) when is_list(term), do: Enum.all?(term, &safe_term?/1)

  defp safe_term?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.all?(&safe_term?/1)

  defp safe_term?(term) when is_map(term),
    do: Enum.all?(term, fn {key, value} -> safe_term?(key) and safe_term?(value) end)

  defp safe_term?(_term), do: true

  defp observation(dependency, outcome, reason, key, duration, saved) do
    %{
      dependency: Atom.to_string(dependency.app),
      outcome: outcome,
      reason: reason,
      key: key,
      duration_ms: duration,
      saved_duration_ms: saved
    }
  end

  defp store_root(options), do: options |> Keyword.get(:path, default_path()) |> Path.expand()
  defp default_path, do: Path.join(:filename.basedir(:user_cache, "tuist"), "mix/dependencies/v1")
  defp now, do: System.monotonic_time(:millisecond)
end
