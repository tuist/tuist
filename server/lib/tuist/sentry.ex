defmodule Tuist.Sentry do
  @moduledoc """
  Sentry integration surface for the server.

  Right now this module carries the runtime switch that lets us reroute
  error envelopes from Sentry to the self-hosted Hive ingest without a
  deploy. `TuistCommon.SentryHTTPClient` calls `hive_reroute_target/0`
  on every request: when it returns a target, the client rewrites the
  destination URL and the `X-Sentry-Auth` header; when it returns `nil`,
  envelopes continue to Sentry unchanged. See
  `Tuist.FeatureFlags.hive_error_tracking_enabled?/0` for the flag polarity
  and `runtime.exs` for the wiring.
  """

  alias Tuist.Environment
  alias Tuist.FeatureFlags

  @doc """
  Reroute target for `TuistCommon.SentryHTTPClient`.

  Returns `nil` when the Hive kill switch is off, when no Hive DSN is
  configured on this node, or when the configured DSN cannot be parsed.
  Returns `%{endpoint_uri: uri, public_key: key, secret_key: secret_or_nil}`
  when the client should POST to Hive instead of Sentry.
  """
  def hive_reroute_target do
    if FeatureFlags.hive_error_tracking_enabled?() do
      parsed_hive_target()
    end
  end

  defp parsed_hive_target do
    case Environment.sentry_hive_dsn() do
      dsn when is_binary(dsn) and dsn != "" ->
        case Sentry.DSN.parse(dsn) do
          {:ok, %Sentry.DSN{} = parsed} ->
            %{
              endpoint_uri: parsed.endpoint_uri,
              public_key: parsed.public_key,
              secret_key: parsed.secret_key
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end
end
