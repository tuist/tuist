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

  defp empty_commits!(dir, count) do
    for index <- 1..count do
      git!(dir, ["commit", "--quiet", "--allow-empty", "-m", "commit #{index}"])
      git!(dir, ["rev-parse", "HEAD"])
    end
  end

  defp shallow_clone!(repo, branch) do
    clone = repo <> "-clone"
    on_exit(fn -> File.rm_rf!(clone) end)
    git!(repo, ["config", "uploadpack.allowFilter", "true"])

    git!(Path.dirname(repo), [
      "clone",
      "--quiet",
      "--depth=1",
      "--branch=#{branch}",
      "file://" <> repo,
      clone
    ])

    clone
  end

  # Answers which commits a server that has `known` lacks, and tells the test
  # what it was asked.
  defp server(known) do
    test_pid = self()

    fn shas ->
      send(test_pid, {:asked, shas})
      Enum.reject(shas, &(&1 in known))
    end
  end

  defp asked do
    receive do
      {:asked, shas} -> [shas | asked()]
    after
      0 -> []
    end
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

  describe "connected_history/5" do
    test "deepens a shallow clone until it reaches the commits the server has", %{repo: repo} do
      commits = empty_commits!(repo, 60)
      head = List.last(commits)
      clone = shallow_clone!(repo, "main")
      # The remote moves on after the checkout, as it does while a job runs.
      git!(repo, ["commit", "--quiet", "--allow-empty", "-m", "later"])

      assert {:ok, %{commits: [%{sha: ^head}]} = history} = Git.history(clone, head, nil)

      connected = Git.connected_history(clone, history, "main", server(Enum.take(commits, 5)))

      # The head's parent, then the parent of the commit the first 50 stop at.
      assert asked() == [[Enum.at(commits, 58)], [Enum.at(commits, 8)]]

      assert Enum.map(connected.commits, &{&1.sha, &1.parents}) ==
               commits
               |> Enum.zip([[] | Enum.map(commits, &[&1])])
               |> Enum.reverse()

      assert %{connected | commits: history.commits} == history
      assert git!(clone, ["rev-parse", "origin/main"]) == head
    end

    test "keeps the deepening steps within the window together", %{repo: repo} do
      commits = empty_commits!(repo, 70)
      head = List.last(commits)
      clone = shallow_clone!(repo, "main")
      limits = %{window_commits: 60}
      assert {:ok, history} = Git.history(clone, head, nil, limits)

      connected = Git.connected_history(clone, history, "main", limits, server([]))

      # 50 commits, then the 10 the window has left: the chain now ends at the
      # window rather than where the clone stops, so nothing more is asked.
      assert asked() == [[Enum.at(commits, 68)], [Enum.at(commits, 18)]]
      assert Enum.map(connected.commits, & &1.sha) == commits |> Enum.reverse() |> Enum.take(60)
      assert git!(clone, ["rev-list", "--count", "HEAD"]) == "61"
    end

    test "fetches nothing when the server has the parent", %{repo: repo} do
      [parent, head] = empty_commits!(repo, 2)
      clone = shallow_clone!(repo, "main")
      assert {:ok, history} = Git.history(clone, head, nil)

      assert Git.connected_history(clone, history, "main", server([parent])) == history
      assert asked() == [[parent]]
      assert git!(clone, ["rev-list", "--count", "HEAD"]) == "1"
    end

    test "asks nothing about a whole clone", %{repo: repo} do
      [_parent, head] = empty_commits!(repo, 2)
      assert {:ok, history} = Git.history(repo, head, nil)

      assert Git.connected_history(repo, history, "main", server([])) == history
      assert asked() == []
    end

    test "never fetches without history access or a branch", %{repo: repo} do
      [_parent, head] = empty_commits!(repo, 2)
      clone = shallow_clone!(repo, "main")
      assert {:ok, history} = Git.history(clone, head, nil)

      for {remote_access, branch} <- [base_head: "main", none: "main", history: nil] do
        limits = %{remote_access: remote_access}
        assert Git.connected_history(clone, history, branch, limits, server([])) == history
      end

      assert asked() == []
      assert git!(clone, ["rev-list", "--count", "HEAD"]) == "1"
    end

    test "asks once about the parent a pull request's merge commit and its base branch end at",
         %{repo: repo} do
      [below, base_head] = empty_commits!(repo, 2)
      git!(repo, ["checkout", "--quiet", "-b", "feature"])
      empty_commits!(repo, 1)
      git!(repo, ["checkout", "--quiet", "-b", "merge", "main"])
      git!(repo, ["merge", "--quiet", "--no-ff", "-m", "merge", "feature"])
      merge = git!(repo, ["rev-parse", "HEAD"])
      clone = shallow_clone!(repo, "merge")
      git!(clone, ["fetch", "--quiet", "--depth=1", "origin", "+main:refs/remotes/origin/main"])

      assert {:ok, %{base_head_sha: ^base_head} = history} =
               Git.history(clone, merge, "main", %{remote_access: :none})

      # Only first parents place a commit on its branch, and both chains end
      # at the same one.
      assert Git.connected_history(clone, history, "main", server([below])) == history
      assert asked() == [[below]]
    end

    test "keeps the collected history when the fetch fails", %{repo: repo} do
      [parent, head] = empty_commits!(repo, 2)
      clone = shallow_clone!(repo, "main")
      git!(clone, ["remote", "set-url", "origin", "file://" <> repo <> "-gone"])
      assert {:ok, history} = Git.history(clone, head, nil)

      assert Git.connected_history(clone, history, "main", server([])) == history
      assert asked() == [[parent]]
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
