# Code coverage seed data for the `tuist/tuist` project.
#
# Coverage is a property of a commit: a run measures one scheme of it and the
# commit's figure is the union of its runs, so the pages need the whole chain:
# the repository's commit graph, each commit's file listing, runs carrying
# coverage and per-test evidence, the tests each run could have run, and the
# per-commit totals every coverage surface reads.
#
# Everything is derived from one model of the repository, so the numbers
# agree wherever they are read:
#
#   - a file has versions; a version is a list of functions laid out as xccov
#     reports them (a function's executable lines are contiguous from its
#     first line, a closure's inside its function's) and its blob id;
#   - a test executes fixed lines of the functions it exercises, a number of
#     times; a run's line counts are the hits of the tests it ran, and a
#     function's executions are the hits on its first line;
#   - a commit changes files (a function is added) and tests (a test is
#     added for an untested function), so coverage and executable lines move.
#
# The figures themselves (commit totals, reused coverage, trends) are
# computed by the application from the stored runs, and checked against the
# model at the end, so a seed that drifts from the rules fails loudly.
#
# Over the last 90 days (the Code Coverage page defaults to 30):
#   - `main`, a commit a week and then a day, measured by the `App` and `Core`
#     schemes, `DesignSystem` for the last month and `AppIntegration` for the
#     last two weeks, with commits no run measured, one measured by a single
#     scheme and never signalled (off the trend), a run from a dirty checkout
#     (ignored), two merged pull requests, and selective runs whose skipped
#     tests' coverage is reused;
#   - twenty feature branches, two of them without history (listed in the
#     order they were measured), so the branch list pages;
#   - four open pull requests: one whose head reuses its skipped tests'
#     coverage (Reused), one that cannot for a test that failed last time
#     (Unknown), one pending and one complete;
#   - about twenty product targets and sixty files, one with thirty
#     functions, so every list pages; a generated file excluded from every
#     figure, and sources no scheme compiles.
#
# Runnable on its own after the main seed: `mix run priv/repo/coverage_seeds.exs`.

import Ecto.Query

alias Tuist.GitHistory
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Repo
alias Tuist.Tests
alias Tuist.Tests.Coverage.Commits

