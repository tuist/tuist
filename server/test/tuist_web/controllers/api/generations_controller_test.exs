defmodule TuistWeb.API.GenerationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = assign(conn, :selected_project, project)

    %{conn: conn, user: user, project: project}
  end

  describe "GET /api/projects/:account_handle/:project_handle/generations" do
    test "returns a list of generations", %{conn: conn, user: user, project: project} do
      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          duration: 5000,
          status: "success",
          git_branch: "main",
          cacheable_targets: ["TargetA", "TargetB"],
          local_cache_target_hits: ["TargetA"],
          remote_cache_target_hits: ["TargetB"],
          command_arguments: ["--no-open"],
          user_id: user.id
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations")

      assert %{
               "generations" => generations,
               "pagination_metadata" => _pagination
             } = json_response(conn, 200)

      assert length(generations) == 1
      [returned_generation] = generations
      assert returned_generation["id"] == generation.id
      assert returned_generation["duration"] == 5000
      assert returned_generation["status"] == "success"
      assert returned_generation["cacheable_targets"] == ["TargetA", "TargetB"]
      assert returned_generation["command_arguments"] == "--no-open"
      assert returned_generation["ran_by"] == %{"handle" => user.account.name}
    end

    test "returns empty list when no generations exist", %{conn: conn, user: user, project: project} do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "cache"
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations")

      assert %{
               "generations" => [],
               "pagination_metadata" => %{
                 "total_count" => 0
               }
             } = json_response(conn, 200)
    end

    test "filters by git_branch", %{conn: conn, user: user, project: project} do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        git_branch: "main"
      )

      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          git_branch: "feature"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?git_branch=feature")

      assert %{"generations" => [returned]} = json_response(conn, 200)
      assert returned["id"] == generation.id
    end

    test "paginates forward with the after cursor", %{conn: conn, user: user, project: project} do
      expected_ids = create_ordered_generations(user, project)

      # The real client flow: fetch the first page without any cursor, then reuse
      # the returned end_cursor as `after` to walk forward.
      first_conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?page_size=2")

      assert %{
               "generations" => first_page,
               "pagination_metadata" => first_metadata
             } = json_response(first_conn, 200)

      first_page_ids = Enum.map(first_page, & &1["id"])
      assert first_page_ids == Enum.take(expected_ids, 2)
      assert is_binary(first_metadata["end_cursor"])

      end_cursor = first_metadata["end_cursor"]

      second_conn =
        build_conn()
        |> Authentication.put_current_user(user)
        |> assign(:selected_project, project)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?page_size=2&after=#{end_cursor}")

      assert %{
               "generations" => second_page,
               "pagination_metadata" => second_metadata
             } = json_response(second_conn, 200)

      second_page_ids = Enum.map(second_page, & &1["id"])

      # The second page holds the next (older) distinct events, with no overlap with page one.
      assert second_page_ids == expected_ids |> Enum.drop(2) |> Enum.take(2)
      assert second_page_ids -- first_page_ids == second_page_ids
      assert second_metadata["has_next_page"] == true
      assert second_metadata["has_previous_page"] == true
      assert second_metadata["current_page"] == nil
      assert second_metadata["total_pages"] == nil
      assert is_binary(second_metadata["start_cursor"])
      assert is_binary(second_metadata["end_cursor"])
    end

    test "paginates backward with the before cursor", %{conn: conn, user: user, project: project} do
      expected_ids = create_ordered_generations(user, project)

      first_conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?page_size=2")

      assert %{"pagination_metadata" => %{"end_cursor" => end_cursor}} = json_response(first_conn, 200)

      # Step forward to the second page to grab its start_cursor.
      second_conn =
        build_conn()
        |> Authentication.put_current_user(user)
        |> assign(:selected_project, project)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?page_size=2&after=#{end_cursor}")

      assert %{"pagination_metadata" => %{"start_cursor" => start_cursor}} = json_response(second_conn, 200)
      assert is_binary(start_cursor)

      # Walking back from the second page returns the first page again.
      third_conn =
        build_conn()
        |> Authentication.put_current_user(user)
        |> assign(:selected_project, project)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?page_size=2&before=#{start_cursor}")

      assert %{
               "generations" => third_page,
               "pagination_metadata" => third_metadata
             } = json_response(third_conn, 200)

      assert Enum.map(third_page, & &1["id"]) == Enum.take(expected_ids, 2)
      assert third_metadata["has_next_page"] == true
      assert third_metadata["current_page"] == nil
    end

    test "page-based pagination keeps page metadata and now also emits cursors", %{
      conn: conn,
      user: user,
      project: project
    } do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        user_id: user.id
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?page=1&page_size=20")

      assert %{
               "generations" => [_generation],
               "pagination_metadata" => metadata
             } = json_response(conn, 200)

      assert metadata["current_page"] == 1
      assert metadata["total_count"] == 1
      assert is_binary(metadata["start_cursor"])
      assert is_binary(metadata["end_cursor"])
    end

    test "returns nil cursors when the page is empty", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations")

      assert %{
               "generations" => [],
               "pagination_metadata" => metadata
             } = json_response(conn, 200)

      assert metadata["start_cursor"] == nil
      assert metadata["end_cursor"] == nil
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/generations/:generation_id" do
    test "returns generation details", %{conn: conn, user: user, project: project} do
      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          duration: 5000,
          status: "success",
          git_branch: "main",
          command_arguments: ["--no-open"]
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{generation.id}")

      response = json_response(conn, 200)

      assert response["id"] == generation.id
      assert response["duration"] == 5000
      assert response["status"] == "success"
      assert response["command_arguments"] == "--no-open"
    end

    test "returns 404 when generation not found", %{conn: conn, user: user, project: project} do
      event_id = UUIDv7.generate()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{event_id}")

      assert %{"message" => "Generation not found."} = json_response(conn, 404)
    end

    test "returns 404 when event is not a generation", %{conn: conn, user: user, project: project} do
      cache_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "cache"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{cache_event.id}")

      assert %{"message" => "Generation not found."} = json_response(conn, 404)
    end

    test "returns 404 when event belongs to different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: other_project.id,
          name: "generate"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{generation.id}")

      assert %{"message" => "Generation not found."} = json_response(conn, 404)
    end
  end

  # Creates five generate command events with distinct ran_at values and returns
  # their ids ordered newest-first, matching the controller's ran_at desc ordering.
  defp create_ordered_generations(user, project) do
    base = ~U[2024-06-01 12:00:00Z]

    0..4
    |> Enum.map(fn index ->
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        user_id: user.id,
        created_at: DateTime.add(base, index, :minute),
        ran_at: DateTime.add(base, index, :minute)
      )
    end)
    |> Enum.reverse()
    |> Enum.map(& &1.id)
  end
end
