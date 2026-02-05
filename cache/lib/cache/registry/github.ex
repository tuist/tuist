defmodule Cache.Registry.GitHub do
  @moduledoc """
  GitHub API client for registry ingestion.

  Delegates to `TuistCommon.GitHub` for the actual API calls.
  """

  @finch_opts [finch: Cache.Finch, retry: false]

  def list_tags(repository_full_handle, token) do
    TuistCommon.GitHub.list_tags(repository_full_handle, token, @finch_opts)
  end

  def list_repository_contents(repository_full_handle, token, ref) do
    TuistCommon.GitHub.list_repository_contents(repository_full_handle, token, ref, @finch_opts)
  end

  def get_file_content(repository_full_handle, token, path, ref) do
    TuistCommon.GitHub.get_file_content(repository_full_handle, token, path, ref, @finch_opts)
  end

  def download_zipball(repository_full_handle, token, tag, destination_path) do
    TuistCommon.GitHub.download_zipball(repository_full_handle, token, tag, destination_path, @finch_opts)
  end

  def fetch_packages_json(token) do
    TuistCommon.GitHub.fetch_packages_json(token, @finch_opts)
  end
end
