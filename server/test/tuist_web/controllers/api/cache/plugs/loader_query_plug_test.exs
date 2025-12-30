defmodule TuistWeb.API.Cache.Plugs.LoaderQueryPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Cache.Plugs.LoaderQueryPlug

  describe "call/2" do
    test "loads project and account from query parameters", %{conn: conn} do
      # Given
      project = ProjectsFixtures.project_fixture(preload: [:account])
      account_handle = project.account.name
      project_handle = project.name
      plug_opts = LoaderQueryPlug.init([])

      # When
      conn_with_query = %{
        conn
        | query_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_handle
          }
      }

      result = LoaderQueryPlug.call(conn_with_query, plug_opts)

      # Then
      assert result.assigns[:selected_project].id == project.id
      assert result.assigns[:selected_account].id == project.account.id
    end
  end

  test "returns not found error when project is not found", %{conn: conn} do
    # Given
    account_handle = "nonexistent"
    project_handle = "project"
    project_slug = "#{account_handle}/#{project_handle}"
    plug_opts = LoaderQueryPlug.init([])

    # When
    conn_with_query = %{
      conn
      | query_params: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle
        }
    }

    result = LoaderQueryPlug.call(conn_with_query, plug_opts)

    # Then
    assert result.halted
    assert result.status == 404
    assert JSON.decode!(result.resp_body) == %{"message" => "The project #{project_slug} was not found."}
  end

  test "returns bad request error when account_handle is missing", %{conn: conn} do
    # Given
    plug_opts = LoaderQueryPlug.init([])
    conn_with_partial_query = %{conn | query_params: %{"project_handle" => "project"}}

    # When
    result = LoaderQueryPlug.call(conn_with_partial_query, plug_opts)

    # Then
    assert result.halted
    assert result.status == 400

    assert JSON.decode!(result.resp_body) == %{
             "message" => "account_handle and project_handle query parameters are required"
           }
  end

  test "returns bad request error when project_handle is missing", %{conn: conn} do
    # Given
    plug_opts = LoaderQueryPlug.init([])
    conn_with_partial_query = %{conn | query_params: %{"account_handle" => "account"}}

    # When
    result = LoaderQueryPlug.call(conn_with_partial_query, plug_opts)

    # Then
    assert result.halted
    assert result.status == 400

    assert JSON.decode!(result.resp_body) == %{
             "message" => "account_handle and project_handle query parameters are required"
           }
  end

  test "returns bad request error when both parameters are missing", %{conn: conn} do
    # Given
    plug_opts = LoaderQueryPlug.init([])
    conn_with_no_query = %{conn | query_params: %{}}

    # When
    result = LoaderQueryPlug.call(conn_with_no_query, plug_opts)

    # Then
    assert result.halted
    assert result.status == 400

    assert JSON.decode!(result.resp_body) == %{
             "message" => "account_handle and project_handle query parameters are required"
           }
  end
end
