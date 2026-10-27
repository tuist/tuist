defmodule TuistWeb.CodeReloader do
  @moduledoc false

  alias Mix.Tasks.Compile.Elixir, as: CompileElixir

  def reload(endpoint, opts) do
    normalize_mix_compile_lock_mtime(
      Mix.Project.config_files(),
      reloadable_app_manifests(endpoint)
    )

    Phoenix.CodeReloader.reload(endpoint, opts)
  end

  def stale_config_files(config_files, manifests) do
    manifests = List.flatten(manifests)

    config_files
    |> Enum.reject(&mix_compile_lock?/1)
    |> Mix.Utils.extract_stale(manifests)
  end

  def normalize_mix_compile_lock_mtime(config_files, manifests) do
    manifests = List.flatten(manifests)
    compile_locks = Enum.filter(config_files, &mix_compile_lock?/1)
    stale_compile_locks = Mix.Utils.extract_stale(compile_locks, manifests)

    # Mix 1.19 reports compile.lock as a config file; Phoenix can safely ignore it
    # when no real config file changed because it is only a build artifact.
    if stale_compile_locks != [] and stale_config_files(config_files, manifests) == [] do
      oldest_manifest_mtime = oldest_manifest_mtime(manifests)
      Enum.each(stale_compile_locks, &File.touch!(&1, oldest_manifest_mtime))
    end

    :ok
  end

  defp reloadable_app_manifests(endpoint) do
    endpoint
    |> reloadable_apps()
    |> Enum.flat_map(&manifests_for_app/1)
  end

  defp reloadable_apps(endpoint) do
    endpoint.config(:reloadable_apps) || default_reloadable_apps()
  end

  defp default_reloadable_apps do
    if Mix.Project.umbrella?() do
      Enum.map(Mix.Dep.Umbrella.cached(), & &1.app)
    else
      [Mix.Project.config()[:app]]
    end
  end

  defp manifests_for_app(app) do
    current_app = Mix.Project.config()[:app]
    dep = Enum.find(Mix.Dep.cached(), &(&1.app == app))

    cond do
      app == current_app ->
        [CompileElixir.manifests()]

      dep ->
        [dep_manifests(dep)]

      true ->
        []
    end
  end

  # Reads the dependency's manifest out of its build directory instead of
  # entering its Mix project.
  #
  # `Mix.Dep.in_dependency/3` changes the working directory and pushes the
  # dependency onto Mix's project stack. For a path dependency whose project
  # module is already loaded, that raises, and this runs on every request in
  # dev, so one failure leaves the stack dirty and every later request raises
  # too. The raise also breaks `Plug.Static`, which stops resolving
  # `priv/static` and serves the dashboard without its stylesheet.
  #
  # Mix records each dependency's build directory in its opts, and the
  # manifest sits at the same `.mix/` path the compiler uses, so the location
  # is derivable without loading anything.
  defp dep_manifests(%{opts: opts}) do
    case Keyword.fetch(opts, :build) do
      {:ok, build} -> Enum.map(CompileElixir.manifests(), &Path.join([build, ".mix", Path.basename(&1)]))
      :error -> []
    end
  end

  defp mix_compile_lock?(path) do
    Path.basename(path) == "compile.lock" and path |> Path.dirname() |> Path.basename() == ".mix"
  end

  defp oldest_manifest_mtime(manifests) do
    manifests
    |> Enum.map(&Mix.Utils.last_modified/1)
    |> Enum.min()
  end
end
