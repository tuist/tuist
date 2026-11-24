defmodule TuistWeb.API.TelemetryController do
  @moduledoc """
  Telemetry from Tuist's own clients, forwarded to the Pulse of the account the
  server is configured with (`Tuist.Pulse.own_telemetry?/0`).

  The clients run on people's devices and Pulse is internal to the cluster, so
  they send their batches here with their own signed-in session. The session
  decides who is sending (`@producers`): its app names the producer, whose
  policy confines what it may write and under which service. Today that is
  only Luft (`Tuist.Pulse.LuftTelemetry`, the service `luft-client`); other
  credentials get a 403 (`TuistWeb.Plugs.AppSessionPlug`). The endpoints
  follow the conventions client SDKs implement, so a stock exporter given the
  base URL and an `Authorization` header works:

    * `POST /api/telemetry/v1/{traces,logs,metrics}` is an OTLP/HTTP receiver
      (https://opentelemetry.io/docs/specs/otlp/#otlphttp): binary protobuf or
      JSON, optionally gzipped; a success is the signal's
      `Export…ServiceResponse` in the request's encoding (a partial success
      counts what the producer's policy rejected), a failure a
      `google.rpc.Status`. Only 429, 502, 503 and 504 are worth retrying, and a
      429 says when in `Retry-After`.
    * `POST /api/telemetry/api/:project_id/envelope/` takes a Sentry envelope,
      the path Sentry SDKs derive from the DSN `<server>/api/telemetry/1`; its
      events become Pulse errors. Failures answer `{"detail": ...}`, and a 429
      carries `Retry-After` and `X-Sentry-Rate-Limits`.

  Both answer 404 when this server takes no telemetry, which tells a client
  to stop sending, and 403 to a user blocked from sending
  (`Tuist.FeatureFlags.telemetry_blocked?/1`), which it should not retry.

  Anyone with a Tuist account can hold a client session, so what a session
  may write is an allowlist and how much is limited per user and across all
  users, in requests and in bytes forwarded (`@requests`, `@user_kib`,
  `@all_kib`), instead of the app session's shared write limit. Not part of
  the public API spec: only Tuist's clients call it.
  """
  use TuistWeb, :controller

  alias Tuist.FeatureFlags
  alias Tuist.Pulse
  alias Tuist.Pulse.OTLP
  alias TuistWeb.Plugs.DeflateBodyReader
  alias TuistWeb.RateLimit

  # The policy of each app whose session may send telemetry.
  @producers %{"luft" => Tuist.Pulse.LuftTelemetry}

  plug TuistWeb.Plugs.AppSessionPlug, apps: Map.keys(@producers), limit_writes: false

  # Each of a user's devices flushes at most four batches a minute and resends
  # what failed the next minute: 60 requests a minute and a burst of 100 leave
  # room for a dozen devices. The shared limiter refills in whole seconds, so
  # a slower rate would round to nothing between requests seconds apart.
  @requests [capacity: 100, refill_rate: 1]
  # KiB forwarded per user: an 8 MiB burst and 16 KiB/s (about 56 MiB/h).
  @user_kib [capacity: 8192, refill_rate: 16]
  # KiB forwarded across all users, so many accounts can't flood Pulse either.
  @all_kib [capacity: 131_072, refill_rate: 2048]
  # What a request may carry before it is parsed or inflated, as
  # `TuistWeb.Plugs.DeflateBodyReader` holds the endpoint's parsers to.
  @read_limit 4_000_000

  # gRPC status codes for `google.rpc.Status`.
  @invalid_argument 3
  @not_found 5
  @permission_denied 7
  @resource_exhausted 8
  @unavailable 14

  def otlp(conn, %{"signal" => signal}) do
    format = format(conn)

    with true <- (signal in OTLP.signals() and Pulse.own_telemetry?()) || :not_found,
         :ok <- admit_user(conn),
         true <- format != :unsupported || :unsupported,
         :ok <- admit_request(conn),
         {:ok, payload, conn} <- otlp_payload(conn, format),
         {:ok, body, dropped} <- producer(conn).prepare(signal, payload),
         :ok <- admit_bytes(conn, byte_size(body)),
         {:ok, status, response} <- Pulse.forward_otlp(signal, body) do
      if status in 200..299 do
        {rejected, message} = OTLP.rejected(signal, response)
        message = partial_message(signal, dropped, message)

        conn
        |> put_resp_content_type(content_type(format), nil)
        |> send_resp(200, OTLP.response(signal, format, dropped + rejected, message))
      else
        otlp_error(conn, format, {:pulse, status})
      end
    else
      error -> otlp_error(conn, format, error)
    end
  end

  def errors(conn, _params) do
    producer = producer(conn)

    with true <- Pulse.own_telemetry?() || :not_found,
         :ok <- admit_user(conn),
         :ok <- admit_request(conn),
         {:ok, body, conn} <- read(conn),
         true <- byte_size(body) <= producer.max_bytes() || {:error, :too_large, conn},
         {:ok, body} <- producer.prepare_envelope(body),
         :ok <- admit_bytes(conn, byte_size(body)),
         {:ok, status, response, headers} <-
           Pulse.forward_sentry_envelope(producer.service(), "1", body, [
             {"content-type", "application/x-sentry-envelope"}
           ]) do
      conn = Enum.reduce(headers, conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)

      if status in 200..299,
        do: conn |> put_resp_content_type("application/json") |> send_resp(status, response),
        else: sentry_error(conn, {:pulse, status})
    else
      error -> sentry_error(conn, error)
    end
  end

  defp producer(conn), do: Map.fetch!(@producers, conn.assigns.app_session.app)

  defp admit_user(conn), do: if(FeatureFlags.telemetry_blocked?(conn.assigns.app_user), do: :blocked, else: :ok)

  defp format(conn) do
    case get_req_header(conn, "content-type") do
      ["application/x-protobuf" <> _] -> :protobuf
      ["application/json" <> _] -> :json
      _ -> :unsupported
    end
  end

  defp content_type(:protobuf), do: "application/x-protobuf"
  defp content_type(_format), do: "application/json"

  # The endpoint's parsers already decoded JSON; protobuf passes through unread.
  defp otlp_payload(conn, :json) do
    if Map.has_key?(conn.body_params, "_json"),
      do: {:error, :invalid},
      else: {:ok, {:json, conn.body_params}, conn}
  end

  defp otlp_payload(conn, :protobuf) do
    with {:ok, body, conn} <- read(conn), do: {:ok, {:protobuf, body}, conn}
  end

  defp read(conn) do
    case DeflateBodyReader.read_body(conn, length: @read_limit) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial, conn} -> {:error, :too_large, conn}
      {:error, :invalid_deflate_body} -> {:error, :invalid}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp partial_message(_signal, 0, message), do: message

  defp partial_message(signal, _dropped, message) do
    dropped =
      case signal do
        "metrics" -> "Dropped data points outside the accepted metrics or time window."
        "traces" -> "Dropped spans outside the accepted time window."
        "logs" -> "Dropped log records outside the accepted time window."
      end

    String.trim(dropped <> " " <> message)
  end

  defp admit_request(conn), do: hit("telemetry:requests:user:#{conn.assigns.app_user.id}", @requests, 1)

  defp admit_bytes(conn, bytes) do
    kib = max(1, div(bytes + 1023, 1024))

    with :ok <- hit("telemetry:kib:user:#{conn.assigns.app_user.id}", @user_kib, kib) do
      hit("telemetry:kib", @all_kib, kib)
    end
  end

  defp hit(key, bucket, cost) do
    case RateLimit.hit(key, [algorithm: :token_bucket, cost: cost] ++ bucket) do
      {:allow, _count} ->
        :ok

      # The limiter's own wait is a fixed second for token buckets, so the
      # wait is at least what refilling `cost` tokens takes.
      {:deny, retry_after_ms} ->
        refill_ms = ceil(cost / Keyword.fetch!(bucket, :refill_rate) * 1000)
        {:throttled, max(1, div(max(retry_after_ms, refill_ms) + 999, 1000))}
    end
  end

  # Pulse's own 429 carries no wait; its admission recovers within a minute.
  @pulse_retry_after 30

  defp retry_after({:throttled, seconds}), do: seconds
  defp retry_after({:pulse, 429}), do: @pulse_retry_after
  defp retry_after(_error), do: nil

  defp otlp_error(conn, format, error) do
    format = if format == :protobuf, do: :protobuf, else: :json
    {status, code, message} = failure(error)

    conn =
      case {error, retry_after(error)} do
        {{:error, :too_large, read}, _} -> read
        {_, nil} -> conn
        {_, seconds} -> put_resp_header(conn, "retry-after", Integer.to_string(seconds))
      end

    conn
    |> put_resp_content_type(content_type(format), nil)
    |> send_resp(status, OTLP.status(format, code, message))
  end

  # Pulse already supplied category-specific backoff. Only locally enforced
  # request/byte limits below restrict every category.
  defp sentry_error(conn, {:pulse, _status} = error) do
    {status, _code, message} = failure(error)
    conn |> put_status(status) |> json(%{detail: message})
  end

  defp sentry_error(conn, error) do
    {status, _code, message} = failure(error)

    conn =
      case {error, retry_after(error)} do
        {{:error, :too_large, read}, _} ->
          read

        {_, nil} ->
          conn

        {_, seconds} ->
          conn
          |> put_resp_header("retry-after", Integer.to_string(seconds))
          |> put_resp_header("x-sentry-rate-limits", "#{seconds}::organization")
      end

    conn |> put_status(status) |> json(%{detail: message})
  end

  defp failure(:not_found), do: {404, @not_found, "This server does not take telemetry."}
  defp failure(:blocked), do: {403, @permission_denied, "This account may not send telemetry."}

  defp failure(:unsupported), do: {415, @invalid_argument, "Send OTLP as application/x-protobuf or application/json."}

  defp failure({:error, :invalid}), do: {400, @invalid_argument, "The telemetry is not a valid request."}
  defp failure({:error, :too_large}), do: too_large()
  defp failure({:error, :too_large, _conn}), do: too_large()
  defp failure({:throttled, _seconds}), do: {429, @resource_exhausted, "Too much telemetry. Try again later."}
  defp failure({:error, :not_configured}), do: {503, @unavailable, "Pulse is not configured."}
  defp failure({:error, :unavailable}), do: {503, @unavailable, "Pulse is unavailable."}

  # Pulse's answer describes the batch when it rejects its data or its rate;
  # anything else is the server's own writer failing, which is worth retrying.
  defp failure({:pulse, 400}), do: {400, @invalid_argument, "Pulse rejected the telemetry."}
  defp failure({:pulse, 413}), do: too_large()
  defp failure({:pulse, 429}), do: {429, @resource_exhausted, "Pulse is throttling telemetry."}
  defp failure({:pulse, _status}), do: {502, @unavailable, "Pulse rejected the telemetry."}

  defp too_large, do: {413, @resource_exhausted, "The batch is larger than 1 MiB."}
end
