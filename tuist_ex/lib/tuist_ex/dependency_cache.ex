defmodule TuistEx.DependencyCache do
  @moduledoc false

  alias TuistEx.Analytics.CompileProfile
  alias TuistEx.Analytics.CompileReporter
  alias TuistEx.Analytics.Report
  alias TuistEx.Cache.Compiler
  alias TuistEx.Cache.Key
  alias TuistEx.Cache.Plan
  alias TuistEx.Cache.Prefetch
  alias TuistEx.Cache.Reapi
  alias TuistEx.Cache.Store

  @compiler_config [
    :app,
    :version,
    :description,
    :language,
    :application_definition,
    :elixir,
    :compilers,
    :elixirc_paths,
    :elixirc_options,
    :erlc_include_path,
    :xref,
    :build_per_environment,
    :erlc_paths,
    :erlc_options,
    :yecc_options,
    :leex_options,
    :source_generators,
    :generated_sources,
    :consolidate_protocols,
    :build_embedded,
    :rebar,
    :rebar_toolchain,
    :cache_builder,
    :builder_configuration,
    :builder_inputs
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
      Compiler.validate_builders!(options)
      Mix.ensure_application!(:crypto)
      Mix.ensure_application!(:parsetools)

      Mix.Project.with_build_lock(fn ->
        Plan.with_plan(fn -> prepare_dependencies(args, options, reporter, analytics_options) end)
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
        Prefetch.with_fetcher(
          remote,
          &prefetch_requests(&1, &2, dependencies, options),
          fn fetch ->
            dependencies_by_app = Map.new(dependencies, &{&1.app, &1})

            {pending, _support} =
              Enum.reduce(dependencies, {[], %{}}, fn dependency, {pending, support} ->
                dependency = check_dependency(dependency, options)

                cond do
                  not Mix.Dep.compilable?(dependency) ->
                    support =
                      record_current_dependency(
                        dependency,
                        dependencies_by_app,
                        options,
                        reporter,
                        support
                      )

                    {pending, support}

                  selected?(dependency, options) ->
                    compile_dependencies(Enum.reverse(pending))
                    context = capture_context(options)

                    observation =
                      compile(dependency, dependencies, context, options, remote, fetch)

                    CompileReporter.record_cache(reporter, observation)
                    Mix.Dep.load_and_cache()
                    {[], %{}}

                  local_chain?(dependency, dependencies) ->
                    {pending, support}

                  true ->
                    {[dependency | pending], support}
                end
              end)

            compile_dependencies(Enum.reverse(pending))
            Mix.Dep.load_and_cache()
          end
        )
      end
    )
  end

  defp prefetch_requests(key, dependency, dependencies, options) do
    remaining = Enum.drop_while(dependencies, &(&1.app != dependency.app))
    by_app = Map.new(dependencies, &{&1.app, &1})

    {requests, _seen, _context} =
      Enum.reduce_while(remaining, {[], MapSet.new(), :uncaptured}, fn candidate,
                                                                       {requests, seen, context} ->
        candidate = check_dependency(candidate, options)

        cond do
          MapSet.size(seen) >= Reapi.concurrency() ->
            {:halt, {requests, seen, context}}

          Mix.Dep.ok?(candidate) and not Mix.Dep.compilable?(candidate) ->
            {:cont, {requests, seen, context}}

          not selected?(candidate, options) or not Mix.Dep.compilable?(candidate) or
              Enum.any?(closure(candidate, by_app, MapSet.new()), &MapSet.member?(seen, &1.app)) ->
            {:halt, {requests, seen, context}}

          true ->
            {modeled, context} =
              if candidate.app == dependency.app do
                {{:ok, key}, context}
              else
                # One speculative context per window; staging still reads fresh inputs.
                context = if context == :uncaptured, do: capture_context(options), else: context
                {action_key(candidate, dependencies, context, options), context}
              end

            case modeled do
              {:ok, candidate_key} ->
                # Presence is only a prefetch hint, never an integrity decision.
                local = Path.join([store_root(options), candidate_key, "manifest.json"])
                request = {candidate_key, candidate.app}
                requests = if File.regular?(local), do: requests, else: [request | requests]
                {:cont, {requests, MapSet.put(seen, candidate.app), context}}

              _ ->
                {:halt, {requests, seen, context}}
            end
        end
      end)

    # A corrupt local entry can miss despite the presence hint.
    [{key, dependency.app} | requests]
    |> Enum.uniq()
    |> Enum.take(Reapi.concurrency())
  end

  defp check_dependency(dependency, options) do
    dependency = Mix.Dep.check_lock(dependency)

    if Mix.Dep.ok?(dependency) and
         not outputs_present?(dependency.opts[:build], dependency, options),
       do: %{dependency | status: :compile},
       else: dependency
  end

  defp outputs_present?(build, dependency, options) do
    builder = Compiler.builder(dependency, options)

    not Compiler.supported_manager?(dependency, builder) or
      Compiler.outputs_present?(build, builder)
  rescue
    _ -> true
  catch
    :unmodeled_input -> true
  end

  defp record_current_dependency(dependency, dependencies, options, reporter, support) do
    started = now()

    if Mix.Dep.ok?(dependency) and selected?(dependency, options) and
         not Enum.any?(Code.compiler_options()[:tracers] || [], &(&1 != CompileProfile)) do
      {supported?, support} =
        Enum.reduce_while(
          [dependency | closure(dependency, dependencies, MapSet.new())],
          {true, support},
          fn dep, {true, support} ->
            {config, support} = current_dependency_config(dep, support, options)
            if config, do: {:cont, {true, support}}, else: {:halt, {false, support}}
          end
        )

      if supported? and
           valid_application?(
             dependency.opts[:build],
             dependency,
             support[dependency.app][:version]
           ) do
        # Mix reused installed outputs, not a keyed snapshot. Do not hash their
        # inputs or invent an artifact key, transfer metrics or original duration.
        CompileReporter.record_cache(
          reporter,
          observation(dependency, "local_hit", "up_to_date", "", now() - started, nil)
        )
      end

      support
    else
      support
    end
  rescue
    error ->
      Report.debug("tuist cache: cannot observe current dependency: #{inspect(error)}")
      support
  catch
    :unmodeled_input ->
      Report.debug("tuist cache: cannot observe current dependency: unsupported source tree")
      support
  end

  defp current_dependency_config(dependency, support, options) do
    case Map.fetch(support, dependency.app) do
      {:ok, config} ->
        {config, support}

      :error ->
        config =
          if dependency.scm.fetchable?() and
               Compiler.supported_manager?(dependency, Compiler.builder(dependency, options)) do
            config = Compiler.config(dependency, false, Compiler.builder(dependency, options))

            if Compiler.supported_config?(config) and
                 not Enum.any?(
                   Compiler.source_paths(dependency, config),
                   &Compiler.unsupported_source?(&1, config)
                 ),
               do: config
          end

        {config, Map.put(support, dependency.app, config)}
    end
  end

  defp compile(dependency, dependencies, context, options, remote, fetch) do
    case action_key(dependency, dependencies, context, options) do
      {:ok, key} ->
        cached_compile(dependency, dependencies, context, options, key, remote, fetch)

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

  defp cached_compile(dependency, dependencies, context, options, key, remote, fetch) do
    root = store_root(options)
    started = now()

    current? = fn ->
      Plan.fresh(fn ->
        capture_context(options) == context and
          action_key(dependency, dependencies, context, options) == {:ok, key}
      end)
    end

    case restore(fetch, root, key, dependency, current?, options) do
      {:ok, previous_duration, metrics, outcome} ->
        Plan.invalidate(dependency.app)

        dependency
        |> observation(outcome, "", key, now() - started, previous_duration)
        |> Map.merge(metrics)

      :miss ->
        # Lookup models may be shared, but compilation/publication must use a
        # newly captured key even when a stale plan never found an artifact.
        {context, modeled} =
          Plan.fresh(fn ->
            context = capture_context(options)
            {context, action_key(dependency, dependencies, context, options)}
          end)

        case modeled do
          {:ok, key} ->
            publish_compilation(dependency, dependencies, context, options, key, remote)

          {:bypass, reason} ->
            duration = compile_dependency(dependency)
            observation(dependency, "bypass", reason, "", duration, nil)
        end
    end
  end

  defp publish_compilation(dependency, dependencies, context, options, key, remote) do
    root = store_root(options)

    current? = fn ->
      Plan.fresh(fn ->
        capture_context(options) == context and
          action_key(dependency, dependencies, context, options) == {:ok, key}
      end)
    end

    prepared = prepare_sources(dependency, options)
    duration = compile_dependency(dependency)

    {reason, metrics} =
      case prepared do
        {:ok, materialize?} ->
          case Store.publish_with_metrics(
                 root,
                 key,
                 dependency.opts[:build],
                 dependency.opts[:dest],
                 duration,
                 &(valid_artifact?(&1, dependency, options) and current?.()),
                 materialize_resources: materialize?
               ) do
            {:ok, metrics} ->
              metrics =
                if Keyword.get(options, :upload, true),
                  do: publish_remote(remote, root, key, dependency.app, metrics),
                  else: metrics

              {"", metrics}

            {:error, _} ->
              {if(current?.(), do: "store_failed", else: "inputs_changed"), %{}}
          end

        :error ->
          {"unmodeled_input", %{}}
      end

    dependency
    |> observation("miss", reason, key, duration, nil)
    |> Map.merge(metrics)
  end

  defp restore(fetch, root, key, dependency, current?, options) do
    validate = &(valid_artifact?(&1, dependency, options) and current?.())

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
        with {:ok, binary, metrics} <- fetch.(key, dependency),
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

  defp prepare_sources(dependency, options) do
    config = dependency_config(dependency, options)
    Compiler.prepare_sources(dependency, config)
    {:ok, Compiler.materialize?(config)}
  rescue
    _ -> :error
  catch
    :unmodeled_input -> :error
  end

  defp valid_artifact?(staging, dependency, options) do
    builder = Compiler.builder(dependency, options)
    config = Compiler.config(dependency, false, builder)

    materialized? =
      not Compiler.materialize?(config) or
        Enum.all?(["ebin", "priv", "include", "src"], fn name ->
          case File.lstat(Path.join(staging, name)) do
            {:ok, %{type: :directory}} -> true
            {:error, :enoent} -> true
            _ -> false
          end
        end)

    materialized? and Compiler.outputs_present?(staging, builder) and
      valid_application?(staging, dependency, config[:version])
  end

  defp valid_application?(staging, dependency, version) do
    app = dependency.app
    path = Path.join([staging, "ebin", "#{app}.app"])
    Code.ensure_loaded!(Mix.Dep.ElixirSCM)

    manifest =
      if dependency.manager != :mix and not function_exported?(Mix.Dep.ElixirSCM, :update, 3),
        do: "compile.fetch",
        else: "compile.elixir_scm"

    with {:ok, [{:application, ^app, properties}]} <- :file.consult(String.to_charlist(path)),
         true <- Keyword.keyword?(properties),
         true <- to_string(Keyword.fetch!(properties, :vsn)) == version,
         modules when is_list(modules) <- Keyword.fetch!(properties, :modules),
         true <- File.regular?(Path.join([staging, ".mix", manifest])) do
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
      Plan.clear()
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

      not Enum.all?(
        [dependency | closure],
        &Compiler.supported_manager?(&1, Compiler.builder(&1, options))
      ) ->
        {:bypass, "custom_compiler"}

      is_nil(context) ->
        {:bypass, "unmodeled_input"}

      Enum.any?(context.compiler_options[:tracers] || [], &(&1 != CompileProfile)) ->
        {:bypass, "custom_compiler"}

      true ->
        Plan.in_context({context, options}, fn ->
          model_key(dependency, closure, context, options)
        end)
    end
  rescue
    _ -> {:bypass, "unmodeled_input"}
  catch
    :unmodeled_input -> {:bypass, "unmodeled_input"}
    :custom_compiler -> {:bypass, "custom_compiler"}
  end

  defp model_key(dependency, closure, context, options) do
    root = planned_path(store_root(options))

    for dep <- [dependency | closure], input <- [dep.opts[:dest], dep.opts[:build]] do
      if Path.type(Path.relative_to(root, planned_path(input))) == :relative,
        do: throw(:unmodeled_input)
    end

    # A rejected closure needs no source bytes, even for its supported members.
    [{_, config, sources} | upstream_sources] =
      [dependency | closure]
      |> Enum.map(&structural_model(&1, options))
      |> Enum.map(&modeled_source/1)

    upstream =
      upstream_sources
      |> Enum.sort_by(fn {dep, _, _} -> dep.app end)
      |> Enum.map(fn {dep, upstream_config, tree} ->
        {dep.app, dependency_options(dep), tree, compiler_config(upstream_config),
         Plan.fetch({:artifacts, dep}, fn -> Compiler.artifacts(dep, upstream_config) end)}
      end)

    paths =
      if !Keyword.get(options, :portable, false),
        do: {File.cwd!(), dependency.opts[:dest], dependency.opts[:build]}

    inputs =
      {context, dependency.app, dependency_options(dependency), sources, compiler_config(config),
       upstream, paths}

    {:ok, inputs |> model_term() |> Key.build()}
  end

  defp planned_path(path), do: Plan.fetch({:path, path}, fn -> Key.canonical_path(path) end)

  defp structural_model(dependency, options) do
    modeled =
      Plan.fetch({:structure, dependency}, fn ->
        config = dependency_config(dependency, options)

        if Compiler.supported_config?(config) and
             not Enum.any?(
               Compiler.source_paths(dependency, config),
               &Compiler.unsupported_source?(&1, config)
             ), do: {dependency, config}, else: :unsupported
      end)

    if modeled == :unsupported, do: throw(:custom_compiler), else: modeled
  end

  defp modeled_source({dependency, config}) do
    modeled =
      Plan.fetch({:source, dependency}, fn ->
        sources = Compiler.source_tree(dependency, config)

        if unsupported_sources?(sources, config),
          do: :unsupported,
          else: {dependency, config, sources}
      end)

    if modeled == :unsupported, do: throw(:custom_compiler), else: modeled
  end

  defp dependency_config(dependency, options),
    do: Compiler.config(dependency, true, Compiler.builder(dependency, options))

  defp compiler_config(config),
    do: config |> Keyword.take(@compiler_config) |> Compiler.effective_config()

  defp dependency_options(dependency) do
    options = fn dep ->
      dep.opts
      |> Keyword.take([:compile, :lock, :app, :runtime, :optional, :only, :targets])
      |> Keyword.put(:env, dep.opts[:env] || :prod)
      |> Compiler.effective_config()
    end

    {dependency.manager, dependency.scm, options.(dependency),
     dependency.system_env |> Map.new() |> Enum.sort(),
     dependency.deps |> Enum.map(&{&1.app, options.(&1)}) |> Enum.sort()}
  end

  defp unsupported_sources?(sources, config) do
    Enum.any?(sources, &Compiler.unsupported_source?(elem(&1, 0), config))
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
        parsetools_includes:
          :parsetools |> :code.lib_dir() |> to_string() |> Path.join("include") |> Key.tree(),
        os: {:os.type(), :os.version()},
        compilers:
          Enum.map(
            [
              :compile,
              :yecc,
              :leex,
              :epp,
              :elixir_compiler,
              :elixir_erl_compiler,
              Kernel,
              Macro,
              Mix.Tasks.Deps.Compile,
              Mix.Tasks.Compile.App,
              Mix.Tasks.Compile.Elixir,
              Mix.Tasks.Compile.Erlang,
              Mix.Tasks.Compile.Yecc,
              Mix.Tasks.Compile.Leex,
              Mix.Compilers.Elixir,
              Mix.Compilers.Erlang
            ],
            &compiler_digest/1
          )
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
      inputs:
        options
        |> Keyword.get(:inputs, [])
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.map(&{&1, Key.tree(&1)}),
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

  defp model_term(%Regex{} = regex),
    do: %{__struct__: Regex, source: Regex.source(regex), opts: Regex.opts(regex)}

  defp model_term(term)
       when is_pid(term) or is_reference(term) or is_function(term) or is_port(term),
       do: throw(:unmodeled_input)

  defp model_term(term) when is_list(term), do: Enum.map(term, &model_term/1)

  defp model_term(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(&model_term/1) |> List.to_tuple()

  defp model_term(term) when is_map(term),
    do: Map.new(:maps.to_list(term), fn {key, value} -> {model_term(key), model_term(value)} end)

  defp model_term(term), do: term

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
