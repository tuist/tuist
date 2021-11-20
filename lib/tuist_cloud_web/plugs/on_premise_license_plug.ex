defmodule TuistCloudWeb.OnPremiseLicensePlug do
  @moduledoc """
  This module contains plugs specific to on-premise customers.
  """
  import Plug.Conn
  use TuistCloudWeb, :controller
  alias TuistCloud.Environment

  def init(:api), do: :api

  def call(conn, _opts) do
    if Environment.on_premise?() do
      cond do
        Environment.license_expired?() ->
          conn
          |> put_status(422)
          |> json(%{
            message: "The license has expired. Please, contact contact@tuist.io to renovate it."
          })

        Environment.license_expiration_days_span() < 30 ->
          TuistCloudWeb.WarningsHeaderPlug.put_warning(
            conn,
            "The license will expire in #{Environment.license_expiration_days_span()} days. Please, contact contact@tuist.io to renovate it."
          )
      end
    else
      conn
    end
  end
end
