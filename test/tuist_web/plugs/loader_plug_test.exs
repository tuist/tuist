defmodule TuistWeb.Plugs.LoaderPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.LoaderPlug

  setup :set_mimic_from_context

  setup do
    cache = String.to_atom(UUIDv7.generate())
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

      expect(CommandEvents, :get_command_event_by_id, 1, fn ^run_id,
                                                            [
                                                              preload: [
                                                                user: :account,
                                                                project: :account
                                                              ]
                                                            ] ->
        {:ok, run}
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

      conn = assign(%{conn | path_params: %{"run_id" => run_id}}, :caching, false)

      assert_raise NotFoundError,
                   "The run with ID #{run_id} was not found.",
                   fn ->
                     LoaderPlug.call(conn, plug_opts)
                   end
    end
  end

  describe "call/2 when the 'account_handle' and 'project_handle' path params are present" do
    test "caches the responses across consecutive runs", %{conn: conn, cache: cache} do
      # Given
      project = %{account: account} = ProjectsFixtures.project_fixture()
      slug = "#{project.account.name}/#{project.name}"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      expect(Projects, :get_project_by_slug, 1, fn ^slug, [preload: [:account]] ->
        {:ok, project}
      end)

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

    test "raises an error when the project full handle is invalid", %{conn: conn, cache: cache} do
      # Given
      slug = "invalid"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      # When/then
      assert_raise BadRequestError,
                   "The project full handle #{slug} is invalid. It should follow the convention 'account_handle/project_handle'.",
                   fn ->
                     %{
                       conn
                       | query_params: %{"project_id" => slug}
                     }
                     |> assign(:cache, cache)
                     |> LoaderPlug.call(plug_opts)
                   end
    end

    test "raises an error when the project full handle has more than two components", %{
      conn: conn,
      cache: cache
    } do
      # Given
      slug = "tuist/foo/bar"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      # When/then
      assert_raise BadRequestError,
                   "The project full handle #{slug} is invalid. It should follow the convention 'account_handle/project_handle'.",
                   fn ->
                     %{
                       conn
                       | query_params: %{"project_id" => slug}
                     }
                     |> assign(:cache, cache)
                     |> LoaderPlug.call(plug_opts)
                   end
    end
  end

  describe "call/2 when the 'account_handle' param is present" do
    test "caches the responses across consecutive runs", %{conn: conn, cache: cache} do
      # Given
      user = AccountsFixtures.user_fixture()
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])
      account_handle = user.account.name

      expect(Accounts, :get_account_by_handle, 1, fn ^account_handle ->
        user.account
      end)

      # When
      first_response =
        %{
          conn
          | params: %{"account_handle" => user.account.name}
        }
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      second_response =
        %{
          conn
          | params: %{"account_handle" => user.account.name}
        }
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      # Then
      assert first_response.assigns[:selected_account] == user.account
      assert second_response.assigns[:selected_account] == user.account
    end

    test "raises when the account is not found", %{conn: conn, cache: cache} do
      # Given
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])
      account_handle = UUIDv7.generate()

      # When/Then
      assert_raise NotFoundError,
                   "The account #{account_handle} was not found.",
                   fn ->
                     %{
                       conn
                       | params: %{"account_handle" => account_handle}
                     }
                     |> assign(:cache, cache)
                     |> LoaderPlug.call(plug_opts)
                   end
    end
  end

  describe "call/2 when body_params contains a project_id" do
    test "caches the responses across consecutive runs", %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      slug = "#{project.account.name}/#{project.name}"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      expect(Projects, :get_project_by_slug, 1, fn ^slug, [preload: [:account]] ->
        {:ok, project}
      end)

      # When
      first_response =
        %{conn | body_params: %{project_id: slug}}
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      second_response =
        %{conn | body_params: %{project_id: slug}}
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

      # When/Then
      assert_raise NotFoundError, "The project #{slug} was not found.", fn ->
        %{conn | body_params: %{project_id: slug}}
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)
      end
    end
  end

  describe "call/2 when query_params contains a project_id" do
    test "caches the responses across consecutive runs", %{conn: conn, cache: cache} do
      # Given
      project = ProjectsFixtures.project_fixture()
      slug = "#{project.account.name}/#{project.name}"
      plug_opts = TuistWeb.Plugs.LoaderPlug.init([])

      expect(Projects, :get_project_by_slug, 1, fn ^slug, [preload: [:account]] ->
        {:ok, project}
      end)

      # When
      first_response =
        %{conn | query_params: %{"project_id" => slug}}
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)

      second_response =
        %{conn | query_params: %{"project_id" => slug}}
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

      # When/Then
      assert_raise NotFoundError, "The project #{slug} was not found.", fn ->
        %{conn | query_params: %{"project_id" => slug}}
        |> assign(:cache, cache)
        |> LoaderPlug.call(plug_opts)
      end
    end
  end
end
