defmodule TuistWeb.Plugs.AppsignalAttributionPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
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

    test "sets auth tags for authenticated user" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "tags", data ->
        assert data == %{
                 auth_user_id: user.id,
                 auth_account_id: user.account.id,
                 auth_account_handle: user.account.name
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

    test "sets auth tags for authenticated project" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "tags", data ->
        assert data == %{
                 auth_project_id: project.id,
                 auth_account_id: project.account.id,
                 auth_account_handle: project.account.name
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

    test "sets auth tags for authenticated account" do
      account = AccountsFixtures.account_fixture()
      authenticated_account = %AuthenticatedAccount{account: account, scopes: [:registry_read]}
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "tags", data ->
        assert data == %{auth_account_id: account.id, auth_account_handle: account.name}
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_subject, authenticated_account)
        |> AppsignalAttributionPlug.call(%{})

      assert conn
    end

    test "sets selection tags for selected project and account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(preload: [:account])
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "tags", data ->
        assert data == %{
                 auth_user_id: user.id,
                 auth_account_id: user.account.id,
                 auth_account_handle: user.account.name,
                 selected_project_id: project.id,
                 selected_project_handle: project.name,
                 selected_account_id: project.account.id,
                 selected_account_handle: project.account.name,
                 selected_account_customer_id: project.account.customer_id
               }

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

    test "sets selection tags for only selected account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = AccountsFixtures.account_fixture()
      span = make_ref()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      stub(Appsignal.Tracer, :root_span, fn -> span end)

      expect(Appsignal.Span, :set_sample_data, fn ^span, "tags", data ->
        assert data == %{
                 auth_user_id: user.id,
                 auth_account_id: user.account.id,
                 auth_account_handle: user.account.name,
                 selected_account_id: account.id,
                 selected_account_handle: account.name,
                 selected_account_customer_id: account.customer_id
               }

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

    test "does not set tags when no authentication or selection" do
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
