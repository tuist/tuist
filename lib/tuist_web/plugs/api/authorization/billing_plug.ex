defmodule TuistWeb.API.Authorization.BillingPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Billing
  alias Tuist.Accounts
  alias TuistWeb.API.EnsureProjectPresencePlug
  alias Tuist.Environment

  def init(opts), do: opts

  def call(conn, params) do
    if Environment.on_premise?() do
      call_on_premise(conn, params)
    else
      call_tuist_hosted(conn, params)
    end
  end

  defp call_on_premise(conn, _) do
    case Tuist.License.get_license() do
      {:ok, %{valid: true}} ->
        conn

      _ ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The current license is expired. Please update your license to continue using the service. Contact your administrator for more information.
          """
        })
        |> halt()
    end
  end

  # credo:disable-for-next-line
  def call_tuist_hosted(conn, _) do
    account =
      %{current_month_remote_cache_hits_count: current_month_remote_cache_hits_count} =
      Accounts.get_account_by_id(EnsureProjectPresencePlug.get_project(conn).account_id)

    subscription = Billing.get_current_active_subscription(account)

    thresholds_surpassed =
      current_month_remote_cache_hits_count >=
        Billing.get_payment_thresholds()[:remote_cache_hits]

    subscription_plan = if(is_nil(subscription), do: :air, else: subscription.plan)

    subscription_active? =
      if(is_nil(subscription),
        do: subscription_plan == :air,
        else: subscription.status == "active"
      )

    case {subscription_plan, subscription_active?, thresholds_surpassed} do
      {:enterprise, true, _} ->
        conn

      {:enterprise, false, _} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The 'Tuist Enterprise' plan of the account '#{account.name}' is not active. You can contact sales@tuist.io to renovate your plan.
          """
        })
        |> halt()

      {:air, _, false} ->
        conn

      {:air, _, true} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account.name}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account.name}/billing/upgrade")}.
          """
        })
        |> halt()

      {:pro, false, _} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account.name}' 'Tuist Pro' plan is not active. You can manage your billing at #{url(~p"/#{account.name}/billing/manage")}.
          """
        })
        |> halt()

      {:pro, true, _} ->
        conn

      {:open_source, false, _} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account.name}' 'Tuist Open Source' plan is not active. You can contact Tuist at contact@tuist.io to renovate it, or upgrade to 'Tuist Pro' at #{url(~p"/#{account.name}/billing/upgrade")}.
          """
        })
        |> halt()

      {:open_source, true, _} ->
        conn
    end
  end
end
