defmodule TuistWeb.Plugs.SentryContextPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Plug.Test

  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.SentryContextPlug

  setup :set_mimic_from_context

  setup do
    Logger.metadata(auth_account_handle: nil, selected_account_handle: nil, selected_project_handle: nil)
    stub(OpenTelemetry.Tracer, :set_attribute, fn _, _ -> :ok end)
    :ok
  end

  describe "call/2" do
    test "skips sentry when error tracking is disabled but still sets observability context" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> false end)
      reject(&Sentry.Context.set_extra_context/1)

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == user.account.name
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_user(user)
        |> SentryContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == user.account.name
    end

    test "sets auth context for authenticated user" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == user.account.name
        :ok
      end)

      expect(Sentry.Context, :set_extra_context, fn data ->
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
        |> SentryContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == user.account.name
    end

    test "sets auth context for authenticated project" do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == project.account.name
        :ok
      end)

      expect(Sentry.Context, :set_extra_context, fn data ->
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
        |> SentryContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == project.account.name
    end

    test "sets auth context for authenticated account" do
      account = AccountsFixtures.account_fixture()
      authenticated_account = %AuthenticatedAccount{account: account, scopes: [:registry_read]}

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == account.name
        :ok
      end)

      expect(Sentry.Context, :set_extra_context, fn data ->
        assert data == %{auth_account_id: account.id, auth_account_handle: account.name}
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_subject, authenticated_account)
        |> SentryContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == account.name
    end

    test "does not set auth context when no authentication" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      reject(&Sentry.Context.set_extra_context/1)
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/")
        |> SentryContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == nil
    end
  end

  describe "set_selection_context/1" do
    test "skips sentry when error tracking is disabled but still sets observability context" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> false end)
      reject(&Sentry.Context.set_extra_context/1)
      parent = self()

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      project = ProjectsFixtures.project_fixture(preload: [:account])

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:selected_project, project)
        |> Plug.Conn.assign(:selected_account, project.account)
        |> SentryContextPlug.set_selection_context()

      assert conn
      assert Logger.metadata()[:selected_account_handle] == project.account.name
      assert Logger.metadata()[:selected_project_handle] == project.name

      account_handle = project.account.name
      project_handle = project.name

      assert_receive {:trace_attribute, "selected_account_handle", ^account_handle}
      assert_receive {:trace_attribute, "selected_project_handle", ^project_handle}
    end

    test "sets selection context for selected project and account" do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      parent = self()

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      expect(Sentry.Context, :set_extra_context, fn data ->
        assert data == %{
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
        |> Plug.Conn.assign(:selected_project, project)
        |> Plug.Conn.assign(:selected_account, project.account)
        |> SentryContextPlug.set_selection_context()

      assert conn
      assert Logger.metadata()[:selected_account_handle] == project.account.name
      assert Logger.metadata()[:selected_project_handle] == project.name

      account_handle = project.account.name
      project_handle = project.name

      assert_receive {:trace_attribute, "selected_account_handle", ^account_handle}
      assert_receive {:trace_attribute, "selected_project_handle", ^project_handle}
    end

    test "sets selection context for only selected account" do
      account = AccountsFixtures.account_fixture()

      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)

      expect(OpenTelemetry.Tracer, :set_attribute, fn "selected_account_handle", value ->
        assert value == account.name
        :ok
      end)

      expect(Sentry.Context, :set_extra_context, fn data ->
        assert data == %{
                 selected_account_id: account.id,
                 selected_account_handle: account.name,
                 selected_account_customer_id: account.customer_id
               }

        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:selected_account, account)
        |> SentryContextPlug.set_selection_context()

      assert conn
      assert Logger.metadata()[:selected_account_handle] == account.name
      assert Logger.metadata()[:selected_project_handle] == nil
    end

    test "does not set context when no selection" do
      stub(Tuist.Environment, :error_tracking_enabled?, fn -> true end)
      reject(&Sentry.Context.set_extra_context/1)
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/")
        |> SentryContextPlug.set_selection_context()

      assert conn
      assert Logger.metadata()[:selected_account_handle] == nil
      assert Logger.metadata()[:selected_project_handle] == nil
    end
  end
end
