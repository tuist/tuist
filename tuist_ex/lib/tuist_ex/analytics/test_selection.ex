defmodule TuistEx.Analytics.TestSelection do
  @moduledoc false

  # Coverage-based test selection for `mix tuist.test`: asks the server which
  # tests a change can't affect, from the per-test evidence earlier runs
  # recorded (`Analytics.Evidence`), and leaves them out of the run. A port
  # of the command line tool's `TestImpactSelector`, against the same
  # endpoints (`…/tests/selective-testing/coverage/baseline` and `…/runs`).
  #
  # The project opts in with `tuist: [selective_testing: [strategy:
  # :coverage]]`; a run selects only with `--cover`, which keeps the
  # evidence fresh, and never with `--no-selective-testing`. Its
  # `tracked_files` adds files a change to which runs every test
  # (`tracked_files/3`).
  #
  # Mix has no module hashing, so every test module of the suite is in
  # scope, none skipped, and the server decides every test. The unit is the
  # ExUnit test module, as runs report it.
  #
  # Nothing here ever fails a run: anything that goes wrong runs every test,
  # with a warning, as a run the server didn't let select does without one.

  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.Isolated
  alias TuistEx.Analytics.Report
  alias TuistEx.Analytics.Shards
  alias TuistEx.Git

  @ancestor_limit 200
  @changed_files_limit 5_000
  @baseline_timeout 5_000
  @runs_timeout 30_000
  @falsy ["0", "false", "FALSE", "no", "NO"]

  @doc "Whether the project opts into the coverage strategy."
  def configured?(config \\ Mix.Project.config()) do
    get_in(config, [:tuist, :selective_testing, :strategy]) == :coverage
  end

  @doc """
  Decides which tests of the project run. `index` is `index/1`'s. Returns
  `{:selected, %{run_id, counts, skipped_tests}}`, `{:fallback, %{run_id,
  reason, matched_path}}`, `:not_enabled`, or `{:failed, reason}`. Options:
  `:url`, `:project`, `:scheme`, `:request` (stands in for
  `HTTP.project_request/4`), `:environment`, `:dir` (the project's
  directory, in the checkout) and `:config` (the project's).
  """
  def decide(index, options) do
    environment = Keyword.get(options, :environment, &System.get_env/1)
    dir = Keyword.get(options, :dir, File.cwd!())

    options =
      Keyword.merge(options,
        dir: dir,
        config: Keyword.get(options, :config, Mix.Project.config())
      )

    with {:ok, root} <- Git.toplevel(dir) |> or_failed("the directory is not a Git repository"),
         {:ok, checkout} <-
           Git.checked_out_commit(root) |> or_failed("the checkout could not be read") do
      do_decide(
        index,
        Path.expand(root),
        checkout,
        Keyword.put(options, :environment, environment)
      )
    end
  end

  defp or_failed(:error, reason), do: {:failed, reason}
  defp or_failed(ok, _reason), do: ok

  defp do_decide(index, root, checkout, options) do
    environment = options[:environment]
    limits = limits(environment)
    refs = deepening_refs(environment)
    context = context(options)

    {baseline, ancestors, refs} =
      case resolve_baseline(checkout, [], context, options) do
        {:unavailable, "history_unknown"} ->
          Git.deepen_once(root, refs, limits)
          ancestors = Git.ancestor_shas(root, @ancestor_limit)
          {resolve_baseline(checkout, ancestors, context, options), ancestors, []}

        baseline ->
          {baseline, [], refs}
      end

    basis =
      case baseline do
        {:baseline, sha, diff_cached?} ->
          diff_basis(
            root,
            sha,
            diff_cached?,
            refs,
            limits,
            owner(root, index, options[:config], options[:dir])
          )

        other ->
          other
      end

    case basis do
      :not_enabled ->
        :not_enabled

      {:failed, reason} ->
        {:failed, reason}

      basis ->
        body =
          %{
            build_system: "mix",
            head_sha: Env.git_commit_sha(environment) || checkout.sha,
            parent_shas: checkout.parent_shas,
            ancestor_shas: ancestors,
            modules: index |> modules() |> Enum.map(&%{name: &1, skipped: false}),
            git_branch: Env.git_branch(environment),
            tracked_files: tracked_files(root, options[:config], options[:dir]),
            mix: context
          }
          |> then(fn body ->
            if body.head_sha == checkout.sha,
              do: body,
              else: Map.put(body, :commit_sha, checkout.sha)
          end)
          |> Map.merge(basis_fields(basis))
          |> Map.reject(fn {_key, value} -> value in [nil, []] end)

        create_run(body, options)
    end
  end

  defp context(options) do
    %{
      scheme: options[:scheme],
      app: options[:config][:app] && to_string(options[:config][:app])
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp resolve_baseline(checkout, ancestors, context, options) do
    body =
      %{
        build_system: "mix",
        commit_sha: checkout.sha,
        parent_shas: checkout.parent_shas,
        ancestor_shas: ancestors,
        mix: context
      }
      |> Map.reject(fn {_key, value} -> value == [] end)

    case request(
           :post,
           "/tests/selective-testing/coverage/baseline",
           body,
           options,
           @baseline_timeout
         ) do
      {:ok, %{"baseline_sha" => sha} = response} when is_binary(sha) ->
        {:baseline, sha, response["diff_cached"] == true}

      {:ok, %{"reason" => "not_enabled"}} ->
        :not_enabled

      {:ok, %{"reason" => reason}} when is_binary(reason) ->
        {:unavailable, reason}

      {:ok, other} ->
        {:failed, {:unexpected_response, other}}

      {:error, reason} ->
        {:failed, reason}
    end
  end

  # A dirty checkout's diff is its own, so the server never has it. Untracked
  # files don't make it dirty, as they don't make a coverage run dirty.
  defp diff_basis(root, sha, diff_cached?, refs, limits, owner) do
    dirty? = Git.dirty?(root)

    if diff_cached? and not dirty? do
      {:baseline, sha, nil, false}
    else
      case Git.changed_files(root, sha, refs, limits) do
        {:ok, %{files: files, dirty?: dirty?}} ->
          files =
            Enum.map(files, fn file ->
              %{
                path: file.path,
                status: file.status,
                blob: file.blob,
                affected_modules: owner.(file.path),
                dirty: if(file.dirty, do: true)
              }
              |> Map.reject(fn {_key, value} -> is_nil(value) end)
            end)

          {:baseline, sha, files, dirty?}

        {:history_unavailable, reason} ->
          Report.debug(
            "tuist analytics: coverage-based test selection has no history to diff: " <> reason
          )

          {:unavailable, "history_unavailable"}

        {:error, reason} ->
          Report.debug(
            "tuist analytics: coverage-based test selection could not diff: #{inspect(reason)}"
          )

          {:unavailable, "history_unavailable"}
      end
    end
  end

  defp basis_fields({:unavailable, reason}), do: %{fallback_reason: reason}
  defp basis_fields({:baseline, sha, nil, dirty?}), do: %{baseline_sha: sha, dirty: dirty?}

  defp basis_fields({:baseline, sha, files, dirty?}) do
    %{
      baseline_sha: sha,
      dirty: dirty?,
      changed_files: files |> Enum.sort_by(& &1.path) |> Enum.take(@changed_files_limit),
      changed_files_count: length(files)
    }
  end

  defp create_run(body, options) do
    case request(:post, "/tests/selective-testing/coverage/runs", body, options, @runs_timeout) do
      {:ok, %{"id" => id, "outcome" => "selected"} = run} when is_binary(id) ->
        {:selected,
         %{
           run_id: id,
           counts: run["counts"] || %{},
           skipped_tests:
             for(
               %{"module" => module} = entry <- run["skipped_tests"] || [],
               do: entry(module, entry)
             )
         }}

      # An outcome this client doesn't know runs everything, as a fallback.
      {:ok, %{"id" => id} = run} when is_binary(id) ->
        {:fallback, %{run_id: id, reason: run["reason"], matched_path: run["matched_path"]}}

      {:ok, other} ->
        {:failed, {:unexpected_response, other}}

      {:error, reason} ->
        {:failed, reason}
    end
  end

  defp entry(module, entry),
    do: %{module: module, suite: entry["suite"] || "", name: entry["name"]}

  defp request(method, suffix, body, options, timeout) do
    request = Keyword.get(options, :request, &HTTP.project_request/4)

    Isolated.run(
      fn -> request.(method, suffix, body, Keyword.take(options, [:url, :project])) end,
      timeout
    )
  end

  # What deepening may read from the remote: the history coverage needs,
  # unless `TUIST_GIT_UNSHALLOW_ENABLED=false` keeps runs to the checkout.
  defp limits(environment) do
    access = if environment.("TUIST_GIT_UNSHALLOW_ENABLED") in @falsy, do: :none, else: :history
    Map.put(Git.default_limits(), :remote_access, access)
  end

  # The remote refs whose history leads from the checkout to a baseline.
  defp deepening_refs(environment) do
    ref = Env.git_ref(environment)
    pull = if is_binary(ref) and String.starts_with?(ref, "refs/pull/"), do: ref

    Enum.reject([pull, Env.base_branch(environment) || Env.git_branch(environment)], &is_nil/1)
  end

  @doc """
  Each changed file's `affected_modules`, by its path in the repository at
  `root`: the test modules a test file defines, none for any other file.
  The server never skips whole a module that gained a file, so a new test
  in an existing module runs; any other file selects through the evidence,
  or through a tracked pattern (`tracked_files/3`).
  """
  def owner(root, index, _config, project_dir) do
    test_files =
      Map.new(index.files, fn {file, modules} ->
        {relative(Path.expand(file, project_dir), root), Enum.map(modules, & &1.module)}
      end)

    &Map.get(test_files, &1, [])
  end

  @doc """
  The tracked-file patterns the runs request sends, repository-relative: the
  project's `tuist: [selective_testing: [tracked_files: [...]]]`, written
  relative to the project's directory (a `!` pattern excludes, Tuist's
  defaults included), and the code and `priv` of the path dependencies
  inside the repository, umbrella siblings included, which aren't compiled
  with counters, so no evidence names them.
  """
  def tracked_files(root, config, project_dir) do
    prefix = relative(Path.expand(project_dir), root)

    configured =
      for pattern <- get_in(config, [:tuist, :selective_testing, :tracked_files]) || [],
          is_binary(pattern),
          pattern = String.trim(pattern),
          pattern not in ["", "!"] do
        case pattern do
          "!" <> glob -> "!" <> in_project(prefix, glob)
          glob -> in_project(prefix, glob)
        end
      end

    dependencies =
      for dir <- path_dependencies(root), sub <- ["lib", "priv"], do: Path.join([dir, sub, "**"])

    Enum.uniq(dependencies ++ configured)
  end

  defp in_project(prefix, glob) when prefix in [nil, ""], do: String.trim_leading(glob, "/")
  defp in_project(prefix, glob), do: Path.join(prefix, String.trim_leading(glob, "/"))

  defp path_dependencies(root) do
    deps_dir = Path.expand(Mix.Project.deps_path())

    for {_app, path} <- Mix.Project.deps_paths(),
        path = Path.expand(path),
        not within?(path, deps_dir),
        relative = relative(path, root),
        relative != nil,
        do: relative
  rescue
    _ -> []
  end

  defp relative(path, root) do
    cond do
      path == root -> ""
      String.starts_with?(path, root <> "/") -> Path.relative_to(path, root)
      true -> nil
    end
  end

  defp within?(_path, ""), do: true
  defp within?(path, dir), do: path == dir or String.starts_with?(path, dir <> "/")

  @doc """
  The project's test modules, read from the test files without loading
  them: `%{files: %{file => [%{module: name}]}}`. A file that can't be
  parsed holds no modules.
  """
  def index(files) do
    %{files: Map.new(files, &{&1, file_modules(&1)})}
  end

  @doc "The test files under the project's test paths."
  def test_files(config \\ Mix.Project.config()) do
    for path <- config[:test_paths] || ["test"],
        file <- Path.wildcard(Path.join(path, "**/*_test.exs")),
        do: file
  end

  @doc "Every test module the index holds."
  def modules(index) do
    index.files
    |> Map.values()
    |> Enum.concat()
    |> Enum.map(& &1.module)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp file_modules(file) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source) do
      {_ast, modules} =
        Macro.prewalk(ast, [], fn
          {:defmodule, _meta, [{:__aliases__, _, parts}, [do: _body]]}, acc when is_list(parts) ->
            if Enum.all?(parts, &is_atom/1),
              do: {nil, [%{module: Enum.join(parts, ".")} | acc]},
              else: {nil, acc}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(modules)
    else
      _ -> []
    end
  end

  @doc "The test modules a skip list leaves nothing of."
  def unselected_modules(skipped_tests) do
    for %{module: module, name: nil, suite: ""} <- skipped_tests, into: MapSet.new(), do: module
  end

  @doc """
  The shard units (`Shards.scan/1`'s, each unit to its file) a skip list
  leaves something of. A file is planned under one of its modules, so it
  goes only when the list leaves nothing of any module it defines.
  """
  def selected_units(units, index, skipped_tests) do
    unselected = unselected_modules(skipped_tests)

    for {unit, file} <- units,
        modules = Enum.map(Map.get(index.files, file, []), & &1.module),
        modules == [] or not Enum.all?(modules, &MapSet.member?(unselected, &1)),
        do: unit
  end

  @doc "Prints what selection decided, as the command line tool does."
  def report(outcome, shell \\ Mix.shell()) do
    case outcome do
      {:selected, %{counts: counts, skipped_tests: skipped}} ->
        modules = skipped |> unselected_modules() |> Enum.sort()

        shell.info(
          "Tuist: coverage-based test selection: #{counts["selected"] || 0} of #{counts["requested"] || 0} tests selected, " <>
            "#{counts["skipped"] || 0} skipped" <>
            if(modules == [],
              do: "",
              else:
                "\n  Nothing selected in #{Shards.count(length(modules), "module")}: #{Enum.join(modules, ", ")}"
            )
        )

      {:fallback, %{reason: reason, matched_path: path}} ->
        shell.info(
          "Tuist: coverage-based test selection not applied: #{reason || "unknown"}" <>
            if(path, do: " (#{path})", else: "") <> ", so every test runs."
        )

      :not_enabled ->
        :ok

      # Without a project or credentials there is nothing to ask, as for
      # quarantine: a plain `mix test` alias never warns locally.
      {:failed, reason} when is_binary(reason) ->
        Report.debug("tuist analytics: coverage-based test selection not applied: " <> reason)

      {:failed, reason} ->
        shell.info(
          "warning: Tuist coverage-based test selection is unavailable (#{inspect(reason)}), so every test runs."
        )
    end

    :ok
  end
end
