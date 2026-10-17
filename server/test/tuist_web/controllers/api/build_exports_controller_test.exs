defmodule TuistWeb.API.BuildExportsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Builds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{
      conn: Authentication.put_current_user(conn, user),
      project: project,
      path: "/api/projects/#{user.account.name}/#{project.name}/xcode/builds"
    }
  end

  test "paginates tied timestamps in both directions while new builds arrive", %{conn: conn, project: project, path: path} do
    builds =
      for _ <- 1..5 do
        {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, inserted_at: ~N[2026-10-14 09:30:15.123456])
        build
      end

    RunsFixtures.build_fixture(inserted_at: ~N[2026-10-14 09:30:15.123456])

    expected_ids =
      conn
      |> get(path, page_size: 1000)
      |> json_response(:ok)
      |> Map.fetch!("builds")
      |> Enum.map(& &1["id"])

    assert MapSet.new(expected_ids) == MapSet.new(builds, & &1.id)
    first = conn |> get(path, page_size: 2) |> json_response(:ok)
    assert Enum.map(first["builds"], & &1["id"]) == Enum.take(expected_ids, 2)
    assert first["pagination_metadata"]["has_next_page"]
    refute first["pagination_metadata"]["has_previous_page"]
    assert first["pagination_metadata"]["current_page"] == 1
    assert first["pagination_metadata"]["total_count"] == 5
    assert first["pagination_metadata"]["total_pages"] == 3

    explicit_first = conn |> get(path, page: 1, page_size: 2) |> json_response(:ok)
    assert explicit_first["builds"] == first["builds"]

    assert Map.drop(explicit_first["pagination_metadata"], ["start_cursor", "end_cursor"]) ==
             Map.drop(first["pagination_metadata"], ["start_cursor", "end_cursor"])

    assert explicit_first["pagination_metadata"]["start_cursor"] == nil
    assert explicit_first["pagination_metadata"]["end_cursor"] == nil

    assert {:ok, %{inserted_at: ~N[2026-10-14 09:30:15.123456]}} =
             Flop.Cursor.decode(first["pagination_metadata"]["end_cursor"])

    RunsFixtures.build_fixture(project_id: project.id, inserted_at: ~N[2026-10-14 09:31:00.000000])
    second = conn |> get(path, page_size: 2, after: first["pagination_metadata"]["end_cursor"]) |> json_response(:ok)
    assert Enum.map(second["builds"], & &1["id"]) == Enum.slice(expected_ids, 2, 2)
    assert second["pagination_metadata"]["has_next_page"]
    assert second["pagination_metadata"]["has_previous_page"]
    assert second["pagination_metadata"]["current_page"] == nil
    assert second["pagination_metadata"]["total_count"] == nil
    assert second["pagination_metadata"]["total_pages"] == nil

    third = conn |> get(path, page_size: 2, after: second["pagination_metadata"]["end_cursor"]) |> json_response(:ok)
    assert Enum.map(third["builds"], & &1["id"]) == Enum.drop(expected_ids, 4)
    refute third["pagination_metadata"]["has_next_page"]
    previous = conn |> get(path, page_size: 2, before: third["pagination_metadata"]["start_cursor"]) |> json_response(:ok)
    assert Enum.map(previous["builds"], & &1["id"]) == Enum.map(second["builds"], & &1["id"])

    empty = conn |> get(path, page_size: 2, after: third["pagination_metadata"]["end_cursor"]) |> json_response(:ok)
    assert empty["builds"] == []
    assert empty["pagination_metadata"]["start_cursor"] == nil
    assert empty["pagination_metadata"]["end_cursor"] == nil
  end

  test "filters by inclusive creation time and CI environment before pagination", %{
    conn: conn,
    project: project,
    path: path
  } do
    start = ~N[2026-10-14 09:30:00.000000]
    finish = ~N[2026-10-14 10:30:00.000000]

    {:ok, first} =
      RunsFixtures.build_fixture(project_id: project.id, inserted_at: start, is_ci: false, custom_tags: ["export"])

    {:ok, last} =
      RunsFixtures.build_fixture(project_id: project.id, inserted_at: finish, is_ci: false, custom_tags: ["export"])

    {:ok, ci} =
      RunsFixtures.build_fixture(project_id: project.id, inserted_at: start, is_ci: true, custom_tags: ["export"])

    RunsFixtures.build_fixture(
      project_id: project.id,
      inserted_at: NaiveDateTime.add(start, -1),
      is_ci: false,
      custom_tags: ["export"]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      inserted_at: NaiveDateTime.add(finish, 1),
      is_ci: false,
      custom_tags: ["export"]
    )

    RunsFixtures.build_fixture(project_id: project.id, inserted_at: start, is_ci: false)
    RunsFixtures.build_fixture(inserted_at: start, is_ci: false, custom_tags: ["export"])

    from = start |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    to = finish |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    params = %{from: from, to: to, is_ci: false, tags: ["export"], page_size: 1}
    page = conn |> get(path, params) |> json_response(:ok)
    assert Enum.map(page["builds"], & &1["id"]) == [last.id]
    next = conn |> get(path, Map.put(params, :after, page["pagination_metadata"]["end_cursor"])) |> json_response(:ok)
    assert Enum.map(next["builds"], & &1["id"]) == [first.id]
    refute next["pagination_metadata"]["has_next_page"]

    ci_page = conn |> get(path, %{from: from, to: to, is_ci: true}) |> json_response(:ok)
    assert Enum.map(ci_page["builds"], & &1["id"]) == [ci.id]
    from_only = conn |> get(path, from: to, is_ci: false) |> json_response(:ok)
    assert length(from_only["builds"]) == 2
    to_only = conn |> get(path, to: from - 1) |> json_response(:ok)
    assert length(to_only["builds"]) == 1
  end

  test "accepts 1000 builds per page without silently capping at 100", %{conn: conn, project: project, path: path} do
    for _ <- 1..101, do: RunsFixtures.build_fixture(project_id: project.id)
    response = conn |> get(path, page_size: 1000) |> json_response(:ok)
    assert length(response["builds"]) == 101
    assert response["pagination_metadata"]["page_size"] == 1000
    refute response["pagination_metadata"]["has_next_page"]

    legacy_default = conn |> get(path) |> json_response(:ok)
    assert length(legacy_default["builds"]) == 20
    assert legacy_default["pagination_metadata"]["current_page"] == 1
    assert legacy_default["pagination_metadata"]["page_size"] == 20
    assert legacy_default["pagination_metadata"]["total_count"] == 101
    assert legacy_default["pagination_metadata"]["total_pages"] == 6

    legacy_second = conn |> get(path, page: 2) |> json_response(:ok)
    assert length(legacy_second["builds"]) == 20
    assert legacy_second["pagination_metadata"]["current_page"] == 2
    assert legacy_second["pagination_metadata"]["total_count"] == 101
    assert legacy_second["pagination_metadata"]["total_pages"] == 6
    assert legacy_second["pagination_metadata"]["start_cursor"] == nil
    assert legacy_second["pagination_metadata"]["end_cursor"] == nil
  end

  test "rejects invalid ranges, page sizes, and cursors before querying", %{conn: conn, path: path} do
    reject(&Builds.list_build_runs/2)
    cursor = Flop.Cursor.encode(%{inserted_at: ~N[2026-10-14 09:30:15.123456], id: Ecto.UUID.generate()})

    for params <- [
          %{from: 2, to: 1},
          %{from: 9_223_372_036_854_775_807},
          %{to: -9_223_372_036_854_775_808},
          %{from: "not-a-timestamp"},
          %{is_ci: "not-a-boolean"},
          %{page_size: 0},
          %{page_size: 1001},
          %{after: "garbage"},
          %{before: "garbage"},
          %{after: Flop.Cursor.encode(%{inserted_at: "wrong-type", id: Ecto.UUID.generate()})},
          %{
            after:
              Flop.Cursor.encode(%{
                inserted_at: Map.put(~N[2026-10-14 09:30:15.123456], :year, nil),
                id: Ecto.UUID.generate()
              })
          },
          %{
            after:
              Flop.Cursor.encode(%{
                inserted_at: Map.put(~N[2026-10-14 09:30:15.123456], :calendar, String),
                id: Ecto.UUID.generate()
              })
          },
          %{after: Flop.Cursor.encode(%{inserted_at: ~N[2026-10-14 09:30:15], id: "invalid"})},
          %{after: Flop.Cursor.encode(%{inserted_at: ~N[2026-10-14 09:30:15]})},
          %{after: cursor, before: cursor},
          %{page: 1, after: cursor},
          %{page: 2, before: cursor}
        ] do
      conn |> get(path, params) |> json_response(:bad_request)
    end
  end

  test "exposes actual start time separately from upload time in lists and details", %{
    conn: conn,
    project: project,
    path: path
  } do
    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        inserted_at: ~N[2026-10-14 09:30:15.123456],
        started_at: ~N[2026-10-14 09:29:00.654321]
      )

    list = conn |> get(path) |> json_response(:ok)
    assert [%{"started_at" => "2026-10-14T09:29:00Z", "inserted_at" => "2026-10-14T09:30:15Z"}] = list["builds"]
    detail = conn |> get("#{path}/#{build.id}") |> json_response(:ok)
    assert detail["started_at"] == "2026-10-14T09:29:00Z"
    assert detail["inserted_at"] == "2026-10-14T09:30:15Z"
  end

  test "leaves unknown start times null", %{conn: conn, project: project, path: path} do
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
    list = conn |> get(path) |> json_response(:ok)
    assert [%{"started_at" => nil}] = list["builds"]
    detail = conn |> get("#{path}/#{build.id}") |> json_response(:ok)
    assert Map.has_key?(detail, "started_at")
    assert detail["started_at"] == nil
  end
end
