defmodule Tuist.Builds.StepsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds.Steps
  alias TuistTestSupport.Fixtures.RunsFixtures

  @step %{
    event_id: 1,
    title: "Compile App.swift",
    project: "Workspace",
    target: "App",
    category: "swiftCompilation",
    start_ms: 100.25,
    duration_ms: 200.5,
    status: "success",
    log: "swiftc App.swift",
    log_truncated: false
  }

  test "deduplicates retries, isolates builds and omits logs from lists" do
    {:ok, build} = RunsFixtures.build_fixture(build_steps: [@step, @step])
    {:ok, other} = RunsFixtures.build_fixture(build_steps: [%{@step | title: "Other.swift"}])

    assert {:ok, %{steps: [step], availability: "available", pagination_metadata: %{total_count: 1}}} = Steps.list(build)
    assert step.id == "1"
    assert step.title == "Compile App.swift"
    assert step.project == "Workspace"
    assert step.target == "App"
    refute Map.has_key?(step, :log)
    refute Map.has_key?(step, :log_truncated)
    assert {:ok, %{title: "Other.swift"}} = Steps.get(other.id, "1")
  end

  test "preserves UInt64 IDs and returns recorded logs and truncation" do
    {:ok, build} =
      RunsFixtures.build_fixture(
        build_steps: [
          %{@step | event_id: 18_446_744_073_709_551_615, log_truncated: true}
        ]
      )

    assert {:ok, %{steps: [%{id: id}]}} = Steps.list(build)
    assert id == "18446744073709551615"
    assert {:ok, %{id: ^id, log: "swiftc App.swift", log_truncated: true}} = Steps.get(build.id, id)
    assert {:error, :not_found} = Steps.get(Ecto.UUID.generate(), id)
    assert {:error, :not_found} = Steps.get(build.id, "1")
  end

  test "orders and paginates stably across equal durations and starts" do
    {:ok, build} =
      RunsFixtures.build_fixture(
        build_steps: [
          %{@step | event_id: 3, duration_ms: 2.0},
          %{@step | event_id: 2},
          @step
        ]
      )

    assert {:ok, %{steps: [%{id: "1"}], pagination_metadata: metadata}} = Steps.list(build, %{page_size: 1})

    assert metadata == %{
             current_page: 1,
             page_size: 1,
             total_count: 3,
             total_pages: 3,
             has_next_page: true,
             has_previous_page: false
           }

    assert {:ok, %{steps: [%{id: "2"}]}} = Steps.list(build, %{page: 2, page_size: 1})

    assert {:ok, %{steps: [%{id: "3"}], pagination_metadata: %{has_next_page: false, has_previous_page: true}}} =
             Steps.list(build, %{page: 3, page_size: 1})

    assert {:ok, %{steps: steps}} = Steps.list(build, %{sort_by: "start_ms"})
    assert Enum.map(steps, & &1.id) == ["1", "2", "3"]
    assert {:ok, %{steps: []}} = Steps.list(build, %{page: 4, page_size: 1})
  end

  test "combines search, exact metadata and overlapping time filters" do
    {:ok, build} =
      RunsFixtures.build_fixture(
        build_steps: [
          @step,
          %{@step | event_id: 2, start_ms: 250.0, duration_ms: 10.0, status: "failure"},
          %{@step | event_id: 3, target: "Library", project: "Package", category: "linker"}
        ]
      )

    filters = %{
      search: "APP.SWIFT",
      project: "Workspace",
      target: "App",
      category: "swiftCompilation",
      status: "success",
      start_ms: 200,
      end_ms: 250
    }

    assert {:ok, %{steps: [%{id: "1"}], pagination_metadata: %{total_count: 1}}} = Steps.list(build, filters)
    assert {:ok, %{steps: [%{id: "2"}]}} = Steps.list(build, %{status: "failure"})
    assert {:ok, %{steps: [%{id: "3"}]}} = Steps.list(build, %{search: "PACKAGE"})
    assert {:ok, %{steps: [%{id: "3"}]}} = Steps.list(build, %{search: "library"})
    assert {:ok, %{steps: []}} = Steps.list(build, %{target: "app"})
  end

  test "excludes steps ending at the lower bound but includes zero-duration steps within the range" do
    {:ok, build} =
      RunsFixtures.build_fixture(
        build_steps: [
          %{@step | start_ms: 0.0, duration_ms: 100.0},
          %{@step | event_id: 2, start_ms: 100.0, duration_ms: 0.0},
          %{@step | event_id: 3, start_ms: 200.0, duration_ms: 0.0}
        ]
      )

    assert {:ok, %{steps: [%{id: "2"}]}} = Steps.list(build, %{start_ms: 100, end_ms: 200})
  end

  test "distinguishes unavailable data from processing and empty search results" do
    {:ok, empty} = RunsFixtures.build_fixture()
    assert {:ok, %{steps: [], availability: "unavailable"}} = Steps.list(empty)
    assert {:ok, %{steps: [], availability: "processing"}} = Steps.list(%{empty | status: "processing"})
    {:ok, build} = RunsFixtures.build_fixture(build_steps: [@step])
    assert {:ok, %{steps: [], availability: "available"}} = Steps.list(build, %{search: "not recorded"})
  end

  test "rejects invalid pagination, filters, ranges and IDs before querying" do
    for filters <- [
          %{page: 0},
          %{page: 100_001},
          %{page_size: 0},
          %{page_size: 101},
          %{page_size: "bad"},
          %{start_ms: -1},
          %{end_ms: -1},
          %{status: "bad"},
          %{sort_by: "log"},
          %{search: String.duplicate("x", 513)}
        ] do
      assert {:error, :invalid_filters} = Steps.list(%{}, filters)
    end

    for end_ms <- [9, 10] do
      assert {:error, :invalid_range} = Steps.list(%{}, %{start_ms: 10, end_ms: end_ms})
    end

    for id <- [nil, 1, "", "+1", "-1", "1a", "18446744073709551616", String.duplicate("1", 21)] do
      assert {:error, :invalid_step_id} = Steps.get(nil, id)
    end
  end
end
