defmodule Tuist.GitHistory.CompletionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Completion
  alias Tuist.GitHistory.Providers
  alias Tuist.GitHub.Client
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    repository = GitHistory.repository_id(account.id, "https://github.com/acme/app")
    connection = %{repository_full_handle: "acme/app", github_app_installation: %{installation_id: "1"}}
    settings = Map.merge(GitHistory.settings(nil), %{window_days: 30, provider_page_budget: 5})
    %{repository: repository, connection: connection, settings: settings}
  end

  defp at(days_ago), do: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -days_ago * 86_400, :second)

  defp commit(sha, parents, days_ago), do: %{sha: sha, parents: parents, committed_at: at(days_ago)}

  defp github(commits) do
    Enum.map(commits, fn commit ->
      %{
        "sha" => commit.sha,
        "parents" => Enum.map(commit.parents, &%{"sha" => &1}),
        "commit" => %{"committer" => %{"date" => DateTime.to_iso8601(commit.committed_at)}}
      }
    end)
  end

  # GitHub's listing from each SHA, newest first, as `git log` lists it.
  defp stub_listing(listings) do
    stub(Client, :list_commits, fn %{sha: sha, page: page} ->
      case Map.fetch(listings, sha) do
        {:ok, commits} -> {:ok, commits |> Enum.chunk_every(100) |> Enum.at(page - 1, []) |> github()}
        :error -> {:error, "Unexpected status code: 422."}
      end
    end)
  end

  defp complete(context, sha),
    do: Completion.complete(context.connection, context.repository, sha, context.settings, Providers.GitHub)

  test "fills both parents of a depth-1 pull request merge commit until they reach the known graph", context do
    # main: a ← b ← c; the pull request branches off a with p1 ← p2, and m
    # is GitHub's merge of p2 into c. The checkout only saw m; main's runs
    # stored a.
    %{repository: repository} = context
    a = commit("a", ["root"], 10)
    b = commit("b", ["a"], 6)
    c = commit("c", ["b"], 2)
    p1 = commit("p1", ["a"], 5)
    p2 = commit("p2", ["p1"], 3)
    GitHistory.record_commits(repository, "sha1", [a, commit("root", [], 11), commit("m", ["c", "p2"], 1)])

    stub_listing(%{"c" => [c, p2, b, p1, a], "p2" => [p2, p1, a]})

    assert {:ok, %{pages: 1, recorded: 4, gaps_left: []}} = complete(context, "m")
    assert GitHistory.parents(repository, "p1") == ["a"]
    assert {"a", 3} = GitHistory.nearest_ancestor(repository, "m", ["a"])
  end

  test "asks nothing when the graph behind the commit is whole", context do
    GitHistory.record_commits(context.repository, "sha1", [commit("a", [], 2), commit("b", ["a"], 1)])
    reject(&Client.list_commits/1)

    assert {:ok, %{pages: 0, recorded: 0, gaps_left: []}} = complete(context, "b")
  end

  test "lists a commit the client never uploaded", context do
    GitHistory.record_commits(context.repository, "sha1", [commit("a", [], 3)])
    stub_listing(%{"h" => [commit("h", ["a"], 1), commit("a", [], 3)]})

    assert {:ok, %{recorded: 1, gaps_left: []}} = complete(context, "h")
    assert GitHistory.parents(context.repository, "h") == ["a"]
  end

  test "stops at the history window and remembers a gap beyond it", context do
    GitHistory.record_commits(context.repository, "sha1", [commit("h", ["old"], 1)])
    expect(Client, :list_commits, fn %{sha: "old", page: 1} -> {:ok, github([commit("old", ["older"], 40)])} end)

    assert {:ok, %{pages: 1, recorded: 0, gaps_left: []}} = complete(context, "h")
    refute GitHistory.known?(context.repository, "old")

    reject(&Client.list_commits/1)
    assert {:ok, %{pages: 0, gaps_left: []}} = complete(context, "h")
  end

  test "spends no more pages than the budget", context do
    chain = for n <- 1..400, do: commit("c#{n}", ["c#{n + 1}"], 0)
    GitHistory.record_commits(context.repository, "sha1", [commit("h", ["c1"], 0)])
    stub_listing(%{"c1" => chain})

    assert {:ok, %{pages: 2, recorded: 200, gaps_left: ["c201"]}} =
             Completion.complete(
               context.connection,
               context.repository,
               "h",
               %{context.settings | provider_page_budget: 2},
               Providers.GitHub
             )
  end

  test "stops at the first error and does not ask for that commit again for a while", context do
    GitHistory.record_commits(context.repository, "sha1", [commit("h", ["gone", "other"], 1)])
    expect(Client, :list_commits, fn %{sha: "gone"} -> {:error, "Unexpected status code: 403."} end)

    assert {:error, "Unexpected status code: 403.", %{pages: 0, gaps_left: ["gone", "other"]}} = complete(context, "h")

    expect(Client, :list_commits, fn %{sha: "other"} -> {:ok, github([commit("other", [], 2)])} end)
    assert {:ok, %{pages: 1, recorded: 1, gaps_left: []}} = complete(context, "h")
  end
end
