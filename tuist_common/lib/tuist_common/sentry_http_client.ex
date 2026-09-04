defmodule TuistCommon.SentryHTTPClient do
  @moduledoc """
  Sentry HTTP client that uses Finch.

  ## Runtime rerouting

  The client can be told, per request, to POST to a different endpoint than
  the one the Sentry SDK computed from `config :sentry, :dsn`. Opt in by
  setting

      config :tuist_common, TuistCommon.SentryHTTPClient,
        reroute: {SomeModule, :some_function, []}

  The MFA is invoked on every `post/3`. Returning `nil` (the default when no
  reroute is configured) sends the request to the Sentry-computed endpoint
  unchanged. Returning `%{endpoint_uri: uri, public_key: key, secret_key:
  secret_or_nil}` replaces the URL and rewrites `sentry_key` / `sentry_secret`
  in the `X-Sentry-Auth` header so the receiving ingest accepts the envelope
  under its own project credentials.
  """

  @behaviour Sentry.HTTPClient

  @finch_name TuistCommon.SentryFinch

  @impl true
  def child_spec do
    Supervisor.child_spec({Finch, name: @finch_name}, id: @finch_name)
  end

  @impl true
  def post(url, headers, body) do
    {url, headers} = apply_reroute(url, headers)

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, @finch_name) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, status, headers, body}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Applies the reroute callback (if configured) to `{url, headers}`, returning
  either the original pair or a rewritten one aimed at an alternate ingest.

  Exposed as a public function so the rewrite can be exercised in isolation.
  """
  def apply_reroute(url, headers) do
    case reroute_target() do
      %{endpoint_uri: new_url, public_key: public_key} = target ->
        secret_key = Map.get(target, :secret_key)
        {new_url, rewrite_auth_header(headers, public_key, secret_key)}

      _ ->
        {url, headers}
    end
  end

  defp reroute_target do
    with cfg when is_list(cfg) <- Application.get_env(:tuist_common, __MODULE__),
         {mod, fun, args} <- Keyword.get(cfg, :reroute) do
      apply(mod, fun, args)
    else
      _ -> nil
    end
  end

  defp rewrite_auth_header(headers, public_key, secret_key) do
    Enum.map(headers, fn
      {"X-Sentry-Auth", value} ->
        {"X-Sentry-Auth", rewrite_auth_value(value, public_key, secret_key)}

      other ->
        other
    end)
  end

  defp rewrite_auth_value("Sentry " <> params, public_key, secret_key) do
    kept =
      params
      |> String.split(", ")
      |> Enum.reject(fn part ->
        String.starts_with?(part, "sentry_key=") or
          String.starts_with?(part, "sentry_secret=")
      end)

    replacement =
      case secret_key do
        nil -> ["sentry_key=#{public_key}"]
        secret -> ["sentry_key=#{public_key}", "sentry_secret=#{secret}"]
      end

    "Sentry " <> Enum.join(kept ++ replacement, ", ")
  end

  defp rewrite_auth_value(other, _public_key, _secret_key), do: other
end
