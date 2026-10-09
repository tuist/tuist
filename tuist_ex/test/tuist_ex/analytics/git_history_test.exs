defmodule TuistEx.Analytics.GitHistoryTest do
  use ExUnit.Case, async: false
  use Mimic

  alias TuistEx.Analytics.GitHistory
  alias TuistEx.Analytics.HTTP

  setup do
    repo = Path.join(System.tmp_dir!(), "tuist-ex-history-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)
    git!(repo, ["init", "--quiet", "--initial-branch=main"])
    File.write!(Path.join(repo, "a.ex"), "a\n")
    base = commit!(repo, "base")
    git!(repo, ["checkout", "--quiet", "-b", "feature"])
    File.write!(Path.join(repo, "a.ex"), "a\nb\n")
    head = commit!(repo, "change")
    %{repo: repo, base: base, head: head}
  end

  defp git!(dir, args) do
    env = [
      {"GIT_AUTHOR_NAME", "Test"},
      {"GIT_AUTHOR_EMAIL", "test@tuist.dev"},
      {"GIT_COMMITTER_NAME", "Test"},
      {"GIT_COMMITTER_EMAIL", "test@tuist.dev"},
      {"GIT_CONFIG_GLOBAL", "/dev/null"}
    ]

    {output, 0} =
      System.cmd("git", ["-C", dir, "-c", "commit.gpgsign=false" | args],
        env: env,
        stderr_to_stdout: true
      )

    String.trim(output)
  end

  defp commit!(dir, message) do
    git!(dir, ["add", "-A"])
    git!(dir, ["commit", "--quiet", "-m", message])
    git!(dir, ["rev-parse", "HEAD"])
  end

  defp environment(head, extra \\ %{}) do
    variables =
      Map.merge(
        %{
          "GIT_COMMIT" => head,
          "GIT_BRANCH" => "feature",
          "GIT_REMOTE_URL" => "https://github.com/tuist/app",
          "GITHUB_BASE_REF" => "main",
          "GITHUB_REF" => "refs/pull/7/merge"
        },
        extra
      )

    &Map.get(variables, &1)
  end

  defp stub_settings do
    stub(HTTP, :project_request, fn :get, "/tests/git-history/settings", nil, _options ->
      {:ok,
       %{
         "window_days" => 30,
         "window_commits" => 100,
         "deepen_budget_seconds" => 5,
         "upload_batch_size" => 1,
         "commit_file_limit" => 10
       }}
    end)
  end

  test "reports the merge base, the changed files and the pull request", %{
    repo: repo,
    base: base,
    head: head
  } do
    stub_settings()

    collected = GitHistory.collect(repo, [], environment(head))

    assert %{
             base_branch: "main",
             merge_base_sha: ^base,
             is_pull_request: true,
             pull_request_number: 7,
             git_object_format: "sha1",
             history_source: "client",
             git_dirty: false,
             changed_files: [%{path: "a.ex", status: "modified", hunks: [%{start: 2, end: 2}]}]
           } = GitHistory.payload(collected)

    assert collected.settings.upload_batch_size == 1
  end

  test "reports a checkout it cannot read as having no history", %{head: head} do
    outside =
      Path.join(System.tmp_dir!(), "tuist-ex-not-git-#{System.unique_integer([:positive])}")

    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)

    payload = outside |> GitHistory.collect([], environment(head)) |> GitHistory.payload()

    assert payload.history_source == "none"
    assert payload.history_fallback_reason == "the working directory is not a Git repository"
    assert payload.pull_request_number == 7
  end

  test "uploads the missing commits oldest first, the branch head last, then the listing", %{
    repo: repo,
    base: base,
    head: head
  } do
    stub_settings()
    collected = GitHistory.collect(repo, [], environment(head))
    test_pid = self()

    stub(HTTP, :project_request, fn
      :post, "/tests/git-history/commits/missing", %{shas: shas}, _ ->
        assert Enum.sort(shas) == Enum.sort([base, head])
        {:ok, %{"missing" => [base, head]}}

      :post, "/tests/git-history/commits", body, _ ->
        send(test_pid, {:commits, body})
        {:ok, %{}}

      :post, "/tests/git-history/listings/missing", %{shas: [^head]}, _ ->
        {:ok, %{"missing" => [head]}}

      :post, "/tests/git-history/listings", body, _ ->
        send(test_pid, {:listing, body})
        {:ok, %{}}
    end)

    assert GitHistory.upload(collected, []) == []

    assert_received {:commits, %{commits: [%{sha: ^base, parents: []}], branch_heads: []}}

    assert_received {:commits,
                     %{
                       repository_url: "https://github.com/tuist/app",
                       object_format: "sha1",
                       commits: [%{sha: ^head, parents: [^base]}],
                       branch_heads: [%{branch: "feature", sha: ^head}]
                     }}

    assert_received {:listing,
                     %{
                       sha: ^head,
                       files: [%{path: "a.ex"}],
                       complete: true,
                       truncated: false,
                       files_count: 1
                     }}
  end

  test "never uploads the listing of a dirty checkout", %{repo: repo, head: head} do
    stub_settings()
    File.write!(Path.join(repo, "untracked.ex"), "u\n")
    collected = GitHistory.collect(repo, [], environment(head))
    assert GitHistory.payload(collected).git_dirty

    stub(HTTP, :project_request, fn
      :post, "/tests/git-history/commits/missing", _, _ ->
        {:ok, %{"missing" => []}}

      :post, "/tests/git-history/commits", _, _ ->
        {:ok, %{}}

      :post, "/tests/git-history/listings" <> _, _, _ ->
        flunk("a dirty checkout's listing was uploaded")
    end)

    assert GitHistory.upload(collected, []) == []
  end

  test "reports an upload failure instead of raising", %{repo: repo, head: head} do
    stub_settings()
    collected = GitHistory.collect(repo, [], environment(head))
    stub(HTTP, :project_request, fn :post, _, _, _ -> {:error, {:http, 404, %{}}} end)

    assert [commits, listing] = GitHistory.upload(collected, [])
    assert commits =~ "the run's Git history could not be uploaded"
    assert listing =~ "the commit's file listing could not be uploaded"
  end
end
