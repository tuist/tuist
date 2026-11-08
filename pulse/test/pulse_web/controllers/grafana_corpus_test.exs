defmodule PulseWeb.GrafanaCorpusTest do
  # Every PromQL and LogQL query in Tuist's Grafana dashboards and alert rules
  # (test/fixtures/grafana/tuist-corpus.json), interpolated as Grafana does,
  # evaluated through the Prometheus and Loki HTTP APIs over the S3 adapter
  # against synthetic data shaped like the queried metric names, labels and
  # log lines. Answers must equal Prometheus 3.5.0 and Loki 3.7.9 on the same
  # data (tuist-corpus-reference.json, scripts/tuist_corpus_reference.exs).
  use PulseWeb.ConnCase, async: true

  alias Pulse.Record.MetricSample
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.GrafanaCorpus

  @moduletag timeout: 600_000
  @corpus Path.expand("../../fixtures/grafana/tuist-corpus.json", __DIR__)
  @reference Path.expand("../../fixtures/grafana/tuist-corpus-reference.json", __DIR__)
  @tenant "corpus"

  setup do
    Runtime.put_env(:pulse, Storage, adapter: S3)

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
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    Runtime.put_env(:pulse, S3, %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "corpus-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    })

    start_supervised!(ManifestSupervision)
    :ok
  end

  test "every dashboard and alert query matches Prometheus and Loki" do
    corpus_bytes = File.read!(@corpus)
    reference = @reference |> File.read!() |> JSON.decode!()

    assert reference["corpus_sha256"] == Base.encode16(:crypto.hash(:sha256, corpus_bytes), case: :lower),
           "corpus changed; rerun scripts/tuist_corpus_reference.exs"

    requests = GrafanaCorpus.requests(JSON.decode!(corpus_bytes))
    assert length(requests) == 1178
    assert Enum.frequencies_by(requests, & &1["language"]) == %{"promql" => 1112, "logql" => 66}

    records =
      for {labels, samples} <- GrafanaCorpus.metric_series(requests),
          {time_ms, value} <- samples,
          do: %MetricSample{labels: labels, value: value, timestamp_ns: time_ms * 1_000_000}

    for chunk <- Enum.chunk_every(records, 20_000), do: :ok = Storage.append(:metrics, @tenant, chunk)

    pushed =
      build_conn()
      |> put_req_header("x-scope-orgid", @tenant)
      |> put_req_header("content-type", "application/json")
      |> post("/loki/api/v1/push", GrafanaCorpus.loki_push(GrafanaCorpus.log_streams()))

    assert pushed.status == 204, pushed.resp_body

    mismatches =
      for request <- requests,
          {_backend, path, params} = GrafanaCorpus.http_request(request),
          conn = build_conn() |> put_req_header("x-scope-orgid", @tenant) |> post(path, params),
          outcome = GrafanaCorpus.compare(reference["results"][request["id"]], JSON.decode!(conn.resp_body)),
          outcome != :match,
          do: {request["id"], request["interpolated"], outcome}

    assert mismatches == [],
           mismatches
           |> Enum.take(10)
           |> Enum.map_join("\n\n", fn {id, expr, outcome} -> "#{id} #{expr}\n#{inspect(outcome, limit: 20)}" end)
  end
end
