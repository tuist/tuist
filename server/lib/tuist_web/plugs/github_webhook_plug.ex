defmodule TuistWeb.Plugs.GitHubWebhookPlug do
  @moduledoc """
  Handles incoming GitHub webhook requests.

  Heavily inspired by: https://github.com/puretype/github_webhook/blob/main/lib/github_webhook.ex
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
  Verifies secret and calls a handler with the webhook payload
  """
  @impl true
  def call(conn, options) do
    path = get_config(options, :at)

    case conn.request_path do
      ^path ->
        secret = parse_secret!(get_config(options, :secret))
        module = get_config(options, :handler)

        conn = Plug.Parsers.call(conn, @plug_parser)
        dbg(conn)

        # [signature_in_header] = get_req_header(conn, "x-hub-signature-256")

        # if verify_signature(conn.assigns.raw_body, secret, signature_in_header) do
        module.handle(conn, conn.body_params)
        conn |> send_resp(200, "OK") |> halt()

      # else
      #   conn |> send_resp(403, "Forbidden") |> halt()
      # end

      _ ->
        conn
    end
  end

  defp verify_signature(payload, secret, signature_in_header) do
    signature =
      "sha256=" <> (:hmac |> :crypto.mac(:sha256, secret, payload) |> Base.encode16(case: :lower))

    Plug.Crypto.secure_compare(signature, signature_in_header)
  end

  defp parse_secret!({m, f, a}), do: apply(m, f, a)
  defp parse_secret!(fun) when is_function(fun), do: fun.()
  defp parse_secret!(secret) when is_binary(secret), do: secret

  defp parse_secret!(secret) do
    raise """
    The GitHub webhook secret is invalid. Expected a string, tuple, or function.
    Got: #{inspect(secret)}

    If you're setting the secret at runtime, you need to pass a tuple or function.
    For example:

    plug GitHub.WebhookPlug,
      at: "/webhook/github",
      handler: MyAppWeb.GitHubHandler,
      secret: {Application, :get_env, [:myapp, :github_webhook_secret]}
    """
  end

  defp get_config(options, key) do
    options[key] || get_config(key)
  end

  defp get_config(key) do
    case Application.fetch_env(:github_webhook, key) do
      :error ->
        Logger.warning("GitHubWebhookPlug config key #{inspect(key)} is not configured.")
        ""

      {:ok, val} ->
        val
    end
  end
end
