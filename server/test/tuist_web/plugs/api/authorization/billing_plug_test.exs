defmodule TuistWeb.API.Authorization.BillingPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Authorization.BillingPlug

  # This is needed in combination with "async: false" to ensure
  # that mocks are used within the cache process.
  setup :set_mimic_from_context

  setup context do
    current_month_remote_cache_hits_count =
      Map.get(context, :current_month_remote_cache_hits_count, 0)

    %{account: account} =
      user =
      AccountsFixtures.user_fixture(
        current_month_remote_cache_hits_count: current_month_remote_cache_hits_count,
        preload: [:account]
      )

    project =
      [account_id: account.id] |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)

    cache = String.to_atom(UUIDv7.generate())
    {:ok, _} = Cachex.start_link(name: cache)

    %{
      project: project,
      user: user,
      cache: cache
    }
  end

  @tag current_month_remote_cache_hits_count: 50
  test "caches the billing information across requests",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    Enum.reduce(0..10, Billing, fn _idx, mod ->
      expect(mod, :get_current_active_subscription, 1, fn ^account ->
        %Subscription{plan: :enterprise, status: "active"}
      end)
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    for _n <- 0..10 do
      assert(BillingPlug.call(conn, plug_opts) == conn)
    end
  end

  @tag current_month_remote_cache_hits_count: 50
  test "returns the same connection when the plan is enterprise, and the subscription is active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :enterprise, status: "active"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

    # Then
    assert got == conn
  end

  @tag current_month_remote_cache_hits_count: 50
  test "returns the same connection when the plan is enterprise, and the subscription is not active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :enterprise, status: "canceled"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The 'Tuist Enterprise' plan of the account '#{account.name}' is not active. You can contact contact@tuist.dev to renovate your plan.
             """
           }
  end

  @tag current_month_remote_cache_hits_count: 250
  test "returns an error when the plan is air, and the usage is above the threshold",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :air}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

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

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :pro, status: "canceled"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

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

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :pro, status: "active"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

    # Then
    assert got == conn
  end

  @tag current_month_remote_cache_hits_count: 1000
  test "returns the same connection the plan is open_source, and the subscription is active",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :open_source, status: "active"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

    # Then
    assert got == conn
  end

  @tag current_month_remote_cache_hits_count: 1000
  test "returns the an error if the plan is open_source, and the subscription is canceled",
       %{conn: conn, project: project} do
    # Given
    account = project.account

    stub(Billing, :get_current_active_subscription, fn ^account ->
      %Subscription{plan: :open_source, status: "canceled"}
    end)

    plug_opts = BillingPlug.init([])

    conn =
      assign(
        %{conn | query_params: Map.put(conn.query_params, "cache_category", "builds")},
        :selected_project,
        project
      )

    # When
    got = BillingPlug.call(conn, plug_opts)

    # Then
    assert json_response(got, :payment_required) == %{
             "message" => ~s"""
             The account '#{account.name}' 'Tuist Open Source' plan is not active. You can contact Tuist at contact@tuist.dev to renovate it, or upgrade to 'Tuist Pro' at #{url(~p"/#{account.name}/billing/upgrade")}.
             """
           }
  end
end
