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
        handle_webhook(conn, options)

      _ ->
        conn
    end
  end

  defp handle_webhook(conn, options) do
    secret = parse_secret!(get_config(options, :secret))
    module = get_config(options, :handler)
    signature_header = get_config(options, :signature_header) || "x-hub-signature-256"
    signature_prefix = get_config(options, :signature_prefix)

    conn = Plug.Parsers.call(conn, @plug_parser)
    signature = conn |> get_req_header(signature_header) |> List.first()

    cond do
      is_nil(signature) ->
        conn
        |> send_resp(401, "Missing #{signature_header} header")
        |> halt()

      conn.assigns.raw_body
      |> List.flatten()
      |> IO.iodata_to_binary()
      |> verify_signature(
        secret,
        signature,
        signature_prefix
      ) ->
        handle_verified_webhook(conn, module)

      true ->
        conn
        |> send_resp(403, "Invalid signature")
        |> halt()
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

  defp parse_secret!({m, f, a}), do: apply(m, f, a)
  defp parse_secret!(fun) when is_function(fun), do: fun.()
  defp parse_secret!(secret) when is_binary(secret), do: secret

  defp parse_secret!(secret) do
    raise """
    The webhook secret is invalid. Expected a string, tuple, or function.
    Got: #{inspect(secret)}

    If you're setting the secret at runtime, you need to pass a tuple or function.
    For example:

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
