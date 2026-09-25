defmodule Tuist.GitHistory.Providers.GitHubTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.GitHistory.Providers.GitHub
  alias Tuist.GitHub.Client

  @connection %{repository_full_handle: "tuist/tuist", github_app_installation: %{installation_id: "1", client_url: nil}}

  defp api_commit(sha, parents, date) do
    %{"sha" => sha, "parents" => Enum.map(parents, &%{"sha" => &1}), "commit" => %{"committer" => %{"date" => date}}}
  end

  test "compare maps the merge base, commits and files with head-side hunks" do
    expect(Client, :compare_commits, fn %{base: "main", head: "head", page: 1} ->
      {:ok,
       %{
         "merge_base_commit" => %{"sha" => "base"},
         "total_commits" => 1,
         "commits" => [api_commit("head", ["base"], "2026-09-01T00:03:00Z")],
         "files" => [
           %{
             "filename" => "Sources/A.swift",
             "status" => "modified",
             "sha" => "blobA",
             "patch" => "@@ -1,3 +1,4 @@\n a\n+b\n@@ -10 +11 @@\n-x\n+y\n@@ -20,2 +22,0 @@\n-gone\n-gone"
           },
           %{
             "filename" => "Sources/New.swift",
             "previous_filename" => "Sources/Old.swift",
             "status" => "renamed",
             "sha" => "blobN"
           },
           %{
             "filename" => "Sources/Gone.swift",
             "status" => "removed",
             "sha" => "blobG",
             "patch" => "@@ -1,2 +0,0 @@\n-a\n-b"
           }
         ]
       }}
    end)

    assert {:ok, compare} = GitHub.compare(@connection, "main", "head", page_budget: 3)
    assert compare.merge_base_sha == "base"
    assert [%{sha: "head", parents: ["base"], committed_at: ~U[2026-09-01 00:03:00Z]}] = compare.commits
    refute compare.truncated

    assert compare.files == [
             %{
               path: "Sources/A.swift",
               previous_path: nil,
               status: "modified",
               git_blob_id: "blobA",
               hunks: [%{start: 1, end: 4}, %{start: 11, end: 11}],
               truncated: false
             },
             %{
               path: "Sources/New.swift",
               previous_path: "Sources/Old.swift",
               status: "renamed",
               git_blob_id: "blobN",
               hunks: [],
               truncated: true
             },
             %{
               path: "Sources/Gone.swift",
               previous_path: nil,
               status: "deleted",
               git_blob_id: nil,
               hunks: [],
               truncated: false
             }
           ]
  end

  test "compare stops at the page budget and says so" do
    expect(Client, :compare_commits, 2, fn %{page: page} ->
      {:ok,
       %{
         "merge_base_commit" => %{"sha" => "base"},
         "total_commits" => 600,
         "commits" => [api_commit("c#{page}", [], "2026-09-01T00:00:00Z")],
         "files" => []
       }}
    end)

    assert {:ok, %{commits: [%{sha: "c1"}, %{sha: "c2"}], truncated: true}} =
             GitHub.compare(@connection, "main", "head", page_budget: 2)
  end

  test "history walks pages newest first and stops at the window" do
    expect(Client, :list_commits, fn %{sha: "head", page: 1} ->
      {:ok, Enum.map(1..100, fn i -> api_commit("c#{i}", ["c#{i + 1}"], "2026-09-01T00:00:00Z") end)}
    end)

    expect(Client, :list_commits, fn %{sha: "head", page: 2} ->
      {:ok, [api_commit("c101", ["c102"], "2026-09-01T00:00:00Z"), api_commit("old", [], "2020-01-01T00:00:00Z")]}
    end)

    assert {:ok, commits} = GitHub.history(@connection, "head", page_budget: 5, since: ~U[2026-01-01 00:00:00Z])
    assert length(commits) == 101
    refute Enum.any?(commits, &(&1.sha == "old"))
  end

  test "pull_request returns the base branch and both heads" do
    expect(Client, :get_pull_request, fn %{pr_number: 42} ->
      {:ok, %{"base" => %{"ref" => "main", "sha" => "basehead"}, "head" => %{"sha" => "head"}}}
    end)

    assert GitHub.pull_request(@connection, 42) == {:ok, %{base_branch: "main", base_sha: "basehead", head_sha: "head"}}
  end
end
