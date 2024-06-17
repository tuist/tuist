defmodule TuistCloudWeb.API.Authorization.BillingPlugTest do
  alias TuistCloudWeb.API.Authorization.BillingPlug
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  alias TuistCloud.Accounts.Account
  use TuistCloudWeb.ConnCase
  alias TuistCloud.Repo
  use Mimic

  setup do
    project = ProjectsFixtures.project_fixture() |> Repo.preload(:account)

    TuistCloud.Environment
    |> stub(:new_pricing_model?, fn -> true end)

    %{
      project: project,
      user: AccountsFixtures.user_fixture(preloads: [:account])
    }
  end

  test "returns the same connection if the plan is enterprise", %{
    conn: conn,
    project: project
  } do
    # Given
    {:ok, _} =
      project.account
      |> Account.update_changeset(%{plan: :enterprise})
      |> Repo.update()

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert got == conn
  end

  test "returns the same connection if the plan is pro", %{
    conn: conn,
    project: project
  } do
    # Given
    {:ok, _} =
      project.account
      |> Account.update_changeset(%{plan: :pro})
      |> Repo.update()

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert got == conn
  end

  test "returns the same connection if the plan is air", %{
    conn: conn,
    project: project
  } do
    # Given
    {:ok, _} =
      project.account
      |> Account.update_changeset(%{plan: :air})
      |> Repo.update()

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert got == conn
  end

  test "returns an error if the plan is none", %{
    conn: conn,
    project: project
  } do
    # Given
    {:ok, _} =
      project.account
      |> Account.update_changeset(%{plan: :none})
      |> Repo.update()

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The account '#{project.account.name}' has reached the limit of remote cache hits #{BillingPlug.remote_cache_hits_threshold()} of the 'Tuist Air' plan and requires payment. Manage your billing at #{url(~p"/organizations/#{project.account.name}/billing")}.
             """
           }
  end
end
