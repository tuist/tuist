defmodule Tuist.BuildsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Builds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "create_build/1" do
    test "creates a build" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      # When
      {:ok, build} =
        Builds.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: []
        })

      # Then
      assert build.duration == 1000
      assert build.macos_version == "11.2.3"
      assert build.xcode_version == "12.4"
      assert build.is_ci == false
      assert build.model_identifier == "Mac15,6"
      assert build.scheme == "App"
      assert build.project_id == project_id
      assert build.account_id == account_id
      assert build.status == :success
    end

    test "creates a build with cacheable tasks and calculates counts correctly" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      cacheable_tasks = [
        %{type: :swift, status: :hit_local, key: "task1"},
        %{type: :swift, status: :hit_remote, key: "task2"},
        %{type: :clang, status: :miss, key: "task3"},
        %{type: :swift, status: :hit_local, key: "task4"},
        %{type: :clang, status: :hit_remote, key: "task5"}
      ]

      # When
      {:ok, build} =
        Builds.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: [],
          cacheable_tasks: cacheable_tasks
        })

      # Then
      assert build.cacheable_tasks_count == 5
      assert build.cacheable_task_local_hits_count == 2
      assert build.cacheable_task_remote_hits_count == 2
    end

    test "creates a build with empty cacheable tasks" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      # When
      {:ok, build} =
        Builds.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: [],
          cacheable_tasks: []
        })

      # Then
      assert build.cacheable_tasks_count == 0
      assert build.cacheable_task_local_hits_count == 0
      assert build.cacheable_task_remote_hits_count == 0
    end
  end

  describe "get_build/1" do
    test "returns build" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture()

      build_id = build.id

      # When
      build = Builds.get_build(build_id)

      # Then
      assert build.id == build_id
    end

    test "returns nil when build does not exist" do
      # Given
      non_existent_build_id = UUIDv7.generate()

      # When
      build = Builds.get_build(non_existent_build_id)

      # Then
      assert build == nil
    end
  end

  describe "project_build_tags/1" do
    test "returns unique tags from project builds" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      {:ok, _build1} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_tags: ["nightly", "release"]
        )

      {:ok, _build2} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_tags: ["nightly", "staging"]
        )

      # When
      tags = Builds.project_build_tags(project)

      # Then
      assert "nightly" in tags
      assert "release" in tags
      assert "staging" in tags
      assert length(tags) == 3
    end

    test "returns empty list when no builds have tags" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      tags = Builds.project_build_tags(project)

      # Then
      assert tags == []
    end

    test "excludes builds older than 30 days" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      old_date = DateTime.add(DateTime.utc_now(), -31, :day)

      {:ok, _old_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_tags: ["old-tag"],
          inserted_at: old_date
        )

      {:ok, _recent_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_tags: ["recent-tag"]
        )

      # When
      tags = Builds.project_build_tags(project)

      # Then
      assert "recent-tag" in tags
      refute "old-tag" in tags
    end
  end

  describe "list_build_runs/2 with custom_values filter" do
    test "returns all builds when custom_values is nil" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_values: %{"ticket" => "PROJ-1234"}
        )

      # When
      {builds, _meta} =
        Builds.list_build_runs(
          %{filters: [%{field: :project_id, op: :==, value: project.id}]},
          custom_values: nil
        )

      # Then
      assert length(builds) == 1
      assert hd(builds).id == build.id
    end

    test "returns all builds when custom_values is empty" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_values: %{"ticket" => "PROJ-1234"}
        )

      # When
      {builds, _meta} =
        Builds.list_build_runs(
          %{filters: [%{field: :project_id, op: :==, value: project.id}]},
          custom_values: %{}
        )

      # Then
      assert length(builds) == 1
      assert hd(builds).id == build.id
    end

    test "filters builds by custom_values" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      {:ok, matching_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_values: %{"ticket" => "PROJ-1234", "runner" => "macos-14"}
        )

      {:ok, _non_matching_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_values: %{"ticket" => "PROJ-5678"}
        )

      # When
      {builds, _meta} =
        Builds.list_build_runs(
          %{filters: [%{field: :project_id, op: :==, value: project.id}]},
          custom_values: %{"ticket" => "PROJ-1234"}
        )

      # Then
      assert length(builds) == 1
      assert hd(builds).id == matching_build.id
    end

    test "filters by multiple custom_values using AND logic" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      {:ok, matching_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_values: %{"ticket" => "PROJ-1234", "runner" => "macos-14"}
        )

      {:ok, _partial_match} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account_id,
          custom_values: %{"ticket" => "PROJ-1234", "runner" => "macos-13"}
        )

      # When
      {builds, _meta} =
        Builds.list_build_runs(
          %{filters: [%{field: :project_id, op: :==, value: project.id}]},
          custom_values: %{"ticket" => "PROJ-1234", "runner" => "macos-14"}
        )

      # Then
      assert length(builds) == 1
      assert hd(builds).id == matching_build.id
    end
  end

  describe "list_build_runs/1" do
    test "lists build runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      project_two = ProjectsFixtures.project_fixture()

      {:ok, build_one} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          inserted_at: ~U[2024-03-04 01:00:00Z]
        )

      RunsFixtures.build_fixture(project_id: project_two.id)

      {:ok, build_two} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          inserted_at: ~U[2024-03-04 02:00:00Z]
        )

      # When
      {got_builds_first_page, got_meta_first_page} =
        Builds.list_build_runs(%{
          page_size: 1,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:inserted_at],
          order_directions: [:desc]
        })

      {got_builds_second_page, _meta} =
        Builds.list_build_runs(Flop.to_next_page(got_meta_first_page.flop))

      # Then
      assert Enum.map(got_builds_first_page, & &1.id) == [build_two.id]
      assert Enum.map(got_builds_second_page, & &1.id) == [build_one.id]
    end
  end

  describe "project_build_schemes/1" do
    test "returns distinct schemes for the given project within the last 30 days" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      # Create builds with different schemes for the project
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "Framework",
        inserted_at: DateTime.utc_now()
      )

      # Create another build with a duplicate scheme (should be de-duped in the result)
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        inserted_at: DateTime.utc_now()
      )

      # Create a build with nil scheme (should be excluded)
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: nil,
        inserted_at: DateTime.utc_now()
      )

      # Create a build for another project (should be excluded)
      RunsFixtures.build_fixture(
        project_id: other_project.id,
        scheme: "OtherApp",
        inserted_at: DateTime.utc_now()
      )

      # Create a build older than 30 days (should be excluded)
      old_date = DateTime.add(DateTime.utc_now(), -31, :day)

      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "OldScheme",
        inserted_at: old_date
      )

      # When
      schemes = Builds.project_build_schemes(project)

      # Then
      assert Enum.sort(schemes) == ["App", "Framework"]
    end

    test "returns an empty list when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      schemes = Builds.project_build_schemes(project)

      # Then
      assert schemes == []
    end

    test "returns an empty list when only no schemes exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create a build with nil scheme
      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          scheme: nil,
          inserted_at: DateTime.utc_now()
        )

      # When
      schemes = Builds.project_build_schemes(project)

      # Then
      assert schemes == []
    end
  end

  describe "project_build_configurations/1" do
    test "returns distinct configurations for the given project within the last 30 days" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "Debug",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "Release",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "Debug",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: nil,
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: other_project.id,
        configuration: "Beta",
        inserted_at: DateTime.utc_now()
      )

      old_date = DateTime.add(DateTime.utc_now(), -31, :day)

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "OldConfiguration",
        inserted_at: old_date
      )

      # When
      configurations = Builds.project_build_configurations(project)

      # Then
      assert Enum.sort(configurations) == ["Debug", "Release"]
    end

    test "returns an empty list when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      configurations = Builds.project_build_configurations(project)

      # Then
      assert configurations == []
    end

    test "returns an empty list when only no configurations exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create a build with nil configuration
      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          configuration: nil,
          inserted_at: DateTime.utc_now()
        )

      # When
      configurations = Builds.project_build_configurations(project)

      # Then
      assert configurations == []
    end
  end

  describe "recent_build_status_counts/2" do
    test "returns counts of successful and failed builds for the most recent builds" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 04:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: other_project.id,
        status: "failure",
        inserted_at: ~U[2024-01-01 05:00:00Z]
      )

      # When
      result = Builds.recent_build_status_counts(project.id, limit: 3)

      # Then
      assert result.successful_count == 2
      assert result.failed_count == 1
    end

    test "returns zero counts when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Builds.recent_build_status_counts(project.id)

      # Then
      assert result.successful_count == 0
      assert result.failed_count == 0
    end

    test "uses default limit of 40 when not specified" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for i <- 1..45 do
        status = if rem(i, 2) == 0, do: :success, else: :failure

        RunsFixtures.build_fixture(
          project_id: project.id,
          status: status,
          inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], i, :minute)
        )
      end

      # When
      result = Builds.recent_build_status_counts(project.id)

      # Then
      assert result.successful_count == 20
      assert result.failed_count == 20
    end

    test "respects custom limit parameter" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for i <- 1..10 do
        status = if i <= 5, do: :success, else: :failure

        RunsFixtures.build_fixture(
          project_id: project.id,
          status: status,
          inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], i, :minute)
        )
      end

      # When
      result = Builds.recent_build_status_counts(project.id, limit: 5)

      # Then
      assert result.successful_count == 0
      assert result.failed_count == 5
    end

    test "orders by inserted_at descending to get most recent builds" do
      # Given
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      # When
      result = Builds.recent_build_status_counts(project.id, limit: 2)

      # Then
      assert result.successful_count == 1
      assert result.failed_count == 1
    end
  end

  test "returns counts of successful and failed builds ordered by insertion time ascending" do
    # Given
    project = ProjectsFixtures.project_fixture()
    other_project = ProjectsFixtures.project_fixture()

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 01:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "failure",
      inserted_at: ~U[2024-01-01 02:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 03:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 04:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: other_project.id,
      status: "failure",
      inserted_at: ~U[2024-01-01 05:00:00Z]
    )

    # When
    result = Builds.recent_build_status_counts(project.id, limit: 3, order: :asc)

    # Then
    assert result.successful_count == 2
    assert result.failed_count == 1
  end

  test "supports ascending order with custom limit" do
    # Given
    project = ProjectsFixtures.project_fixture()

    for i <- 1..10 do
      status = if i <= 5, do: :success, else: :failure

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: status,
        inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], i, :minute)
      )
    end

    # When
    result = Builds.recent_build_status_counts(project.id, limit: 5, order: :asc)

    # Then
    assert result.successful_count == 5
    assert result.failed_count == 0
  end

  test "orders by inserted_at ascending to get earliest builds" do
    # Given
    project = ProjectsFixtures.project_fixture()

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 03:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "failure",
      inserted_at: ~U[2024-01-01 01:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 02:00:00Z]
    )

    # When
    result = Builds.recent_build_status_counts(project.id, limit: 2, order: :asc)

    # Then
    assert result.successful_count == 1
    assert result.failed_count == 1
  end

  describe "list_cacheable_tasks/1" do
    test "lists cacheable tasks with pagination" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{type: :swift, status: :hit_local, key: "task1"},
            %{type: :swift, status: :hit_remote, key: "task2"},
            %{type: :clang, status: :miss, key: "task3"},
            %{type: :swift, status: :hit_local, key: "task4"}
          ]
        )

      # When
      {tasks, meta} =
        Builds.list_cacheable_tasks(%{
          page_size: 2,
          filters: [%{field: :build_run_id, op: :==, value: build.id}]
        })

      # Then
      assert length(tasks) == 2
      assert meta.total_count == 4
      assert meta.total_pages == 2
    end

    test "lists cacheable tasks with filters" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{type: :swift, status: :hit_local, key: "swift_task"},
            %{type: :clang, status: :hit_remote, key: "clang_task"},
            %{type: :swift, status: :miss, key: "another_swift"}
          ]
        )

      # When - filter by type
      {swift_tasks, _meta} =
        Builds.list_cacheable_tasks(%{
          filters: [
            %{field: :build_run_id, op: :==, value: build.id},
            %{field: :type, op: :==, value: "swift"}
          ]
        })

      # Then
      assert length(swift_tasks) == 2
      assert Enum.all?(swift_tasks, &(&1.type == "swift"))
    end

    test "lists cacheable tasks with sorting by key ascending" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{type: :swift, status: :hit_local, key: "zebra_task"},
            %{type: :swift, status: :hit_remote, key: "alpha_task"},
            %{type: :clang, status: :miss, key: "beta_task"}
          ]
        )

      # When
      {tasks, _meta} =
        Builds.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}],
          order_by: [:key],
          order_directions: [:asc]
        })

      # Then
      keys = Enum.map(tasks, & &1.key)
      assert keys == ["alpha_task", "beta_task", "zebra_task"]
    end

    test "returns empty list when no cacheable tasks exist for build" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture(cacheable_tasks: [])

      # When
      {tasks, meta} =
        Builds.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}]
        })

      # Then
      assert tasks == []
      assert meta.total_count == 0
    end
  end

  describe "build_ci_run_url/1" do
    test "returns GitHub Actions URL for GitHub provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :github,
          ci_run_id: "123456789",
          ci_project_handle: "owner/repo"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://github.com/owner/repo/actions/runs/123456789"
    end

    test "returns GitLab CI URL for GitLab provider with default host" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :gitlab,
          ci_run_id: "987654321",
          ci_project_handle: "namespace/project",
          ci_host: nil
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://gitlab.com/namespace/project/-/pipelines/987654321"
    end

    test "returns GitLab CI URL for GitLab provider with custom host" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :gitlab,
          ci_run_id: "987654321",
          ci_project_handle: "namespace/project",
          ci_host: "gitlab.example.com"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://gitlab.example.com/namespace/project/-/pipelines/987654321"
    end

    test "returns Bitrise URL for Bitrise provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :bitrise,
          ci_run_id: "build-slug-123",
          ci_project_handle: "app-slug-456"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://app.bitrise.io/build/build-slug-123"
    end

    test "returns CircleCI URL for CircleCI provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :circleci,
          ci_run_id: "42",
          ci_project_handle: "owner/project"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://app.circleci.com/pipelines/github/owner/project/42"
    end

    test "returns Buildkite URL for Buildkite provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :buildkite,
          ci_run_id: "1234",
          ci_project_handle: "org/pipeline"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://buildkite.com/org/pipeline/builds/1234"
    end

    test "returns Codemagic URL for Codemagic provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :codemagic,
          ci_run_id: "build-id-123",
          ci_project_handle: "project-id-456"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == "https://codemagic.io/app/project-id-456/build/build-id-123"
    end

    test "returns nil when ci_provider is nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: nil,
          ci_run_id: "123",
          ci_project_handle: "owner/repo"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == nil
    end

    test "returns nil when ci_run_id is nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :github,
          ci_run_id: nil,
          ci_project_handle: "owner/repo"
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == nil
    end

    test "returns nil when ci_project_handle is nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :github,
          ci_run_id: "123",
          ci_project_handle: nil
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == nil
    end

    test "returns nil when all CI fields are nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: nil,
          ci_run_id: nil,
          ci_project_handle: nil,
          ci_host: nil
        )

      # When
      url = Builds.build_ci_run_url(build)

      # Then
      assert url == nil
    end
  end

  describe "cas_output_metrics/1" do
    test "returns correct metrics for build with CAS outputs" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node3",
              checksum: "ghi789",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :upload,
              type: :swift
            }
          ]
        )

      # When
      metrics = Builds.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 1
      assert metrics.download_bytes == 4000
      assert metrics.upload_bytes == 2000
      assert metrics.time_weighted_avg_download_throughput == 1000.0
      assert metrics.time_weighted_avg_upload_throughput == 1000.0
    end

    test "returns zeros for build with no CAS outputs" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture(cas_outputs: [])

      # When
      metrics = Builds.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 0
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 0
      assert metrics.upload_bytes == 0
      assert metrics.time_weighted_avg_download_throughput == 0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "returns zeros for non-existent build" do
      # Given
      non_existent_build_id = UUIDv7.generate()

      # When
      metrics = Builds.cas_output_metrics(non_existent_build_id)

      # Then
      assert metrics.download_count == 0
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 0
      assert metrics.upload_bytes == 0
      assert metrics.time_weighted_avg_download_throughput == 0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "handles only download operations" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 5000,
              duration: 5000,
              compressed_size: 4000,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 10_000,
              duration: 10_000,
              compressed_size: 8000,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      metrics = Builds.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 15_000
      assert metrics.upload_bytes == 0
      # Time-weighted average: (5000 + 10000) / (5000 + 10000) * 1000 = 1000 bytes/s
      assert metrics.time_weighted_avg_download_throughput == 1000.0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "handles only upload operations" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 8000,
              duration: 4000,
              compressed_size: 6400,
              operation: :upload,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 12_000,
              duration: 6000,
              compressed_size: 9600,
              operation: :upload,
              type: :swift
            }
          ]
        )

      # When
      metrics = Builds.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 0
      assert metrics.upload_count == 2
      assert metrics.download_bytes == 0
      assert metrics.upload_bytes == 20_000
      assert metrics.time_weighted_avg_download_throughput == 0
      # Time-weighted average: (8000 + 12000) / (4000 + 6000) * 1000 = 2000 bytes/s
      assert metrics.time_weighted_avg_upload_throughput == 2000.0
    end

    test "ignores operations with zero duration for throughput calculation" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 1000,
              duration: 0,
              compressed_size: 800,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      metrics = Builds.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 3000
      assert metrics.upload_bytes == 0
      # Only the second operation (duration > 0) is included in throughput
      # Time-weighted average: 2000 / 2000 * 1000 = 1000 bytes/s
      assert metrics.time_weighted_avg_download_throughput == 1000.0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "handles mixed operations with different throughputs" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 10_000,
              duration: 10_000,
              compressed_size: 8000,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 20_000,
              duration: 4000,
              compressed_size: 16_000,
              operation: :upload,
              type: :swift
            },
            %{
              node_id: "node3",
              checksum: "ghi789",
              size: 15_000,
              duration: 5000,
              compressed_size: 12_000,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      metrics = Builds.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 1
      assert metrics.download_bytes == 25_000
      assert metrics.upload_bytes == 20_000
      # Download throughput: (10000 + 15000) / (10000 + 5000) * 1000 = 1666.67 bytes/s
      assert_in_delta metrics.time_weighted_avg_download_throughput, 1666.67, 0.1
      # Upload throughput: 20000 / 4000 * 1000 = 5000 bytes/s
      assert metrics.time_weighted_avg_upload_throughput == 5000.0
    end
  end

  describe "cacheable_task_latency_metrics/1" do
    test "returns correct metrics for build with cacheable tasks with durations" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{
              type: :swift,
              status: :hit_local,
              key: "task1",
              read_duration: 100.0,
              write_duration: nil
            },
            %{
              type: :swift,
              status: :miss,
              key: "task2",
              read_duration: nil,
              write_duration: 200.0
            },
            %{
              type: :clang,
              status: :hit_remote,
              key: "task3",
              read_duration: 150.0,
              write_duration: 250.0
            },
            %{
              type: :swift,
              status: :hit_local,
              key: "task4",
              read_duration: 200.0,
              write_duration: 300.0
            }
          ]
        )

      # When
      metrics = Builds.cacheable_task_latency_metrics(build.id)

      # Then
      assert metrics.avg_read_duration == 150.0
      assert metrics.avg_write_duration == 250.0
      assert metrics.p99_read_duration == 199.0
      assert metrics.p99_write_duration == 299.0
      assert metrics.p90_read_duration == 190.0
      assert metrics.p90_write_duration == 290.0
      assert metrics.p50_read_duration == 150.0
      assert metrics.p50_write_duration == 250.0
    end

    test "returns zeros for build with no cacheable tasks" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture(cacheable_tasks: [])

      # When
      metrics = Builds.cacheable_task_latency_metrics(build.id)

      # Then
      assert metrics.avg_read_duration == 0
      assert metrics.avg_write_duration == 0
      assert metrics.p99_read_duration == 0
      assert metrics.p99_write_duration == 0
      assert metrics.p90_read_duration == 0
      assert metrics.p90_write_duration == 0
      assert metrics.p50_read_duration == 0
      assert metrics.p50_write_duration == 0
    end
  end

  describe "get_cas_outputs_by_node_ids/3" do
    test "returns CAS outputs matching the given node_ids" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 1000,
              duration: 100,
              compressed_size: 800,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 2000,
              duration: 200,
              compressed_size: 1600,
              operation: :upload,
              type: :swift
            },
            %{
              node_id: "node3",
              checksum: "ghi789",
              size: 3000,
              duration: 300,
              compressed_size: 2400,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      outputs = Builds.get_cas_outputs_by_node_ids(build.id, ["node1", "node3"])

      # Then
      assert length(outputs) == 2
      node_ids = Enum.map(outputs, & &1.node_id)
      assert "node1" in node_ids
      assert "node3" in node_ids
      refute "node2" in node_ids
    end

    test "returns empty list when node_ids is empty" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 1000,
              duration: 100,
              compressed_size: 800,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      outputs = Builds.get_cas_outputs_by_node_ids(build.id, [])

      # Then
      assert outputs == []
    end

    test "returns all CAS outputs" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      {:ok, _output1} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :download)
      {:ok, _output2} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :upload)
      {:ok, _output3} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node2", operation: :download)

      # When
      outputs = Builds.get_cas_outputs_by_node_ids(build.id, ["node1", "node2"])

      # Then
      assert length(outputs) == 3
      node_ids = Enum.map(outputs, & &1.node_id)
      assert Enum.count(node_ids, &(&1 == "node1")) == 2
      assert Enum.count(node_ids, &(&1 == "node2")) == 1
    end

    test "returns only distinct CAS outputs by node_id when distinct is true" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      {:ok, _output1} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :download)
      {:ok, _output2} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :upload)
      {:ok, _output3} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node2", operation: :download)
      {:ok, _output4} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node2", operation: :upload)

      # When
      outputs = Builds.get_cas_outputs_by_node_ids(build.id, ["node1", "node2"], distinct: true)

      # Then
      assert length(outputs) == 2
      node_ids = Enum.map(outputs, & &1.node_id)
      assert "node1" in node_ids
      assert "node2" in node_ids
    end
  end
end
