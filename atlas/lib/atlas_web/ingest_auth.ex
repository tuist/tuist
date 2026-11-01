defmodule AtlasWeb.IngestAuth do
  @moduledoc """
  Bearer authentication for machine-to-machine ingest endpoints.

  Callers such as the Tuist server and marketing site authenticate with
  `Authorization: Bearer <token>`. Each endpoint passes its own configured
  token; an unset token keeps the endpoint closed.
  """

  import Plug.Conn, only: [get_req_header: 2]

  def authorize(conn, token) do
    case token do
      token when is_binary(token) and token != "" ->
        if valid_token?(conn, token), do: :ok, else: {:error, :unauthorized}

      _missing ->
        {:error, :not_configured}
    end
  end

  defp valid_token?(conn, token) do
    conn
    |> get_req_header("authorization")
    |> Enum.any?(fn header ->
      case String.split(header, " ", parts: 2) do
        [scheme, presented] ->
          String.downcase(scheme) == "bearer" and Plug.Crypto.secure_compare(presented, token)

        _other ->
          false
      end
    end)
  end
end
