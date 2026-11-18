defmodule AtlasWeb.Oauth.RedirectURIs do
  @moduledoc """
  Redirect URIs that anonymous dynamic client registration may claim, and how
  the consent page names them.

  Registration is unauthenticated, so a registered redirect must be one an
  outsider cannot receive a code at: the loopback interface (CLI and desktop
  MCP clients), the native app and local editor schemes, or the hosted MCP
  clients Atlas supports. Clients registered before this allowlist keep their
  stored redirects; the consent page still names them before any code is issued.
  """

  @loopback_hosts ~w(127.0.0.1 localhost ::1)

  # Private-use schemes handled by apps on the person's own device.
  @native_schemes ~w(dev.tuist.atlas cursor vscode vscode-insiders)

  # Hosted MCP clients' exact OAuth callbacks, so no other page on these hosts
  # (an open redirect or user content) can receive a code.
  @https_callbacks %{
    "claude.ai" => ["/api/mcp/auth_callback"],
    "claude.com" => ["/api/mcp/auth_callback"],
    # ChatGPT uses the stable callback only for servers implementing RFC 9207
    # issuer identification; otherwise it registers a per-connector callback,
    # `/connector/oauth/{callback_id}` (see developers.openai.com/apps-sdk/build/auth).
    "chatgpt.com" => ["/connector_platform_oauth_redirect", {:prefix, "/connector/oauth/"}],
    "vscode.dev" => ["/redirect"],
    "insiders.vscode.dev" => ["/redirect"]
  }

  def allowed?(redirect_uri) when is_binary(redirect_uri) do
    case URI.new(redirect_uri) do
      {:ok, %URI{userinfo: nil, fragment: nil} = uri} -> allowed_uri?(uri)
      _ -> false
    end
  end

  def allowed?(_redirect_uri), do: false

  defp allowed_uri?(%URI{scheme: scheme, host: host}) when scheme in ["http", "https"] and host in @loopback_hosts,
    do: true

  defp allowed_uri?(%URI{scheme: "https", host: host, port: 443, path: path, query: nil})
       when is_map_key(@https_callbacks, host) and is_binary(path) do
    Enum.any?(Map.fetch!(@https_callbacks, host), fn
      {:prefix, prefix} -> callback_id_path?(path, prefix)
      callback -> callback == path
    end)
  end

  defp allowed_uri?(%URI{scheme: scheme}) when scheme in @native_schemes, do: true
  defp allowed_uri?(_uri), do: false

  # One non-empty path segment of URL-safe ID characters after `prefix`.
  defp callback_id_path?(path, prefix) do
    String.starts_with?(path, prefix) and
      String.match?(String.replace_prefix(path, prefix, ""), ~r/\A[A-Za-z0-9_-]+\z/)
  end

  @doc "Where a code for this redirect URI is delivered, in terms a person can check."
  def describe(redirect_uri) when is_binary(redirect_uri) do
    case URI.new(redirect_uri) do
      {:ok, %URI{scheme: scheme, host: host, port: port}} when scheme in ["http", "https"] and is_binary(host) ->
        if host in @loopback_hosts, do: "#{host}:#{port} (this computer)", else: host

      {:ok, %URI{scheme: scheme}} when is_binary(scheme) ->
        "#{scheme}:// (an app on this device)"

      _ ->
        redirect_uri
    end
  end

  def describe(_redirect_uri), do: ""
end
