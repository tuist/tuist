defmodule TuistEx.GitTest do
  use ExUnit.Case, async: true

  alias TuistEx.Git

  setup do
    directory = Path.join(System.tmp_dir!(), "tuist-ex-git-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    git!(directory, ["init", "--quiet", "--initial-branch=main"])
    %{repo: directory}
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

  defp write!(dir, path, contents) do
    path = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp commit!(dir, message) do
    git!(dir, ["add", "-A"])
    git!(dir, ["commit", "--quiet", "-m", message])
    git!(dir, ["rev-parse", "HEAD"])
  end

  describe "history/4" do
    test "reads the merge base and the commits", %{repo: repo} do
      write!(repo, "lib/a.ex", "one\ntwo\nthree\n")
      write!(repo, "lib/gone.ex", "bye\n")
      base = commit!(repo, "base")

      git!(repo, ["checkout", "--quiet", "-b", "feature"])
      write!(repo, "lib/a.ex", "one\nTWO\nthree\nfour\n")
      write!(repo, "lib/new file.ex", "hello\n")
      File.rm!(Path.join(repo, "lib/gone.ex"))
      head = commit!(repo, "change")

      assert {:ok, history} = Git.history(repo, head, "main")

      assert history.object_format == "sha1"
      assert history.head_sha == head
      assert history.merge_base_sha == base
      assert history.fallback_reason == nil
      assert Enum.map(history.commits, &{&1.sha, &1.parents}) == [{head, [base]}, {base, []}]
    end

    test "says why there is no merge base", %{repo: repo} do
      write!(repo, "a.ex", "a\n")
      head = commit!(repo, "only")

      assert {:ok,
              %{
                merge_base_sha: nil,
                fallback_reason: "no base branch is known"
              }} =
               Git.history(repo, head, nil)

      assert {:ok, %{merge_base_sha: nil, fallback_reason: reason}} =
               Git.history(repo, head, "develop", %{deepen_budget_seconds: 2})

      assert reason =~ "the base branch develop is not in the checkout"
    end

    test "fetches the base branch and deepens a shallow clone until the merge base", %{repo: repo} do
      write!(repo, "a.ex", "a\n")
      base = commit!(repo, "base")
      git!(repo, ["checkout", "--quiet", "-b", "feature"])

      for index <- 1..4 do
        write!(repo, "a.ex", "a#{index}\n")
        commit!(repo, "feature #{index}")
      end

      head = git!(repo, ["rev-parse", "HEAD"])
      clone = repo <> "-clone"
      on_exit(fn -> File.rm_rf!(clone) end)

      git!(Path.dirname(repo), [
        "clone",
        "--quiet",
        "--depth=1",
        "--branch=feature",
        "--single-branch",
        "file://" <> repo,
        clone
      ])

      assert {:ok, history} = Git.history(clone, head, "main")
      assert history.merge_base_sha == base
      assert history.fallback_reason == nil
      # The clone's boundary commit keeps the parent its commit object names.
      assert Enum.find(history.commits, &(&1.sha == head)).parents != []
    end

    test "reports the base branch's head and lists its commits", %{repo: repo} do
      write!(repo, "a.ex", "a\n")
      base = commit!(repo, "base")
      git!(repo, ["checkout", "--quiet", "-b", "feature"])
      write!(repo, "a.ex", "feature\n")
      head = commit!(repo, "feature")
      git!(repo, ["checkout", "--quiet", "main"])
      write!(repo, "b.ex", "b\n")
      base_head = commit!(repo, "landed")

      assert {:ok, history} = Git.history(repo, head, "main")
      assert history.merge_base_sha == base
      assert history.base_head_sha == base_head
      assert Enum.sort(Enum.map(history.commits, & &1.sha)) == Enum.sort([head, base_head, base])

      assert {:ok, %{base_head_sha: nil}} = Git.history(repo, head, nil)
    end

    test "reports the pull request's head from a depth-1 checkout of its merge ref", %{repo: repo} do
      write!(repo, "a.ex", "a\n")
      fork_point = commit!(repo, "base")
      git!(repo, ["checkout", "--quiet", "-b", "feature"])
      write!(repo, "feature.ex", "feature\n")
      pull_request_head = commit!(repo, "feature")
      git!(repo, ["checkout", "--quiet", "main"])
      write!(repo, "main.ex", "main\n")
      commit!(repo, "main")
      git!(repo, ["merge", "--quiet", "--no-ff", "feature", "-m", "Merge feature into main"])
      merge_commit = git!(repo, ["rev-parse", "HEAD"])
      git!(repo, ["update-ref", "refs/pull/1/merge", merge_commit])
      git!(repo, ["reset", "--quiet", "--hard", "HEAD^1"])
      git!(repo, ["config", "uploadpack.allowFilter", "true"])

      clone = repo <> "-clone"
      on_exit(fn -> File.rm_rf!(clone) end)
      File.mkdir_p!(clone)
      git!(clone, ["init", "--quiet"])
      git!(clone, ["remote", "add", "origin", "file://" <> repo])

      git!(clone, [
        "fetch",
        "--quiet",
        "--depth=1",
        "origin",
        "+refs/pull/1/merge:refs/remotes/pull/1/merge"
      ])

      git!(clone, ["checkout", "--quiet", "--detach", "refs/remotes/pull/1/merge"])

      git = fn subcommand, args ->
        case System.cmd("git", ["-C", clone, subcommand | args], stderr_to_stdout: true) do
          {output, 0} -> String.trim(output)
          _ -> nil
        end
      end

      environment = &%{"GITHUB_REF" => "refs/pull/1/merge", "GITHUB_SHA" => merge_commit}[&1]
      assert git.("rev-parse", ["HEAD^2"]) == nil
      assert TuistEx.Analytics.Env.git_commit_sha(environment, git) == pull_request_head

      assert {:ok, %{fallback_reason: reason, commits: commits}} =
               Git.history(clone, pull_request_head, "main", %{remote_access: :base_head})

      assert reason ==
               "the base branch main is not in the checkout; #{String.slice(pull_request_head, 0, 12)} is not in the checkout"

      refute Enum.any?(commits, &(&1.sha == pull_request_head))
      # The walk starts at the checkout's merge commit, as it did before.
      assert Enum.find(commits, &(&1.sha == merge_commit)).parents |> length() == 2

      assert {:ok, history} = Git.history(clone, pull_request_head, "main")
      # Whether the base branch's deepen then connects the fork point depends on
      # the Git version: 2.50 does; 2.54 and 2.56 fetch it but leave one side's
      # shallow boundary in place.
      assert history.merge_base_sha in [nil, fork_point]
      assert Enum.find(history.commits, &(&1.sha == pull_request_head)).parents == [fork_point]

      assert {:ok, %{files: files}} = Git.commit_files(clone, pull_request_head, 10)
      assert Enum.map(files, & &1.path) == ["a.ex", "feature.ex"]
    end

    test "reads only what the checkout has without remote access", %{repo: repo} do
      write!(repo, "a.ex", "a\n")
      commit!(repo, "base")
      git!(repo, ["checkout", "--quiet", "-b", "feature"])

      for index <- 1..2 do
        write!(repo, "a.ex", "a#{index}\n")
        commit!(repo, "feature #{index}")
      end

      head = git!(repo, ["rev-parse", "HEAD"])
      clone = repo <> "-clone"
      on_exit(fn -> File.rm_rf!(clone) end)

      git!(Path.dirname(repo), [
        "clone",
        "--quiet",
        "--depth=1",
        "--branch=feature",
        "--single-branch",
        "file://" <> repo,
        clone
      ])

      assert {:ok, %{merge_base_sha: nil, base_head_sha: nil, fallback_reason: reason}} =
               Git.history(clone, head, "main", %{remote_access: :none})

      assert reason == "the base branch main is not in the checkout"
      remote_main = git!(repo, ["rev-parse", "main"])

      assert {:ok,
              %{
                merge_base_sha: nil,
                base_head_sha: ^remote_main,
                commits: [%{sha: ^head}],
                fallback_reason: ^reason
              }} = Git.history(clone, head, "main", %{remote_access: :base_head})

      refute git!(clone, ["branch", "--remotes"]) =~ "origin/main"

      git!(clone, ["fetch", "--quiet", "--depth=1", "origin", "+main:refs/remotes/origin/main"])
      main = git!(clone, ["rev-parse", "origin/main"])

      assert {:ok, %{merge_base_sha: nil, base_head_sha: ^main, fallback_reason: reason}} =
               Git.history(clone, head, "main", %{remote_access: :none})

      assert reason ==
               "shallow clone: the merge base with main is not in the checkout"

      assert git!(clone, ["rev-list", "--count", "HEAD"]) == "1"
    end
  end

  test "dirty?/1 counts untracked files, as the command line tool does", %{repo: repo} do
    write!(repo, "a.ex", "a\n")
    commit!(repo, "base")
    refute Git.dirty?(repo)

    write!(repo, "untracked.ex", "u\n")
    assert Git.dirty?(repo)
  end

  test "commit_files/3 lists a commit's blobs and stops at the limit", %{repo: repo} do
    write!(repo, "a.ex", "a\n")
    write!(repo, "dir/b.ex", "b\n")
    sha = commit!(repo, "base")

    assert {:ok, %{files: files, truncated: false}} = Git.commit_files(repo, sha, 10)

    assert Enum.map(files, &{&1.path, &1.mode}) == [{"a.ex", 0o100644}, {"dir/b.ex", 0o100644}]
    assert hd(files).git_blob_id == git!(repo, ["rev-parse", "#{sha}:a.ex"])
    assert {:ok, %{files: [_], truncated: true}} = Git.commit_files(repo, sha, 1)
  end

  test "blob_ids/2 takes the working tree's blob for modified and untracked files", %{repo: repo} do
    write!(repo, "lib/a.ex", "a\n")
    write!(repo, "lib/b.ex", "b\n")
    write!(repo, "README.md", "readme\n")
    commit!(repo, "base")
    write!(repo, "lib/b.ex", "changed\n")
    write!(repo, "lib/c.ex", "new\n")

    assert {:ok, blobs} = Git.blob_ids(Path.join(repo, "lib"), &String.ends_with?(&1, ".ex"))

    assert Map.keys(blobs) |> Enum.sort() == ["lib/a.ex", "lib/b.ex", "lib/c.ex"]
    assert blobs["lib/a.ex"] == git!(repo, ["rev-parse", "HEAD:lib/a.ex"])
    assert blobs["lib/b.ex"] == git!(repo, ["hash-object", "lib/b.ex"])
    assert blobs["lib/c.ex"] == git!(repo, ["hash-object", "lib/c.ex"])
  end

  test "parse_raw_parents/1 reads parents off commit objects" do
    raw = """
    commit aaa
    tree ttt
    parent bbb
    parent ccc
    author A <a> 1 +0000

        parent not-a-header
    """

    assert Git.parse_raw_parents(raw) == %{"aaa" => ["bbb", "ccc"]}
  end
end
