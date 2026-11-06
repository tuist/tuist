defmodule PulseWeb.CompatController do
  @moduledoc """
  Metadata endpoints Grafana's Prometheus and Tempo datasources call around
  queries: build information for feature detection, metric metadata,
  exemplars and query formatting, and Tempo's health echo.

  Remote-write metric metadata is retained (`Pulse.MetricMetadata`) and
  exemplars are stored with their samples (`Pulse.Exemplars`).
  """

  use PulseWeb, :controller

  alias Pulse.Auth
  alias Pulse.PromQL.Formatter

  # Versions whose APIs Pulse's compatible endpoints follow.
  @prometheus_version "3.5.0"
  @tempo_version "2.9.0"

  def prometheus_buildinfo(conn, _params) do
    json(conn, %{
      "status" => "success",
      "data" => %{
        "version" => @prometheus_version,
        "revision" => revision(),
        "branch" => "",
        "buildUser" => "",
        "buildDate" => "",
        "goVersion" => ""
      }
    })
  end

  @doc """
  Retained remote-write metric metadata by family (`Pulse.MetricMetadata`),
  with Prometheus's `metric`, `limit` and `limit_per_metric` parameters.
  """
  def metadata(conn, params) do
    authorized(conn, fn tenant ->
      with {:ok, limit} <- metadata_limit(params["limit"]),
           {:ok, per_metric} <- metadata_limit(params["limit_per_metric"]),
           {:ok, data} <-
             Pulse.MetricMetadata.query(tenant, metric: params["metric"], limit: limit, limit_per_metric: per_metric) do
        %{"status" => "success", "data" => data}
      else
        {:error, :invalid_limit} -> {:bad_data, "invalid limit"}
        {:error, reason} -> {:unavailable, inspect(reason)}
      end
    end)
  end

  defp metadata_limit(nil), do: {:ok, nil}
  defp metadata_limit(""), do: {:ok, nil}

  defp metadata_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :invalid_limit}
    end
  end

  defp metadata_limit(_value), do: {:error, :invalid_limit}

  @doc """
  Exemplars of the series a query selects, with Prometheus' `query`, `start`
  and `end` parameters (`end` defaults to now, `start` to an hour before it).
  """
  def query_exemplars(conn, %{"query" => query} = params) when is_binary(query) do
    authorized(conn, fn tenant ->
      with {:ok, finish} <- exemplar_time(params["end"], System.os_time(:nanosecond)),
           {:ok, start} <- exemplar_time(params["start"], finish - 3_600_000_000_000),
           {:ok, data} <- Pulse.Exemplars.query(query, tenant, start, finish) do
        %{"status" => "success", "data" => data}
      else
        {:error, reason} when reason in [:invalid_timestamp, :invalid_time_range] -> {:bad_data, to_string(reason)}
        {:error, reason} when reason in [:query_timeout, :query_overloaded] -> {:unavailable, to_string(reason)}
        {:error, reason} -> {:bad_data, inspect(reason)}
      end
    end)
  end

  def query_exemplars(conn, _params), do: bad_data(conn, "missing query")

  defp exemplar_time(nil, default), do: {:ok, default}
  defp exemplar_time("", default), do: {:ok, default}
  defp exemplar_time(value, _default), do: Pulse.PromQL.Time.parse_timestamp(value)

  @doc "Formats a query in Pulse's supported PromQL grammar without executing it."
  def format_query(conn, %{"query" => query}) when is_binary(query) do
    authorized(conn, fn ->
      case Formatter.format(query) do
        {:ok, formatted} -> %{"status" => "success", "data" => formatted}
        {:error, reason} -> {:bad_data, inspect(reason)}
      end
    end)
  end

  def format_query(conn, _params), do: bad_data(conn, "missing query")

  def tempo_echo(conn, _params), do: text(conn, "echo")

  def tempo_buildinfo(conn, _params) do
    json(conn, %{
      "version" => @tempo_version,
      "revision" => revision(),
      "branch" => "",
      "buildUser" => "",
      "buildDate" => "",
      "goVersion" => ""
    })
  end

  defp respond(conn, {:bad_data, message}), do: bad_data(conn, message)

  defp respond(conn, {:unavailable, message}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{"status" => "error", "errorType" => "unavailable", "error" => message})
  end

  defp respond(conn, body), do: json(conn, body)

  defp authorized(conn, fun) do
    tenant =
      case get_req_header(conn, "x-scope-orgid") do
        [value | _] when value != "" -> value
        _ -> "default"
      end

    case Auth.verify(conn, tenant, :read) do
      :ok ->
        respond(conn, if(is_function(fun, 1), do: fun.(tenant), else: fun.()))

      {:error, reason} ->
        conn
        |> put_status(Map.get(%{forbidden: :forbidden, auth_unavailable: :service_unavailable}, reason, :unauthorized))
        |> json(%{"status" => "error", "errorType" => "unauthorized", "error" => to_string(reason)})
    end
  end

  defp bad_data(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{"status" => "error", "errorType" => "bad_data", "error" => message})
  end

  defp revision, do: "pulse-" <> (:pulse |> Application.spec(:vsn) |> to_string())
end
