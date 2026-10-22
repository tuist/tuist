defmodule TuistEx.Cache.Compiler do
  @moduledoc false

  alias TuistEx.Cache.Key

  # Only options consumed by bare compilation, or inert without their skipped
  # project plugins. Build plugins and hooks still require a builder contract.
  @rebar_options ~w(erl_opts deps profiles overrides src_dirs extra_src_dirs erl_first_files project_plugins minimum_otp_vsn min_otp_version xref_checks xref_extra_paths xref_ignores shell hex ex_doc edoc_opts eunit_opts ct_opts ct_compile_opts cover_enabled cover_opts cover_export_enabled covertool dialyzer dialyzer_opts escript_main_app escript_incl_apps escript_emu_args escript_name grpc relx alias pre_hooks post_hooks)a

  @native_environment ~w(PATH CC CXX CPP AR AS LD RANLIB STRIP CFLAGS CXXFLAGS CPPFLAGS LDFLAGS MAKE MAKEFLAGS PKG_CONFIG PKG_CONFIG_PATH PKG_CONFIG_LIBDIR SDKROOT DEVELOPER_DIR MACOSX_DEPLOYMENT_TARGET RUSTC RUSTFLAGS RUSTC_WRAPPER CARGO CARGO_BUILD_TARGET CARGO_ENCODED_RUSTFLAGS SOURCE_DATE_EPOCH)

  def validate_builders!(options) do
    if not Keyword.keyword?(options), do: Mix.raise("tuist cache options must be a keyword list")
    builders = Keyword.get(options, :builders, [])

    if not Keyword.keyword?(builders),
      do: Mix.raise("tuist cache builders must be a keyword list keyed by dependency name")

    Enum.each(builders, fn {app, builder} ->
      if not valid_builder?(builder),
        do:
          Mix.raise(
            "Invalid tuist cache builder for #{inspect(app)}: expected platform and outputs, with optional generated, env, inputs and tools"
          )
    end)
  end

  def builder(dependency, options) do
    case Keyword.fetch(Keyword.get(options, :builders, []), dependency.app) do
      :error -> nil
      {:ok, builder} -> normalize_builder(builder)
    end
  end

  def supported_manager?(dependency, builder \\ nil) do
    if builder do
      valid_builder?(builder) and dependency.manager in [:mix, :rebar3, :make] and
        dependency.opts[:compile] != false
    else
      dependency.manager in [:mix, :rebar3] and is_nil(dependency.opts[:compile])
    end
  end

  def config(dependency, toolchain? \\ true, builder \\ nil) do
    # Mix resolves the rebar launcher in the parent environment, then applies the
    # dependency's overrides to the spawned command. Mix projects use overrides
    # for both project evaluation and compilation.
    config = if dependency.manager != :mix, do: project_config(dependency, toolchain?)

    Mix.Dep.Loader.with_system_env(dependency, fn ->
      config = config || project_config(dependency, toolchain?)

      if builder do
        builder = normalize_builder(builder)

        configuration =
          config
          |> Enum.map(fn {key, value} ->
            if key in [
                 :deps_path,
                 :deps_build_path,
                 :deps_app_path,
                 :build_path,
                 :consolidation_path,
                 :lockfile
               ] and is_binary(value) do
              absolute = Path.expand(value, dependency.opts[:dest])
              relative = Path.relative_to(absolute, File.cwd!())

              {key,
               if(relative == absolute,
                 do: {:absolute, absolute},
                 else: {:checkout_relative, relative}
               )}
            else
              {key, value}
            end
          end)
          |> effective_config()

        config =
          config
          |> Keyword.put(:cache_builder, builder)
          |> Keyword.put(:builder_configuration, configuration)

        if toolchain? do
          Keyword.put(config, :builder_inputs, %{
            environment:
              (@native_environment ++ builder[:env])
              |> Enum.uniq()
              |> Enum.sort()
              |> Enum.map(&{&1, System.get_env(&1)}),
            files: Enum.map(builder[:inputs], &{&1, Key.tree(&1)}),
            tools: Enum.map(builder[:tools], &tool_identity(&1, dependency.opts[:dest]))
          })
        else
          config
        end
      else
        generator_config(dependency, config, toolchain?)
      end
    end)
  end

  def materialize?(config),
    do:
      not is_nil(config[:cache_builder]) or
        (Keyword.has_key?(config, :rebar) and (config[:source_generators] || []) != [])

  def prepare_sources(dependency, config) do
    Enum.each(config[:generated_sources] || [], fn path ->
      case File.rm(Path.join(dependency.opts[:dest], path)) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        _ -> throw(:unmodeled_input)
      end
    end)
  end

  defp generator_config(dependency, config, toolchain?) do
    {paths, extensions} =
      if dependency.manager == :mix do
        # Mix prepends both generators, even when :compilers omits :erlang.
        {config[:erlc_paths] || ["src"], [".yrl", ".xrl"]}
      else
        rebar = config[:rebar] || []
        prod = Keyword.get(rebar[:profiles] || [], :prod, [])

        {Keyword.get(prod, :src_dirs, rebar[:src_dirs] || ["src"]) ++
           Keyword.get(prod, :extra_src_dirs, rebar[:extra_src_dirs] || []), [".yrl", ".xrl"]}
      end

    if not Enum.all?(paths, &source_path?/1), do: throw(:unmodeled_input)
    root = dependency.opts[:dest]
    directories = Enum.map(paths, &Path.expand(to_string(&1), root))

    outputs =
      root
      |> Key.paths()
      |> Enum.filter(fn path ->
        absolute = Path.expand(path, root)

        Path.extname(path) in extensions and File.regular?(absolute) and
          Enum.any?(directories, &(Path.type(Path.relative_to(absolute, &1)) == :relative))
      end)
      |> Enum.map(&(Path.rootname(&1) <> ".erl"))
      |> Enum.uniq()
      |> Enum.sort()

    config = Keyword.put(config, :source_generators, outputs)

    if toolchain? and outputs != [] do
      originals = original_files(dependency)
      # Keep shipped files and opaque directory/submodule contents as inputs.
      # A regenerated shipped file is caught by post-staging reconciliation.
      derived =
        Enum.reject(outputs, fn path ->
          path
          |> Path.split()
          |> Enum.scan(&Path.join(&2, &1))
          |> Enum.any?(&MapSet.member?(originals, &1))
        end)

      Keyword.put(config, :generated_sources, derived)
    else
      config
    end
  end

  defp original_files(%{scm: Mix.SCM.Git} = dependency) do
    {:git, _, revision, _} = dependency.opts[:lock]

    {files, 0} =
      System.cmd("git", ["ls-tree", "-rz", "--name-only", revision, "--"],
        cd: dependency.opts[:dest],
        stderr_to_stdout: true,
        env: [{"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}, {"GIT_INDEX_FILE", nil}]
      )

    files |> String.split(<<0>>, trim: true) |> MapSet.new()
  end

  defp original_files(dependency) do
    if dependency.scm != Hex.SCM, do: throw(:unmodeled_input)

    {:ok, metadata} =
      :file.consult(String.to_charlist(Path.join(dependency.opts[:dest], "hex_metadata.config")))

    {"files", files} = List.keyfind(metadata, "files", 0)
    if not is_list(files) or not Enum.all?(files, &is_binary/1), do: throw(:unmodeled_input)
    MapSet.new(files)
  end

  def outputs_present?(_build, nil), do: true

  def outputs_present?(build, builder) do
    Enum.all?(builder[:outputs], fn path ->
      case File.stat(Path.join(build, path)) do
        {:ok, %{type: type}} when type in [:regular, :directory] -> true
        _ -> false
      end
    end)
  end

  def source_tree(dependency, config), do: Key.tree(dependency.opts[:dest], generated(config))

  def source_paths(dependency, config), do: Key.paths(dependency.opts[:dest], generated(config))

  def artifacts(dependency, _config) do
    build = dependency.opts[:build]
    resources = ["ebin", "priv", "include", "src"]

    # Mix manifests contain volatile incremental state, not consumable library
    # resources. All other application outputs participate, including custom bins.
    other =
      case File.ls(build) do
        {:ok, names} -> names -- [".mix" | resources]
        {:error, :enoent} -> []
        _ -> throw(:unmodeled_input)
      end

    Enum.map(Enum.sort(resources ++ other), fn name ->
      path =
        if name in resources,
          do: resource_directory(build, dependency.opts[:dest], name),
          else: Path.join(build, name)

      {name, Key.tree(path, [], true)}
    end)
  end

  def effective_config(config) do
    config
    |> Keyword.keys()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, Keyword.fetch!(config, &1)})
  end

  def resource_directory(build, source, name) when name in ["ebin", "priv", "include", "src"] do
    path = Path.join(build, name)

    if match?({:ok, %{type: :symlink}}, File.lstat(path)) do
      target = File.read_link!(path) |> Path.expand(Path.dirname(path))
      expected = Path.expand(Path.join(source, name))

      if target != expected or File.lstat!(expected).type != :directory,
        do: throw(:unmodeled_input)

      Key.canonical_path(expected)
    else
      path
    end
  end

  def supported_config?(config) do
    cond do
      config[:cache_builder] ->
        valid_builder?(config[:cache_builder])

      Keyword.has_key?(config, :rebar) ->
        supported_rebar?(config[:rebar])

      true ->
        compilers = config[:compilers] || Mix.compilers()
        paths = (config[:elixirc_paths] || ["lib"]) ++ (config[:erlc_paths] || ["src"])
        include = config[:erlc_include_path] || "include"

        Enum.all?(compilers, &(&1 in [:yecc, :leex, :erlang, :elixir, :app])) and
          not Enum.any?(config[:aliases] || [], fn {name, _} ->
            name in [
              :compile,
              :loadpaths,
              :"deps.loadpaths",
              :loadconfig,
              :"app.config",
              :will_recompile
            ] or
              (String.starts_with?(to_string(name), "compile.") and
                 String.replace_prefix(to_string(name), "compile.", "") in Enum.map(
                   compilers,
                   &to_string/1
                 ))
          end) and
          (config[:elixirc_options] || [])[:tracers] in [nil, []] and
          Enum.all?([include | paths], &source_path?/1) and
          supported_erl_options?(config[:erlc_options] || []) and
          Enum.all?((config[:yecc_options] || []) ++ (config[:leex_options] || []), fn
            {:includefile, path} -> source_path?(path)
            _ -> true
          end)
    end
  end

  def unsupported_source?(path, config \\ []) do
    is_nil(config[:cache_builder]) and
      (Path.extname(path) in [".c", ".cc", ".cpp", ".rs", ".so", ".dylib", ".dll", ".o", ".a"] or
         String.ends_with?(path, ".app.src.script") or
         (Path.basename(path) == "rebar.config.script" and not Keyword.has_key?(config, :rebar)))
  end

  defp project_config(%{manager: :mix} = dependency, _toolchain?) do
    Mix.Dep.in_dependency(dependency, fn project ->
      application =
        if function_exported?(project, :application, 0), do: project.application(), else: []

      Keyword.put(Mix.Project.config(), :application_definition, application)
    end)
  end

  defp project_config(%{manager: :rebar3} = dependency, toolchain?) do
    config =
      Keyword.put(
        application_config(dependency),
        :rebar,
        Mix.Rebar.dependency_config(dependency.extra)
      )

    if toolchain?, do: Keyword.put(config, :rebar_toolchain, rebar_identity()), else: config
  end

  defp project_config(%{manager: :make} = dependency, _toolchain?),
    do: application_config(dependency)

  defp application_config(dependency) do
    app = dependency.app
    root = dependency.opts[:dest]

    source =
      Enum.find(["src/#{app}.app.src", "ebin/#{app}.app"], fn path ->
        File.regular?(Path.join(root, path))
      end)

    if is_nil(source), do: throw(:unmodeled_input)

    {:ok, [{:application, ^app, properties}]} =
      :file.consult(String.to_charlist(Path.join(root, source)))

    version = Keyword.fetch!(properties, :vsn)
    if not (is_binary(version) or is_list(version)), do: throw(:unmodeled_input)
    [app: app, version: to_string(version)]
  end

  defp valid_builder?(builder) do
    Keyword.keyword?(builder) and
      Enum.all?(
        Keyword.keys(builder),
        &(&1 in [:platform, :outputs, :generated, :env, :inputs, :tools])
      ) and
      is_binary(builder[:platform]) and String.trim(builder[:platform]) != "" and
      is_list(builder[:outputs]) and is_list(builder[:generated] || []) and
      Enum.all?(builder[:outputs] ++ (builder[:generated] || []), fn path ->
        is_binary(path) and source_path?(path) and Path.join(Path.split(path)) == path and
          not String.contains?(path, "\\") and "." not in Path.split(path)
      end) and
      is_list(builder[:env] || []) and
      Enum.all?(
        builder[:env] || [],
        &(is_binary(&1) and Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, &1))
      ) and
      is_list(builder[:inputs] || []) and Enum.all?(builder[:inputs] || [], &is_binary/1) and
      is_list(builder[:tools] || []) and
      Enum.all?(builder[:tools] || [], &(is_binary(&1) and &1 != ""))
  end

  defp normalize_builder(builder) do
    if not valid_builder?(builder), do: throw(:unmodeled_input)

    [platform: builder[:platform]] ++
      Enum.map([:outputs, :generated, :env, :inputs, :tools], fn key ->
        {key, (builder[key] || []) |> Enum.uniq() |> Enum.sort()}
      end)
  end

  defp tool_identity(tool, source) do
    executable =
      if Path.type(tool) == :absolute or String.contains?(tool, ["/", "\\"]),
        do: System.find_executable(Path.expand(tool, source)),
        else:
          (System.get_env("PATH") || "")
          |> String.split(if(match?({:win32, _}, :os.type()), do: ";", else: ":"))
          |> Enum.find_value(fn directory ->
            System.find_executable(Path.expand(Path.join(directory, tool), source))
          end)

    if is_nil(executable), do: throw(:unmodeled_input)
    {tool, executable, Key.canonical_path(executable), Key.digest(File.read!(executable))}
  end

  defp generated(config),
    do: ((config[:cache_builder] || [])[:generated] || []) ++ (config[:generated_sources] || [])

  defp supported_rebar?([]), do: true

  defp supported_rebar?(config) do
    Keyword.keyword?(config) and
      Enum.all?(config, fn {key, _} -> key in @rebar_options end) and
      supported_erl_options?(config[:erl_opts] || []) and
      Enum.all?(config[:alias] || [], fn {name, _} ->
        to_string(name) not in ["compile", "bare"]
      end) and
      Enum.all?((config[:pre_hooks] || []) ++ (config[:post_hooks] || []), fn
        {:clean, _} -> true
        {_, :clean, _} -> true
        _ -> false
      end) and
      Enum.all?(
        (config[:src_dirs] || ["src"]) ++ (config[:extra_src_dirs] || []),
        &source_path?/1
      ) and
      Enum.all?(config[:erl_first_files] || [], &source_path?/1) and
      supported_rebar?(Keyword.get(config[:profiles] || [], :prod, []))
  end

  defp supported_erl_options?(options) do
    Enum.all?(options, fn
      {:i, path} -> source_path?(path)
      _ -> true
    end)
  end

  defp source_path?(path) do
    path = to_string(path)
    parts = Path.split(path)

    path != "" and Path.type(path) == :relative and ".." not in parts and
      hd(parts) not in [".git", "_build"]
  end

  defp rebar_identity do
    if not Mix.Rebar.available?(:rebar3), do: Mix.Tasks.Local.Rebar.run(["--force"])

    {command, args} =
      if function_exported?(Mix.Rebar, :rebar_args, 2),
        do: apply(Mix.Rebar, :rebar_args, [:rebar3, []]),
        else: {apply(Mix.Rebar, :rebar_cmd, [:rebar3]), []}

    Enum.map([System.find_executable(command) || command | args], fn path ->
      {Path.expand(path), Key.digest(File.read!(path))}
    end)
  end
end
