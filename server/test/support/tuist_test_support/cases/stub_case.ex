defmodule TuistTestSupport.Cases.StubCase do
  @moduledoc ~S"""
  This module shares common setup for stubbing core services like the billing logic.
  """
  use ExUnit.CaseTemplate

  alias TuistTestSupport.Cases.ConnCase
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  using options do
    quote do
      use Mimic

      if unquote(options)[:billing] do
        setup do
          stub(Tuist.Billing, :create_customer, fn _ -> "cust_#{UUIDv7.generate()}" end)
          :ok
        end
      end

      if unquote(options)[:dashboard_project] do
        setup %{conn: conn} do
          user = AccountsFixtures.user_fixture()

          %{account: account} =
            organization =
            AccountsFixtures.organization_fixture(
              name: "tuist-org",
              creator: user,
              preload: [:account]
            )

          selected_project =
            ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

          conn =
            conn
            |> assign(:selected_project, selected_project)
            |> assign(:selected_account, account)
            |> ConnCase.log_in_user(user)

          %{conn: conn, user: user, project: selected_project, organization: organization}
        end
      end
    end
  end
end
