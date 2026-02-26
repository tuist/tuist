defmodule TuistWeb.Plugs.ObservabilityContextPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Plug.Test

  alias Tuist.Accounts.AuthenticatedAccount
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.ObservabilityContextPlug

  setup :set_mimic_from_context

  describe "call/2" do
    test "sets auth context for authenticated user" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == user.account.name
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_user(user)
        |> ObservabilityContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == user.account.name
    end

    test "sets auth context for authenticated project" do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == project.account.name
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Authentication.put_current_project(project)
        |> ObservabilityContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == project.account.name
    end

    test "sets auth context for authenticated account" do
      account = AccountsFixtures.account_fixture()
      authenticated_account = %AuthenticatedAccount{account: account, scopes: [:registry_read]}

      expect(OpenTelemetry.Tracer, :set_attribute, fn "auth_account_handle", value ->
        assert value == account.name
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_subject, authenticated_account)
        |> ObservabilityContextPlug.call(%{})

      assert conn
      assert Logger.metadata()[:auth_account_handle] == account.name
    end

    test "does not set auth context when no authentication" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/")
        |> ObservabilityContextPlug.call(%{})

      assert conn
      refute Keyword.has_key?(Logger.metadata(), :auth_account_handle)
    end
  end

  describe "set_selection_context/1" do
    test "sets selection context for selected project and account" do
      parent = self()
      project = ProjectsFixtures.project_fixture(preload: [:account])

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:selected_project, project)
        |> Plug.Conn.assign(:selected_account, project.account)
        |> ObservabilityContextPlug.set_selection_context()

      assert conn
      assert Logger.metadata()[:selected_account_handle] == project.account.name
      assert Logger.metadata()[:selected_project_handle] == project.name
      assert_receive {:trace_attribute, "selected_account_handle", _}
      assert_receive {:trace_attribute, "selected_project_handle", _}
    end

    test "sets selection context for only selected account" do
      account = AccountsFixtures.account_fixture()

      expect(OpenTelemetry.Tracer, :set_attribute, fn "selected_account_handle", value ->
        assert value == account.name
        :ok
      end)

      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:selected_account, account)
        |> ObservabilityContextPlug.set_selection_context()

      assert conn
      assert Logger.metadata()[:selected_account_handle] == account.name
      refute Keyword.has_key?(Logger.metadata(), :selected_project_handle)
    end

    test "does not set context when no selection" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      conn =
        :get
        |> conn("/")
        |> ObservabilityContextPlug.set_selection_context()

      assert conn
      refute Keyword.has_key?(Logger.metadata(), :selected_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :selected_project_handle)
    end
  end
end
