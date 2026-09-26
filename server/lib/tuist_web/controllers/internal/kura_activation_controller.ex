defmodule TuistWeb.Internal.KuraActivationController do
  use TuistWeb, :controller

  alias Tuist.Kura.Activation
  alias TuistWeb.Authentication

  # This is the gateway's control protocol, not part of the public CLI API.
  # Cache-scoped JWTs are accepted here without making them API credentials.
  def create(conn, params) do
    conn = put_resp_header(conn, "cache-control", "no-store")
    token = Authentication.get_authorization_token_from_conn(conn)

    case Activation.resolve(params["host"], token) do
      {:ok, endpoint} -> json(conn, %{endpoint: endpoint})
      :pending -> conn |> put_status(:accepted) |> json(%{status: "provisioning"})
      {:error, status} -> conn |> put_status(status) |> json(%{error: status})
    end
  end
end
