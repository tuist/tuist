defmodule TuistWeb.API.Authorization.BillingPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Environment

  def init(opts), do: opts

  def call(conn, params) do
    if Environment.tuist_hosted?() do
      call_tuist_hosted(conn, params)
    else
      call_on_premise(conn, params)
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
    subscription_data =
      if Map.get(conn.assigns, :caching, false) do
        Tuist.KeyValueStore.get_or_update(
          [
            Atom.to_string(__MODULE__),
            "subscription_data",
            conn.assigns[:selected_project].id
          ],
          [
            ttl: Map.get(conn.assigns, :cache_ttl, to_timeout(minute: 1)),
            cache: Map.get(conn.assigns, :cache, :tuist),
            locking: true
          ],
          fn ->
            get_subscription_data(conn)
          end
        )
      else
        get_subscription_data(conn)
      end

    case subscription_data do
      {:enterprise, true, _, _} ->
        conn

      {:enterprise, false, _, account_handle} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The 'Tuist Enterprise' plan of the account '#{account_handle}' is not active. You can contact contact@tuist.dev to renovate your plan.
          """
        })
        |> halt()

      {:air, _, false, _} ->
        conn

      {:air, _, true, account_handle} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account_handle}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'. You can upgrade your plan at #{url(~p"/#{account_handle}/billing/upgrade")}.
          """
        })
        |> halt()

      {:pro, false, _, account_handle} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account_handle}' 'Tuist Pro' plan is not active. You can manage your billing at #{url(~p"/#{account_handle}/billing/manage")}.
          """
        })
        |> halt()

      {:pro, true, _, _} ->
        conn

      {:open_source, false, _, account_handle} ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account_handle}' 'Tuist Open Source' plan is not active. You can contact Tuist at contact@tuist.dev to renovate it, or upgrade to 'Tuist Pro' at #{url(~p"/#{account_handle}/billing/upgrade")}.
          """
        })
        |> halt()

      {:open_source, true, _, _} ->
        conn
    end
  end

  defp get_subscription_data(%{assigns: %{selected_project: selected_project}}) do
    {:ok, account} = Accounts.get_account_by_id(selected_project.account_id)
    %{current_month_remote_cache_hits_count: current_month_remote_cache_hits_count} = account

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

    {subscription_plan, subscription_active?, thresholds_surpassed, account.name}
  end
end
