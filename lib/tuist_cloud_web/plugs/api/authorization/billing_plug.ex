defmodule TuistCloudWeb.API.Authorization.BillingPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistCloudWeb, :controller
  use TuistCloudWeb, :verified_routes

  alias TuistCloud.Billing
  alias TuistCloud.Accounts
  alias TuistCloudWeb.API.EnsureProjectPresencePlug

  @remote_cache_hits_threshold 200

  def init(opts), do: opts

  def call(conn, opts) do
    call(conn, opts, TuistCloud.Environment.new_pricing_model?())
  end

  def call(conn, _, false) do
    conn
  end

  def call(conn, _, true) do
    %{account: %{name: account_handle} = account} =
      EnsureProjectPresencePlug.get_project(conn)

    subscription = Billing.get_current_active_subscription(account)

    case {subscription, Accounts.get_current_month_remote_cache_hits_count(account)} do
      {nil, hits} when hits > @remote_cache_hits_threshold ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          message: ~s"""
          The account '#{account_handle}' has reached the limit of remote cache hits #{@remote_cache_hits_threshold} of the 'Tuist Air' plan and requires payment. Manage your billing at #{url(~p"/#{account_handle}/settings/billing")}.
          """
        })
        |> halt()

      {nil, hits} when hits <= @remote_cache_hits_threshold ->
        conn

      {_, _} ->
        conn
    end
  end

  def remote_cache_hits_threshold do
    @remote_cache_hits_threshold
  end
end
