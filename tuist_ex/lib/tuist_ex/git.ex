defmodule TuistEx.Git do
  @moduledoc false

  # Reads what coverage needs from a Git checkout: the commit graph within a
  # window, the merge base with the branch a commit merges into, a commit's file
  # listing, and the blob each source file has. A port of the Tuist command line tool's
  # `GitController+History.swift` and `GitHistoryParser.swift`; the two must
  # agree, since the server compares what both report.

  @default_limits %{
    window_days: 365,
    window_commits: 5000,
    deepen_budget_seconds: 60,
    remote_access: :history
  }

  # Git must never stop to ask for credentials, and signature checks would
  # interleave with the `log` output parsed below.
  @hardened_env [
    {"GIT_TERMINAL_PROMPT", "0"},
    {"GIT_ASKPASS", "/usr/bin/false"},
    {"GIT_CONFIG_COUNT", "1"},
    {"GIT_CONFIG_KEY_0", "log.showSignature"},
    {"GIT_CONFIG_VALUE_0", "false"}
  ]

  def default_limits, do: @default_limits

  @doc """
  Runs `git -C dir args` and returns `{:ok, stdout}` when it exits 0. Git's
  standard error is discarded: a failure is an answer here, such as a
  directory that is not a repository, not something to show the user.
  """
  def capture(dir, args, env \\ []) do
    case System.find_executable("git") do
      nil ->
        :error

      git ->
        case System.cmd("sh", ["-c", ~s(exec "$0" "$@" 2>/dev/null), git, "-C", dir | args],
               env: @hardened_env ++ env
             ) do
          {output, 0} -> {:ok, output}
          _ -> :error
        end
    end
  rescue
    _ -> :error
  end

  def toplevel(dir) do
    case capture(dir, ["rev-parse", "--show-toplevel"]) do
      {:ok, output} -> {:ok, String.trim(output)}
      :error -> :error
    end
  end

  def repository?(dir), do: capture(dir, ["rev-parse"]) != :error

  @doc """
  Whether the checkout has changes of any kind, untracked files included: the
  same test the command line tool applies.
  """
  def dirty?(dir) do
    case capture(dir, ["status", "--porcelain"]) do
      {:ok, output} -> String.trim(output) != ""
      :error -> false
    end
  end

  @doc """
  The blob each file of the checkout has, keyed by its path relative to the
  repository's root: the index's for unchanged files, and the working tree's
  for modified and untracked ones, so each id describes the contents a run
  compiled. `source?` picks the paths to include.
  """
  def blob_ids(dir, source?) do
    with {:ok, root} <- toplevel(dir),
         {:ok, staged} <- capture(root, ["ls-files", "--stage", "-z"]),
         {:ok, modified} <- capture(root, ["diff", "--name-only", "--diff-filter=d", "-z"]),
         {:ok, untracked} <- capture(root, ["ls-files", "--others", "--exclude-standard", "-z"]) do
      indexed =
        for entry <- String.split(staged, <<0>>, trim: true),
            [meta, path] <- [String.split(entry, "\t", parts: 2)],
            [mode, object | _] <- [String.split(meta, " ")],
            mode != "160000" and source?.(path),
            into: %{},
            do: {path, object}

      working_tree =
        (modified <> <<0>> <> untracked)
        |> String.split(<<0>>, trim: true)
        |> Enum.filter(source?)
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, Map.merge(indexed, hash_objects(root, working_tree))}
    end
  end

  # Batched so a large change set never exceeds the argument list limit.
  defp hash_objects(root, paths) do
    paths
    |> Enum.chunk_every(500)
    |> Enum.reduce(%{}, fn batch, acc ->
      case capture(root, ["hash-object", "--" | batch]) do
        {:ok, output} ->
          Map.merge(acc, Map.new(Enum.zip(batch, String.split(output, "\n", trim: true))))

        :error ->
          acc
      end
    end)
  end

  @doc """
  A commit's file listing, from its tree rather than the index, which is the
  checkout's and may not be the reported commit's.
  """
  def commit_files(_dir, _sha, limit) when limit <= 0, do: {:ok, %{files: [], truncated: true}}

  def commit_files(dir, sha, limit) do
    with {:ok, output} <- capture(dir, ["ls-tree", "-r", "-z", "--full-tree", sha]) do
      files = parse_commit_files(output)
      {:ok, %{files: Enum.take(files, limit), truncated: length(files) > limit}}
    end
  end

  @doc """
  The run's history: the object format, the merge base with `base_branch`,
  the base branch's commit, and the commits within the window reachable from
  the head and from that commit when the checkout has it. `fallback_reason`
  says what could not be collected. `remote_access` is what may be read from
  the remote, each call a round trip whatever it transfers: with `:history`,
  the base branch is fetched and a shallow clone deepened within the budget
  until the merge base is found; with `:base_head`, a checkout without the
  base branch gets its latest commit from one `git ls-remote`; with `:none`,
  only the checkout is read.
  """
  def history(dir, head, base_branch, limits \\ @default_limits) do
    limits = Map.merge(@default_limits, limits)

    with {:ok, head} <- resolve_head(dir, head) do
      object_format =
        case capture(dir, ["rev-parse", "--show-object-format"]) do
          {:ok, output} when output != "" -> String.trim(output)
          _ -> "sha1"
        end

      {merge_base, ref, reasons} =
        if base_branch,
          do: resolve_merge_base(dir, head, base_branch, limits),
          else: {nil, nil, ["no base branch is known"]}

      # Read after any deepening, which fetches the base branch again and can move it.
      local_base_head = if ref, do: commit_sha(dir, ref)

      base_head =
        cond do
          local_base_head ->
            local_base_head

          base_branch && limits.remote_access == :base_head ->
            remote_head(dir, base_branch, limits)

          true ->
            nil
        end

      {:ok,
       %{
         object_format: object_format,
         head_sha: head,
         base_branch: base_branch,
         merge_base_sha: merge_base,
         base_head_sha: base_head,
         commits: window_commits(dir, Enum.uniq([head | List.wrap(local_base_head)]), limits),
         fallback_reason: if(reasons != [], do: Enum.join(reasons, "; "))
       }}
    end
  end

  @doc """
  The history with the gap a shallow clone leaves below it closed. The server
  places a commit on its branch from the parents it has when the commit
  arrives, so a commit uploaded before its parent leaves the parent off the
  branch for good. `unknown` answers which of the given commits the server
  lacks, and is asked about the first parents the clone stops at on the
  first-parent chain of each head the run reports. While any is missing, the
  clone is deepened through `branch` and its commits listed again, with the
  steps and bounds of the merge base's deepening. Only with `:history` access
  and a branch to name.
  """
  def connected_history(dir, history, branch, limits \\ @default_limits, unknown) do
    limits = Map.merge(@default_limits, limits)

    if limits.remote_access == :history and branch do
      heads = Enum.uniq([history.head_sha | List.wrap(history.base_head_sha)])
      deadline = System.monotonic_time(:millisecond) + limits.deepen_budget_seconds * 1000

      state = %{
        commits: history.commits,
        parents: boundary_first_parents(dir, history.commits, heads),
        unreachable: MapSet.new(),
        depth: 0,
        step: 50
      }

      # The full ref, so a branch name is never read as a tag or as an option
      # of `git fetch`.
      ref = "refs/heads/#{branch}"
      %{history | commits: connect(dir, state, heads, ref, limits, unknown, deadline)}
    else
      history
    end
  end

  # Deepening is relative to every commit the clone stops at that a ref of the
  # remote still reaches, so naming one branch the remote has also deepens a
  # head that is not on it, a pull request's merge commit. The empty refmap
  # keeps the checkout's own `origin/<branch>` where the job's later steps
  # expect it.
  defp connect(dir, state, heads, ref, limits, unknown, deadline) do
    max_depth = max(limits.window_commits, 50)
    step = min(state.step, max_depth - state.depth)

    fetch =
      ["fetch", "--quiet", "--no-tags", "--refmap=", "--filter=blob:none", "--deepen=#{step}"] ++
        ["origin", ref]

    with true <- state.parents != [] and state.depth < max_depth,
         true <- System.monotonic_time(:millisecond) < deadline,
         false <- Enum.empty?(unknown.(state.parents)),
         {:succeeded, _} <- run_until(dir, fetch, deadline),
         [_ | _] = commits <- window_commits(dir, heads, limits) do
      # A parent the fetch left out of reach is not where the remote's branch
      # leads, as after a force-push: a deeper fetch would bring more of that
      # branch, never the parent.
      reached = boundary_first_parents(dir, commits, heads)

      still_missing = Enum.filter(reached, &(&1 in state.parents))
      unreachable = MapSet.union(state.unreachable, MapSet.new(still_missing))

      state = %{
        commits: commits,
        parents: Enum.reject(reached, &MapSet.member?(unreachable, &1)),
        unreachable: unreachable,
        depth: state.depth + step,
        step: step * 2
      }

      connect(dir, state, heads, ref, limits, unknown, deadline)
    else
      _ -> state.commits
    end
  end

  # The first parents the checkout lacks: where each head's first-parent chain
  # reaches a commit the shallow clone stops at. A chain that ends at a root,
  # or at the history window, has none. Only first parents count: they are
  # what places a commit on its branch.
  defp boundary_first_parents(dir, commits, heads) do
    boundary = shallow_boundary(dir)
    by_sha = Map.new(commits, &{&1.sha, &1})

    heads
    |> Enum.flat_map(&List.wrap(boundary_first_parent(by_sha[&1], by_sha, boundary)))
    |> Enum.uniq()
  end

  defp boundary_first_parent(%{sha: sha, parents: [parent | _]}, by_sha, boundary) do
    case by_sha do
      %{^parent => commit} -> boundary_first_parent(commit, by_sha, boundary)
      _ -> if MapSet.member?(boundary, sha), do: parent
    end
  end

  defp boundary_first_parent(_commit, _by_sha, _boundary), do: nil

  defp commit_sha(dir, ref) do
    case capture(dir, ["rev-parse", "--verify", "--quiet", "#{ref}^{commit}"]) do
      {:ok, output} -> if String.trim(output) != "", do: String.trim(output)
      :error -> nil
    end
  end

  defp resolve_head(_dir, head) when is_binary(head) and head != "", do: {:ok, head}

  defp resolve_head(dir, _head) do
    case capture(dir, ["rev-parse", "HEAD"]) do
      {:ok, output} -> {:ok, String.trim(output)}
      :error -> {:error, "the checkout has no commit"}
    end
  end

  # `git log` lists a shallow clone's boundary commits without parents, so
  # theirs are read from the commit objects, which the raw format prints
  # regardless of the shallow grafts. When they cannot be read, the boundary
  # commits are left out rather than stored as roots.
  defp window_commits(dir, heads, limits) do
    case capture(dir, [
           "log",
           "--format=%H %P %ct",
           "--max-count=#{limits.window_commits}",
           "--since=#{limits.window_days}.days.ago" | heads
         ]) do
      {:ok, output} -> output |> parse_commits() |> with_boundary_parents(dir)
      :error -> []
    end
  end

  # The commits a shallow clone's history stops at; none in a whole clone.
  defp shallow_boundary(dir) do
    with {:ok, path} <- capture(dir, ["rev-parse", "--git-path", "shallow"]),
         {:ok, contents} <- File.read(Path.expand(String.trim(path), dir)) do
      contents |> String.split("\n", trim: true) |> MapSet.new()
    else
      _ -> MapSet.new()
    end
  end

  defp with_boundary_parents(commits, dir) do
    boundary = shallow_boundary(dir)

    case Enum.filter(commits, &MapSet.member?(boundary, &1.sha)) do
      [] ->
        commits

      boundary_commits ->
        parents =
          case capture(dir, [
                 "log",
                 "--no-walk",
                 "--no-decorate",
                 "--format=raw" | Enum.map(boundary_commits, & &1.sha)
               ]) do
            {:ok, raw} -> parse_raw_parents(raw)
            :error -> %{}
          end

        Enum.flat_map(commits, fn commit ->
          cond do
            not MapSet.member?(boundary, commit.sha) -> [commit]
            Map.has_key?(parents, commit.sha) -> [%{commit | parents: parents[commit.sha]}]
            true -> []
          end
        end)
    end
  end

  # Only commits and trees place the merge base, and blobs are most of what a
  # fetch carries, hence `--filter=blob:none`. The base branch is named on
  # every fetch: without a refspec git fetches what the checkout's config
  # says, which for `actions/checkout` is every branch. Deepening steps add up
  # and stop at the window, and never continue past a fetch that failed.
  # Returns the merge base, the base branch's ref it was resolved against, and
  # why either is missing.
  defp resolve_merge_base(dir, head, base_branch, limits) do
    deadline = System.monotonic_time(:millisecond) + limits.deepen_budget_seconds * 1000
    shallow? = capture(dir, ["rev-parse", "--is-shallow-repository"]) == {:ok, "true\n"}
    refspec = "+#{base_branch}:refs/remotes/origin/#{base_branch}"

    {ref, fetch_problem} =
      case {base_ref(dir, base_branch), limits.remote_access} do
        {nil, :history} ->
          fetch =
            ["fetch", "--quiet", "--no-tags", "--filter=blob:none"] ++
              if(shallow?, do: ["--depth=1"], else: [])

          case run_until(dir, fetch ++ ["origin", refspec], deadline) do
            :timed_out -> {nil, :timed_out}
            _ -> {base_ref(dir, base_branch), nil}
          end

        {nil, _remote_access} ->
          {nil, :not_fetched}

        {ref, _remote_access} ->
          {ref, nil}
      end

    cond do
      fetch_problem == :not_fetched ->
        {nil, nil, ["the base branch #{base_branch} is not in the checkout"]}

      fetch_problem == :timed_out ->
        {nil, nil,
         [
           "the base branch #{base_branch} is not in the checkout and could not be fetched within #{limits.deepen_budget_seconds}s"
         ]}

      is_nil(ref) ->
        {nil, nil,
         ["the base branch #{base_branch} is not in the checkout and could not be fetched"]}

      sha = merge_base(dir, ref, head) ->
        {sha, ref, []}

      not shallow? ->
        {nil, ref,
         ["#{String.slice(head, 0, 12)} and #{base_branch} share no history in the checkout"]}

      limits.remote_access != :history ->
        {nil, ref, ["shallow clone: the merge base with #{base_branch} is not in the checkout"]}

      sha = deepen(dir, ref, head, refspec, deadline, max(limits.window_commits, 50), 0, 50) ->
        {sha, ref, []}

      true ->
        {nil, ref,
         [
           "shallow clone: the merge base with #{base_branch} was not found within #{limits.deepen_budget_seconds}s"
         ]}
    end
  end

  defp deepen(dir, ref, head, refspec, deadline, max_depth, depth, step) do
    step = min(step, max_depth - depth)

    if System.monotonic_time(:millisecond) < deadline and depth < max_depth and
         match?(
           {:succeeded, _},
           run_until(
             dir,
             [
               "fetch",
               "--quiet",
               "--no-tags",
               "--filter=blob:none",
               "--deepen=#{step}",
               "origin",
               refspec
             ],
             deadline
           )
         ) do
      merge_base(dir, ref, head) ||
        deepen(dir, ref, head, refspec, deadline, max_depth, depth + step, step * 2)
    end
  end

  defp base_ref(dir, base_branch) do
    Enum.find(["origin/#{base_branch}", base_branch], fn candidate ->
      capture(dir, ["rev-parse", "--verify", "--quiet", "#{candidate}^{commit}"]) != :error
    end)
  end

  defp merge_base(dir, ref, head) do
    case capture(dir, ["merge-base", ref, head]) do
      {:ok, output} -> if String.trim(output) != "", do: String.trim(output)
      :error -> nil
    end
  end

  # The branch's latest commit as the remote has it: one `git ls-remote`,
  # which transfers no objects, killed like a fetch when it outlasts the budget.
  defp remote_head(dir, branch, limits) do
    deadline = System.monotonic_time(:millisecond) + limits.deepen_budget_seconds * 1000
    ref = "refs/heads/#{branch}"

    case run_until(dir, ["ls-remote", "origin", ref], deadline) do
      {:succeeded, output} ->
        Enum.find_value(String.split(output, "\n"), fn line ->
          case String.split(line, "\t") do
            [sha, ^ref] -> sha
            _ -> nil
          end
        end)

      _ ->
        nil
    end
  end

  # Runs git until it exits or the deadline passes. A fetch still running at
  # the deadline is stopped, as a stalled remote would otherwise keep it alive:
  # with SIGTERM, on which git removes its lock files, and with SIGKILL only
  # when that does not end it. A deepening killed outright leaves
  # `shallow.lock` behind, which fails every later deepening of the checkout.
  defp run_until(dir, args, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    with true <- remaining > 0 || :timed_out,
         git when is_binary(git) <- System.find_executable("git") || :failed do
      port =
        Port.open({:spawn_executable, git}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: ["-C", dir | args],
          env: Enum.map(@hardened_env, fn {key, value} -> {~c"#{key}", ~c"#{value}"} end)
        ])

      os_pid = port |> Port.info(:os_pid) |> elem(1)
      await_port(port, os_pid, deadline, [])
    end
  end

  defp await_port(port, os_pid, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> await_port(port, os_pid, deadline, [output, data])
      {^port, {:exit_status, 0}} -> {:succeeded, IO.iodata_to_binary(output)}
      {^port, {:exit_status, _}} -> :failed
    after
      remaining ->
        System.cmd("kill", ["-TERM", to_string(os_pid)], stderr_to_stdout: true)

        receive do
          {^port, {:exit_status, _}} -> :ok
        after
          1000 ->
            System.cmd("kill", ["-KILL", to_string(os_pid)], stderr_to_stdout: true)
            Port.close(port)
        end

        :timed_out
    end
  end

  # Coverage-based test selection: a port of the command line tool's
  # `GitController+TestImpact.swift`, which must stay in step with it.

  @test_impact_deepen 100

  @doc "How many commits selection deepens a shallow clone by, at most once per run."
  def test_impact_deepen, do: @test_impact_deepen

  @doc """
  The checked-out commit and its parents, read from the commit object, since
  a depth-1 checkout grafts them away.
  """
  def checked_out_commit(dir) do
    with {:ok, head} <- capture(dir, ["rev-parse", "HEAD"]) do
      head = String.trim(head)

      parents =
        case capture(dir, ["log", "--no-walk", "--no-decorate", "--format=raw", head]) do
          {:ok, raw} -> Map.get(parse_raw_parents(raw), head, [])
          :error -> []
        end

      {:ok, %{sha: head, parent_shas: parents}}
    end
  end

  @doc "The checkout's ancestors, nearest first, at most `limit`."
  def ancestor_shas(_dir, limit) when limit <= 0, do: []

  def ancestor_shas(dir, limit) do
    case capture(dir, ["rev-list", "--topo-order", "--max-count=#{limit + 1}", "HEAD"]) do
      {:ok, output} -> output |> String.split("\n", trim: true) |> Enum.drop(1)
      :error -> []
    end
  end

  @doc """
  Deepens a shallow clone once by `test_impact_deepen/0` commits through
  `refs`. Returns `:deepened`, `:not_shallow`, `:not_allowed` (no refs, or
  remote access other than `:history`), `:failed` or `:timed_out`.
  """
  def deepen_once(dir, refs, limits \\ @default_limits) do
    shallow? = match?({:ok, "true" <> _}, capture(dir, ["rev-parse", "--is-shallow-repository"]))

    cond do
      not shallow? ->
        :not_shallow

      limits.remote_access != :history or refs == [] ->
        :not_allowed

      true ->
        deadline = System.monotonic_time(:millisecond) + limits.deepen_budget_seconds * 1000

        deepen =
          ~w(fetch --quiet --no-tags --filter=blob:none --deepen=#{@test_impact_deepen} origin)

        outcome = run_until(dir, deepen ++ refs, deadline)
        # A pull request ref exists only on GitHub, and one missing ref fails
        # the whole fetch, so the other refs are fetched without it.
        others = Enum.reject(refs, &String.starts_with?(&1, "refs/pull/"))

        outcome =
          if outcome == :failed and others != [] and length(others) < length(refs),
            do: run_until(dir, deepen ++ others, deadline),
            else: outcome

        case outcome do
          {:succeeded, _output} -> :deepened
          other -> other
        end
    end
  end

  @doc """
  The files that differ between `baseline` and the working tree, in path
  order, as `%{path, status, blob}` (`blob` nil for a deleted file), and
  whether the working tree had dirty or untracked files. When the baseline
  isn't in the checkout, a shallow clone is deepened once through `refs`;
  `{:history_unavailable, reason}` when that doesn't reach it. Only trees
  are read, never blobs.
  """
  def changed_files(dir, baseline, refs, limits \\ @default_limits) do
    with :ok <- reach(dir, baseline, refs, limits),
         raw = ~w(diff --raw -z --no-renames --no-abbrev --ignore-submodules=dirty),
         {:ok, committed} <- capture(dir, raw ++ [baseline, "HEAD"]),
         {:ok, working_tree} <- capture(dir, raw ++ ["HEAD"]),
         {:ok, untracked} <- capture(dir, ~w(ls-files --others --exclude-standard -z)) do
      committed = parse_raw_diff(committed)
      working_tree = parse_raw_diff(working_tree)
      untracked = String.split(untracked, <<0>>, trim: true)
      changes = working_tree_changes(committed, working_tree, untracked)
      hashed = hash_objects(dir, for(%{hash?: true, path: path} <- changes, do: path))

      {:ok,
       %{
         files: merge_changes(committed, changes, hashed),
         dirty?: working_tree != [] or untracked != []
       }}
    else
      :error -> {:error, :diff_failed}
      other -> other
    end
  end

  defp reach(dir, sha, refs, limits) do
    if commit?(dir, sha) do
      :ok
    else
      short = String.slice(sha, 0, 12)

      reason =
        case deepen_once(dir, refs, limits) do
          :not_shallow ->
            "the baseline #{short} is not in the checkout's history"

          :not_allowed ->
            "shallow clone: the baseline #{short} is not in the checkout"

          :failed ->
            "shallow clone: the baseline #{short} is not in the checkout and deepening failed"

          :timed_out ->
            "shallow clone: the baseline #{short} was not reached within #{limits.deepen_budget_seconds}s"

          :deepened ->
            if not commit?(dir, sha),
              do:
                "shallow clone: the baseline #{short} is more than #{@test_impact_deepen} commits beyond the checkout"
        end

      if reason, do: {:history_unavailable, reason}, else: :ok
    end
  end

  # A partial clone would otherwise fetch a missing commit on its own, and
  # then its trees one by one as the diff reads them, with no budget.
  defp commit?(dir, sha),
    do:
      capture(dir, ["cat-file", "-e", "#{sha}^{commit}"], [{"GIT_NO_LAZY_FETCH", "1"}]) != :error

  # A working-tree change is compared with the baseline's blob, so a file the
  # working tree reverts drops out. The baseline's blob is the committed
  # change's source, or HEAD's when the commits didn't change the file.
  defp working_tree_changes(committed, working_tree, untracked) do
    by_path = Map.new(committed, &{&1.path, &1})
    baseline_blob = fn path, head -> if c = by_path[path], do: c.src, else: head end

    Enum.map(working_tree, fn change ->
      %{
        path: change.path,
        baseline: baseline_blob.(change.path, change.src),
        blob: if(change.status != "D", do: change.dst),
        hash?: change.status != "D" and is_nil(change.dst),
        type_changed?: change.status == "T" or match?(%{status: "T"}, by_path[change.path])
      }
    end) ++
      Enum.map(untracked, fn path ->
        %{
          path: path,
          baseline: baseline_blob.(path, nil),
          blob: nil,
          hash?: true,
          type_changed?: false
        }
      end)
  end

  defp merge_changes(committed, changes, hashed) do
    files = Map.new(committed, &{&1.path, %{path: &1.path, status: &1.status, blob: &1.dst}})

    changes
    |> Enum.reduce(files, fn change, files ->
      blob = if change.hash?, do: Map.get(hashed, change.path), else: change.blob

      if blob == change.baseline do
        Map.delete(files, change.path)
      else
        status =
          cond do
            is_nil(change.baseline) -> "A"
            is_nil(blob) -> "D"
            change.type_changed? -> "T"
            true -> "M"
          end

        Map.put(files, change.path, %{path: change.path, status: status, blob: blob})
      end
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.path)
  end

  @doc """
  The entries of `git diff --raw -z --no-renames --no-abbrev`:
  `:<src mode> <dst mode> <src> <dst> <status>`, then the path, NUL-separated.
  An all-zero blob is none.
  """
  def parse_raw_diff(output), do: output |> String.split(<<0>>) |> raw_entries()

  defp raw_entries([":" <> _ = header, path | rest]) do
    case String.split(header, " ") do
      [_src_mode, _dst_mode, src, dst, status] ->
        [
          %{path: path, status: String.first(status), src: blob(src), dst: blob(dst)}
          | raw_entries(rest)
        ]

      _ ->
        raw_entries([path | rest])
    end
  end

  defp raw_entries([_field | rest]), do: raw_entries(rest)
  defp raw_entries([]), do: []

  defp blob(id), do: if(String.trim(id, "0") != "", do: id)

  @doc "`git log --format=%H %P %ct` lines: the SHA, the parent SHAs and the committer time."
  def parse_commits(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      fields = String.split(line, " ", trim: true)

      with [sha | rest] when rest != [] <- fields,
           {time, ""} <- Integer.parse(List.last(rest)) do
        [%{sha: sha, parents: Enum.drop(rest, -1), committed_at: DateTime.from_unix!(time)}]
      else
        _ -> []
      end
    end)
  end

  @doc """
  The parents of each commit in a `git log --format=raw` listing, as their
  commit objects store them.
  """
  def parse_raw_parents(output) do
    output
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn
      "commit " <> rest, {parents, _current} ->
        sha = rest |> String.split(" ") |> hd()
        {Map.put(parents, sha, []), sha}

      "parent " <> parent, {parents, current} when is_binary(current) ->
        {Map.update!(parents, current, &(&1 ++ [parent])), current}

      _line, acc ->
        acc
    end)
    |> elem(0)
  end

  @doc """
  The entries of `git ls-tree -r -z`: `<mode> <type> <object>\\t<path>`,
  NUL-separated. Only blobs count: a submodule's entry is a commit.
  """
  def parse_commit_files(output) do
    output
    |> String.split(<<0>>, trim: true)
    |> Enum.flat_map(fn entry ->
      with [meta, path] <- String.split(entry, "\t", parts: 2),
           [mode, "blob", object] <- String.split(meta, " ", trim: true),
           {mode, ""} <- Integer.parse(mode, 8) do
        [%{path: path, git_blob_id: object, mode: mode}]
      else
        _ -> []
      end
    end)
  end
end
