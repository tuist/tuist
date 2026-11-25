defmodule Symptoms.Sources.Prometheus do
  @moduledoc """
  A small Prometheus HTTP API client for Pulse, used by
  `Symptoms.Sources.PromMetrics` and `Symptoms.Sources.Probes`.

  Configuration, from `config :symptoms, #{inspect(__MODULE__)}` (set from the
  environment in `config/runtime.exs`), then the `:prometheus` option of a call:

  - `:base_url` (`SYMPTOMS_PROMETHEUS_URL`), the Prometheus API root, for
    example `http://pulse.observability.svc.cluster.local:4000/v1/prometheus`
  - `:user` (`SYMPTOMS_PROMETHEUS_USER`), Pulse's read-only `dashboard` identity
  - `:token` (`SYMPTOMS_PROMETHEUS_TOKEN`), that identity's password
  - `:receive_timeout` (default 30 s)

  Responses are bounded to 8 MiB and 10 000 series.
  """

  @max_body 8_388_608
  @max_series 10_000

  @type sample :: {integer(), float()}
  @type series :: %{metric: %{String.t() => String.t()}, value: float()}
  @type range_series :: %{metric: %{String.t() => String.t()}, values: [sample()]}

  @doc "An instant query at `time` (Unix seconds). NaN and infinite values are dropped."
  @spec query(String.t(), integer(), keyword()) :: {:ok, [series()]} | {:error, term()}
  def query(promql, time, opts \\ []) do
    with {:ok, data} <- get("/api/v1/query", [query: promql, time: time], opts) do
      case data do
        %{"resultType" => "vector", "result" => result} -> vector(result)
        %{"resultType" => "scalar", "result" => value} -> vector([%{"metric" => %{}, "value" => value}])
        %{"resultType" => "matrix", "result" => result} -> matrix(result)
        _ -> {:error, :malformed_response}
      end
    end
  end

  @doc "A range query over `[start, finish]` at `step` seconds."
  @spec query_range(String.t(), integer(), integer(), pos_integer(), keyword()) ::
          {:ok, [range_series()]} | {:error, term()}
  def query_range(promql, start, finish, step, opts \\ []) do
    with {:ok, data} <- get("/api/v1/query_range", [query: promql, start: start, end: finish, step: step], opts) do
      case data do
        %{"resultType" => "matrix", "result" => result} -> matrix(result)
        _ -> {:error, :malformed_response}
      end
    end
  end

  defp vector(result) when is_list(result) and length(result) <= @max_series do
    if Enum.all?(result, &match?(%{"metric" => %{}, "value" => [_, _]}, &1)) do
      {:ok,
       for(
         %{"metric" => metric, "value" => [_t, raw]} <- result,
         value = number(raw),
         is_float(value),
         do: %{metric: metric, value: value}
       )}
    else
      {:error, :malformed_response}
    end
  end

  defp vector(result) when is_list(result), do: {:error, :query_result_limit}
  defp vector(_result), do: {:error, :malformed_response}

  defp matrix(result) when is_list(result) and length(result) <= @max_series do
    if Enum.all?(result, &match?(%{"metric" => %{}, "values" => values} when is_list(values), &1)) do
      {:ok,
       for %{"metric" => metric, "values" => values} <- result do
         samples =
           for [t, raw] <- values, value = number(raw), is_float(value), do: {trunc(t), value}

         %{metric: metric, values: samples}
       end}
    else
      {:error, :malformed_response}
    end
  end

  defp matrix(result) when is_list(result), do: {:error, :query_result_limit}
  defp matrix(_result), do: {:error, :malformed_response}

  defp number(raw) when is_binary(raw) do
    case Float.parse(raw) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp number(raw) when is_number(raw), do: raw * 1.0
  defp number(_raw), do: nil

  defp get(path, params, opts) do
    config = config(opts)

    with {:ok, url} <- base_url(config) do
      request =
        Req.new(
          method: :get,
          url: url <> path,
          headers: [{"accept", "application/json"}, {"x-pulse-db-name", "public"}],
          params: params,
          compressed: false,
          into: &bounded_body/2,
          redirect: false,
          retry: false,
          receive_timeout: Keyword.get(config, :receive_timeout, 30_000),
          connect_options: [timeout: 10_000]
        )

      request =
        if config[:token], do: Req.merge(request, auth: {:basic, "#{config[:user]}:#{config[:token]}"}), else: request

      case Req.request(request) do
        {:ok, %Req.Response{body: :too_large}} -> {:error, :query_result_limit}
        {:ok, %Req.Response{status: 200, body: body}} -> data(body)
        {:ok, %Req.Response{status: status}} when status in [400, 422] -> {:error, :invalid_query}
        {:ok, %Req.Response{status: 429}} -> {:error, :rate_limited}
        {:ok, %Req.Response{}} -> {:error, :upstream_error}
        {:error, %Req.TransportError{reason: :timeout}} -> {:error, :timeout}
        {:error, _reason} -> {:error, :unavailable}
      end
    end
  end

  defp data(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> data(decoded)
      _ -> {:error, :malformed_response}
    end
  end

  defp data(%{"status" => "success", "data" => %{} = data}), do: {:ok, data}
  defp data(_body), do: {:error, :malformed_response}

  defp bounded_body({:data, data}, {request, response}) do
    body = response.body || ""

    if byte_size(body) + byte_size(data) <= @max_body,
      do: {:cont, {request, %{response | body: body <> data}}},
      else: {:halt, {request, %{response | body: :too_large}}}
  end

  defp base_url(config) do
    case config[:base_url] do
      url when is_binary(url) and url != "" -> {:ok, String.trim_trailing(url, "/")}
      _ -> {:error, :not_configured}
    end
  end

  defp config(opts) do
    :symptoms
    |> Application.get_env(__MODULE__, [])
    |> Keyword.merge(Keyword.get(opts, :prometheus, []))
  end
end
