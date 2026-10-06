defmodule TuistOps.GitHub.OrgMembership do
  @moduledoc """
  Reads and changes a user's role in the GitHub organization that owns
  `Environment.github_repository/0`. Backs GitHub admin elevations:
  approval promotes the member to `admin` (organization owner) and the
  revert demotes them back to `member`.

  Requires the GitHub App installation to hold the organization
  "Members" permission with read and write access.
  """

  alias TuistOps.Environment
  alias TuistOps.GitHub.AppToken

  @github_api_url "https://api.github.com"

  @doc """
  Returns `{:ok, %{state: state, role: role}}` for `login`'s membership,
  where `state` is `"active"` or `"pending"` and `role` is `"admin"` or
  `"member"`. Returns `{:error, :not_member}` when the login is not part
  of the organization.
  """
  def membership(login) when is_binary(login) do
    with {:ok, headers} <- headers() do
      login
      |> membership_url()
      |> Req.get(headers: headers)
      |> handle_membership()
    end
  end

  @doc """
  Sets `login`'s organization role to `role` (`"admin"` or `"member"`).
  For an existing active member the change is immediate.
  """
  def set_role(login, role) when is_binary(login) and role in ["admin", "member"] do
    with {:ok, headers} <- headers() do
      login
      |> membership_url()
      |> Req.put(headers: headers, body: JSON.encode!(%{role: role}))
      |> handle_membership()
    end
  end

  def organization do
    Environment.github_repository()
    |> String.split("/", parts: 2)
    |> hd()
  end

  defp membership_url(login) do
    "#{@github_api_url}/orgs/#{organization()}/memberships/#{URI.encode(login, &URI.char_unreserved?/1)}"
  end

  defp headers do
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

  defp handle_membership(
         {:ok, %Req.Response{status: 200, body: %{"state" => state, "role" => role}}}
       ) do
    {:ok, %{state: state, role: role}}
  end

  defp handle_membership({:ok, %Req.Response{status: 404}}), do: {:error, :not_member}

  defp handle_membership({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:github_status, status, body}}
  end

  defp handle_membership({:error, reason}), do: {:error, {:github_error, reason}}
end
