# Records reference answers for the Tuist Grafana corpus from real backends.
#
#   MIX_ENV=test mix run scripts/tuist_corpus_reference.exs \
#     --prometheus /path/to/prometheus-3.5.0.linux-amd64 \
#     --loki /path/to/loki-linux-amd64
#
# Builds the synthetic metrics and logs from `Pulse.Test.GrafanaCorpus`, loads
# them into a temporary Prometheus TSDB (promtool create-blocks-from
# openmetrics) and a temporary single-binary Loki with filesystem storage,
# sends every interpolated corpus query to them over HTTP and writes their
# answers to test/fixtures/grafana/tuist-corpus-reference.json. Local and
# offline apart from the two child processes; nothing reads production data.
alias Pulse.Test.GrafanaCorpus

{:ok, _} = Application.ensure_all_started(:req)

{opts, _, _} = OptionParser.parse(System.argv(), strict: [prometheus: :string, loki: :string])
prometheus_dir = opts[:prometheus] || raise "--prometheus DIR (with prometheus and promtool) is required"
loki_bin = opts[:loki] || raise "--loki BINARY is required"

{version, 0} = System.cmd(Path.join(prometheus_dir, "prometheus"), ["--version"], stderr_to_stdout: true)
unless String.contains?(version, "version 3.5.0 "), do: raise("the reference requires Prometheus 3.5.0")
{loki_version, 0} = System.cmd(loki_bin, ["--version"], stderr_to_stdout: true)
[_, loki_version] = Regex.run(~r/loki, version (\S+)/, loki_version)

tmp = Path.join(System.tmp_dir!(), "pulse-corpus-#{System.unique_integer([:positive])}")
File.mkdir_p!(tmp)

free_port = fn ->
  {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
  {:ok, port} = :inet.port(socket)
  :gen_tcp.close(socket)
  port
end

start = fn bin, args ->
  port = Port.open({:spawn_executable, bin}, [:binary, :exit_status, :stderr_to_stdout, args: args])
  {:os_pid, pid} = Port.info(port, :os_pid)
  pid
end

await_ready = fn url ->
  Enum.find_value(1..120, fn _ ->
    Process.sleep(500)

    case Req.get(url, retry: false) do
      {:ok, %{status: 200}} -> true
      _ -> nil
    end
  end) || raise "#{url} did not become ready"
end

fixture_bytes = File.read!("test/fixtures/grafana/tuist-corpus.json")
requests = GrafanaCorpus.requests(JSON.decode!(fixture_bytes))

# Prometheus over a TSDB created from the synthetic series.
openmetrics = Path.join(tmp, "series.om")
File.write!(openmetrics, GrafanaCorpus.openmetrics(GrafanaCorpus.metric_series(requests)))
tsdb = Path.join(tmp, "tsdb")

{_, 0} =
  System.cmd(Path.join(prometheus_dir, "promtool"), ["tsdb", "create-blocks-from", "openmetrics", openmetrics, tsdb],
    stderr_to_stdout: true
  )

prom_config = Path.join(tmp, "prometheus.yml")
File.write!(prom_config, "global:\n  scrape_interval: #{GrafanaCorpus.scenario().scrape_s}s\n")
prom_port = free_port.()

prom_pid =
  start.(Path.join(prometheus_dir, "prometheus"), [
    "--config.file=#{prom_config}",
    "--storage.tsdb.path=#{tsdb}",
    "--storage.tsdb.retention.time=20y",
    "--web.listen-address=127.0.0.1:#{prom_port}"
  ])

# Loki with ingest-time service_name/level discovery off, so stream labels are
# exactly the pushed ones (see the corpus README).
loki_port = free_port.()
loki_config = Path.join(tmp, "loki.yaml")

File.write!(loki_config, """
auth_enabled: false
server:
  http_listen_address: 127.0.0.1
  http_listen_port: #{loki_port}
  grpc_listen_address: 127.0.0.1
  grpc_listen_port: #{free_port.()}
  log_level: warn
common:
  instance_addr: 127.0.0.1
  path_prefix: #{tmp}/loki
  storage:
    filesystem:
      chunks_directory: #{tmp}/loki/chunks
      rules_directory: #{tmp}/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
limits_config:
  reject_old_samples: false
  creation_grace_period: 87600h
  max_query_length: 0
  max_entries_limit_per_query: 100000
  discover_service_name: []
  discover_log_levels: false
  ingestion_rate_mb: 1024
  ingestion_burst_size_mb: 1024
  split_queries_by_interval: 0
query_range:
  cache_results: false
ingester:
  max_chunk_age: 87600h
analytics:
  reporting_enabled: false
""")

loki_pid = start.(loki_bin, ["-config.file=#{loki_config}"])

try do
  prom = "http://127.0.0.1:#{prom_port}"
  loki = "http://127.0.0.1:#{loki_port}"
  await_ready.(prom <> "/-/ready")
  await_ready.(loki <> "/ready")

  %{status: 204} =
    Req.post!(loki <> "/loki/api/v1/push",
      body: GrafanaCorpus.loki_push(GrafanaCorpus.log_streams()),
      headers: [{"content-type", "application/json"}],
      retry: false
    )

  Process.sleep(2000)

  results =
    Map.new(requests, fn request ->
      {base, path, params} = GrafanaCorpus.http_request(request)
      url = if(base == :prometheus, do: prom, else: loki) <> path
      %{body: body} = Req.post!(url, form: params, retry: false, receive_timeout: 120_000)
      {request["id"], GrafanaCorpus.reference_result(body)}
    end)

  reference = %{
    "oracles" => %{"prometheus" => "3.5.0", "loki" => loki_version},
    "corpus_sha256" => Base.encode16(:crypto.hash(:sha256, fixture_bytes), case: :lower),
    "results" => results
  }

  File.write!("test/fixtures/grafana/tuist-corpus-reference.json", GrafanaCorpus.encode_reference(reference))
  IO.puts("recorded #{map_size(results)} reference answers")
after
  System.cmd("kill", [Integer.to_string(prom_pid), Integer.to_string(loki_pid)])
  File.rm_rf!(tmp)
end
