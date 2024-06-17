defmodule TuistCloudWeb.API.Authorization.BillingPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistCloudWeb, :controller
  use TuistCloudWeb, :verified_routes

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
    %{account: %{plan: plan, name: account_handle} = account} =
      EnsureProjectPresencePlug.get_project(conn)

    case {plan, Accounts.get_current_month_remote_cache_hits_count(account)} do
      {plan, _} when plan in [:pro, :enterprise, :air] ->
        conn

      {:none, hits} when plan in [:none] and hits < @remote_cache_hits_threshold ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          # credo:disable-for-next-line
          # TODO: Add a link to the billing page
          message: ~s"""
          The account '#{account_handle}' has reached the limit of remote cache hits #{@remote_cache_hits_threshold} of the 'Tuist Air' plan and requires payment. Manage your billing at #{url(~p"/organizations/#{account_handle}/billing")}.
          """
        })
        |> halt()
    end
  end

  def remote_cache_hits_threshold do
    @remote_cache_hits_threshold
  end
end
