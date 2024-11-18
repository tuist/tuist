defmodule TuistWeb.API.Authorization.BillingPlugTest do
  alias Tuist.Environment
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

  test "returns the same connection if the plan is air and the trial ends in more than 3 days",
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

    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2020-12-20 00:00:00Z] end)

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

    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2020-12-30 00:00:00Z] end)

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
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

    Tuist.Time
    |> stub(:utc_now, fn -> ~U[2021-01-01 00:00:00Z] end)

    project = project |> Repo.reload() |> Repo.preload(:account)

    plug_opts = BillingPlug.init([])

    conn =
      %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")}
      |> EnsureProjectPresencePlug.put_project(project)

    # When
    got = conn |> BillingPlug.call(plug_opts)

    # Then
    assert TuistWeb.WarningsHeaderPlug.get_warnings(got) ==
             [
               "Your trial period ends today. Please update your billing information to avoid service interruption: #{url(~p"/#{project.account.name}/billing")}"
             ]
  end

  @tag current_month_remote_cache_hits_count: 201
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

  @tag current_month_remote_cache_hits_count: 201
  test "returns the same connection if the on premise license is not expired",
       %{
         conn: conn,
         project: project
       } do
    # Given
    Environment
    |> stub(:on_premise?, fn -> true end)

    Tuist.License |> stub(:get_license, fn -> {:ok, %{valid: true}} end)

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

  @tag current_month_remote_cache_hits_count: 201
  test "returns an error if the on premise license is expired",
       %{
         conn: conn,
         project: project
       } do
    # Given
    Environment
    |> stub(:on_premise?, fn -> true end)

    Tuist.License |> stub(:get_license, fn -> {:ok, %{valid: false}} end)

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
             The current license is expired. Please update your license to continue using the service. Contact your administrator for more information.
             """
           }
  end

  @tag current_month_remote_cache_hits_count: 199
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
