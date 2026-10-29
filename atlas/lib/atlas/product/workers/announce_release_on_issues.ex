defmodule Atlas.Product.Workers.AnnounceReleaseOnIssues do
  @moduledoc """
  When a GitHub release is published in a repository connected to Atlas, walks
  the pull requests referenced by the release body, then the issues referenced
  by those pull requests, and posts a comment on each referenced issue linking
  back to the release.

  The comment is intentionally short and idempotent: if an existing comment on
  the issue already contains the release URL, the worker skips it. Combined with
  Oban's `unique` on `(owner, repo, tag)`, a duplicate release delivery is a
  no-op.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Atlas.Audit
  alias Atlas.Integrations
  alias Atlas.Integrations.GitHubAPI

  require Logger

  @issue_ref_re ~r/(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s*#(\d+)/i
  @pr_ref_re ~r/#(\d+)/

  @impl true
  def perform(%Oban.Job{args: args}) do
    %{
      "owner" => owner,
      "repo" => repo,
      "tag" => tag,
      "release_url" => release_url,
      "release_body" => release_body
    } = args

    github_app_id = Map.get(args, "github_app_id")

    with {:ok, repository} <- fetch_repository(github_app_id, owner, repo),
         {:ok, client} <- GitHubAPI.req(repository.github_app) do
      pr_numbers = pr_numbers(release_body)

      issue_numbers =
        pr_numbers
        |> Enum.flat_map(&issue_numbers_for_pr(client, owner, repo, &1))
        |> Enum.uniq()
        |> Enum.reject(&(&1 in pr_numbers))

      Enum.each(issue_numbers, fn number ->
        announce_on_issue(client, owner, repo, number, tag, release_url)
      end)

      :ok
    end
  end

  defp fetch_repository(github_app_id, owner, repo) when is_binary(github_app_id) do
    Integrations.get_github_repository(github_app_id, owner, repo)
  end

  defp fetch_repository(_github_app_id, owner, repo) do
    Integrations.get_github_repository(owner, repo)
  end

  @doc """
  Extracts pull request numbers referenced in a release body. Auto-generated
  release notes list PRs as `#NNN` links.
  """
  def pr_numbers(body) when is_binary(body) do
    @pr_ref_re
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(fn [n] -> String.to_integer(n) end)
    |> Enum.uniq()
  end

  def pr_numbers(_body), do: []

  defp issue_numbers_for_pr(client, owner, repo, pr_number) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/pulls/#{pr_number}") do
      {:ok, %{status: 200, body: pr}} ->
        body = pr["body"] || ""

        candidates =
          @issue_ref_re
          |> Regex.scan(body, capture: :all_but_first)
          |> Enum.map(fn [n] -> String.to_integer(n) end)
          |> Enum.uniq()

        Enum.filter(candidates, &issue?(client, owner, repo, &1))

      _ ->
        []
    end
  end

  defp issue?(client, owner, repo, number) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/issues/#{number}") do
      {:ok, %{status: 200, body: %{"pull_request" => _}}} -> false
      {:ok, %{status: 200, body: %{"number" => ^number}}} -> true
      _ -> false
    end
  end

  defp announce_on_issue(client, owner, repo, number, tag, release_url) do
    if already_announced?(client, owner, repo, number, release_url) do
      :ok
    else
      case Req.post(client,
             url: "/repos/#{owner}/#{repo}/issues/#{number}/comments",
             json: %{"body" => comment_body(tag, release_url)}
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          Audit.record("github.release.issue_announced", %{
            interface: "worker",
            target_type: "github_issue",
            target_id: "#{owner}/#{repo}##{number}",
            target_label: "#{owner}/#{repo}##{number}",
            metadata: %{"tag" => tag, "release_url" => release_url}
          })

          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.warning(
            "Failed to post release announcement on #{owner}/#{repo}##{number}: #{status} #{inspect(body)}"
          )

          :ok

        {:error, reason} ->
          Logger.warning("Failed to post release announcement on #{owner}/#{repo}##{number}: #{inspect(reason)}")

          :ok
      end
    end
  end

  defp already_announced?(client, owner, repo, number, release_url) do
    case Req.get(client, url: "/repos/#{owner}/#{repo}/issues/#{number}/comments", params: [per_page: 100]) do
      {:ok, %{status: 200, body: comments}} when is_list(comments) ->
        Enum.any?(comments, fn comment ->
          body = comment["body"] || ""
          String.contains?(body, release_url)
        end)

      _ ->
        false
    end
  end

  defp comment_body(tag, release_url) do
    "Shipped in [#{tag}](#{release_url})."
  end
end
