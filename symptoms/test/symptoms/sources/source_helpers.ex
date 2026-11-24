defmodule Symptoms.SourceHelpers do
  @moduledoc false
  # Fakes for `Req.request/1` in the source tests: Pulse's /v1/sql replies and
  # Prometheus API replies, built from rows shaped like the real tables.

  @pulse [pulse: [base_url: "http://pulse.test", token: "read-only", write_token: "writer"]]

  def pulse_opts(opts \\ []), do: Keyword.merge(@pulse, opts)

  @doc "Pulse's SQL reply for rows given as maps with the same keys."
  def sql_reply(rows) do
    names = rows |> List.first(%{}) |> Map.keys() |> Enum.sort()

    %{
      "output" => [
        %{
          "records" => %{
            "schema" => %{"column_schemas" => Enum.map(names, &%{"name" => &1, "data_type" => "String"})},
            "rows" => Enum.map(rows, fn row -> Enum.map(names, &Map.fetch!(row, &1)) end)
          }
        }
      ]
    }
  end

  @doc """
  Stubs Req so every Pulse query goes to `fun.(sql)`, which returns rows,
  `{:error, status}` or `:insert`. Sends `{:sql, sql, request}` to the test.
  """
  def stub_pulse(fun) do
    test = self()

    Mimic.stub(Req, :request, fn request ->
      sql = request.options.params[:sql]
      send(test, {:sql, sql, request})

      case fun.(sql) do
        {:error, status} -> {:ok, %Req.Response{status: status, body: ""}}
        :insert -> {:ok, %Req.Response{status: 200, body: %{"output" => [%{"affectedrows" => 12}]}}}
        rows -> {:ok, %Req.Response{status: 200, body: sql_reply(rows)}}
      end
    end)
  end

  @doc "A Flow sink completeness reply: the newest window."
  def latest(latest), do: [%{"latest" => latest}]

  @doc "Prometheus vector reply."
  def vector(series) do
    %{
      "status" => "success",
      "data" => %{
        "resultType" => "vector",
        "result" => Enum.map(series, fn {metric, value} -> %{"metric" => metric, "value" => [0, to_string(value)]} end)
      }
    }
  end

  @doc "Prometheus matrix reply."
  def matrix(series) do
    %{
      "status" => "success",
      "data" => %{
        "resultType" => "matrix",
        "result" =>
          Enum.map(series, fn {metric, values} ->
            %{"metric" => metric, "values" => Enum.map(values, fn {t, v} -> [t, to_string(v)] end)}
          end)
      }
    }
  end

  @doc "Stubs Req so every Prometheus query goes to `fun.(promql)`, returning a body or `{:error, status}`."
  def stub_prometheus(fun) do
    Mimic.stub(Req, :request, fn request ->
      case fun.(request.options.params[:query]) do
        {:error, status} -> {:ok, %Req.Response{status: status, body: ""}}
        body -> {:ok, %Req.Response{status: 200, body: body}}
      end
    end)
  end

  def prom_opts(opts \\ []), do: Keyword.merge([prometheus: [base_url: "http://mimir.test/api/prom"]], opts)

  @doc "A `:baseline` function from `%{{stream, key} => baseline}`."
  def baselines(map), do: fn stream, entity -> Map.get(map, {stream, entity.key}) end
end
