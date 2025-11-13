defmodule TuistWeb.Plugs.CacheAuthPlug do
  @moduledoc """
  Plug to authenticate cache API requests using HMAC signature verification.

  This plug must run in the endpoint BEFORE Plug.Parsers to access the raw body.
  """

  @behaviour Plug

  import Phoenix.Controller
  import Plug.Conn

  require Logger

  defmodule CacheBodyReader do
    @moduledoc false

    def read_body(conn, opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
      conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
      {:ok, body, conn}
    end
  end

  @plug_parser Plug.Parsers.init(
                 parsers: [:json],
                 body_reader: {CacheBodyReader, :read_body, []},
                 json_decoder: Phoenix.json_library()
               )

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, options) do
    path_prefix = get_config(options, :at)

    if String.starts_with?(conn.request_path, path_prefix) do
      verify_cache_request(conn)
    else
      conn
    end
  end

  defp verify_cache_request(conn) do
    secret = Tuist.Environment.cache_api_key()

    if is_nil(secret) or secret == "" do
      Logger.error("TUIST_CACHE_API_KEY environment variable not configured")

      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Server misconfiguration"})
      |> halt()
    else
      signature = conn |> get_req_header("x-signature") |> List.first()

      if is_nil(signature) do
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Missing x-signature header"})
        |> halt()
      else
        # Parse the body and capture raw body
        conn = Plug.Parsers.call(conn, @plug_parser)
        raw_body = conn.assigns.raw_body |> List.flatten() |> IO.iodata_to_binary()

        Logger.debug("Cache auth - Secret: #{secret}")
        Logger.debug("Cache auth - Body length: #{byte_size(raw_body)}")
        Logger.debug("Cache auth - Body: #{raw_body}")
        Logger.debug("Cache auth - Received signature: #{signature}")

        # Compute expected signature: HMAC-SHA256(secret, body)
        expected_signature =
          :hmac
          |> :crypto.mac(:sha256, secret, raw_body)
          |> Base.encode16(case: :lower)

        Logger.debug("Cache auth - Expected signature: #{expected_signature}")

        if Plug.Crypto.secure_compare(signature, expected_signature) do
          conn
        else
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Invalid signature"})
          |> halt()
        end
      end
    end
  end

  defp get_config(options, key) do
    options[key]
  end
end
