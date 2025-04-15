defmodule TuistWeb.Plugs.LoaderPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistWeb.Plugs.LoaderPlug
  alias Tuist.CommandEvents
  alias TuistWeb.Errors.NotFoundError
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias Tuist.Projects

  use Mimic
  setup :set_mimic_from_context

  setup do
    cache = UUIDv7.generate() |> String.to_atom()
    {:ok, _} = Cachex.start_link(name: cache)
    %{cache: cache}
  end

  describe "call/2 when the 'run_id' path param is present" do
    test "returns a cache response on consecutive calls", %{conn: conn, cache: cache} do
      # Given
      run =
        %{id: run_id} =
        CommandEventsFixtures.command_event_fixture(preload: [user: :account, project: :account])

      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      CommandEvents
      |> expect(:get_command_event_by_id, 1, fn ^run_id,
                                                preload: [user: :account, project: :account] ->
        run
      end)

      # When
      first_response =
        %{conn | path_params: %{"run_id" => run.id}}
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      second_response =
        %{conn | path_params: %{"run_id" => run.id}}
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      # Then
      assert first_response.assigns[:selected_account] == run.project.account
      assert first_response.assigns[:selected_project] == run.project
      assert first_response.assigns[:selected_run] == run

      assert second_response.assigns[:selected_account] == run.project.account
      assert second_response.assigns[:selected_project] == run.project
      assert second_response.assigns[:selected_run] == run
    end

    test "raises when the run id is not found", %{conn: conn} do
      # Given
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      # When
      run_id = :rand.uniform(100)

      conn =
        %{conn | path_params: %{"run_id" => run_id}}
        |> assign(:caching, false)

      assert_raise NotFoundError,
                   "The run with ID #{run_id} was not found.",
                   fn ->
                     conn |> LoaderPlug.call(plug_opts)
                   end
    end
  end

  describe "call/2 when the 'account_handle' and 'project_handle' path params are present" do
    test "caches the responses across consecutive runs", %{conn: conn, cache: cache} do
      # Given
      project = %{account: account} = ProjectsFixtures.project_fixture()
      slug = "#{project.account.name}/#{project.name}"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      Projects
      |> expect(:get_project_by_slug, 1, fn ^slug, preload: [:account] -> {:ok, project} end)

      # When
      first_response =
        %{
          conn
          | path_params: %{"account_handle" => account.name, "project_handle" => project.name}
        }
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      second_response =
        %{
          conn
          | path_params: %{"account_handle" => account.name, "project_handle" => project.name}
        }
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      # Then
      assert first_response.assigns[:selected_project] == project
      assert first_response.assigns[:selected_account] == project.account
      assert second_response.assigns[:selected_project] == project
      assert second_response.assigns[:selected_account] == project.account
    end

    test "raises an error when the project is not found", %{conn: conn, cache: cache} do
      # Given
      account_handle = UUIDv7.generate()
      project_handle = UUIDv7.generate()
      slug = "#{account_handle}/#{project_handle}"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      # When/then
      assert_raise NotFoundError, "The project #{slug} was not found.", fn ->
        %{
          conn
          | path_params: %{"account_handle" => account_handle, "project_handle" => project_handle}
        }
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)
      end
    end
  end
end
