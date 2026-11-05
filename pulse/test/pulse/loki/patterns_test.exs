defmodule Pulse.Loki.PatternsTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.Parser
  alias Pulse.Loki.Patterns
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Test.NativeQueryStorage

  @second 1_000_000_000

  setup do
    tenant = "patterns-#{System.unique_integer([:positive])}"
    now = div(System.system_time(:nanosecond), 60 * @second) * 60 * @second

    records =
      for i <- 1..300 do
        body =
          case rem(i, 3) do
            0 -> "level=info msg=\"request done\" route=/r#{rem(i, 7)} duration=#{i}ms"
            1 -> "GET /api/projects/#{i} 200 #{i}ms"
            2 -> ~s({"level":"debug","id":"#{i}","msg":"check capacity"})
          end

        %Log{
          timestamp_ns: now - 120 * @second + i * @second,
          service: "api",
          body: body,
          resource: %{},
          attributes: %{}
        }
      end

    :ok = Storage.append(:logs, tenant, records)
    {:ok, tenant: tenant, now: now}
  end

  defp mine(ctx, query) do
    {:ok, ast} = Parser.parse(query)
    window = %{start_ns: ctx.now - 180 * @second, end_ns: ctx.now + 180 * @second, step_ns: 60 * @second}
    Patterns.query(ctx.tenant, ast, window)
  end

  test "mines patterns with counts per step, natively and through the evaluator alike", ctx do
    assert {:ok, folded} = mine(ctx, ~s({service_name="api"}))

    assert Enum.map(folded, fn {pattern, samples} -> {pattern, Enum.sum_by(samples, &elem(&1, 1))} end) == [
             {"GET <_> 200 <_>", 100},
             {"level=info msg=\"request done\" route=<_> duration=<_>", 100},
             {~s({"level":"debug","id":"<_>","msg":"check capacity"}), 100}
           ]

    assert Enum.all?(folded, fn {_pattern, samples} ->
             Enum.all?(samples, fn {ts, _} -> rem(ts - ctx.now, 60 * @second) == 0 end)
           end)

    Pulse.Runtime.put_env(:pulse, Storage, adapter: NativeQueryStorage)
    assert mine(ctx, ~s({service_name="api"})) == {:ok, folded}
  end

  test "line filters and pipelines narrow the mined lines", ctx do
    assert {:ok, [{"GET <_> 200 <_>", _}]} = mine(ctx, ~s({service_name="api"} |= "GET"))
    assert {:ok, [{"GET <_> 200 <_>", _}]} = mine(ctx, ~s({service_name="api"} |> "GET <_>"))
  end

  test "returned patterns filter the lines they summarize", ctx do
    {:ok, patterns} = mine(ctx, ~s({service_name="api"}))

    for {pattern, samples} <- patterns do
      {:ok, ast} = Parser.parse(~s({service_name="api"} |> ) <> Pulse.JSON.encode!(pattern))
      window = %{start_ts_ns: ctx.now - 180 * @second, end_ts_ns: ctx.now + 180 * @second, limit: 1000}
      {:ok, streams} = Evaluator.evaluate_log(ast, ctx.tenant, window)
      assert Enum.sum_by(streams, fn {_labels, entries} -> length(entries) end) == Enum.sum_by(samples, &elem(&1, 1))
    end
  end

  test "serves Loki's patterns response", %{conn: conn} = ctx do
    response =
      conn
      |> put_req_header("x-scope-orgid", ctx.tenant)
      |> get("/loki/api/v1/patterns", %{
        "query" => ~s({service_name="api"}),
        "start" => Integer.to_string(ctx.now - 180 * @second),
        "end" => Integer.to_string(ctx.now + 180 * @second),
        "step" => "1m"
      })
      |> json_response(200)

    assert %{"status" => "success", "data" => [%{"pattern" => "GET <_> 200 <_>", "samples" => [[ts, n] | _]} | _]} =
             response

    assert is_integer(ts) and ts < 10_000_000_000 and n > 0

    assert conn
           |> put_req_header("x-scope-orgid", ctx.tenant)
           |> get("/loki/api/v1/patterns", %{"query" => ~s({service_name="api"}), "step" => "1ms"})
           |> json_response(400)
  end
end
