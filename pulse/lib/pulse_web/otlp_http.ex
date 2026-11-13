defmodule PulseWeb.OTLPHTTP do
  @moduledoc false
  import Plug.Conn

  alias Plug.Conn.Utils
  alias Pulse.OTLP.Ingest
  alias Pulse.Storage.S3

  @doc """
  Handle one OTLP/HTTP export request for `signal`: tenant, authorization,
  idempotency, media type and encoding, then the shared `Pulse.OTLP.Ingest`.
  """
  def export(conn, signal) do
    with {:ok, tenant} <- single_header(conn, "x-scope-orgid", "default"),
         :ok <- S3.validate_tenant(tenant),
         :ok <- Pulse.Auth.verify(conn, tenant, :ingest),
         {:ok, key} <- single_header(conn, "idempotency-key", nil),
         {:ok, format} <- format(conn),
         :ok <- encoding(conn) do
      {conn, decoded} = decode(conn, format, signal)

      case Ingest.ingest(signal, tenant, key, decoded) do
        {:ok, rejected, message} -> success(conn, format, rejected, Ingest.rejected_field(signal), message)
        {:error, reason} -> failure(conn, signal, reason)
      end
    else
      {:error, reason} -> failure(conn, signal, reason)
    end
  end

  defp failure(conn, signal, reason) do
    {status, message} = Ingest.classify(signal, reason)
    conn = if status in [429, 503], do: put_resp_header(conn, "retry-after", "1"), else: conn
    error(conn, status, message)
  end

  def single_header(conn, name, default) do
    case get_req_header(conn, name) do
      [] -> {:ok, default}
      [""] -> {:ok, default}
      [value] -> {:ok, value}
      _ -> {:error, :ambiguous_header}
    end
  end

  def format(conn) do
    case get_req_header(conn, "content-type") do
      [value] ->
        case Utils.media_type(value) do
          {:ok, "application", "json", _} -> {:ok, :json}
          {:ok, "application", "x-protobuf", _} -> {:ok, :protobuf}
          _ -> {:error, :unsupported_content_type}
        end

      _ ->
        {:error, :unsupported_content_type}
    end
  end

  def encoding(conn) do
    if get_req_header(conn, "content-encoding") in [[], ["gzip"], ["identity"]],
      do: :ok,
      else: {:error, :unsupported_content_encoding}
  end

  def decode(conn, :json, signal), do: {conn, Ingest.decode(signal, :json, conn.body_params)}

  def decode(conn, :protobuf, signal) do
    # Keep the consumed adapter state even when decompression/decoding fails.
    # Sending on the original conn would drain already-read socket bytes again,
    # deadlocking large HTTP/1 bodies until the read timeout.
    case Plug.Conn.read_body(conn, length: 4 * 1024 * 1024) do
      {:ok, body, conn} ->
        result =
          with {:ok, body} <- PulseWeb.CompressedBodyReader.decompress(conn, body),
               do: Ingest.decode(signal, :protobuf, body)

        {conn, result}

      {:more, _, conn} ->
        {conn, {:error, :payload_too_large}}

      {:error, _} = error ->
        {conn, error}
    end
  end

  def success(conn, :json, 0, _field, _message), do: json(conn, 200, %{})

  def success(conn, :json, rejected, field, message) do
    json(conn, 200, %{"partialSuccess" => %{field => Integer.to_string(rejected), "errorMessage" => message}})
  end

  def success(conn, :protobuf, rejected, _field, message),
    do: protobuf(conn, 200, Ingest.response_protobuf(rejected, message))

  def error(conn, status, message) do
    code =
      case status do
        401 -> 16
        409 -> 6
        n when n in [413, 429] -> 8
        503 -> 14
        _ -> 3
      end

    case format(conn) do
      {:ok, :protobuf} ->
        protobuf(conn, status, IO.iodata_to_binary([<<8>>, Ingest.varint(code), Ingest.field_bytes(2, message)]))

      _ ->
        json(conn, status, %{"code" => code, "message" => message})
    end
  end

  defp json(conn, status, body),
    do: conn |> put_resp_content_type("application/json", nil) |> send_resp(status, Pulse.JSON.encode!(body))

  defp protobuf(conn, status, body),
    do: conn |> put_resp_content_type("application/x-protobuf", nil) |> send_resp(status, body)
end
