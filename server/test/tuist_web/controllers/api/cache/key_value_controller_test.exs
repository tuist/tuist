defmodule TuistWeb.API.Cache.KeyValueControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Cache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev", preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{
      user: user,
      project: project,
      account_handle: user.account.name,
      project_handle: project.name
    }
  end

  describe "PUT /api/cache/keyvalue/:cas_id (get_value)" do
    test "gets cache value successfully", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "test_cas_id_123"

      entries = [
        %{id: 1, value: "value1", cas_id: cas_id, project_id: project.id},
        %{id: 2, value: "value2", cas_id: cas_id, project_id: project.id}
      ]

      expect(Cache, :get_entries_by_cas_id_and_project_id, fn ^cas_id, project_id ->
        assert project_id == project.id
        entries
      end)

      # When
      conn =
        get(conn, ~p"/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      # Then
      response = json_response(conn, :ok)

      assert response["entries"] == [
               %{"value" => "value1"},
               %{"value" => "value2"}
             ]
    end

    test "returns not found when no entries exist", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "nonexistent_cas_id"

      expect(Cache, :get_entries_by_cas_id_and_project_id, fn ^cas_id, project_id ->
        assert project_id == project.id
        []
      end)

      # When
      conn =
        get(conn, ~p"/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=#{project_handle}")

      # Then
      response = json_response(conn, :not_found)
      assert String.contains?(response["message"], "No entries found for CAS ID #{cas_id}")
    end

    test "returns not found when account doesn't exist", %{
      conn: conn,
      user: user,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      cas_id = "test_cas_id"

      # When
      conn =
        get(conn, ~p"/api/cache/keyvalue/#{cas_id}?account_handle=nonexistent-account&project_handle=#{project_handle}")

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns not found when project doesn't exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      cas_id = "test_cas_id"

      # When
      conn =
        get(conn, ~p"/api/cache/keyvalue/#{cas_id}?account_handle=#{account_handle}&project_handle=nonexistent-project")

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns forbidden when user doesn't have permission", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      cas_id = "test_cas_id"

      # When
      conn =
        get(
          conn,
          ~p"/api/cache/keyvalue/#{cas_id}?account_handle=#{other_project.account.name}&project_handle=#{other_project.name}"
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end

  describe "PUT /api/cache/keyvalue" do
    test "stores cache value successfully", %{
      conn: conn,
      project: project,
      account_handle: account_handle,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_project(conn, project)

      cas_id = "test_cas_id_123"

      entries = [
        %{"value" => "test_value_1"},
        %{"value" => "test_value_2"}
      ]

      body = %{
        "cas_id" => cas_id,
        "entries" => entries
      }

      created_entries = [
        %{id: 1, value: "test_value_1", cas_id: cas_id, project_id: project.id},
        %{id: 2, value: "test_value_2", cas_id: cas_id, project_id: project.id}
      ]

      expect(Cache, :create_entry, 2, fn entry_attrs ->
        case entry_attrs.value do
          "test_value_1" -> {:ok, Enum.at(created_entries, 0)}
          "test_value_2" -> {:ok, Enum.at(created_entries, 1)}
        end
      end)

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=#{project_handle}",
          body
        )

      # Then
      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns not found when account doesn't exist", %{
      conn: conn,
      user: user,
      project_handle: project_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      body = %{
        "cas_id" => "test_cas_id",
        "entries" => [%{"value" => "test_value"}]
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/cache/keyvalue?account_handle=nonexistent-account&project_handle=#{project_handle}",
          body
        )

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns not found when project doesn't exist", %{
      conn: conn,
      user: user,
      account_handle: account_handle
    } do
      # Given
      conn =
        Authentication.put_current_user(conn, user)

      body = %{
        "cas_id" => "test_cas_id",
        "entries" => [%{"value" => "test_value"}]
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/cache/keyvalue?account_handle=#{account_handle}&project_handle=nonexistent-project",
          body
        )

      # Then
      assert conn.status == 404
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "returns forbidden when user doesn't have permission", %{
      conn: conn
    } do
      # Given
      other_user = AccountsFixtures.user_fixture(email: "other@tuist.io", preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id)

      unauthorized_user = AccountsFixtures.user_fixture(email: "unauthorized@tuist.io")
      conn = Authentication.put_current_user(conn, unauthorized_user)

      body = %{
        "cas_id" => "test_cas_id",
        "entries" => [%{"value" => "test_value"}]
      }

      # When
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/cache/keyvalue?account_handle=#{other_project.account.name}&project_handle=#{other_project.name}",
          body
        )

      # Then
      response = json_response(conn, :forbidden)
      assert String.contains?(response["message"], "not authorized")
    end
  end
end
