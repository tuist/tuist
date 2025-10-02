defmodule Tuist.RunsTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Runs
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
        Runs.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: :success,
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
  end

  describe "build/1" do
    test "returns build" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture()

      build_id = build.id

      # When
      build = Runs.get_build(build_id)

      # Then
      assert build.id == build_id
    end

    test "returns nil when build does not exist" do
      # Given
      non_existent_build_id = UUIDv7.generate()

      # When
      build = Runs.get_build(non_existent_build_id)

      # Then
      assert build == nil
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
        Runs.list_build_runs(%{
          page_size: 1,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:inserted_at],
          order_directions: [:desc]
        })

      {got_builds_second_page, _meta} =
        Runs.list_build_runs(Flop.to_next_page(got_meta_first_page.flop))

      # Then
      assert got_builds_first_page == [Repo.reload(build_two)]
      assert got_builds_second_page == [Repo.reload(build_one)]
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
      schemes = Runs.project_build_schemes(project)

      # Then
      assert schemes == ["App", "Framework"]
    end

    test "returns an empty list when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      schemes = Runs.project_build_schemes(project)

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
      schemes = Runs.project_build_schemes(project)

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
      configurations = Runs.project_build_configurations(project)

      # Then
      assert Enum.sort(configurations) == ["Debug", "Release"]
    end

    test "returns an empty list when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      configurations = Runs.project_build_configurations(project)

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
      configurations = Runs.project_build_configurations(project)

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
        status: :success,
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: :failure,
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-01-01 04:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: other_project.id,
        status: :failure,
        inserted_at: ~U[2024-01-01 05:00:00Z]
      )

      # When
      result = Runs.recent_build_status_counts(project.id, limit: 3)

      # Then
      assert result.successful_count == 2
      assert result.failed_count == 1
    end

    test "returns zero counts when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Runs.recent_build_status_counts(project.id)

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
      result = Runs.recent_build_status_counts(project.id)

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
      result = Runs.recent_build_status_counts(project.id, limit: 5)

      # Then
      assert result.successful_count == 0
      assert result.failed_count == 5
    end

    test "orders by inserted_at descending to get most recent builds" do
      # Given
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: :failure,
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: :success,
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      # When
      result = Runs.recent_build_status_counts(project.id, limit: 2)

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
      status: :success,
      inserted_at: ~U[2024-01-01 01:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: :failure,
      inserted_at: ~U[2024-01-01 02:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: :success,
      inserted_at: ~U[2024-01-01 03:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: :success,
      inserted_at: ~U[2024-01-01 04:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: other_project.id,
      status: :failure,
      inserted_at: ~U[2024-01-01 05:00:00Z]
    )

    # When
    result = Runs.recent_build_status_counts(project.id, limit: 3, order: :asc)

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
    result = Runs.recent_build_status_counts(project.id, limit: 5, order: :asc)

    # Then
    assert result.successful_count == 5
    assert result.failed_count == 0
  end

  test "orders by inserted_at ascending to get earliest builds" do
    # Given
    project = ProjectsFixtures.project_fixture()

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: :success,
      inserted_at: ~U[2024-01-01 03:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: :failure,
      inserted_at: ~U[2024-01-01 01:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: :success,
      inserted_at: ~U[2024-01-01 02:00:00Z]
    )

    # When
    result = Runs.recent_build_status_counts(project.id, limit: 2, order: :asc)

    # Then
    assert result.successful_count == 1
    assert result.failed_count == 1
  end
end