defmodule CoverageSeed do
  @moduledoc false

  @features ~w(Onboarding Projects ProjectDetail Settings Profile Search Notifications Billing Inbox Previews Builds TestInsights Cache Bundles)
  @core ~w(Networking Persistence Auth Logging Utilities Localization)

  @core_files %{
    "Networking" => ~w(APIClient Endpoint RequestBuilder ResponseCache RetryPolicy),
    "Persistence" => ~w(Database Migrations),
    "Auth" => ~w(TokenStore Session),
    "Logging" => ~w(Logger LogFormatter),
    "Utilities" => ~w(DateFormatting Debouncer),
    "Localization" => ~w(LocaleResolver PluralRules)
  }

  @api_client ~w|init(session:) send(_:) data(for:) upload(_:to:) download(_:) decode(_:from:) validate(_:)
    retry(_:after:) authorize(_:) refreshToken() cancel(_:) cancelAll() headers(for:) query(for:) url(for:)
    body(for:) log(_:) record(_:) metrics() reset() invalidate() prepare(_:) finish(_:) handle(_:)
    status(of:) timeout(for:) redirect(_:) backoff(_:)|

  @pools [
    {"ViewModel", ~w|init(service:) load() refresh() select(_:) handle(_:) retry() dismiss()|},
    {"View", ~w|body header content(for:) emptyState toolbarItems errorBanner(_:) footer|},
    {"Store", ~w|init(defaults:) value(for:) set(_:for:) reset() migrate(from:) observe(_:)|},
    {"Cache", ~w|init(capacity:) value(for:) insert(_:for:) evict() clear() size()|},
    {"Policy", ~w|init(maxAttempts:) delay(for:) shouldRetry(_:) jitter(_:) reset()|},
    {"Builder", ~w|init(baseURL:) build(_:) headers(_:) query(_:) body(_:)|}
  ]

  @generic ~w|init() configure() update(_:) describe() validate() reset() apply(_:) resolve(_:)|

  # A tracked file is one whose change could change any test's result; they
  # stay the same, so reused coverage is never invalidated by them.
  def tracked_files, do: [{"Package.resolved", "resolved-0"}, {"Tests/Fixtures/project.json", "fixture-0"}]

  def unmeasured_paths,
    do: [
      "Sources/App/Legacy/UIKitBridge.swift",
      "Sources/Networking/Deprecated/LegacyClient.swift",
      "Sources/Generated/Strings.swift"
    ]

  def generated, do: {"Sources/Generated/Assets.swift", "App"}

  def h(term, n), do: rem(:erlang.phash2(term), n)

  def product_files do
    Process.get(:coverage_seed_products) ||
      then(
        [
          {"Sources/App/AppDelegate.swift", "App"},
          {"Sources/App/RootView.swift", "App"},
          {"Sources/App/Router.swift", "App"}
        ] ++
          for(f <- ~w(Button Card Theme), do: {"Sources/DesignSystem/#{f}.swift", "DesignSystem"}) ++
          for(
            feature <- @features,
            suffix <- if(h({:store, feature}, 3) == 0, do: ~w(View ViewModel Store), else: ~w(View ViewModel)),
            do: {"Sources/Features/#{feature}/#{feature}#{suffix}.swift", feature}
          ) ++
          for(target <- @core, file <- Map.fetch!(@core_files, target), do: {"Sources/#{target}/#{file}.swift", target}),
        fn files ->
          Process.put(:coverage_seed_products, files)
          files
        end
      )
  end

  def target_of(path), do: [generated() | product_files()] |> Map.new() |> Map.fetch!(path)

  def features, do: @features

  # The schemes: the test modules each runs and the product files it compiles.
  def scheme_modules("App"), do: ["AppTests" | Enum.map(@features, &(&1 <> "Tests"))]
  def scheme_modules("Core"), do: Enum.map(@core, &(&1 <> "Tests"))
  def scheme_modules("DesignSystem"), do: ["DesignSystemTests"]
  def scheme_modules("AppIntegration"), do: ["AppIntegrationTests"]

  def scheme_paths(scheme) when scheme in ["App", "AppIntegration"],
    do: Enum.map([generated() | product_files()], &elem(&1, 0))

  def scheme_paths("Core"), do: for({path, target} <- product_files(), target in @core, do: path)

  def scheme_paths("DesignSystem"),
    do: for({path, target} <- product_files(), target in ["DesignSystem", "Utilities"], do: path)

  # ---------------------------------------------------------------------------
  # Files: a version is a list of functions laid out from line 8 on.

  defp pool(path) do
    stem = Path.basename(path, ".swift")

    if stem == "APIClient" do
      @api_client
    else
      Enum.find_value(@pools, @generic, fn {suffix, names} -> if String.ends_with?(stem, suffix), do: names end)
    end
  end

  def base_count(path) do
    case Path.basename(path, ".swift") do
      "APIClient" -> 26
      _ -> 3 + h({:functions, path}, 3)
    end
  end

  def names(path, version) do
    pool = pool(path)
    extra = for i <- 1..20, do: "helper#{i}()"
    Enum.take(pool ++ extra, base_count(path) + version)
  end

  def layout(path, version) do
    key = {:coverage_seed_layout, path, version}

    Process.get(key) ||
      then(build_layout(path, version), fn layout ->
        Process.put(key, layout)
        layout
      end)
  end

  defp build_layout(path, version) do
    {functions, _next} =
      path
      |> names(version)
      |> Enum.with_index()
      |> Enum.map_reduce(8, fn {name, index}, start ->
        function = function_at(path, name, index, start)
        {function, function.close + 3}
      end)

    %{functions: functions, lines: functions |> Enum.flat_map(& &1.lines) |> Enum.sort()}
  end

  defp function_at(path, name, index, start) do
    body_len = 4 + h({:body, path, name}, 9)

    error_len =
      case h({:error, path, name}, 3) do
        0 -> 0
        k -> min(k, body_len - 3)
      end

    # A blank or comment line after every fifth statement: not executable.
    {body, last} =
      Enum.map_reduce(1..body_len, start, fn i, previous ->
        line = previous + 1 + if(rem(i, 5) == 0, do: 1, else: 0)
        {line, line}
      end)

    close = last + 1
    error = if error_len > 0, do: Enum.take(body, -error_len), else: []

    closure =
      if h({:closure, path, name}, 4) == 0 and body_len - error_len >= 5, do: Enum.slice(body, 1, 3)

    %{
      name: name,
      index: index,
      line: start,
      body: body,
      error: error,
      close: close,
      closure: closure,
      lines: [start | body] ++ [close]
    }
  end

  def main_path(function), do: [function.line | function.body -- function.error] ++ [function.close]
  def error_path(function), do: [function.line | Enum.take(function.body, 2)] ++ function.error ++ [function.close]

  def blob(path, version), do: :sha |> :crypto.hash("seed-blob/#{path}/#{version}") |> Base.encode16(case: :lower)

  # ---------------------------------------------------------------------------
  # Tests: a unit test per function most functions have from the start, a
  # failure test for some functions with an error path, and tests added over
  # time for the functions that had none.

  def slug(name), do: name |> String.replace(~r/\(.*\)/, "") |> String.replace(" ", "_")

  def module_of(path), do: target_of(path) <> "Tests"
  def suite_of(path), do: Path.basename(path, ".swift") <> "Tests"

  defp base_unit?(path, function), do: function.index < base_count(path) and h({:unit, path, function.name}, 10) < 6

  defp base_failure?(path, function),
    do: function.index < base_count(path) and function.error != [] and h({:failure, path, function.name}, 10) < 3

  def unit_test?(state, path, function),
    do: base_unit?(path, function) or MapSet.member?(state.added, {path, function.name})

  def tests(state, opts \\ []) do
    integration? = Keyword.get(opts, :integration, false)

    units =
      Enum.flat_map(product_files(), fn {path, _target} ->
        layout = layout(path, Map.get(state.versions, path, 0))

        Enum.flat_map(layout.functions, fn function ->
          unit =
            if unit_test?(state, path, function) do
              extra =
                if String.ends_with?(path, "ViewModel.swift") and function.name == "load()",
                  do: [{"Sources/Networking/APIClient.swift", "send(_:)", :main}],
                  else: []

              [
                test(module_of(path), suite_of(path), "test_#{slug(function.name)}()", [
                  {path, function.name, :main} | extra
                ])
              ]
            else
              []
            end

          failure =
            if base_failure?(path, function),
              do: [
                test(module_of(path), suite_of(path), "test_#{slug(function.name)}_failure()", [
                  {path, function.name, :error}
                ])
              ],
              else: []

          unit ++ failure
        end)
      end)

    if integration?, do: units ++ integration_tests(), else: units
  end

  defp test(module, suite, name, covers),
    do: %{module: module, suite: suite, name: name, covers: covers, reps: 1 + h({module, suite, name}, 4)}

  # End-to-end flows through a feature: its screen, its view model's happy and
  # error paths, the app's root and router, and the generated assets.
  defp integration_tests do
    @features
    |> Enum.take_every(2)
    |> Enum.map(fn feature ->
      base = "Sources/Features/#{feature}/#{feature}"

      test("AppIntegrationTests", "FlowTests", "test_#{Macro.underscore(feature)}_flow()", [
        {"Sources/App/RootView.swift", "body", :main},
        {"Sources/App/Router.swift", "init()", :main},
        {base <> "View.swift", "body", :main},
        {base <> "ViewModel.swift", "load()", :main},
        {base <> "ViewModel.swift", "refresh()", :error},
        {"Sources/Generated/Assets.swift", "init()", :main}
      ])
    end)
  end

  # The lines a test executes, per path, at the state's file versions.
  def test_lines(state, test) do
    test.covers
    |> Enum.flat_map(fn {path, name, kind} ->
      layout = layout(path, Map.get(state.versions, path, 0))

      case Enum.find(layout.functions, &(&1.name == name)) do
        nil -> []
        function -> [{path, if(kind == :main, do: main_path(function), else: error_path(function))}]
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {path, lines} -> {path, lines |> List.flatten() |> Enum.uniq() |> Enum.sort()} end)
  end

  # ---------------------------------------------------------------------------
  # A run: which tests of the scheme ran and what the report says.

  def run(state, scheme, opts) do
    candidates =
      state |> tests(integration: scheme == "AppIntegration") |> Enum.filter(&(&1.module in scheme_modules(scheme)))

    ran =
      case Keyword.get(opts, :selective) do
        nil ->
          candidates

        %{paths: paths, modules: modules} ->
          Enum.filter(candidates, fn test ->
            test.module in modules or Enum.any?(test.covers, fn {path, _name, _kind} -> path in paths end)
          end)
      end

    failing = Keyword.get(opts, :failing)

    hits =
      Enum.reduce(ran, %{}, fn test, acc ->
        Enum.reduce(test_lines(state, test), acc, fn {path, lines}, acc ->
          counts = Map.get(acc, path, %{})
          Map.put(acc, path, Enum.reduce(lines, counts, &Map.update(&2, &1, test.reps, fn n -> n + test.reps end)))
        end)
      end)

    product =
      Enum.map(scheme_paths(scheme), fn path ->
        version = Map.get(state.versions, path, 0)
        layout = layout(path, version)
        path_hits = Map.get(hits, path, %{})
        counts = Enum.map(layout.lines, &Map.get(path_hits, &1, 0))

        %{
          path: path,
          git_blob_id: blob(path, version),
          targets: [target_of(path)],
          is_test: false,
          covered_lines: Enum.count(counts, &(&1 > 0)),
          executable_lines: length(counts),
          line_numbers: layout.lines,
          execution_counts: counts,
          functions: functions(layout, path_hits)
        }
      end)

    test_files =
      scheme
      |> scheme_modules()
      |> Enum.map(fn module ->
        count = Enum.count(candidates, &(&1.module == module))
        ran? = Enum.any?(ran, &(&1.module == module))
        lines = Enum.to_list(1..(6 + 3 * count))
        path = "Tests/#{module}/#{module}.swift"

        %{
          path: path,
          git_blob_id: blob(path, count),
          targets: [module],
          is_test: true,
          covered_lines: if(ran?, do: length(lines), else: 0),
          executable_lines: length(lines),
          line_numbers: lines,
          execution_counts: Enum.map(lines, fn _ -> if ran?, do: 1, else: 0 end),
          functions: []
        }
      end)

    %{
      scheme: scheme,
      candidates: candidates,
      ran: ran,
      failing: failing,
      files: product ++ test_files,
      evidence: evidence(state, ran)
    }
  end

  defp functions(layout, hits) do
    Enum.flat_map(layout.functions, fn function ->
      parent = %{
        name: function.name,
        line_number: function.line,
        execution_count: Map.get(hits, function.line, 0),
        covered_lines: Enum.count(function.lines, &(Map.get(hits, &1, 0) > 0)),
        executable_lines: length(function.lines)
      }

      closure =
        if function.closure do
          [
            %{
              name: "closure #1 in #{function.name}",
              line_number: hd(function.closure),
              execution_count: Map.get(hits, hd(function.closure), 0),
              covered_lines: Enum.count(function.closure, &(Map.get(hits, &1, 0) > 0)),
              executable_lines: length(function.closure)
            }
          ]
        else
          []
        end

      [parent | closure]
    end)
  end

  defp evidence(state, ran) do
    per_test = Enum.map(ran, &{&1, test_lines(state, &1)})
    paths = per_test |> Enum.flat_map(fn {_test, lines} -> Map.keys(lines) end) |> Enum.uniq() |> Enum.sort()
    index = paths |> Enum.with_index() |> Map.new()

    %{
      paths: paths,
      scopes:
        Enum.map(per_test, fn {test, lines} ->
          files = lines |> Map.keys() |> Enum.sort()

          %{
            kind: "test",
            module: test.module,
            suite: test.suite,
            name: test.name,
            files: Enum.map(files, &Map.fetch!(index, &1)),
            lines: Enum.map(files, &ranges(Map.fetch!(lines, &1)))
          }
        end)
    }
  end

  def ranges(lines) do
    lines
    |> Enum.chunk_while(
      nil,
      fn
        line, nil -> {:cont, {line, line}}
        line, {first, last} when line == last + 1 -> {:cont, {first, line}}
        line, range -> {:cont, range, {line, line}}
      end,
      fn
        nil -> {:cont, nil}
        range -> {:cont, range, nil}
      end
    )
    |> Enum.flat_map(fn {first, last} -> [first, last] end)
  end

  # ---------------------------------------------------------------------------
  # Commits: what a commit changes, applied to its parent's state.

  def initial_state, do: %{versions: %{}, added: MapSet.new()}

  # `kind` is :both, :bump (a function added, untested) or :test (a test
  # added for a function that had none). Picks are stable per commit label.
  def ops(state, label, kind, only_paths \\ nil) do
    files = if only_paths, do: Enum.filter(product_files(), &(elem(&1, 0) in only_paths)), else: product_files()

    bump =
      if kind in [:both, :bump] do
        {path, _target} = Enum.at(files, h({:bump, label}, length(files)))
        [{:bump, path}]
      else
        []
      end

    add =
      if kind in [:both, :test] do
        untested =
          for {path, _target} <- files,
              function <- layout(path, Map.get(state.versions, path, 0)).functions,
              not unit_test?(state, path, function),
              do: {path, function.name}

        case untested do
          [] -> []
          _ -> [{:test, Enum.at(untested, h({:test, label}, length(untested)))}]
        end
      else
        []
      end

    bump ++ add
  end

  def apply_ops(state, ops) do
    Enum.reduce(ops, state, fn
      {:bump, path}, state -> %{state | versions: Map.update(state.versions, path, 1, &(&1 + 1))}
      {:test, key}, state -> %{state | added: MapSet.put(state.added, key)}
    end)
  end

  # What selective testing reruns for the commit's changes: the tests that
  # executed a changed file, and every test of a module whose tests changed.
  def selection(ops) do
    %{
      paths: for({:bump, path} <- ops, do: path),
      modules: for({:test, {path, _name}} <- ops, uniq: true, do: module_of(path))
    }
  end

  # The files a pull request changed against its merge base, as its runs
  # report them: each file whose version moved, with the added functions as
  # hunks, and the test files that gained tests.
  def changed_files(base, head) do
    product =
      for {path, version} <- head.versions, version != Map.get(base.versions, path, 0) do
        before = MapSet.new(layout(path, Map.get(base.versions, path, 0)).functions, & &1.name)

        hunks =
          for function <- layout(path, version).functions,
              not MapSet.member?(before, function.name),
              do: %{start: function.line, end: function.close}

        %{path: path, status: "modified", git_blob_id: blob(path, version), hunks: hunks}
      end

    tests =
      head.added
      |> MapSet.difference(base.added)
      |> Enum.map(fn {path, _name} -> "Tests/#{module_of(path)}/#{module_of(path)}.swift" end)
      |> Enum.uniq()
      |> Enum.map(&%{path: &1, status: "modified", git_blob_id: blob(&1, 0), hunks: [%{start: 1, end: 3}]})

    product ++ tests
  end

  def listing(state) do
    product =
      Enum.map([generated() | product_files()], fn {path, _target} ->
        %{path: path, git_blob_id: blob(path, Map.get(state.versions, path, 0)), mode: 0o100644}
      end)

    tracked =
      Enum.map(tracked_files(), fn {path, blob} -> %{path: path, git_blob_id: blob(path, blob), mode: 0o100644} end)

    unmeasured = Enum.map(unmeasured_paths(), &%{path: &1, git_blob_id: blob(&1, 0), mode: 0o100644})
    others = Enum.map(~w(README.md .gitignore Package.swift), &%{path: &1, git_blob_id: blob(&1, 0), mode: 0o100644})
    product ++ tracked ++ unmeasured ++ others
  end
