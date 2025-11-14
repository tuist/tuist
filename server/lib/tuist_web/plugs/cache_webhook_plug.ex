defmodule TuistWeb.Plugs.CacheWebhookPlug do
  @moduledoc """
  Handles incoming cache node webhook requests with HMAC signature verification.

  This plug must run in the endpoint BEFORE Plug.Parsers to access the raw body.
  """

  @behaviour Plug

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
  def init(options) do
    options
  end

  @doc """
  Verifies HMAC signature and calls a handler with the webhook payload
  """
  @impl true
  def call(conn, options) do
    path = get_config(options, :at)

    case conn.request_path do
      ^path ->
        secret = parse_secret!(get_config(options, :secret))
        module = get_config(options, :handler)

        conn = Plug.Parsers.call(conn, @plug_parser)

        signature = conn |> get_req_header("x-cache-signature") |> List.first()

        if is_nil(signature) do
          conn
          |> send_resp(401, "Missing x-cache-signature header")
          |> halt()
        else
          raw_body = conn.assigns.raw_body |> List.flatten() |> IO.iodata_to_binary()

          if verify_signature(raw_body, secret, signature) do
            module.handle(conn, conn.body_params)
          else
            conn
            |> send_resp(403, "Invalid signature")
            |> halt()
          end
        end

      _ ->
        conn
    end
  end

  defp verify_signature(payload, secret, signature_in_header) do
    expected_signature =
      :hmac
      |> :crypto.mac(:sha256, secret, payload)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(signature_in_header, expected_signature)
  end

  defp parse_secret!({m, f, a}), do: apply(m, f, a)
  defp parse_secret!(fun) when is_function(fun), do: fun.()
  defp parse_secret!(secret) when is_binary(secret), do: secret

  defp parse_secret!(secret) do
    raise """
    The cache webhook secret is invalid. Expected a string, tuple, or function.
    Got: #{inspect(secret)}

    If you're setting the secret at runtime, you need to pass a tuple or function.
    For example:

    plug TuistWeb.Plugs.CacheWebhookPlug,
      at: "/webhooks/cache",
      handler: TuistWeb.Webhooks.CacheController,
      secret: {Tuist.Environment, :cache_api_key, []}
    """
  end

  defp get_config(options, key) do
    options[key] || get_config(key)
  end

  defp get_config(key) do
    case Application.fetch_env(:tuist, key) do
      :error ->
        Logger.warning("CacheWebhookPlug config key #{inspect(key)} is not configured.")
        ""

      {:ok, val} ->
        val
    end
  end
end
