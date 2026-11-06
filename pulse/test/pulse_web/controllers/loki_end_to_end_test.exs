defmodule PulseWeb.LokiEndToEndTest do
  # Loki push → S3 Parquet segments → native stream discovery and queries,
  # through the real endpoint and an owned local object store.
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.SharedSecret
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.RuntimePlug

  setup do
    Runtime.share()

    store =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: store}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    tenant = "loki-http-#{System.unique_integer([:positive])}"
    token = "test-token"
    digest = "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
    Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{tenant => digest})
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, S3, config)
    start_supervised!(ManifestSupervision)

    api =
      start_supervised!(
        {Bandit, plug: {RuntimePlug, plug: PulseWeb.Endpoint, runtime: Runtime.current()}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, api_port}} = ThousandIsland.listener_info(api)

    now = System.system_time(:nanosecond)
    ctx = %{url: "http://127.0.0.1:#{api_port}", tenant: tenant, token: token, now: now, store: store}

    # Three pushes become three segments, so discovery unions sources.
    push(ctx, [
      {%{"namespace" => "prod", "pod" => "api-1", "container" => "server"}, ["GET /a", "GET /b"]},
      {%{"namespace" => "prod", "pod" => "api-gw", "container" => "gateway"}, ["proxy"]}
    ])

    push(ctx, [{%{"namespace" => "staging", "pod" => "web-1", "container" => "server"}, ["boot"]}])
    push(ctx, [{%{"namespace" => "prod", "pod" => "api-1", "container" => "server"}, ["GET /c"]}])

    {:ok, Map.put(ctx, :config, config)}
  end

  defp headers(ctx), do: [{"authorization", "Bearer " <> ctx.token}, {"x-scope-orgid", ctx.tenant}]

  defp push(ctx, streams) do
    body = %{
      "streams" =>
        for {{labels, lines}, i} <- Enum.with_index(streams) do
          %{
            "stream" => labels,
            "values" =>
              for({line, j} <- Enum.with_index(lines), do: [to_string(ctx.now - 1_000_000 * (i * 10 + j)), line])
          }
        end
    }

    response = Req.post!(ctx.url <> "/loki/api/v1/push", headers: headers(ctx), json: body)
    assert response.status == 204
  end

  defp get(ctx, path, params) do
    response = Req.get!(ctx.url <> path, headers: headers(ctx), params: params, decode_body: false)
    {response.status, Pulse.JSON.decode!(response.body)}
  end

  test "labels, values and series come from every native segment", ctx do
    assert {200, %{"data" => ["container", "namespace", "pod"]}} = get(ctx, "/loki/api/v1/labels", [])

    assert {200, %{"data" => ["api-1", "api-gw", "web-1"]}} = get(ctx, "/loki/api/v1/label/pod/values", [])

    assert {200, %{"data" => ["api-1", "web-1"]}} =
             get(ctx, "/loki/api/v1/label/pod/values", query: ~s({container="server"}))

    assert {200, %{"data" => series}} = get(ctx, "/loki/api/v1/series", "match[]": ~s({namespace="prod"}))

    assert series == [
             %{"container" => "gateway", "namespace" => "prod", "pod" => "api-gw"},
             %{"container" => "server", "namespace" => "prod", "pod" => "api-1"}
           ]
  end

  test "stream regexes are anchored on the native path", ctx do
    assert {200, %{"data" => []}} = get(ctx, "/loki/api/v1/label/pod/values", query: ~s({pod=~"api"}))

    start = to_string(ctx.now - 3_600_000_000_000)
    params = [query: ~s({pod=~"api"}), start: start, end: to_string(ctx.now + 1)]
    assert {200, %{"data" => %{"result" => []}}} = get(ctx, "/loki/api/v1/query_range", params)

    params = Keyword.put(params, :query, ~s({pod=~"api-.*", container="server"}))
    assert {200, %{"data" => %{"result" => [stream]}}} = get(ctx, "/loki/api/v1/query_range", params)
    assert stream["stream"]["pod"] == "api-1"
    assert length(stream["values"]) == 3
  end

  test "a range before the data discovers nothing", ctx do
    params = [start: "0", end: "1000"]
    assert {200, %{"data" => []}} = get(ctx, "/loki/api/v1/labels", params)
  end

  test "opt-in segment prefetch returns the same results", ctx do
    params = [query: ~s|sum by (pod) (count_over_time({namespace=~".+"}[1h]))|, time: to_string(ctx.now + 1)]
    sequential = get(ctx, "/loki/api/v1/query", params)
    labels = get(ctx, "/loki/api/v1/labels", [])

    Pulse.Runtime.put_env(:pulse, S3, Map.put(ctx.config, :query_prefetch, 4))

    assert get(ctx, "/loki/api/v1/query", params) == sequential
    assert get(ctx, "/loki/api/v1/labels", []) == labels
    assert {200, %{"data" => %{"result" => [_, _, _]}}} = sequential
  end
end