end

{:ok, project} = Projects.get_project_by_slug("tuist/tuist")
{:ok, account} = Tuist.Accounts.get_account_by_id(project.account_id)

repository_url = "https://github.com/tuist/tuist"
repository_key = GitHistory.repository_key(repository_url)

# Re-seeding starts from a clean slate: dropping the repository cascades to its
# commits, parents, refs and listings; the runs that named it and everything
# derived from them go too.
previous_repository_id =
  Repo.one(
    from(r in GitHistory.Repository, where: r.account_id == ^account.id and r.key == ^repository_key, select: r.id)
  )

if previous_repository_id do
  IngestRepo.query!("DELETE FROM git_commit_files WHERE repository_id = {repository_id:Int64}", %{
    repository_id: previous_repository_id
  })

  Repo.delete_all(from(r in GitHistory.Repository, where: r.id == ^previous_repository_id))
end

for table <- ["coverage_files", "coverage_runs", "test_run_enumerated_tests", "test_run_changed_files"] do
  IngestRepo.query!("DELETE FROM #{table} WHERE project_id = {project_id:Int64}", %{project_id: project.id})
end

Repo.delete_all(from(c in Tuist.Tests.CoverageCommit, where: c.project_id == ^project.id))
Repo.delete_all(from(c in "coverage_commit_completions", where: c.project_id == ^project.id))

