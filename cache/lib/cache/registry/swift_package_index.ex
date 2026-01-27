defmodule Cache.Registry.SwiftPackageIndex do
  @moduledoc """
  Fetches and parses the SwiftPackageIndex package list.
  """

  alias Cache.Registry.GitHub

  require Logger

  @spec list_packages(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_packages(token) do
    with {:ok, json} <- GitHub.fetch_packages_json(token),
         {:ok, urls} <- Jason.decode(json) do
      packages =
        urls
        |> Enum.map(&repository_full_handle_from_url/1)
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

    %{
      scope: String.downcase(scope),
      name: name |> String.replace(".", "_") |> String.downcase(),
      repository_full_handle: full_handle
    }
  end

  defp repository_full_handle_from_url(repository_url) do
    normalized = Regex.replace(~r/^git@(.+):/, repository_url, "https://\\1/")
    path = normalized |> URI.parse() |> Map.get(:path)

    full_handle =
      path
      |> to_string()
      |> String.replace_leading("/", "")
      |> String.replace_trailing("/", "")
      |> String.replace_trailing(".git", "")

    if full_handle |> String.split("/") |> Enum.count() == 2 do
      {:ok, full_handle}
    else
      {:error, :invalid_repository_url}
    end
  end
end
