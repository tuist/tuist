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
        [Mix.Dep.in_dependency(dep, fn _ -> CompileElixir.manifests() end)]

      true ->
        []
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