# Mutations rather than lightweight deletes: these tables carry projections,
# which lightweight deletes refuse to touch. A mutation cannot read another
# table, so the runs' ids are read first.
%{rows: previous_run_ids} =
  IngestRepo.query!(
    "SELECT DISTINCT toString(id) FROM test_runs WHERE project_id = {project_id:Int64} AND git_repository_id > 0",
    %{project_id: project.id}
  )

for chunk <- previous_run_ids |> List.flatten() |> Enum.chunk_every(500), chunk != [] do
  IngestRepo.query!(
    "ALTER TABLE test_case_runs DELETE WHERE project_id = {project_id:Int64} AND test_run_id IN {ids:Array(UUID)}",
    %{project_id: project.id, ids: chunk}
  )
end

IngestRepo.query!(
  "ALTER TABLE test_runs DELETE WHERE project_id = {project_id:Int64} AND git_repository_id > 0",
  %{project_id: project.id}
)

repository_id = GitHistory.repository_id(account.id, repository_url)

{:ok, project} =
  Projects.update_project(project, %{
    tracked_file_globs: ["Package.resolved", "Tests/Fixtures/**"],
    coverage_excluded_path_globs: ["Sources/Generated/**"]
  })

sha = fn label -> :sha |> :crypto.hash("tuist-coverage-seed/" <> label) |> Base.encode16(case: :lower) end
at = fn days_ago, hour -> Date.utc_today() |> Date.add(-days_ago) |> DateTime.new!(Time.new!(hour, 0, 0)) end

