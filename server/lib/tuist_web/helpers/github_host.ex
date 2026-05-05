defmodule TuistWeb.Helpers.GitHubHost do
  @moduledoc """
  Resolves the GitHub instance URL (`client_url`) used to build commit / branch
  / blob links for a project or run.

  Callers must preload `vcs_connection: :github_app_installation`. If the
  association is missing we fall back to the default github.com URL — there is
  no on-the-fly preload here because the helper is invoked from per-row
  rendering paths and a hidden `Repo.preload` would cause N+1 queries.
  """

  alias Tuist.VCS

  @doc """
  Returns the base GitHub URL for a project struct (or anything wrapping a
  `:vcs_connection` with a `:github_app_installation`).
  """
  def base_url(%{vcs_connection: %{github_app_installation: %{client_url: client_url}}})
      when is_binary(client_url) and client_url != "", do: client_url

  def base_url(_), do: VCS.default_client_url()

  @doc """
  Same as `base_url/1` but for a run-shaped struct that wraps the project at
  `:project`.
  """
  def base_url_for_run(%{project: project}), do: base_url(project)
  def base_url_for_run(_), do: VCS.default_client_url()
end
