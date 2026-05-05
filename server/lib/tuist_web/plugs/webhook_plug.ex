defmodule TuistWeb.Plugs.WebhookPlug do
  @moduledoc """
  Generic webhook handler with HMAC signature verification.

  Supports different signature formats and headers through configuration.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  defmodule CacheBodyReader do
    @moduledoc false

    def read_body(conn, opts) do
      case Plug.Conn.read_body(conn, opts) do
        {:ok, body, conn} ->
          {:ok, body, cache_raw_body(conn, body)}

        {:more, body, conn} ->
          {:more, body, cache_raw_body(conn, body)}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp cache_raw_body(conn, body) do
      update_in(conn.assigns[:raw_body], fn
        nil -> body
        existing -> [existing, body]
      end)
    end
  end

  @impl true
  def init(options) do
    read_timeout = Keyword.get(options, :read_timeout, 15_000)
    body_length = Keyword.get(options, :body_length)

    parser_options =
      maybe_put_parser_option(
        [
          parsers: [:json],
          body_reader: {CacheBodyReader, :read_body, []},
          json_decoder: Phoenix.json_library(),
          read_timeout: read_timeout
        ],
        :length,
        body_length
      )

    parser_opts =
      Plug.Parsers.init(parser_options)

    Keyword.put(options, :parser_opts, parser_opts)
  end

  @doc """
  Verifies HMAC signature and calls a handler with the webhook payload
  """
  @impl true
  def call(conn, options) do
    path = get_config(options, :at)

    case conn.request_path do
      ^path ->
        handle_webhook(conn, options)

      _ ->
        conn
    end
  end

  defp handle_webhook(conn, options) do
    module = get_config(options, :handler)
    signature_header = get_config(options, :signature_header) || "x-hub-signature-256"
    signature_prefix = get_config(options, :signature_prefix)
    parser_opts = get_config(options, :parser_opts)
    signature = conn |> get_req_header(signature_header) |> List.first()

    if is_nil(signature) do
      conn
      |> send_resp(401, "Missing #{signature_header} header")
      |> halt()
    else
      conn = parse_request_body(conn, parser_opts)

      if conn.halted do
        conn
      else
        # Secret resolution may depend on the parsed body (e.g. webhooks
        # whose signing secret is per-installation, not global), so it
        # has to happen after parse_request_body.
        case resolve_secret(get_config(options, :secret), conn) do
          {:ok, secret} ->
            if valid_signature?(conn, secret, signature, signature_prefix) do
              handle_verified_webhook(conn, module)
            else
              conn
              |> send_resp(403, "Invalid signature")
              |> halt()
            end

          {:error, reason} ->
            conn
            |> send_resp(403, "Invalid signature: #{reason}")
            |> halt()
        end
      end
    end
  end

  defp resolve_secret(config, conn) do
    case parse_secret!(config, conn) do
      nil -> {:error, "no secret"}
      secret when is_binary(secret) -> {:ok, secret}
      {:ok, secret} when is_binary(secret) -> {:ok, secret}
      {:error, reason} -> {:error, reason}
      other -> {:error, "unexpected secret: #{inspect(other)}"}
    end
  end

  defp handle_verified_webhook(conn, module) do
    result_conn = module.handle(conn, conn.body_params)

    if result_conn.status do
      result_conn
    else
      result_conn |> send_resp(200, "OK") |> halt()
    end
  end

  defp verify_signature(payload, secret, signature_in_header, signature_prefix) do
    expected_signature =
      :hmac
      |> :crypto.mac(:sha256, secret, payload)
      |> Base.encode16(case: :lower)

    expected_signature_with_prefix =
      if signature_prefix do
        signature_prefix <> expected_signature
      else
        expected_signature
      end

    Plug.Crypto.secure_compare(signature_in_header, expected_signature_with_prefix)
  end

  defp valid_signature?(conn, secret, signature, signature_prefix) do
    conn.assigns.raw_body
    |> List.wrap()
    |> IO.iodata_to_binary()
    |> verify_signature(secret, signature, signature_prefix)
  end

  defp parse_request_body(conn, parser_opts) do
    Plug.Parsers.call(conn, parser_opts)
  rescue
    error in Bandit.HTTPError ->
      if error.plug_status == :request_timeout do
        conn
        |> send_resp(408, "Request Timeout")
        |> halt()
      else
        reraise error, __STACKTRACE__
      end

    Plug.Parsers.RequestTooLargeError ->
      conn
      |> send_resp(413, "Payload Too Large")
      |> halt()
  end

  defp maybe_put_parser_option(options, _key, nil), do: options
  defp maybe_put_parser_option(options, key, value), do: Keyword.put(options, key, value)

  defp parse_secret!({m, f, a}, _conn), do: apply(m, f, a)
  defp parse_secret!(fun, conn) when is_function(fun, 1), do: fun.(conn)
  defp parse_secret!(fun, _conn) when is_function(fun, 0), do: fun.()
  defp parse_secret!(secret, _conn) when is_binary(secret), do: secret

  defp parse_secret!(secret, _conn) do
    raise """
    The webhook secret is invalid. Expected a string, tuple, or function.
    Got: #{inspect(secret)}

    If you're setting the secret at runtime, pass a tuple or function.
    Functions can be `arity 0` (no args) or `arity 1` (receives the
    parsed conn so the secret can depend on the body, e.g. for
    per-tenant webhooks). For example:

    plug TuistWeb.Plugs.WebhookPlug,
      at: "/webhook/example",
      handler: MyHandler,
      secret: {Application, :get_env, [:myapp, :webhook_secret]},
      signature_header: "x-signature",
      signature_prefix: "sha256="
    """
  end

  defp get_config(options, key) do
    options[key]
  end
end