# ---------------------------------------------------------------------------
# The plan: every commit with its parents, what it changes and how its schemes
# ran. `schemes` are `{scheme, mode}` with mode `:full`, `:selective` or
# `{:failing, test_name}`; `signal` whether its pipeline signalled completion.

main_days = Enum.to_list(90..34//-7) ++ Enum.to_list(30..1//-1)

main_schemes = fn days_ago ->
  ["App", "Core"] ++
    if(days_ago <= 30, do: ["DesignSystem"], else: []) ++ if(days_ago <= 14, do: ["AppIntegration"], else: [])
end

# Days on `main` with something to show: nobody measured it, a single scheme
# measured it (and it never signalled), its `App` run was selective, or its
# pipeline has not signalled yet.
unmeasured_days = [18, 7]
single_scheme_day = 12
selective_days = [9, 4]
pending_days = [1]
dirty_day = 3

main_commit = fn days_ago, index ->
  schemes =
    cond do
      days_ago in unmeasured_days -> []
      days_ago == single_scheme_day -> [{"App", :full}]
      days_ago in selective_days -> Enum.map(main_schemes.(days_ago), &{&1, if(&1 == "App", do: :selective, else: :full)})
      true -> Enum.map(main_schemes.(days_ago), &{&1, :full})
    end

  %{
    label: "main-#{days_ago}",
    days_ago: days_ago,
    hour: 9,
    branch: "main",
    ref?: true,
    kind: Enum.at([:both, :test, :both, :bump, :both], rem(index, 5)),
    schemes: schemes,
    signal: days_ago not in pending_days and days_ago != single_scheme_day,
    pull_request: nil
  }
end

main_plan =
  main_days
  |> Enum.with_index()
  |> Enum.map(fn {days_ago, index} -> main_commit.(days_ago, index) end)

# Feature branches off `main`: `{name, fork day, commits, has history}`. Most
# ran in the last month so the default period pages the branch list.
feature_branches = [
  {"feature/offline-mode", 85, 2, true},
  {"feature/widgets", 70, 3, true},
  {"refactor/navigation", 50, 2, true},
  {"feature/search-filters", 40, 1, true},
  {"feature/dark-mode", 29, 2, true},
  {"fix/login-crash", 28, 1, true},
  {"feature/push-notifications", 27, 3, true},
  {"chore/upgrade-swift", 26, 1, true},
  {"feature/billing-portal", 25, 2, true},
  {"fix/cache-eviction", 23, 1, true},
  {"feature/inbox-threads", 21, 2, true},
  {"refactor/design-tokens", 19, 2, true},
  {"feature/test-insights", 17, 3, true},
  {"fix/retry-backoff", 15, 1, true},
  {"feature/profile-editing", 13, 2, true},
  {"chore/logging-cleanup", 11, 1, true},
  {"feature/bundle-diff", 10, 2, true},
  {"fix/locale-plurals", 8, 1, true},
  {"experiment/snapshot-tests", 6, 2, false},
  {"spike/offline-cache", 5, 1, false}
]

branch_plan =
  Enum.flat_map(feature_branches, fn {name, fork_day, count, ref?} ->
    for i <- 0..(count - 1) do
      %{
        label: "#{name}-#{i}",
        days_ago: max(fork_day - i, 1),
        hour: 13 + i,
        branch: name,
        ref?: ref?,
        fork: fork_day,
        index: i,
        kind: :both,
        schemes: [{"App", :full}, {"Core", :full}],
        signal: true,
        pull_request: nil
      }
    end
  end)

# Pull requests: `{number, branch, fork day, [{day, schemes, signal}], merged
# into main on}`. #4321 reuses its skipped tests' coverage, #4330 cannot for
# a test that failed in its previous commit, #4335 is pending.
pull_requests = [
  {4299, "feature/networking-retries", 60, [{59, :full, true}, {58, :full, true}], 55},
  {4310, "feature/onboarding-v2", 24, [{23, :full, true}, {22, :full, true}], 20},
  {4321, "feature/coverage-page", 3, [{3, :full, true}, {2, :selective, true}], nil},
  {4330, "feature/search-ranking", 4,
   [{4, {:failing, "test_load()", "Sources/Features/Search/SearchViewModel.swift"}, true}, {1, :selective, false}], nil},
  {4335, "fix/settings-sync", 2, [{1, :full, false}], nil},
  {4340, "feature/cache-dashboard", 6, [{6, :full, true}, {5, :full, true}, {4, :full, true}], nil}
]

pull_request_plan =
  Enum.flat_map(pull_requests, fn {number, name, fork_day, commits, _merged} ->
    commits
    |> Enum.with_index()
    |> Enum.map(fn {{day, mode, signal}, i} ->
      %{
        label: "pr-#{number}-#{i}",
        days_ago: day,
        hour: 15 + i,
        branch: name,
        ref?: true,
        fork: fork_day,
        index: i,
        kind: if(mode == :selective, do: :bump, else: :both),
        schemes: [{"App", mode}, {"Core", :full}],
        signal: signal,
        pull_request: number
      }
    end)
  end)

# ---------------------------------------------------------------------------
# States: replay the commits oldest first, each from its parent.

# A first replay of `main` without merges says where branches fork; the
# branches' changes are picked from it and replayed again below, onto `main`
# as its merges left it.
{main_states, _} =
  Enum.map_reduce(main_plan, CoverageSeed.initial_state(), fn commit, state ->
    ops = CoverageSeed.ops(state, commit.label, commit.kind)
    after_state = CoverageSeed.apply_ops(state, ops)
    {{commit.days_ago, %{commit: commit, ops: ops, before: state, state: after_state}}, after_state}
  end)

main_by_day = Map.new(main_states)

# The main commit at or just before a day: where a branch forks.
fork_of = fn day ->
  main_days |> Enum.filter(&(&1 >= day)) |> Enum.min() |> then(&Map.fetch!(main_by_day, &1))
end

side_commits = fn plan ->
  plan
  |> Enum.group_by(& &1.branch)
  |> Enum.flat_map(fn {_branch, commits} ->
    commits = Enum.sort_by(commits, & &1.index)
    fork = fork_of.(hd(commits).fork)

    {entries, _} =
      Enum.map_reduce(commits, {fork.state, fork.commit.label}, fn commit, {state, parent} ->
        # The selective heads change one screen, which their runs retest;
        # #4330's leaves the search view model, whose test failed, alone.
        ops =
          case {commit.pull_request, commit.index} do
            {4321, 1} ->
              CoverageSeed.ops(state, commit.label, :bump, ["Sources/Features/ProjectDetail/ProjectDetailView.swift"])

            {4330, 1} ->
              CoverageSeed.ops(state, commit.label, :bump, ["Sources/Features/Settings/SettingsView.swift"])

            _ ->
              CoverageSeed.ops(state, commit.label, commit.kind)
          end

        after_state = CoverageSeed.apply_ops(state, ops)

        {%{
           commit: commit,
           ops: ops,
           before: state,
           state: after_state,
           parent: parent,
           base: fork.state,
           merge_base: fork.commit.label
         }, {after_state, commit.label}}
      end)

    entries
  end)
end

branch_entries = side_commits.(branch_plan)
pull_request_entries = side_commits.(pull_request_plan)

# Merges bring a pull request's changes onto `main`: the merge commit is the
# main commit of that day, whose state gains every change the branch made.
merged_heads =
  for {number, _name, _fork, _commits, merged} <- pull_requests, merged, into: %{} do
    commits = pull_request_entries |> Enum.filter(&(&1.commit.pull_request == number)) |> Enum.sort_by(& &1.commit.index)
    {merged, %{commit: List.last(commits).commit, ops: Enum.flat_map(commits, & &1.ops)}}
  end

{main_entries, _} =
  Enum.map_reduce(main_plan, {CoverageSeed.initial_state(), nil}, fn commit, {state, parent} ->
    ops = CoverageSeed.ops(state, commit.label, commit.kind)

    ops =
      case Map.get(merged_heads, commit.days_ago) do
        nil -> ops
        head -> ops ++ head.ops
      end

    after_state = CoverageSeed.apply_ops(state, ops)

    parents =
      case {parent, Map.get(merged_heads, commit.days_ago)} do
        {nil, _} -> []
        {parent, nil} -> [parent]
        {parent, head} -> [parent, head.commit.label]
      end

    {%{commit: commit, ops: ops, before: state, state: after_state, parents: parents, base: nil, merge_base: nil},
     {after_state, commit.label}}
  end)

# A branch forks from the main commit of its fork day as replayed with merges.
main_entry_by_label = Map.new(main_entries, &{&1.commit.label, &1})

rebase = fn entries ->
  entries
  |> Enum.group_by(& &1.commit.branch)
  |> Enum.flat_map(fn {_branch, commits} ->
    commits = Enum.sort_by(commits, & &1.commit.index)
    fork = Map.fetch!(main_entry_by_label, hd(commits).merge_base)

    {rebased, _} =
      Enum.map_reduce(commits, {fork.state, fork.commit.label}, fn entry, {state, parent} ->
        after_state = CoverageSeed.apply_ops(state, entry.ops)

        {Map.put(%{entry | before: state, state: after_state, parent: parent, base: fork.state}, :parents, [parent]),
         {after_state, entry.commit.label}}
      end)

    rebased
  end)
end

entries = main_entries ++ rebase.(branch_entries) ++ rebase.(pull_request_entries)

# ---------------------------------------------------------------------------
# The repository: graph, refs and listings.

GitHistory.record_commits(
  repository_id,
  "sha1",
  Enum.map(entries, fn entry ->
    %{
      sha: sha.(entry.commit.label),
      parents: Enum.map(entry.parents, sha),
      committed_at: at.(entry.commit.days_ago, entry.commit.hour)
    }
  end)
)

heads =
  entries
  |> Enum.filter(& &1.commit.ref?)
  |> Enum.group_by(& &1.commit.branch)
  |> Enum.map(fn {branch, commits} ->
    {branch, commits |> Enum.max_by(&{-&1.commit.days_ago, &1.commit.hour}) |> then(&sha.(&1.commit.label))}
  end)

# A merged pull request's branch keeps its head; `main` is recorded last.
for {branch, head} <- Enum.sort_by(heads, fn {branch, _} -> branch == "main" end) do
  GitHistory.record_branch_head(repository_id, branch, head, project.default_branch)
end

for entry <- entries do
  files = CoverageSeed.listing(entry.state)
  GitHistory.record_listing(repository_id, sha.(entry.commit.label), files, files_count: length(files))
end

# ---------------------------------------------------------------------------
# The runs. Runs in the last 30 days list their candidate tests and report
# per-test evidence, what reusing a skipped test's coverage needs; older runs
# report their coverage only.

create_run = fn entry, scheme, mode, opts ->
  commit = entry.commit

  run_opts =
    case mode do
      :selective -> [selective: CoverageSeed.selection(entry.ops)]
      {:failing, test, path} -> [failing: {CoverageSeed.module_of(path), CoverageSeed.suite_of(path), test}]
      :full -> []
    end

  run = CoverageSeed.run(entry.state, scheme, run_opts)
  recent? = commit.days_ago <= 30
  failing = run.failing

  modules =
    run.ran
    |> Enum.group_by(& &1.module)
    |> Enum.map(fn {module, tests} ->
      cases =
        Enum.map(tests, fn test ->
          failed? = {test.module, test.suite, test.name} == failing

          %{
            name: test.name,
            test_suite_name: test.suite,
            status: if(failed?, do: "failure", else: "success"),
            duration: 40 + CoverageSeed.h({test.module, test.suite, test.name}, 400)
          }
        end)

      %{
        name: module,
        status: if(Enum.any?(cases, &(&1.status == "failure")), do: "failure", else: "success"),
        duration: cases |> Enum.map(& &1.duration) |> Enum.sum(),
        test_cases: cases
      }
    end)

  ran_at =
    commit.days_ago
    |> at.(commit.hour)
    |> DateTime.add(600 + CoverageSeed.h({commit.label, scheme}, 3000), :second)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)

  pull_request = commit.pull_request

  {:ok, created} =
    Tests.create_test(%{
      id: UUIDv7.generate(),
      project_id: project.id,
      account_id: account.id,
      duration: modules |> Enum.map(& &1.duration) |> Enum.sum() |> max(1000),
      status: if(Enum.any?(modules, &(&1.status == "failure")), do: "failure", else: "success"),
      is_ci: true,
      ci_provider: "github",
      ci_project_handle: "tuist/tuist",
      ci_run_id: "#{19_000_000_000 + CoverageSeed.h({commit.label, scheme, :ci}, 1_000_000_000)}",
      macos_version: "26.0",
      xcode_version: "26.1",
      scheme: scheme,
      ran_at: ran_at,
      git_branch: commit.branch,
      git_commit_sha: sha.(commit.label),
      git_ref: if(pull_request, do: "refs/pull/#{pull_request}/merge", else: "refs/heads/#{commit.branch}"),
      git_remote_url_origin: repository_url,
      git_dirty: Keyword.get(opts, :dirty, false),
      base_branch: pull_request && "main",
      merge_base_sha: pull_request && sha.(entry.merge_base),
      is_pull_request: pull_request != nil,
      pull_request_number: pull_request,
      git_object_format: "sha1",
      history_source: "client",
      test_modules: modules,
      enumerated_tests:
        if(recent?,
          do: Enum.map(run.candidates, &%{module: &1.module, suite: &1.suite, name: &1.name, enabled: true})
        ),
      coverage_evidence: if(recent?, do: run.evidence),
      changed_files: if(pull_request, do: CoverageSeed.changed_files(entry.base, entry.state), else: []),
      xcode_coverage: %{partial: mode == :selective, files: run.files}
    })

  {created, run}
