defmodule TuistOps.GitHub.API do
  @moduledoc """
  Request headers shared by the GitHub REST clients, authenticated with
  the GitHub App installation token from `TuistOps.GitHub.AppToken`.
  """

  alias TuistOps.GitHub.AppToken

  def headers do
    case AppToken.token() do
      {:ok, token} ->
        {:ok,
         [
           {"Accept", "application/vnd.github+json"},
           {"Authorization", "Bearer #{token}"},
           {"Content-Type", "application/json; charset=utf-8"},
           {"X-GitHub-Api-Version", "2022-11-28"}
         ]}

      {:error, reason} ->
        {:error, {:github_app_token, reason}}
    end
  end
end
