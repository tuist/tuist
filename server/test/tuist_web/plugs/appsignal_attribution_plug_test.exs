defmodule TuistWeb.Plugs.AppsignalAttributionPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Test

  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.AppsignalAttributionPlug

  setup :set_mimic_from_context

  describe "call/2" do
    test "does nothing when error tracking is disabled" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> false end)
      reject(&Appsignal.Tracer.root_span/0)
      reject(&Appsignal.Span.set_sample_data/3)

      conn =
        :get
        |> conn("/")
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "sets auth sample data for authenticated user" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "auth", data ->
        assert data == %{
                 user_id: user.id,
                 account_id: user.account.id,
                 account_handle: user.account.name
               }

        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_user(user)
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "sets auth sample data for authenticated project" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "auth", data ->
        assert data == %{
                 project_id: project.id,
                 account_id: project.account.id,
                 account_handle: project.account.name
               }

        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_project(project)
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "sets auth sample data for authenticated account" do
      account = AccountsFixtures.account_fixture()
      authenticated_account = %AuthenticatedAccount{account: account, scopes: [:registry_read]}
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "auth", data ->
        assert data == %{account_id: account.id, account_handle: account.name}
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_subject, authenticated_account)
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "sets selection sample data for selected project and account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(preload: [:account])
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, 2, fn ^span, key, data ->
        case key do
          "auth" ->
            assert data == %{
                     user_id: user.id,
                     account_id: user.account.id,
                     account_handle: user.account.name
                   }

          "selection" ->
            assert data == %{
                     project_id: project.id,
                     project_name: project.name,
                     account_id: project.account.id,
                     account_handle: project.account.name
                   }
        end

        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_user(user)
        |> Plug.Conn.assign(:selected_project, project)
        |> Plug.Conn.assign(:selected_account, project.account)
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "sets selection sample data for only selected account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = AccountsFixtures.account_fixture()
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, 2, fn ^span, key, data ->
        case key do
          "auth" ->
            assert data == %{
                     user_id: user.id,
                     account_id: user.account.id,
                     account_handle: user.account.name
                   }

          "selection" ->
            assert data == %{account_id: account.id, account_handle: account.name}
        end

        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_user(user)
        |> Plug.Conn.assign(:selected_account, account)
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "does not set sample data when no authentication or selection" do
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)
      reject(&Appsignal.Span.set_sample_data/3)

      conn =
        :get
        |> conn("/")
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end
  end
end
