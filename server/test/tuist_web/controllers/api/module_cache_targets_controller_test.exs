defmodule TuistWeb.API.ModuleCacheTargetsControllerTest do
  use TuistTestSupport.Cases.ConnCase, clickhouse: true
  use Mimic

  alias Tuist.Xcode
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/runs/:run_id/module-cache-targets" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns module cache targets for a run", %{conn: conn, user: user, project: project} do
      # Given
      run = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      stub(Xcode, :binary_cache_analytics, fn _event, _flop_params ->
        {%{
           cacheable_targets: [
             %{
               name: "MyTarget",
               binary_cache_hit: "remote",
               binary_cache_hash: "abc123",
               product: "framework",
               bundle_id: "com.example.MyTarget",
               product_name: "MyTarget",
               sources_hash: "src_hash",
               resources_hash: nil,
               copy_files_hash: nil,
               core_data_models_hash: nil,
               target_scripts_hash: nil,
               environment_hash: nil,
               headers_hash: nil,
               deployment_target_hash: nil,
               info_plist_hash: nil,
               entitlements_hash: nil,
               dependencies_hash: "dep_hash",
               project_settings_hash: nil,
               target_settings_hash: nil,
               buildable_folders_hash: nil,
               external_hash: nil
             }
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/#{run.id}/module-cache-targets"
        )

      # Then
      response = json_response(conn, :ok)
      assert length(response["targets"]) == 1

      target = hd(response["targets"])
      assert target["name"] == "MyTarget"
      assert target["cache_status"] == "remote"
      assert target["cache_hash"] == "abc123"
      assert target["product"] == "framework"
      assert target["bundle_id"] == "com.example.MyTarget"
      assert target["product_name"] == "MyTarget"
      assert target["subhashes"]["sources"] == "src_hash"
      assert target["subhashes"]["dependencies"] == "dep_hash"
      refute Map.has_key?(target["subhashes"], "resources")

      assert response["pagination_metadata"]["has_next_page"] == false
      assert response["pagination_metadata"]["current_page"] == 1
      assert response["pagination_metadata"]["total_count"] == 1
    end

    test "returns nil cache_status when binary_cache_hit is nil", %{conn: conn, user: user, project: project} do
      # Given
      run = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      stub(Xcode, :binary_cache_analytics, fn _event, _flop_params ->
        {%{
           cacheable_targets: [
             %{
               name: "MyTarget",
               binary_cache_hit: nil,
               binary_cache_hash: nil,
               product: nil,
               bundle_id: nil,
               product_name: nil,
               sources_hash: nil,
               resources_hash: nil,
               copy_files_hash: nil,
               core_data_models_hash: nil,
               target_scripts_hash: nil,
               environment_hash: nil,
               headers_hash: nil,
               deployment_target_hash: nil,
               info_plist_hash: nil,
               entitlements_hash: nil,
               dependencies_hash: nil,
               project_settings_hash: nil,
               target_settings_hash: nil,
               buildable_folders_hash: nil,
               external_hash: nil
             }
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/#{run.id}/module-cache-targets"
        )

      # Then
      response = json_response(conn, :ok)
      target = hd(response["targets"])
      assert is_nil(target["cache_status"])
      assert target["subhashes"] == %{}
    end

    test "filters targets by cache_status", %{conn: conn, user: user, project: project} do
      # Given
      run = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      expect(Xcode, :binary_cache_analytics, fn _event, flop_params ->
        assert %{field: :binary_cache_hit, op: :==, value: "miss"} in flop_params.filters

        {%{cacheable_targets: []},
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/#{run.id}/module-cache-targets?cache_status=miss"
        )

      # Then
      assert json_response(conn, :ok)
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      # Given
      run = CommandEventsFixtures.command_event_fixture(project_id: project.id)

      expect(Xcode, :binary_cache_analytics, fn _event, flop_params ->
        assert flop_params.page == 2
        assert flop_params.page_size == 5

        {%{cacheable_targets: []},
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 5,
           total_count: 8,
           total_pages: 2
         }}
      end)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/#{run.id}/module-cache-targets?page=2&page_size=5"
        )

      # Then
      response = json_response(conn, :ok)
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 5
      assert response["pagination_metadata"]["has_previous_page"] == true
      assert response["pagination_metadata"]["total_count"] == 8
    end

    test "returns 404 when run does not exist", %{conn: conn, user: user, project: project} do
      # Given
      run_id = UUIDv7.generate()

      # When / Then
      assert_error_sent :not_found, fn ->
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/runs/#{run_id}/module-cache-targets"
        )
      end
    end

    test "returns 403 when user is not authorized", %{conn: conn} do
      # Given
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)
      run = CommandEventsFixtures.command_event_fixture(project_id: other_project.id)

      # When
      conn =
        get(
          conn,
          "/api/projects/#{other_user.account.name}/#{other_project.name}/runs/#{run.id}/module-cache-targets"
        )

      # Then
      assert json_response(conn, :forbidden)
    end
  end
end
