defmodule TuistWeb.API.Authorization.BillingPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias TuistWeb.WarningsHeaderPlug
  alias Tuist.Billing
  alias Tuist.Accounts
  alias TuistWeb.API.EnsureProjectPresencePlug
  alias Tuist.Environment
  @remote_cache_hits_threshold 200

  def init(opts), do: opts

  def call(conn, params) do
    if Environment.on_premise?() do
      call_on_premise(conn, params)
    else
      call_tuist_hosted(conn, params)
    end
  end

  defp call_on_premise(conn, _) do
    license_valid? = Tuist.License.valid?()

    if license_valid? do
      conn
    else
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

  def call_tuist_hosted(conn, _) do
    account = Accounts.get_account_by_id(EnsureProjectPresencePlug.get_project(conn).account_id)
    subscription = Billing.get_current_active_subscription(account)

    case {subscription, account.current_month_remote_cache_hits_count} do
      {nil, hits} when hits > @remote_cache_hits_threshold ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account.name}' has reached the limit of remote cache hits #{@remote_cache_hits_threshold} of the 'Tuist Air' plan and requires payment. Manage your billing at #{url(~p"/#{account.name}/billing")}.
          """
        })
        |> halt()

      {nil, hits} when hits <= @remote_cache_hits_threshold ->
        conn

      {_, _} ->
        days_until_end_of_trial =
          if is_nil(subscription.trial_end) do
            nil
          else
            DateTime.diff(subscription.trial_end, Tuist.Time.utc_now(), :day)
          end

        cond do
          is_nil(days_until_end_of_trial) ->
            conn

          days_until_end_of_trial == 0 ->
            conn
            |> WarningsHeaderPlug.put_warning(
              "Your trial period ends today. Please update your billing information to avoid service interruption: #{url(~p"/#{account.name}/billing")}"
            )

          days_until_end_of_trial < 3 ->
            conn
            |> WarningsHeaderPlug.put_warning(
              "Your trial period ends in #{days_until_end_of_trial} days. Please update your billing information to avoid service interruption: #{url(~p"/#{account.name}/billing")}"
            )

          true ->
            conn
        end
    end
  end

  def remote_cache_hits_threshold do
    @remote_cache_hits_threshold
  end
end
