defmodule TuistCloudWeb.API.Authorization.BillingPlugTest do
  alias TuistCloud.Accounts
  alias TuistCloud.Billing
  alias TuistCloud.Billing.Subscription
  alias TuistCloudWeb.API.Authorization.BillingPlug
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.AccountsFixtures
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  use TuistCloudWeb.ConnCase
  alias TuistCloud.Repo
  use Mimic

  setup do
    Billing
    |> stub(:start_trial, fn _ -> {:ok, %{}} end)

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
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :enterprise}
    end)

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
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :pro}
    end)

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
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :air}
    end)

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

  test "returns connection with a warning if the plan is air and the trial ends in less than 3 days",
       %{
         conn: conn,
         project: project
       } do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :air, trial_end: ~U[2021-01-01 00:00:00Z]}
    end)

    TuistCloud.Time
    |> stub(:utc_now, fn -> ~U[2020-12-30 00:00:00Z] end)

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert TuistCloudWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "Your trial period ends in 2 days. Please update your billing information to avoid service interruption: #{url(~p"/#{project.account.name}/billing")}"
             ]
  end

  test "returns connection with a warning if the plan is air and the trial ends today",
       %{
         conn: conn,
         project: project
       } do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      %Subscription{plan: :air, trial_end: ~U[2021-01-01 01:00:00Z]}
    end)

    TuistCloud.Time
    |> stub(:utc_now, fn -> ~U[2021-01-01 00:00:00Z] end)

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert TuistCloudWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "Your trial period ends today. Please update your billing information to avoid service interruption: #{url(~p"/#{project.account.name}/billing")}"
             ]
  end

  test "returns an error if the account has no active subscription and the current month remote cache hits count is over the threshold",
       %{
         conn: conn,
         project: project
       } do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      nil
    end)

    Accounts
    |> stub(:get_current_month_remote_cache_hits_count, fn ^account -> 201 end)

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
             The account '#{project.account.name}' has reached the limit of remote cache hits #{BillingPlug.remote_cache_hits_threshold()} of the 'Tuist Air' plan and requires payment. Manage your billing at #{url(~p"/#{project.account.name}/billing")}.
             """
           }
  end

  test "returns the same connection if the account has no active subscription and the current month remote cache hits count is below the threshold",
       %{
         conn: conn,
         project: project
       } do
    # Given
    account = project.account

    Billing
    |> stub(:get_current_active_subscription, fn ^account ->
      nil
    end)

    Accounts
    |> stub(:get_current_month_remote_cache_hits_count, fn ^account -> 199 end)

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
end
