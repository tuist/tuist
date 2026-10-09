# From server/: mise exec -- elixir -pa '_build/test/lib/*/ebin' benchmarks/repo_metrics.exs
# Isolated monitoring tests, using only localhost ClickHouse for SELECT queries.
ExUnit.start()
Application.ensure_all_started(:mimic)
Application.ensure_all_started(:peep)
Application.ensure_all_started(:ecto_sql)
Application.ensure_all_started(:ecto_ch)

Application.put_env(:tuist, Tuist.ClickHouseRepo,
  hostname: "127.0.0.1",
  port: 8123,
  database: "default",
  default_dynamic_repo: Tuist.IngestRepo
)

Mix.start()
Mix.env(:test)
Code.compiler_options(ignore_module_conflict: true)
suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
beam_dir = Path.join(System.tmp_dir!(), "tuist-repo-metrics-#{suffix}")
File.mkdir!(beam_dir)
ExUnit.after_suite(fn _ -> File.rm_rf!(beam_dir) end)
Code.prepend_path(beam_dir)

try do
  for path <- [
        "../lib/tuist/environment.ex",
        "../lib/tuist/telemetry.ex",
        "../../tuist_common/lib/tuist_common/repo/pool_metrics.ex",
        "../../tuist_common/lib/tuist_common/repo/prom_ex_plugin.ex",
        "../lib/tuist/prom_ex/buckets.ex",
        "../lib/tuist/prom_ex/striped_peep.ex",
        "../lib/tuist/repo/prom_ex_plugin.ex",
        "../lib/tuist/clickhouse/array_in_params.ex",
        "../lib/tuist/clickhouse/read_route.ex",
        "../../tuist_common/lib/tuist_common/clickhouse_retry.ex",
        "../lib/tuist/clickhouse_retry.ex",
        "../lib/tuist/clickhouse_repo/query_retry.ex",
        "../lib/tuist/clickhouse_repo.ex",
        "../lib/tuist/shadow_clickhouse_repo.ex",
        "../lib/tuist/clickhouse_repo/prom_ex_plugin.ex",
        "../test/support/tuist_test_support/telemetry_capture.ex"
      ] do
    for {module, binary} <- Code.compile_file(Path.expand(path, __DIR__)) do
      File.write!(Path.join(beam_dir, "#{module}.beam"), binary)
    end
  end

  Mimic.copy(Tuist.Environment)
  Mimic.copy(TuistCommon.Repo.PoolMetrics)
  Tuist.Repo.PromExPlugin.attach()
  Tuist.ClickHouseRepo.PromExPlugin.attach()
  Code.require_file("../test/tuist/repo/prom_ex_plugin_test.exs", __DIR__)
  Code.require_file("../test/tuist/clickhouse_repo/prom_ex_plugin_test.exs", __DIR__)
rescue
  error ->
    File.rm_rf!(beam_dir)
    reraise error, __STACKTRACE__
end