end

runs =
  Enum.flat_map(entries, fn entry ->
    Enum.map(entry.commit.schemes, fn {scheme, mode} ->
      {created, run} = create_run.(entry, scheme, mode, [])
      %{entry: entry, scheme: scheme, mode: mode, test: created, run: run}
    end)
  end)

# A run from a checkout with local changes: stored, and left out of every figure.
{_dirty, _} = create_run.(Map.fetch!(main_entry_by_label, "main-#{dirty_day}"), "App", :full, dirty: true)

Tuist.Tests.Test.Buffer.flush()
Tuist.Tests.TestRunChangedFile.Buffer.flush()

# Publish oldest first, as the commit worker would as the runs land.
published =
  entries
  |> Enum.sort_by(&{-&1.commit.days_ago, &1.commit.hour})
  |> Enum.count(fn entry ->
    commit_sha = sha.(entry.commit.label)

    result =
      if entry.commit.signal and entry.commit.schemes != [],
        do: Commits.signal_complete(project, commit_sha),
        else: Commits.recompute(project, commit_sha)

    result != nil
  end)

# ---------------------------------------------------------------------------
# Checks: the application's figures against the model's own union of runs.

excluded? = &String.starts_with?(&1, "Sources/Generated/")

expected = fn entry ->
  commit_runs = Enum.filter(runs, &(&1.entry.commit.label == entry.commit.label))

  commit_runs
  |> Enum.flat_map(& &1.run.files)
  |> Enum.reject(&(&1.is_test or excluded?.(&1.path)))
  |> Enum.group_by(& &1.path)
  |> Enum.reduce({0, 0}, fn {_path, files}, {covered, executable} ->
    lines =
      files
      |> Enum.flat_map(&Enum.zip(&1.line_numbers, &1.execution_counts))
      |> Enum.filter(fn {_line, count} -> count > 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    {covered + length(lines), executable + hd(files).executable_lines}
  end)
end

mismatches =
  entries
  |> Enum.reject(&(&1.commit.schemes == []))
  |> Enum.flat_map(fn entry ->
    summary = Commits.summary(project.id, sha.(entry.commit.label))
    want = expected.(entry)

    if summary && {summary.covered_lines, summary.executable_lines} == want,
      do: [],
      else: [{entry.commit.label, want, summary && {summary.covered_lines, summary.executable_lines}}]
  end)

kinds = fn label -> Commits.summary(project.id, sha.(label)).reported_kind end

checks = [
  {"#4321's head reuses its skipped tests' coverage", kinds.("pr-4321-1") == "reported"},
  {"#4330's head cannot reuse a test that failed last time", kinds.("pr-4330-1") == "partial"},
  {"main's selective commits reuse theirs", Enum.all?(selective_days, &(kinds.("main-#{&1}") == "reported"))},
  {"recent full runs list their tests", kinds.("main-2") == "measured"},
  {"older runs do not", kinds.("main-90") == "observed"}
]

failed = for {name, false} <- checks, do: name

if mismatches != [] or failed != [] do
  raise """
  The coverage seed's figures do not match its model.
  Totals (commit, expected {covered, executable}, stored): #{inspect(mismatches)}
  Failed checks: #{inspect(failed)}
  """
end

IO.puts(
  "  - coverage: #{length(entries)} commits (#{published} published) over #{length(runs) + 1} runs, " <>
    "#{length(CoverageSeed.product_files())} product files; checks passed"
)

IO.puts("  - coverage pull requests: /#{account.name}/tuist/tests/coverage/pull-requests/4321 (reused), 4330 (unknown)")
