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
    test "reads the merge base, the changed files with their hunks and the commits", %{repo: repo} do
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

      by_path = Map.new(history.changed_files, &{&1.path, &1})

      assert %{
               status: "modified",
               hunks: [%{start: 2, end: 2}, %{start: 4, end: 4}],
               truncated: false
             } =
               by_path["lib/a.ex"]

      assert by_path["lib/a.ex"].git_blob_id == git!(repo, ["rev-parse", "#{head}:lib/a.ex"])
      assert %{status: "added", hunks: [%{start: 1, end: 1}]} = by_path["lib/new file.ex"]
      assert %{status: "deleted", git_blob_id: nil, hunks: []} = by_path["lib/gone.ex"]
    end

    test "reports a rename with its previous path", %{repo: repo} do
      write!(repo, "lib/old.ex", Enum.map_join(1..20, "\n", &"line #{&1}") <> "\n")
      commit!(repo, "base")
      git!(repo, ["checkout", "--quiet", "-b", "feature"])
      git!(repo, ["mv", "lib/old.ex", "lib/new.ex"])
      head = commit!(repo, "rename")

      assert {:ok, %{changed_files: [file]}} = Git.history(repo, head, "main")
      assert %{path: "lib/new.ex", previous_path: "lib/old.ex", status: "renamed"} = file
    end

    test "says why there is no merge base", %{repo: repo} do
      write!(repo, "a.ex", "a\n")
      head = commit!(repo, "only")

      assert {:ok,
              %{
                merge_base_sha: nil,
                changed_files: [],
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

    test "limits the changed files and says how many were left out", %{repo: repo} do
      write!(repo, "seed.ex", "seed\n")
      commit!(repo, "base")
      git!(repo, ["checkout", "--quiet", "-b", "feature"])
      for index <- 1..3, do: write!(repo, "file#{index}.ex", "x\n")
      head = commit!(repo, "three files")

      assert {:ok, %{changed_files: files, fallback_reason: reason}} =
               Git.history(repo, head, "main", %{max_changed_files: 2})

      assert length(files) == 2
      assert reason == "1 changed files beyond the first 2 were left out"
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

  describe "parse_hunks/1" do
    test "ignores added lines that look like file headers and unquotes quoted names" do
      unified = """
      diff --git "a/caf\\303\\251.ex" "b/caf\\303\\251.ex"
      --- "a/caf\\303\\251.ex"
      +++ "b/caf\\303\\251.ex"
      @@ -1 +1,2 @@
      -x
      +++ not a header
      +y
      """

      assert Git.parse_hunks(unified) == %{"café.ex" => [%{start: 1, end: 2}]}
    end

    test "skips hunks that only removed lines" do
      unified = """
      diff --git a/a.ex b/a.ex
      --- a/a.ex
      +++ b/a.ex
      @@ -3,2 +2,0 @@
      """

      assert Git.parse_hunks(unified) == %{}
    end
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
