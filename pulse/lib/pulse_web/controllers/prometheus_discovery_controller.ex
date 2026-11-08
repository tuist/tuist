defmodule PulseWeb.PrometheusDiscoveryController do
  @moduledoc "Bounded Prometheus label names, values and series over retained metric samples."
  use PulseWeb, :controller

  alias Plug.Conn.Utils
  alias Pulse.Auth
  alias Pulse.PromQL.{Discovery, Parser, Time}
  alias Pulse.Storage.S3
  alias PulseWeb.PrometheusLimit

  def labels(conn, _params), do: run(conn, "names", "")
  def label_values(conn, %{"name" => name}), do: run(conn, "values", unescape_label(name))
  def series(conn, _params), do: run(conn, "series", "")

  # Prometheus ValueEncodingEscaping, used by Grafana for UTF-8 label paths.
  # Like upstream UnescapeName, a malformed escape preserves the entire literal
  # name, never a partly decoded prefix or a second decoding pass.
  defp unescape_label("U__" <> encoded = name) when byte_size(name) <= 2048 do
    case unescape_label(encoded, []) do
      {:ok, parts} -> IO.iodata_to_binary(Enum.reverse(parts))
      :error -> name
    end
  end

  defp unescape_label(name), do: name
  defp unescape_label("", parts), do: {:ok, parts}
  defp unescape_label("__" <> rest, parts), do: unescape_label(rest, ["_" | parts])

  defp unescape_label("_" <> rest, parts) do
    with [hex, tail] <- :binary.split(rest, "_"),
         true <- byte_size(hex) in 1..5 and Regex.match?(~r/\A[0-9a-fA-F]+\z/, hex),
         {codepoint, ""} <- Integer.parse(hex, 16),
         true <- codepoint not in 0xD800..0xDFFF do
      unescape_label(tail, [<<codepoint::utf8>> | parts])
    else
      _ -> :error
    end
  end

  defp unescape_label(<<byte, rest::binary>>, parts), do: unescape_label(rest, [byte | parts])

  defp run(conn, mode, key) do
    with {:ok, tenant} <- tenant(conn),
         :ok <- authorize(conn, tenant),
         :ok <- S3.validate_tenant(tenant),
         {:ok, selectors, opts, limit} <- parameters(conn),
         {:ok, data} <- Discovery.query(tenant, mode, key, selectors, opts) do
      if limit > 0 do
        json(conn, PrometheusLimit.response(%{"status" => "success", "data" => Pulse.JSON.decode!(data)}, limit))
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, [~s({"status":"success","data":), data, "}"])
      end
    else
      {:error, :unauthorized} ->
        failure(conn, 401, "unauthorized", "unauthorized")

      {:error, :forbidden} ->
        failure(conn, 403, "forbidden", "forbidden")

      {:error, :auth_unavailable} ->
        failure(conn, 503, "unavailable", "auth_unavailable")

      {:error, :query_overloaded} ->
        failure(conn, 429, "execution", "Query capacity is busy; retry later.")

      {:error, :query_timeout} ->
        failure(conn, 504, "timeout", "Metric discovery timed out.")

      {:error, reason}
      when reason in [:query_scan_limit, :query_sample_limit, :query_work_limit, :query_resource_limit] ->
        failure(
          conn,
          422,
          "execution",
          "Complete metric discovery exceeds safety budgets; narrow selectors or time range."
        )

      {:error, reason} when reason in [:invalid_stored_sample, :query_execution_failed] ->
        failure(conn, 500, "execution", "Stored metric discovery could not be completed safely.")

      {:error, {:decode_failed, _}} ->
        failure(conn, 500, "execution", "Stored metric data is invalid.")

      {:error, :unsupported_media_type} ->
        failure(conn, 415, "bad_data", "POST requires application/x-www-form-urlencoded.")

      {:error, {:invalid_parameter, message}} ->
        failure(conn, 400, "bad_data", message)

      {:error, reason}
      when reason in [
             :invalid_discovery_parameters,
             :invalid_discovery_selector,
             :invalid_parameters,
             :invalid_tenant_header
           ] ->
        failure(conn, 400, "bad_data", "Invalid or unsupported metric discovery parameters.")

      {:error, {:invalid_tenant, _}} ->
        failure(conn, 400, "bad_data", "Invalid tenant.")

      {:error, _} ->
        failure(conn, 503, "execution", "Metric storage is unavailable.")
    end
  end

  defp tenant(conn) do
    case get_req_header(conn, "x-scope-orgid") do
      [] -> {:ok, "default"}
      [value] when value != "" -> {:ok, value}
      _ -> {:error, :invalid_tenant_header}
    end
  end

  defp authorize(conn, tenant) do
    case Auth.verify(conn, tenant, :read) do
      :ok -> :ok
      {:error, reason} when reason in [:forbidden, :auth_unavailable] -> {:error, reason}
      {:error, _} -> {:error, :unauthorized}
    end
  end

  defp parameters(conn) do
    query = conn.query_params
    body = conn.body_params
    allowed = ~w(match start end timeout limit)

    with :ok <- content_type(conn),
         true <- is_map(body) and not is_struct(body),
         true <- byte_size(conn.query_string) <= 32_768,
         true <- Enum.all?(Map.keys(query) ++ Map.keys(body), &(&1 in allowed)),
         true <- Enum.all?(~w(start end timeout limit), &(not (Map.has_key?(query, &1) and Map.has_key?(body, &1)))),
         true <- unique_scalars?(conn.query_string),
         true <- unique_scalars?(Map.get(conn.assigns, :prometheus_discovery_form, "")),
         params = Map.merge(query, body),
         selectors = Map.get(query, "match", []) ++ Map.get(body, "match", []),
         {:ok, limit} <- PrometheusLimit.parse(params["limit"]),
         {:ok, opts} <- time_options(params),
         {:ok, opts} <- timeout_options(params, opts) do
      {:ok, selectors, opts, limit}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_parameters}
    end
  rescue
    _ in [ArgumentError] -> {:error, :invalid_parameters}
  end

  defp unique_scalars?(query) do
    pairs = URI.query_decoder(query) |> Enum.to_list()

    Enum.all?(pairs, fn {key, _} -> key in ~w(match[] start end timeout limit) end) and
      Enum.all?(~w(start end timeout limit), fn key -> Enum.count(pairs, &(elem(&1, 0) == key)) <= 1 end)
  end

  defp content_type(%{method: "GET"}), do: :ok

  defp content_type(conn) do
    case get_req_header(conn, "content-type") do
      [value] ->
        case Utils.media_type(value) do
          {:ok, "application", "x-www-form-urlencoded", _} -> :ok
          _ -> {:error, :unsupported_media_type}
        end

      _ ->
        {:error, :unsupported_media_type}
    end
  end

  defp time_options(params) do
    Enum.reduce_while([{"start", :start_ts_ns}, {"end", :end_ts_ns}], {:ok, %{}}, fn {name, key}, {:ok, opts} ->
      case Map.fetch(params, name) do
        :error ->
          {:cont, {:ok, opts}}

        {:ok, value} ->
          put_bound(timestamp(value), opts, key)
      end
    end)
  end

  defp put_bound({:ok, ns}, opts, key), do: {:cont, {:ok, Map.put(opts, key, ns)}}
  defp put_bound(_, _, _), do: {:halt, {:error, :invalid_parameters}}

  defp timestamp(value) when is_binary(value) and byte_size(value) <= 128 do
    case Time.parse_seconds(value) do
      {:ok, _} = result ->
        result

      _ ->
        with true <- Regex.match?(~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})\z/, value),
             {:ok, dt, _} <- DateTime.from_iso8601(value),
             fraction = fraction(value),
             ns = DateTime.to_unix(dt, :nanosecond) + fraction,
             true <- ns >= -9_223_372_036_854_775_808 and ns <= 9_223_372_036_854_775_807 do
          {:ok, ns}
        else
          _ -> {:error, :invalid_parameters}
        end
    end
  end

  defp timestamp(_), do: {:error, :invalid_parameters}

  defp fraction(value) do
    case Regex.run(~r/\.(\d+)/, value) do
      [_, f] -> rem(String.to_integer(String.pad_trailing(f, 9, "0")), 1000)
      _ -> 0
    end
  end

  defp timeout_options(params, opts) do
    case Map.fetch(params, "timeout") do
      :error ->
        {:ok, opts}

      {:ok, value} when is_binary(value) ->
        parsed =
          case Time.parse_seconds(value) do
            {:ok, _} = value -> value
            _ -> Parser.parse_duration(value)
          end

        case parsed do
          {:ok, ns} when ns > 0 -> {:ok, Map.put(opts, :timeout_ms, min(10_000, div(ns + 999_999, 1_000_000)))}
          _ -> {:error, :invalid_parameters}
        end

      _ ->
        {:error, :invalid_parameters}
    end
  end

  defp failure(conn, status, type, message),
    do: conn |> put_status(status) |> json(%{"status" => "error", "errorType" => type, "error" => message})
end
