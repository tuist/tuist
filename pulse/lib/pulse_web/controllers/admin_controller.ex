defmodule PulseWeb.AdminController do
  @moduledoc """
  Operator API for tenant lifecycle and usage, authorized by an admin Bearer
  token (`PULSE_ADMIN_TOKENS`, SHA-256 digests). Without configured admin
  tokens every route answers 404, so the API is not advertised.
  """
  use PulseWeb, :controller

  alias Pulse.Storage.S3
  alias Pulse.Tenants
  alias Pulse.Usage

  @max_usage_hours 31 * 24

  plug :authorize

  def index(conn, params) do
    with :ok <- registry(),
         {:ok, limit} <- integer(params, "limit", 100, 1..1000),
         {:ok, names, cursor} <- Tenants.list(params["after"], limit) do
      json(conn, %{"tenants" => names, "next" => cursor})
    else
      error -> failure(conn, error)
    end
  end

  def show(conn, %{"tenant" => tenant}) do
    with :ok <- registry(),
         :ok <- S3.validate_tenant(tenant),
         {:ok, record, _etag} when record != nil <- Tenants.read(tenant) do
      json(conn, present(record))
    else
      {:ok, nil, nil} -> failure(conn, {:error, :not_found})
      error -> failure(conn, error)
    end
  end

  def update(conn, %{"tenant" => tenant}) do
    with :ok <- registry(),
         :ok <- S3.validate_tenant(tenant),
         {:ok, record} <- Tenants.put(tenant, Map.delete(conn.body_params, "tenant")) do
      json(conn, present(record))
    else
      error -> failure(conn, error)
    end
  end

  def delete(conn, %{"tenant" => tenant}) do
    with :ok <- registry(),
         :ok <- S3.validate_tenant(tenant),
         {:ok, record} <- Tenants.delete(tenant) do
      conn |> put_status(202) |> json(present(record))
    else
      error -> failure(conn, error)
    end
  end

  def usage(conn, %{"tenant" => tenant} = params) do
    now = div(System.os_time(:second), 3600)

    with :ok <- S3.validate_tenant(tenant),
         {:ok, to} <- hour(params["end"], now),
         {:ok, from} <- hour(params["start"], to - 23),
         :ok <- if(from <= to and to - from < @max_usage_hours, do: :ok, else: {:error, :invalid_range}),
         {:ok, storage} <- Tenants.storage(),
         {:ok, report} <- Usage.report(storage, tenant, from, to) do
      json(
        conn,
        Map.merge(report, %{"tenant" => tenant, "start" => Usage.hour_label(from), "end" => Usage.hour_label(to)})
      )
    else
      error -> failure(conn, error)
    end
  end

  # Hours as RFC 3339 timestamps or Unix seconds, truncated to the hour.
  defp hour(nil, default), do: {:ok, default}

  defp hour(value, _default) when is_binary(value) do
    seconds =
      case Integer.parse(value) do
        {seconds, ""} ->
          {:ok, seconds}

        _ ->
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _offset} -> {:ok, DateTime.to_unix(datetime)}
            _ -> :error
          end
      end

    case seconds do
      {:ok, seconds} when seconds >= 0 -> {:ok, div(seconds, 3600)}
      _ -> {:error, :invalid_range}
    end
  end

  defp hour(_value, _default), do: {:error, :invalid_range}

  defp integer(params, name, default, range) do
    with {:ok, value} <- Map.fetch(params, name),
         {n, ""} <- Integer.parse(to_string(value)),
         true <- n in range do
      {:ok, n}
    else
      :error -> {:ok, default}
      _ -> {:error, {:invalid_request, "#{name} must be an integer in #{inspect(range)}"}}
    end
  end

  # Token hashes are credentials material; responses report only how many.
  defp present(record) do
    record
    |> Map.delete("token_hashes")
    |> Map.put("token_count", length(Map.get(record, "token_hashes", [])))
  end

  defp registry, do: if(Tenants.enabled?(), do: :ok, else: {:error, :registry_disabled})

  defp authorize(conn, _opts) do
    hashes = Keyword.get(Pulse.Runtime.get_env(:pulse, __MODULE__, []), :token_hashes, [])

    with [_ | _] <- hashes,
         ["Bearer " <> token] when token != "" <- get_req_header(conn, "authorization") do
      digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)

      if Enum.reduce(hashes, false, &(Plug.Crypto.secure_compare(digest, &1) or &2)),
        do: conn,
        else: conn |> failure({:error, :unauthorized}) |> halt()
    else
      [] -> conn |> failure({:error, :not_found}) |> halt()
      _ -> conn |> failure({:error, :unauthorized}) |> halt()
    end
  end

  defp failure(conn, {:error, reason}) do
    {status, message} = error_response(reason)
    conn |> put_status(status) |> json(%{"error" => message})
  end

  @errors %{
    unauthorized: {401, "unauthorized"},
    not_found: {404, "not_found"},
    registry_disabled: {404, "tenant registry disabled"},
    invalid_range: {400, "start and end must be RFC 3339 or Unix seconds, at most 31 days apart"},
    usage_range_too_large: {422, "usage range spans too many objects; request a shorter range"},
    tenant_deleted: {409, "tenant is deleted or being deleted"},
    tenant_conflict: {503, "tenant record is being changed concurrently; retry"}
  }

  # Storage details can contain endpoints or credentials; never echo them.
  defp error_response({:invalid_tenant, _tenant}), do: {400, "invalid tenant name"}
  defp error_response({:invalid_request, message}), do: {400, message}
  defp error_response(reason), do: Map.get(@errors, reason, {503, "storage unavailable"})
end
