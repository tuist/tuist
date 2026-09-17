defmodule AtlasWeb.ErrorsAPI.EnvelopeController do
  @moduledoc """
  Sentry-compatible ingest endpoint. Accepts envelopes at
  `POST /api/:project_id/envelope/`, validates the DSN, and ingests
  event items inline via `Atlas.Engineering.Errors.ingest_envelope/3` — the actual
  ClickHouse write is buffered by `Atlas.Engineering.Errors.Event.Buffer`, so the
  request returns quickly without paying an Oban round-trip per event.

  This endpoint is public but authenticated by DSN public key. The
  `X-Sentry-Auth` header (or `?sentry_key=` fallback, or a `dsn`
  field on the envelope header) identifies the project key; the
  key's project must match the URL's `:project_id`. When the key is
  domain-scoped, every event in the envelope inherits its `domain_id`
  attribution — the URL shape does not change.
  """

  use AtlasWeb, :controller

  require Logger

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Auth
  alias Atlas.Engineering.Errors.Envelope

  @max_body_bytes 20 * 1024 * 1024

  def create(conn, %{"project_id" => project_id}) do
    with {:ok, body, conn} <- read_full_body(conn),
         {:ok, body} <- decode_body(body, encoding(conn)),
         {:ok, public_key} <- resolve_public_key(conn, body),
         {:ok, key} <- Errors.fetch_project_key_by_public_key(public_key),
         :ok <- verify_project(key, project_id) do
      event_id = extract_event_id(body)
      :ok = Errors.ingest_envelope(key.project, body, domain_id: key.domain_id)
      Errors.touch_project_key(key)

      conn
      |> put_status(:ok)
      |> put_resp_content_type("application/json")
      |> json(%{id: event_id})
    else
      {:error, :body_too_large} ->
        send_resp(conn, 413, "")

      {:error, :missing_key} ->
        send_resp(conn, 401, "")

      {:error, :not_found} ->
        send_resp(conn, 401, "")

      {:error, :project_mismatch} ->
        send_resp(conn, 403, "")

      {:error, reason} ->
        Logger.warning("errors: ingest failed: #{inspect(reason)}")
        send_resp(conn, 400, "")
    end
  end

  defp read_full_body(conn) do
    do_read(conn, "")
  end

  defp do_read(_conn, acc) when byte_size(acc) > @max_body_bytes,
    do: {:error, :body_too_large}

  defp do_read(conn, acc) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, chunk, conn} -> {:ok, acc <> chunk, conn}
      {:more, chunk, conn} -> do_read(conn, acc <> chunk)
      {:error, _} = err -> err
    end
  end

  defp encoding(conn) do
    conn
    |> Plug.Conn.get_req_header("content-encoding")
    |> List.first()
    |> case do
      nil -> nil
      value -> value |> String.downcase() |> String.trim()
    end
  end

  defp decode_body(body, nil), do: {:ok, body}
  defp decode_body(body, ""), do: {:ok, body}
  defp decode_body(body, "identity"), do: {:ok, body}
  defp decode_body(body, "gzip"), do: bounded_inflate(body, 31)
  defp decode_body(body, "deflate"), do: bounded_inflate(body, 15)
  defp decode_body(_body, _other), do: {:error, :unsupported_encoding}

  # Guard against decompression bombs: a Software Development Kit key
  # holder could submit a small gzip body that expands to gigabytes.
  # Feed the inflate stream in chunks and stop as soon as the decoded
  # size crosses `@max_body_bytes`; anything larger is rejected with
  # 413 upstream, matching the raw-body cap.
  defp bounded_inflate(body, window_bits) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, window_bits)
      inflate_stream(z, body, [], 0)
    rescue
      _ -> {:error, :invalid_encoding}
    after
      _ = safe_inflate_end(z)
      :zlib.close(z)
    end
  end

  @inflate_chunk 65_536

  defp inflate_stream(_z, _rest, _acc, size) when size > @max_body_bytes,
    do: {:error, :body_too_large}

  defp inflate_stream(_z, <<>>, acc, _size) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp inflate_stream(z, rest, acc, size) do
    {chunk, tail} = take_chunk(rest)
    output = :zlib.inflate(z, chunk)
    output_bytes = IO.iodata_length(output)
    inflate_stream(z, tail, [output | acc], size + output_bytes)
  end

  defp take_chunk(binary) when byte_size(binary) <= @inflate_chunk do
    {binary, <<>>}
  end

  defp take_chunk(binary) do
    <<head::binary-size(@inflate_chunk), tail::binary>> = binary
    {head, tail}
  end

  defp safe_inflate_end(z) do
    :zlib.inflateEnd(z)
  rescue
    _ -> :ok
  end

  defp resolve_public_key(conn, body) do
    case Auth.extract(conn) do
      {:ok, key} ->
        {:ok, key}

      {:error, :missing_key} ->
        case envelope_dsn(body) do
          {:ok, dsn} -> Auth.extract_from_dsn(dsn)
          :error -> {:error, :missing_key}
        end
    end
  end

  defp envelope_dsn(body) do
    case Envelope.parse(body) do
      {:ok, %{header: %{"dsn" => dsn}}} when is_binary(dsn) -> {:ok, dsn}
      _ -> :error
    end
  end

  defp verify_project(key, project_id) do
    if to_string(key.dsn_project_id) == to_string(project_id),
      do: :ok,
      else: {:error, :project_mismatch}
  end

  defp extract_event_id(body) do
    case Envelope.parse(body) do
      {:ok, %{header: %{"event_id" => id}}} when is_binary(id) ->
        String.replace(id, "-", "")

      {:ok, %{items: items}} ->
        items
        |> Enum.find_value(fn
          %Envelope.Item{type: "event", payload: payload} ->
            case Jason.decode(payload) do
              {:ok, %{"event_id" => id}} when is_binary(id) -> String.replace(id, "-", "")
              _ -> nil
            end

          _ ->
            nil
        end)
        |> case do
          nil -> random_event_id()
          id -> id
        end

      _ ->
        random_event_id()
    end
  end

  defp random_event_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
