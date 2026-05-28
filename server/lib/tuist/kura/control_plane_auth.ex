defmodule Tuist.Kura.ControlPlaneAuth do
  @moduledoc """
  Authenticates Kura control-plane service calls.
  """

  alias Tuist.Environment
  alias Tuist.OAuth.Clients

  def authorize(conn, grant_type) do
    with {:ok, client_id, client_secret} <- basic_credentials(conn),
         true <- Environment.kura_control_plane_configured?(),
         true <- client_id == Environment.kura_control_plane_client_id(),
         %{secret: expected_secret, supported_grant_types: grant_types} <- Clients.get_client(client_id),
         true <- secure_compare(client_secret, expected_secret),
         true <- grant_type in grant_types do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp basic_credentials(conn) do
    with ["Basic " <> encoded] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [client_id, client_secret] <- String.split(decoded, ":", parts: 2) do
      {:ok, client_id, client_secret}
    else
      _ -> {:error, :missing_credentials}
    end
  end

  defp secure_compare(left, right) when is_binary(left) and is_binary(right) do
    Plug.Crypto.secure_compare(left, right)
  rescue
    _ -> false
  end

  defp secure_compare(_left, _right), do: false
end
