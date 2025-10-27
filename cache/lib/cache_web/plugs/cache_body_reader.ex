defmodule CacheWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Custom body reader that preserves raw binary data for CAS operations.
  """

  def read_body(conn, opts) do
    cond do
      cas_upload?(conn) ->
        consume_cas_body(conn, opts)

      true ->
        case Plug.Conn.read_body(conn, opts) do
          {:ok, body, conn_after} ->
            # Store the raw body so it can be accessed later for CAS operations
            {:ok, body, Plug.Conn.put_private(conn_after, :raw_body, body)}

          {:more, body, conn_after} ->
            {:more, body, conn_after}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp cas_upload?(%Plug.Conn{method: "POST", request_path: request_path}) do
    String.starts_with?(request_path, "/api/cache/cas/")
  end

  defp cas_upload?(_), do: false

  defp consume_cas_body(conn, opts) do
    tmp_path = tmp_path()

    case File.open(tmp_path, [:write, :binary]) do
      {:ok, device} ->
        result = stream_to_device(conn, device, opts)
        File.close(device)

        case result do
          {:ok, conn_after} ->
            {:ok, "", Plug.Conn.put_private(conn_after, :raw_body, {:tempfile, tmp_path})}

          {:error, reason, conn_after} ->
            File.rm(tmp_path)
            {:error, reason, conn_after}
        end

      {:error, reason} ->
        File.rm(tmp_path)
        {:error, reason}
    end
  end

  defp stream_to_device(conn, device, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn_after} ->
        case IO.binwrite(device, chunk) do
          :ok -> {:ok, conn_after}
          {:error, reason} -> {:error, reason, conn_after}
        end

      {:more, chunk, conn_after} ->
        case IO.binwrite(device, chunk) do
          :ok -> stream_to_device(conn_after, device, opts)
          {:error, reason} -> {:error, reason, conn_after}
        end

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp tmp_path do
    base = System.tmp_dir!()
    unique = :erlang.unique_integer([:positive, :monotonic])
    Path.join(base, "cache-upload-#{unique}")
  end
end
