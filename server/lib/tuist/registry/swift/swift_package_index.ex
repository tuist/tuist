defmodule Tuist.Registry.Swift.SwiftPackageIndex do
  @moduledoc """
  Fetches and parses the SwiftPackageIndex packages.json catalog.
  """

  alias TuistCommon.Registry.Swift.KeyNormalizer
  alias TuistCommon.Registry.Swift.RepositoryURL

  require Logger

  @github_opts [finch: Tuist.Finch, retry: false]

  def list_packages(token) do
    with {:ok, json} <- TuistCommon.GitHub.fetch_packages_json(token, @github_opts),
         {:ok, urls} <- JSON.decode(json) do
      packages =
        urls
        |> Enum.map(&RepositoryURL.repository_full_handle_from_url/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, full_handle} -> package_from_full_handle(full_handle) end)

      {:ok, packages}
    else
      {:error, reason} = error ->
        Logger.warning("Failed to fetch SPI packages list: #{inspect(reason)}")
        error
    end
  end

  defp package_from_full_handle(full_handle) do
    [scope, name] = String.split(full_handle, "/")
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)

    %{
      scope: scope,
      name: name,
      repository_full_handle: full_handle
    }
  end
end
