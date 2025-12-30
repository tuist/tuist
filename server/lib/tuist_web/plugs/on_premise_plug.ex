defmodule TuistWeb.OnPremisePlug do
  @moduledoc """
  This module contains plugs specific to on-premise customers.
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.License
  alias Tuist.Time
  alias TuistWeb.Authentication

  def init(:api_license_validation), do: :api_license_validation
  def init(:forward_marketing_to_dashboard), do: :forward_marketing_to_dashboard

  def call(conn, opts) do
    if Environment.tuist_hosted?() do
      conn
    else
      call_on_premise(conn, opts)
    end
  end

  def call_on_premise(conn, :api_license_validation) do
    case License.get_license() do
      {:ok, %{valid: true, expiration_date: expiration_date}} ->
        if Date.diff(expiration_date, Time.utc_now()) < 30 do
          TuistWeb.WarningsHeaderPlug.put_warning(
            conn,
            "The license will expire in #{DateTime.diff(expiration_date, Time.utc_now(), :day)} days. Please, contact contact@tuist.dev to renovate it."
          )
        else
          conn
        end

      {:ok, %{valid: true}} ->
        conn

      _ ->
        conn
        |> put_status(422)
        |> json(%{
          message: "The license has expired. Please, contact contact@tuist.dev to renovate it."
        })
        |> halt()
    end
  end

  def call_on_premise(conn, :forward_marketing_to_dashboard) do
    current_user = Authentication.current_user(conn)

    if is_nil(current_user) do
      conn |> redirect(to: ~p"/users/log_in") |> halt()
    else
      conn |> redirect(to: Authentication.signed_in_path(current_user)) |> halt()
    end
  end
end
