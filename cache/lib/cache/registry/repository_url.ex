defmodule Cache.Registry.RepositoryURL do
  @moduledoc """
  Shared helpers for parsing and normalizing Git repository URLs.
  """

  def normalize_git_url(repository_url) do
    Regex.replace(~r/^git@(.+):/, repository_url, "https://\\1/")
  end

  def repository_full_handle_from_url(repository_url) do
    full_handle =
      repository_url
      |> normalize_git_url()
      |> URI.parse()
      |> Map.get(:path)
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
