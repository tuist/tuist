defmodule Tuist.DashboardSearchTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Bazel.Invocation
  alias Tuist.Cargo.Build
  alias Tuist.ClickHouseRepo
  alias Tuist.DashboardSearch
  alias Tuist.IngestRepo
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.TestCaseRun
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp project(attrs \\ []) do
    attrs |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)
  end

  defp test_case(attrs) do
    test_case = RunsFixtures.test_case_fixture(attrs)
    IngestRepo.insert_all(Tuist.Tests.TestCase, [insertable_attrs(test_case)])
    test_case
  end

  test "empty query suggests five authorized projects without telemetry reads" do
    projects = for _ <- 1..7, do: project()
    preferred = List.last(projects)
    reject(ClickHouseRepo, :query, 3)
    reject(Repo, :query, 3)
    response = DashboardSearch.search(projects, "  ", preferred_project_id: preferred.id)
    assert response.unavailable == []
    assert length(response.results) == 5
    assert hd(response.results).title == preferred.name
    assert Enum.all?(response.results, &(&1.type == "project"))
    assert DashboardSearch.search([], "anything").results == []
  end

  test "cases match modules and suites before limits and remain tenant isolated" do
    allowed = project()
    foreign = project()
    for i <- 1..8, do: test_case(project_id: allowed.id, name: "unrelated#{i}")
    target = test_case(project_id: allowed.id, name: "login", module_name: "AccountsNeedle")
    test_case(project_id: foreign.id, name: "secret", module_name: "AccountsNeedle")
    response = DashboardSearch.search([allowed], "accountsneedle")
    assert response.unavailable == []
    assert [%{type: "test_case", title: "login", path: path, subtitle: context, project: project_name}] = response.results
    assert path == "/#{allowed.account.name}/#{allowed.name}/tests/test-cases/#{target.id}"
    assert project_name == allowed.name
    assert context =~ "AccountsNeedle"
    assert context =~ "TestSuite"
    refute context =~ target.id

    assert [%{title: "login"}] = DashboardSearch.search([allowed], target.id).results

    assert [%{title: "login"}] =
             Enum.filter(DashboardSearch.search([allowed], "TestSuite").results, &(&1.title == "login"))
  end

  test "global relevance outranks preferred project while ties prefer it, before the five result cap" do
    preferred = project()
    other = project()
    for i <- 1..7, do: test_case(project_id: preferred.id, name: "SomeNeedle#{i}")
    exact = test_case(project_id: other.id, name: "Needle")
    test_case(project_id: preferred.id, name: "NeedlePrefix")
    response = DashboardSearch.search([preferred, other], "needle", preferred_project_id: preferred.id)
    assert response.unavailable == []
    cases = Enum.filter(response.results, &(&1.type == "test_case"))
    assert length(cases) == 5
    assert hd(cases).path =~ exact.id
    assert Enum.at(cases, 1).title == "NeedlePrefix"
  end

  test "previews search full notes, literal wildcard characters and exact scoped URLs" do
    allowed = project()
    foreign = project()
    for _ <- 1..8, do: AppBuildsFixtures.preview_fixture(project: allowed, display_name: "Other")

    preview =
      AppBuildsFixtures.preview_fixture(
        project: allowed,
        display_name: "App",
        version: "2.4.1",
        track: "beta",
        release_notes: String.duplicate("x", 500) <> "needle%_"
      )

    AppBuildsFixtures.preview_fixture(project: foreign, display_name: "Private needle%_")
    response = DashboardSearch.search([allowed], "needle%_")
    assert response.unavailable == []
    assert [%{type: "preview", title: "App", path: path, subtitle: context}] = response.results
    assert path == "/#{allowed.account.name}/#{allowed.name}/previews/#{preview.id}"
    assert context =~ "2.4.1 · beta"
    refute context =~ preview.id
    assert [%{path: ^path}] = DashboardSearch.search([allowed], "https://tuist.dev#{path}?tab=details").results
    assert DashboardSearch.search([foreign], path).results == []
  end

  test "exact identity determines group appearance before fuzzy build matches" do
    p = project()
    preview = AppBuildsFixtures.preview_fixture(project: p, display_name: "App")
    test_case(project_id: p.id, name: "prefix-#{preview.id}")
    response = DashboardSearch.search([p], preview.id)
    assert response.unavailable == []
    assert [%{type: "preview"}, %{type: "test_case"}] = response.results

    c = test_case(project_id: p.id, name: "ExactCase")
    AppBuildsFixtures.preview_fixture(project: p, display_name: "prefix-#{c.id}")
    response = DashboardSearch.search([p], c.id)
    assert response.unavailable == []
    assert [%{type: "test_case"}, %{type: "preview"}] = response.results
  end

  test "preferred project wins relevance ties without hiding matches in other authorized projects" do
    preferred = project()
    other = project()

    first =
      test_case(
        project_id: preferred.id,
        name: "TiedNeedle",
        last_ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)
      )

    second = test_case(project_id: other.id, name: "TiedNeedle")
    response = DashboardSearch.search([other, preferred], "TiedNeedle", preferred_project_id: preferred.id)
    assert [%{path: first_path}, %{path: second_path}] = response.results
    assert String.ends_with?(first_path, first.id)
    assert String.ends_with?(second_path, second.id)
    assert length(DashboardSearch.search([preferred], "TiedNeedle").results) == 1
  end

  test "real Xcode and Gradle builds and shared test runs retain native detail paths and search branches" do
    p = project()
    gradle_project = project(build_system: :gradle)
    {:ok, xcode} = RunsFixtures.build_fixture(project_id: p.id, scheme: "NeedleApp")
    gradle = GradleFixtures.build_fixture(project_id: gradle_project.id, root_project_name: "NeedleGradle")
    {:ok, run} = RunsFixtures.test_fixture(project_id: p.id, scheme: "NeedleTests")
    response = DashboardSearch.search([p, gradle_project], "is:build needle")
    assert response.unavailable == []
    paths = Enum.map(response.results, & &1.path)
    assert "/#{p.account.name}/#{p.name}/builds/build-runs/#{xcode.id}" in paths
    assert "/#{gradle_project.account.name}/#{gradle_project.name}/builds/build-runs/#{gradle}" in paths
    assert [%{path: test_path}] = DashboardSearch.search([p], "is:test-run needle").results
    assert test_path == "/#{p.account.name}/#{p.name}/tests/test-runs/#{run.id}"
  end

  test "provider errors report unavailable types independently without dropping projects or previews" do
    p = project(name: "needle")
    AppBuildsFixtures.preview_fixture(project: p, display_name: "Needle Preview")
    stub(ClickHouseRepo, :query, fn _, _, _ -> {:error, :unavailable} end)
    response = DashboardSearch.search([p], "needle")
    assert response.unavailable == ["test_case"]
    assert Enum.sort(Enum.map(response.results, & &1.type)) == ["preview", "project"]
  end

  test "Bazel, Cargo and Mix use their own public run identifiers and detail routes" do
    p = project(build_system: :bazel)
    cargo = project(build_system: :cargo)
    mix = project(build_system: :mix)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    bazel_id = "opaque-invocation-needle"
    cargo_id = UUIDv7.generate()
    mix_id = UUIDv7.generate()

    IngestRepo.insert_all(Invocation, [
      %{
        id: UUIDv7.generate(),
        invocation_id: bazel_id,
        project_id: p.id,
        command: "build",
        target_patterns: ["//app:needle"],
        inserted_at: now
      }
    ])

    IngestRepo.insert_all(Build, [
      %{id: cargo_id, project_id: cargo.id, command: "needle", inserted_at: now},
      %{id: UUIDv7.generate(), project_id: cargo.id, command: "nextest", git_branch: "needle", inserted_at: now}
    ])

    IngestRepo.insert_all(Tuist.Mix.Build, [
      %{id: mix_id, project_id: mix.id, mix_env: "needle", inserted_at: now}
    ])

    response = DashboardSearch.search([p, cargo, mix], "is:build needle")
    assert response.unavailable == []
    paths = Enum.map(response.results, & &1.path)
    prefix = "/#{p.account.name}/#{p.name}"

    assert Enum.sort(paths) ==
             Enum.sort([
               "#{prefix}/builds/invocations/#{bazel_id}",
               "/#{cargo.account.name}/#{cargo.name}/builds/cargo-builds/#{cargo_id}",
               "/#{mix.account.name}/#{mix.name}/builds/mix-builds/#{mix_id}"
             ])

    assert [%{path: path}] = DashboardSearch.search([p], bazel_id).results
    assert path == "#{prefix}/builds/invocations/#{bazel_id}"
  end

  test "Once builds, tests and case attempts keep native routes and tenant scope" do
    p = project(build_system: :once)
    foreign = project()
    now = DateTime.utc_now()

    for i <- 1..7 do
      Repo.insert!(%Run{
        project_id: p.id,
        run_id: "build-#{i}",
        kind: "build",
        command_display: "needle",
        started_at: now
      })
    end

    run =
      Repo.insert!(%Run{
        project_id: p.id,
        run_id: "test-needle",
        kind: "test",
        command_display: "needle test",
        started_at: now
      })

    Repo.insert!(%Run{
      project_id: foreign.id,
      run_id: run.run_id,
      kind: "test",
      command_display: "needle private",
      started_at: now
    })

    c =
      Repo.insert!(%TestCaseRun{
        project_id: p.id,
        once_run_id: run.id,
        run_id: run.run_id,
        target_execution_id: "target",
        case_id: "case",
        name: "needle case",
        result: "passed",
        module: "NativeModule",
        class_name: "NativeSuite"
      })

    response = DashboardSearch.search([p], "is:build needle")
    assert response.unavailable == []
    assert length(Enum.filter(response.results, &(&1.type == "build"))) == 5
    prefix = "/#{p.account.name}/#{p.name}"
    assert [%{path: path}] = DashboardSearch.search([p], "is:test-run needle").results
    assert path == "#{prefix}/once/test-runs/#{run.run_id}"
    assert [%{path: case_path}] = DashboardSearch.search([p], "NativeSuite").results
    assert case_path == "#{prefix}/once/test-runs/#{run.run_id}/test-cases/#{c.id}"
    assert [%{path: ^case_path}] = DashboardSearch.search([p], case_path).results
  end

  test "run searches are bounded to 30 days even for exact IDs, branches and commits" do
    p = project()
    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -31, :day)
    {:ok, build} = RunsFixtures.build_fixture(project_id: p.id, scheme: "ancientneedle", inserted_at: old)

    {:ok, recent} =
      RunsFixtures.test_fixture(project_id: p.id, git_branch: "feature/branchneedle", git_commit_sha: "abcdef1234")

    assert DashboardSearch.search([p], build.id).results == []
    assert DashboardSearch.search([p], "ancientneedle").results == []
    assert DashboardSearch.search([p], "branch:feature/branchneedle").metadata == %{window_days: 30, per_type_limit: 5}
    assert [%{type: "test_run", path: path}] = DashboardSearch.search([p], "commit:abcdef").results
    assert String.ends_with?(path, recent.id)

    assert DashboardSearch.search([p], "branch:feature/branchneedle").results ==
             DashboardSearch.search([p], "commit:abcdef").results
  end

  test "hostile query remains a literal parameter and SQL reads are globally bounded" do
    p = project()
    test_case(project_id: p.id, name: "'; DROP TABLE test_cases; --")
    # Observe the real query without replacing database behavior.
    stub(ClickHouseRepo, :query, fn sql, params, opts ->
      assert sql =~ "LIMIT 5"
      refute sql =~ "DROP TABLE"
      assert opts[:settings][:max_execution_time] == 2
      assert opts[:settings][:max_rows_to_read] == 1_000_000
      # Picking cases returns the best matches it read, in its own query so it
      # cannot use up the budget of the read that formats them. Every other read
      # stays exact.
      assert opts[:settings][:read_overflow_mode] ==
               if(sql =~ "FROM test_cases" and not (sql =~ "case_ids"), do: "break", else: "throw")

      Mimic.call_original(ClickHouseRepo, :query, [sql, params, opts])
    end)

    response = DashboardSearch.search([p], "'; DROP TABLE test_cases; --")
    assert response.unavailable == []
    assert [%{type: "test_case"}] = response.results
  end

  test "case search treats wildcard characters literally and lists an updated case once" do
    p = project()
    target = test_case(project_id: p.id, name: "test_100%\\Done", inserted_at: ~N[2026-01-01 00:00:00.000000])
    # A newer version of the same case, as each run writes before a merge.
    test_case(project_id: p.id, id: target.id, name: target.name, inserted_at: ~N[2026-01-02 00:00:00.000000])
    # Matches only if `%`, `_` or `\` act as LIKE syntax.
    test_case(project_id: p.id, name: "test_1000_xdone")

    response = DashboardSearch.search([p], "100%\\done")

    assert response.unavailable == []
    assert [%{type: "test_case", path: path}] = response.results
    assert String.ends_with?(path, target.id)

    # ClickHouse lowercases a word-final Σ to ς; Elixir lowercases it to σ.
    greek = test_case(project_id: p.id, name: "ΟΔΟΣ")
    assert [%{type: "test_case", path: greek_path}] = DashboardSearch.search([p], "ΟΔΟΣ").results
    assert String.ends_with?(greek_path, greek.id)
  end

  test "a filter without text still searches test cases" do
    p = project()
    target = test_case(project_id: p.id, name: "testFilterOnly")

    for query <- ["is:test-case", "project:#{p.name}"] do
      response = DashboardSearch.search([p], query)
      assert response.unavailable == []
      assert Enum.any?(response.results, &String.ends_with?(&1.path, target.id))
    end
  end

  test "one failed source leaves other sources of the same type available" do
    p = project()
    gradle = project(build_system: :gradle)
    {:ok, build} = RunsFixtures.build_fixture(project_id: p.id, scheme: "needle")

    stub(ClickHouseRepo, :query, fn sql, params, opts ->
      if sql =~ "FROM gradle_builds" do
        raise "provider down"
      else
        Mimic.call_original(ClickHouseRepo, :query, [sql, params, opts])
      end
    end)

    response = DashboardSearch.search([p, gradle], "is:build needle")
    assert response.unavailable == ["build"]
    assert [%{type: "build", path: path}] = response.results
    assert String.ends_with?(path, build.id)
  end

  test "multi-project search has one batched query per source, not per project" do
    projects = for _ <- 1..6, do: project()
    ref = make_ref()

    stub(ClickHouseRepo, :query, fn sql, params, opts ->
      send(self(), {ref, params.ids})
      Mimic.call_original(ClickHouseRepo, :query, [sql, params, opts])
    end)

    assert DashboardSearch.search(projects, "no-matches").unavailable == []
    ids = Enum.sort(Enum.map(projects, & &1.id))

    # Ordinary words query the case catalog, not UUID-only build/run sources.
    assert_receive {^ref, queried_ids}
    assert Enum.sort(queried_ids) == ids

    refute_receive {^ref, _}
  end

  test "short plain terms stay in memory and expired budgets skip resource providers" do
    p = project(name: "app")
    reject(ClickHouseRepo, :query, 3)
    reject(Repo, :query, 3)

    assert [%{type: "project", title: "app"}] = DashboardSearch.search([p], "ap").results

    result = DashboardSearch.search([p], "app", deadline: System.monotonic_time(:millisecond) - 1)
    assert [%{type: "project", title: "app"}] = result.results
    assert Enum.sort(result.unavailable) == ["preview", "test_case"]
  end

  test "invalid syntax returns a safe error without any database reads or widened suggestions" do
    p = project()
    reject(ClickHouseRepo, :query, 3)
    reject(Repo, :query, 3)

    for query <- [
          "unknown:secret",
          "is:bad",
          "status:success",
          "pr:0",
          "pr:##12",
          "pr:-1",
          "commit:not-a-sha",
          "date:2026-02-30",
          "date:2026-03-02..2026-03-01",
          "is:build is:preview",
          "branch:main branch:other",
          "project:",
          "branch:",
          "\"unfinished",
          "\"\""
        ] do
      assert %{results: [], unavailable: [], metadata: %{window_days: 30}, error: message} =
               DashboardSearch.search([p], query)

      assert is_binary(message)
      refute message =~ "secret"
    end

    assert DashboardSearch.search([p], "is:page settings").results == []
  end

  test "quoted phrases and all free terms AND with exact authorized project names" do
    p = project(name: "named-project")
    other = project(name: "named-project-other")

    target =
      test_case(project_id: p.id, name: "Login with spaces", suite_name: "SessionSuite", module_name: "AccountModule")

    test_case(project_id: p.id, name: "Login with spaces", suite_name: "DifferentSuite")
    test_case(project_id: other.id, name: target.name, suite_name: target.suite_name)

    response =
      DashboardSearch.search([p, other], ~s(is:test-case project:"named-project" "Login with spaces" SessionSuite))

    assert response.unavailable == []
    assert [%{path: path}] = response.results
    assert String.ends_with?(path, target.id)
    assert DashboardSearch.search([p], ~s(is:test-case "Login with spaces" missing)).results == []
    assert DashboardSearch.search([p], "project:named-project-other").results == []
    assert [%{type: "project"}] = DashboardSearch.search([p, other], "is:project project:named-project").results
    test_case(project_id: p.id, name: "Suite::test:with-colons")
    assert [%{type: "test_case"}] = DashboardSearch.search([p], ~s("Suite::test:with-colons")).results
  end

  test "plain text discovers named resources but runs require explicit discovery or exact identity" do
    p = project(name: "needle-project")
    {:ok, build} = RunsFixtures.build_fixture(project_id: p.id, scheme: "needle-build")
    {:ok, run} = RunsFixtures.test_fixture(project_id: p.id, scheme: "needle-tests")
    test_case(project_id: p.id, name: "needle-case")
    AppBuildsFixtures.preview_fixture(project: p, display_name: "needle-preview")

    assert Enum.sort(Enum.map(DashboardSearch.search([p], "needle").results, & &1.type)) == [
             "preview",
             "project",
             "test_case"
           ]

    assert [%{type: "build", path: path}] = DashboardSearch.search([p], build.id).results
    assert String.ends_with?(path, build.id)
    assert [%{type: "build"}] = DashboardSearch.search([p], "#{build.id} needle-build").results
    assert [%{type: "test_run"}] = DashboardSearch.search([p], run.id).results
    assert [%{type: "build"}] = DashboardSearch.search([p], "is:build needle").results
    assert [%{type: "test_run"}] = DashboardSearch.search([p], "is:test-run needle").results
    assert [%{type: "build"}] = DashboardSearch.search([p], path).results
  end

  test "run filters apply together before limits and subtitles carry recognition metadata" do
    p = project()
    other = project()

    for _ <- 1..8,
        do: RunsFixtures.build_fixture(project_id: p.id, scheme: "Release App", git_branch: "wrong", status: "failure")

    {:ok, target} =
      RunsFixtures.build_fixture(
        project_id: p.id,
        scheme: "Release App",
        git_branch: "feature with spaces",
        git_commit_sha: "abcdef123456",
        git_ref: "refs/pull/42/merge",
        status: "failure",
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1, :day)
      )

    RunsFixtures.build_fixture(
      project_id: other.id,
      scheme: "Release App",
      git_branch: "feature with spaces",
      git_commit_sha: "abcdef123456",
      git_ref: "refs/pull/42/merge",
      status: "failure"
    )

    response =
      DashboardSearch.search([p], ~s(is:build "Release App" branch:"feature with spaces" commit:abc status:failed pr:#42))

    assert response.unavailable == []
    assert [%{path: path, subtitle: subtitle}] = response.results
    assert String.ends_with?(path, target.id)
    refute subtitle =~ target.id
    refute subtitle =~ "/#{p.account.name}/#{p.name}"

    for field <- [
          "failed",
          "feature with spaces",
          "abcdef123456",
          "PR #42",
          target.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()
        ],
        do: assert(subtitle =~ field)

    assert DashboardSearch.search([p], ~s(#{target.id} status:passed)).results == []
    assert DashboardSearch.search([p], ~s(#{target.id} status:failed)).results == response.results
    assert DashboardSearch.search([p], "is:test-case branch:wrong").results == []
  end

  test "PR filters use explicit run evidence or recognized refs, not branch or same-commit guesses" do
    p = project()

    {:ok, explicit} =
      RunsFixtures.test_fixture(project_id: p.id, pull_request_number: 81, git_branch: "main", git_commit_sha: "abc123")

    {:ok, from_ref} =
      RunsFixtures.test_fixture(project_id: p.id, git_ref: "refs/merge-requests/81/head", git_commit_sha: "abc123")

    RunsFixtures.test_fixture(project_id: p.id, git_branch: "pr/81", git_commit_sha: "abc123")

    unknown =
      AppBuildsFixtures.preview_fixture(
        project: p,
        display_name: "Unknown PR",
        git_branch: "pr/81",
        git_commit_sha: "abc123"
      )

    known =
      AppBuildsFixtures.preview_fixture(
        project: p,
        display_name: "Known PR",
        git_ref: "refs/pull/81/head",
        git_commit_sha: "abc123"
      )

    response = DashboardSearch.search([p], "pr:81")
    assert response.unavailable == []
    paths = Enum.map(response.results, & &1.path)
    for id <- [explicit.id, from_ref.id, known.id], do: assert(Enum.any?(paths, &String.ends_with?(&1, id)))
    refute Enum.any?(paths, &String.ends_with?(&1, unknown.id))
    assert length(paths) == 3
  end

  test "Bazel and Once never satisfy PR filters and catalogs never borrow run metadata" do
    bazel = project(build_system: :bazel)
    once = project(build_system: :once)
    test_case(project_id: bazel.id, name: "case")
    now = DateTime.utc_now()

    Repo.insert!(%Run{
      project_id: once.id,
      run_id: "pr-22",
      command_display: "pr-22",
      git_branch: "pr/22",
      started_at: now
    })

    stub(ClickHouseRepo, :query, fn sql, params, opts ->
      refute sql =~ "FROM bazel_invocations"
      refute sql =~ "FROM test_cases"
      Mimic.call_original(ClickHouseRepo, :query, [sql, params, opts])
    end)

    assert %{results: [], unavailable: []} = DashboardSearch.search([bazel, once], "pr:22")
  end

  test "UTC dates use half-open days, inclusive ranges and exclusive greater/less calendar days" do
    p = project()
    date = Date.add(Date.utc_today(), -2)
    next = Date.add(date, 1)
    midnight = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    next_midnight = DateTime.add(midnight, 1, :day)
    inside = AppBuildsFixtures.preview_fixture(project: p, display_name: "inside", inserted_at: midnight)
    after_day = AppBuildsFixtures.preview_fixture(project: p, display_name: "after", inserted_at: next_midnight)

    {:ok, build} =
      RunsFixtures.build_fixture(project_id: p.id, inserted_at: DateTime.to_naive(midnight), scheme: "inside")

    {:ok, later} =
      RunsFixtures.build_fixture(project_id: p.id, inserted_at: DateTime.to_naive(next_midnight), scheme: "after")

    response = DashboardSearch.search([p], "date:#{date}")
    assert response.unavailable == []
    assert Enum.sort(Enum.map(response.results, & &1.title)) == ["inside", "inside"]
    assert Enum.any?(response.results, &String.ends_with?(&1.path, inside.id))
    assert Enum.any?(response.results, &String.ends_with?(&1.path, build.id))
    range = DashboardSearch.search([p], "date:#{date}..#{next}")
    assert length(range.results) == 4
    greater = DashboardSearch.search([p], "date:>#{date}")
    assert Enum.sort(Enum.map(greater.results, & &1.title)) == ["after", "after"]
    assert Enum.any?(greater.results, &String.ends_with?(&1.path, after_day.id))
    assert Enum.any?(greater.results, &String.ends_with?(&1.path, later.id))
    assert DashboardSearch.search([p], "date:<#{next}").results == response.results
    assert DashboardSearch.search([p], "date:today").results == []
    assert length(DashboardSearch.search([p], "date:yesterday").results) == 2
  end

  test "native statuses normalize without inventing success for cancelled or unknown runs" do
    xcode = project()
    gradle = project(build_system: :gradle)
    cargo = project(build_system: :cargo)
    mix = project(build_system: :mix)
    bazel = project(build_system: :bazel)
    once = project(build_system: :once)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    RunsFixtures.build_fixture(project_id: xcode.id, status: "processing", scheme: "running")
    GradleFixtures.build_fixture(project_id: gradle.id, status: "failure", root_project_name: "failed")
    GradleFixtures.build_fixture(project_id: gradle.id, status: "cancelled", root_project_name: "cancelled")

    for {schema, p, fields} <- [
          {Build, cargo, %{command: "failed"}},
          {Tuist.Mix.Build, mix, %{mix_env: "failed"}},
          {Invocation, bazel, %{command: "failed", invocation_id: "native-failed"}}
        ] do
      IngestRepo.insert_all(schema, [
        Map.merge(%{id: UUIDv7.generate(), project_id: p.id, status: "failure", inserted_at: now}, fields)
      ])
    end

    Repo.insert!(%Run{
      project_id: once.id,
      run_id: "native-passed",
      command_display: "passed",
      started_at: DateTime.utc_now(),
      finalization: "finalized",
      exit_status: 0
    })

    Repo.insert!(%Run{
      project_id: once.id,
      run_id: "native-running",
      command_display: "running",
      started_at: DateTime.utc_now()
    })

    projects = [xcode, gradle, cargo, mix, bazel, once]
    failed = DashboardSearch.search(projects, "is:build status:failed")
    assert failed.unavailable == []
    assert length(failed.results) == 4
    assert Enum.all?(failed.results, &(&1.subtitle =~ "failed"))
    assert length(DashboardSearch.search(projects, "is:build status:running").results) == 2
    assert [%{title: "passed"}] = DashboardSearch.search(projects, "is:build status:passed").results
    assert DashboardSearch.search(projects, "is:preview status:passed").results == []
  end

  test "Gradle, Cargo and Mix use only their own PR refs and filter before the global cap" do
    gradle = project(build_system: :gradle)
    cargo = project(build_system: :cargo)
    mix = project(build_system: :mix)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    GradleFixtures.build_fixture(project_id: gradle.id, root_project_name: "known", git_ref: "refs/pull/93/merge")
    GradleFixtures.build_fixture(project_id: gradle.id, root_project_name: "unknown", git_branch: "pr/93")

    for {schema, p, label} <- [{Build, cargo, :command}, {Tuist.Mix.Build, mix, :mix_env}] do
      for _ <- 1..7 do
        IngestRepo.insert_all(schema, [
          %{id: UUIDv7.generate(), project_id: p.id, inserted_at: now, git_branch: "pr/93", git_commit_sha: "abc123"}
        ])
      end

      attrs = %{
        id: UUIDv7.generate(),
        project_id: p.id,
        inserted_at: now,
        git_ref: "refs/merge-requests/93/head",
        git_commit_sha: "abc123"
      }

      IngestRepo.insert_all(schema, [Map.put(attrs, label, "known")])
    end

    response = DashboardSearch.search([gradle, cargo, mix], "is:build pr:93")
    assert response.unavailable == []
    assert length(response.results) == 3
    assert Enum.all?(response.results, &(&1.title == "known" and &1.subtitle =~ "PR #93"))
  end

  test "shared test-run filters honor status and exact ID together and exclude catalog identities" do
    p = project()

    {:ok, run} =
      RunsFixtures.test_fixture(
        project_id: p.id,
        status: "failure",
        scheme: "NativeTests",
        git_branch: "release",
        git_commit_sha: "123abc"
      )

    test_case(project_id: p.id, name: "NativeTests")

    assert [%{type: "test_run", subtitle: subtitle}] =
             DashboardSearch.search([p], "is:test-run status:failed branch:release commit:123 NativeTests").results

    assert subtitle =~ "failed"
    assert DashboardSearch.search([p], "#{run.id} status:passed").results == []
    assert [%{type: "test_run"}] = DashboardSearch.search([p], "#{run.id} status:failed").results
  end
end
