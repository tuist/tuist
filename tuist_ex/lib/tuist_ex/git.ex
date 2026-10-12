defmodule TuistEx.Git do
  @moduledoc false

  # Reads what coverage needs from a Git checkout: the commit graph within a
  # window, the merge base with the branch a commit merges into, the files and
  # line ranges that changed since, a commit's file listing, and the blob each
  # source file has. A port of the Tuist command line tool's
  # `GitController+History.swift` and `GitHistoryParser.swift`; the two must
  # agree, since the server compares what both report.

  @default_limits %{
    window_days: 365,
    window_commits: 5000,
    deepen_budget_seconds: 60,
    max_changed_files: 2000,
    max_hunks_per_file: 200
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
  def capture(dir, args) do
    case System.find_executable("git") do
      nil ->
        :error

      git ->
        case System.cmd("sh", ["-c", ~s(exec "$0" "$@" 2>/dev/null), git, "-C", dir | args],
               env: @hardened_env
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
  A commit's file listing, from its tree rather than the index: on a pull
  request's merge checkout the run reports the pull request's head, while the
  index is the merge commit's.
  """
  def commit_files(_dir, _sha, limit) when limit <= 0, do: {:ok, %{files: [], truncated: true}}

  def commit_files(dir, sha, limit) do
    with {:ok, output} <- capture(dir, ["ls-tree", "-r", "-z", "--full-tree", sha]) do
      files = parse_commit_files(output)
      {:ok, %{files: Enum.take(files, limit), truncated: length(files) > limit}}
    end
  end

  @doc """
  The run's history: the object format, the merge base with `base_branch`
  (fetching and deepening a shallow clone within the budget), the commits
  within the window, and the files changed since the merge base with their
  hunks. `fallback_reason` says what could not be collected.
  """
  def history(dir, head, base_branch, limits \\ @default_limits) do
    limits = Map.merge(@default_limits, limits)

    with {:ok, head} <- resolve_head(dir, head) do
      object_format =
        case capture(dir, ["rev-parse", "--show-object-format"]) do
          {:ok, output} when output != "" -> String.trim(output)
          _ -> "sha1"
        end

      {merge_base, reasons} =
        if base_branch,
          do: resolve_merge_base(dir, head, base_branch, limits),
          else: {nil, ["no base branch is known"]}

      {changed_files, reasons} = changed_files(dir, merge_base, head, limits, reasons)

      {:ok,
       %{
         object_format: object_format,
         head_sha: head,
         base_branch: base_branch,
         merge_base_sha: merge_base,
         commits: window_commits(dir, head, limits),
         changed_files: changed_files,
         fallback_reason: if(reasons != [], do: Enum.join(reasons, "; "))
       }}
    end
  end

  defp resolve_head(_dir, head) when is_binary(head) and head != "", do: {:ok, head}

  defp resolve_head(dir, _head) do
    case capture(dir, ["rev-parse", "HEAD"]) do
      {:ok, output} -> {:ok, String.trim(output)}
      :error -> {:error, "the checkout has no commit"}
    end
  end

  defp changed_files(_dir, nil, _head, _limits, reasons), do: {[], reasons}

  defp changed_files(dir, merge_base, head, limits, reasons) do
    # `--no-abbrev`: the raw format abbreviates blob ids by default, and patch
    # coverage matches them against the full ids the coverage rows carry. The
    # hunks are keyed by the `+++ b/<path>` headers, so they must not depend on
    # the user's config: prefixes and quoting.
    with {:ok, raw} <-
           capture(dir, ["diff", "--raw", "--no-abbrev", "-z", "-M", merge_base, head]),
         {:ok, unified} <-
           capture(dir, [
             "-c",
             "core.quotePath=false",
             "diff",
             "-U0",
             "-M",
             "--no-color",
             "--no-ext-diff",
             "--src-prefix=a/",
             "--dst-prefix=b/",
             merge_base,
             head
           ]) do
      {files, dropped} = parse_changed_files(raw, unified, limits)

      reasons =
        if dropped > 0,
          do:
            reasons ++
              [
                "#{dropped} changed files beyond the first #{limits.max_changed_files} were left out"
              ],
          else: reasons

      {files, reasons}
    else
      :error -> {[], reasons ++ ["the changes since the merge base could not be read"]}
    end
  end

  # `git log` lists a shallow clone's boundary commits without parents, so
  # theirs are read from the commit objects, which the raw format prints
  # regardless of the shallow grafts. When they cannot be read, the boundary
  # commits are left out rather than stored as roots.
  defp window_commits(dir, head, limits) do
    case capture(dir, [
           "log",
           "--format=%H %P %ct",
           "--max-count=#{limits.window_commits}",
           "--since=#{limits.window_days}.days.ago",
           head
         ]) do
      {:ok, output} -> output |> parse_commits() |> with_boundary_parents(dir)
      :error -> []
    end
  end

  defp with_boundary_parents(commits, dir) do
    boundary =
      with {:ok, path} <- capture(dir, ["rev-parse", "--git-path", "shallow"]),
           {:ok, contents} <- File.read(Path.expand(String.trim(path), dir)) do
        contents |> String.split("\n", trim: true) |> MapSet.new()
      else
        _ -> MapSet.new()
      end

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
  defp resolve_merge_base(dir, head, base_branch, limits) do
    deadline = System.monotonic_time(:millisecond) + limits.deepen_budget_seconds * 1000
    shallow? = capture(dir, ["rev-parse", "--is-shallow-repository"]) == {:ok, "true\n"}
    refspec = "+#{base_branch}:refs/remotes/origin/#{base_branch}"

    {ref, timed_out?} =
      case base_ref(dir, base_branch) do
        nil ->
          fetch =
            ["fetch", "--quiet", "--no-tags", "--filter=blob:none"] ++
              if(shallow?, do: ["--depth=1"], else: [])

          case run_until(dir, fetch ++ ["origin", refspec], deadline) do
            :timed_out -> {nil, true}
            _ -> {base_ref(dir, base_branch), false}
          end

        ref ->
          {ref, false}
      end

    cond do
      timed_out? ->
        {nil,
         [
           "the base branch #{base_branch} is not in the checkout and could not be fetched within #{limits.deepen_budget_seconds}s"
         ]}

      is_nil(ref) ->
        {nil, ["the base branch #{base_branch} is not in the checkout and could not be fetched"]}

      sha = merge_base(dir, ref, head) ->
        {sha, []}

      not shallow? ->
        {nil,
         ["#{String.slice(head, 0, 12)} and #{base_branch} share no history in the checkout"]}

      sha = deepen(dir, ref, head, refspec, deadline, max(limits.window_commits, 50), 0, 50) ->
        {sha, []}

      true ->
        {nil,
         [
           "shallow clone: the merge base with #{base_branch} was not found within #{limits.deepen_budget_seconds}s"
         ]}
    end
  end

  defp deepen(dir, ref, head, refspec, deadline, max_depth, depth, step) do
    step = min(step, max_depth - depth)

    if System.monotonic_time(:millisecond) < deadline and depth < max_depth and
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
         ) == :succeeded do
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

  # Runs git until it exits or the deadline passes. A fetch still running at
  # the deadline is killed, as a stalled remote would otherwise keep it alive.
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
      await_port(port, os_pid, deadline)
    end
  end

  defp await_port(port, os_pid, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, _}} -> await_port(port, os_pid, deadline)
      {^port, {:exit_status, 0}} -> :succeeded
      {^port, {:exit_status, _}} -> :failed
    after
      remaining ->
        System.cmd("kill", ["-KILL", to_string(os_pid)], stderr_to_stdout: true)
        Port.close(port)
        :timed_out
    end
  end

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
  The files of a `git diff --raw -z -M` listing joined with the hunks of the
  matching `git diff -U0`. Returns the files kept and how many were dropped
  past the limit.
  """
  def parse_changed_files(raw, unified, limits) do
    hunks = parse_hunks(unified)

    raw
    |> String.split(<<0>>)
    |> raw_entries([])
    |> Enum.reduce({[], 0}, fn {fields, paths}, {files, dropped} ->
      if length(files) >= limits.max_changed_files do
        {files, dropped + 1}
      else
        {[changed_file(fields, paths, hunks, limits) | files], dropped}
      end
    end)
    |> then(fn {files, dropped} -> {Enum.reverse(files), dropped} end)
  end

  # `:<old mode> <new mode> <old blob> <new blob> <status>` then one path, or
  # two for a rename or copy.
  defp raw_entries([":" <> header | rest], acc) do
    fields = String.split(header, " ", trim: true)
    two_paths? = match?([_, _, _, _, <<status, _::binary>>] when status in [?R, ?C], fields)

    case {two_paths?, rest} do
      {true, [previous, path | rest]} -> raw_entries(rest, [{fields, {previous, path}} | acc])
      {false, [path | rest]} -> raw_entries(rest, [{fields, {nil, path}} | acc])
      _ -> Enum.reverse(acc)
    end
  end

  defp raw_entries([_ | rest], acc), do: raw_entries(rest, acc)
  defp raw_entries([], acc), do: Enum.reverse(acc)

  defp changed_file([_, _, _, blob, status | _], {previous, path}, hunks, limits) do
    status =
      case status do
        "A" <> _ -> "added"
        "D" <> _ -> "deleted"
        "R" <> _ -> "renamed"
        _ -> "modified"
      end

    file_hunks = Map.get(hunks, path, [])

    %{
      path: path,
      previous_path: previous,
      status: status,
      git_blob_id: if(!(status == "deleted" or String.trim(blob, "0") == ""), do: blob),
      hunks: Enum.take(file_hunks, limits.max_hunks_per_file),
      truncated: length(file_hunks) > limits.max_hunks_per_file
    }
  end

  @doc """
  The head-side line ranges of each file's hunks in a unified diff: `+++
  b/<path>` names the file, `@@ -a,b +c,d @@` covers lines c..c+d-1; a hunk
  with d = 0 only removed lines. A `+++ ` line only names the file right after
  the `--- ` line of a `diff --git` header: in a hunk it is an added line.
  """
  def parse_hunks(unified) do
    unified
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({%{}, nil, false, false}, fn line, {hunks, path, header?, old_name?} ->
      cond do
        String.starts_with?(line, "diff --git ") ->
          {hunks, nil, true, false}

        header? and String.starts_with?(line, "--- ") ->
          {hunks, path, header?, true}

        header? and old_name? and String.starts_with?(line, "+++ ") ->
          {hunks, header_path(binary_part(line, 4, byte_size(line) - 4)), false, false}

        path && String.starts_with?(line, "@@ ") ->
          {add_hunk(hunks, path, line), path, header?, old_name?}

        true ->
          {hunks, path, header?, old_name?}
      end
    end)
    |> elem(0)
    |> Map.new(fn {path, ranges} -> {path, Enum.reverse(ranges)} end)
  end

  defp add_hunk(hunks, path, line) do
    case Regex.run(~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/, line) do
      [_, start] ->
        prepend_hunk(hunks, path, String.to_integer(start), 1)

      [_, start, count] ->
        prepend_hunk(hunks, path, String.to_integer(start), String.to_integer(count))

      nil ->
        hunks
    end
  end

  defp prepend_hunk(hunks, _path, _start, 0), do: hunks

  defp prepend_hunk(hunks, path, start, count),
    do:
      Map.update(
        hunks,
        path,
        [%{start: start, end: start + count - 1}],
        &[%{start: start, end: start + count - 1} | &1]
      )

  # Git ends the name with a tab when it has a space, and quotes it, C-style,
  # when it has a character `core.quotePath=false` still escapes.
  defp header_path(name) do
    name = String.trim_trailing(name, "\t")

    path =
      if String.starts_with?(name, "\"") and String.ends_with?(name, "\"") and
           byte_size(name) >= 2,
         do: name |> binary_part(1, byte_size(name) - 2) |> unquote_c(),
         else: name

    cond do
      name == "/dev/null" -> nil
      String.starts_with?(path, "b/") -> binary_part(path, 2, byte_size(path) - 2)
      true -> path
    end
  end

  @escapes %{?a => 7, ?b => 8, ?t => 9, ?n => 10, ?v => 11, ?f => 12, ?r => 13}

  defp unquote_c(quoted), do: unquote_c(quoted, <<>>)

  defp unquote_c(<<?\\, a, b, c, rest::binary>>, acc)
       when a in ?0..?7 and b in ?0..?7 and c in ?0..?7,
       do: unquote_c(rest, <<acc::binary, (a - ?0) * 64 + (b - ?0) * 8 + (c - ?0)>>)

  defp unquote_c(<<?\\, next, rest::binary>>, acc),
    do: unquote_c(rest, <<acc::binary, Map.get(@escapes, next, next)>>)

  defp unquote_c(<<byte, rest::binary>>, acc), do: unquote_c(rest, <<acc::binary, byte>>)
  defp unquote_c(<<>>, acc), do: acc

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
