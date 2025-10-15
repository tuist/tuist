defmodule TuistWeb.API.Cache.Plugs.LoaderQueryPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Cache.Plugs.LoaderQueryPlug
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.Errors.NotFoundError

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

  test "raises NotFoundError when project is not found", %{conn: conn} do
    # Given
    account_handle = "nonexistent"
    project_handle = "project"
    project_slug = "#{account_handle}/#{project_handle}"
    plug_opts = LoaderQueryPlug.init([])

    # When/Then
    conn_with_query = %{
      conn
      | query_params: %{
          "account_handle" => account_handle,
          "project_handle" => project_handle
        }
    }

    assert_raise NotFoundError,
                 "The project #{project_slug} was not found.",
                 fn ->
                   LoaderQueryPlug.call(conn_with_query, plug_opts)
                 end
  end

  test "raises BadRequestError when account_handle is missing", %{conn: conn} do
    # Given
    plug_opts = LoaderQueryPlug.init([])
    conn_with_partial_query = %{conn | query_params: %{"project_handle" => "project"}}

    # When/Then
    assert_raise BadRequestError,
                 "account_handle and project_handle query parameters are required",
                 fn ->
                   LoaderQueryPlug.call(conn_with_partial_query, plug_opts)
                 end
  end

  test "raises BadRequestError when project_handle is missing", %{conn: conn} do
    # Given
    plug_opts = LoaderQueryPlug.init([])
    conn_with_partial_query = %{conn | query_params: %{"account_handle" => "account"}}

    # When/Then
    assert_raise BadRequestError,
                 "account_handle and project_handle query parameters are required",
                 fn ->
                   LoaderQueryPlug.call(conn_with_partial_query, plug_opts)
                 end
  end

  test "raises BadRequestError when both parameters are missing", %{conn: conn} do
    # Given
    plug_opts = LoaderQueryPlug.init([])
    conn_with_no_query = %{conn | query_params: %{}}

    # When/Then
    assert_raise BadRequestError,
                 "account_handle and project_handle query parameters are required",
                 fn ->
                   LoaderQueryPlug.call(conn_with_no_query, plug_opts)
                 end
  end
end
