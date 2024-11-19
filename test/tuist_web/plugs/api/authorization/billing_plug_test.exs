defmodule TuistWeb.API.Authorization.BillingPlugTest do
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias TuistWeb.API.Authorization.BillingPlug
  alias Tuist.ProjectsFixtures
  alias Tuist.AccountsFixtures
  alias TuistWeb.API.EnsureProjectPresencePlug
  use TuistWeb.ConnCase
  alias Tuist.Repo
  use Mimic

  setup context do
    current_month_remote_cache_hits_count =
      context |> Map.get(:current_month_remote_cache_hits_count, 0)

    %{account: account} =
      user =
      AccountsFixtures.user_fixture(
        current_month_remote_cache_hits_count: current_month_remote_cache_hits_count,
        preload: [:account]
      )

    project = ProjectsFixtures.project_fixture(account_id: account.id) |> Repo.preload(:account)

    %{
      project: project,
      user: user
    }
  end

  @tag current_month_remote_cache_hits_count: 50
  test "returns the same connection when the plan is enterprise, and the subscription is active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :enterprise, status: "active"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert got == conn
  end

  @tag current_month_remote_cache_hits_count: 50
  test "returns the same connection when the plan is enterprise, and the subscription is not active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :enterprise, status: "canceled"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The 'Tuist Enterprise' plan of the account '#{account.name}' is not active. You can contact sales@tuist.io to renovate your plan.
             """
           }
  end

  @tag current_month_remote_cache_hits_count: 250
  test "returns an error when the plan is air, and the usage is above the threshold",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :air}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
           }
  end

  @tag current_month_remote_cache_hits_count: 1000
  test "returns an error when the plan is pro, and the subscription is not active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :pro, status: "canceled"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The account '#{account.name}' 'Tuist Pro' plan is not active. You can manage your billing at #{url(~p"/#{account.name}/billing/manage")}.
             """
           }
  end

  @tag current_month_remote_cache_hits_count: 1000
  test "returns the same connection the plan is pro, and the subscription is active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :pro, status: "active"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert got == conn
  end

  @tag current_month_remote_cache_hits_count: 1000
  test "returns the same connection the plan is open_source, and the subscription is active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :open_source, status: "active"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert got == conn
  end

  @tag current_month_remote_cache_hits_count: 1000
  test "returns the an error if the plan is open_source, and the subscription is canceled",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :open_source, status: "canceled"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The account '#{account.name}' 'Tuist Open Source' plan is not active. You can contact Tuist at contact@tuist.io to renovate it, or upgrade to 'Tuist Pro' at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
           }
  end
end
