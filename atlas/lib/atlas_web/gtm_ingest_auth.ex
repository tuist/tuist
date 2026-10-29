defmodule AtlasWeb.GTMIngestAuth do
  @moduledoc """
  Bearer authentication for the Loops-compatible email endpoints.

  Loops authenticates with `Authorization: Bearer <api key>`, so the contact and
  transactional endpoints accept the same scheme and callers only swap the key.
  The token is unset by default, which keeps both endpoints closed until
  `ATLAS_GTM_INGEST_TOKEN` is configured.
  """

  import Plug.Conn, only: [get_req_header: 2]

  alias Atlas.GTM

  def authorize(conn) do
    case GTM.email_contact_ingest_token() do
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
