alias TuistEx.Analytics.{HTTP, Shards}
alias TuistEx.HTTP, as: RawHTTP

# Exercise the plan-ID protocol used by Cargo, using normal GitHub OIDC and the
# job's dispatch grant. Object-store credentials never enter this process.
grant = System.fetch_env!("TUIST_CACHE_SIGNING_GRANT")
ref = "cargo-api-#{System.fetch_env!("GITHUB_RUN_ID")}-#{System.fetch_env!("GITHUB_RUN_ATTEMPT")}"
env = fn
  "TUIST_PROJECT" -> "tuist/shard-storage-cargo-e2e"
  key -> System.get_env(key)
end
opts = [environment: env, shard_total: 2]
{:ok, plan} = Shards.create_plan(ref, ["crate-a", "crate-b"], [], opts)
id = plan["id"]
{:ok, %{"data" => %{"upload_id" => upload}}} = HTTP.project_request(:post, "/tests/shards/upload/start", %{shard_plan_id: id}, opts)
{:ok, %{"data" => %{"url" => url}}} = HTTP.project_request(:post, "/tests/shards/upload/generate-url", %{shard_plan_id: id, upload_id: upload, part_number: 1}, opts)
true = URI.parse(url).host == "shard-storage.kura.svc.cluster.local"
bytes = :crypto.strong_rand_bytes(8 * 1_048_576)
{:ok, etag} = RawHTTP.put_binary(url, bytes)
{:ok, _} = HTTP.project_request(:post, "/tests/shards/upload/complete", %{shard_plan_id: id, upload_id: upload, parts: [%{part_number: 1, etag: etag}]}, opts)
{:ok, shard} = HTTP.project_request(:get, "/tests/shards/ignored-reference/0?shard_plan_id=#{id}", nil, opts)
target = Path.join(System.fetch_env!("RUNNER_TEMP"), "cargo-api.bin")
:ok = RawHTTP.download(shard["download_url"], target)
true = File.read!(target) == bytes
File.rm!(target)
no_grant = Keyword.put(opts, :environment, fn key -> if key == "TUIST_CACHE_SIGNING_GRANT", do: nil, else: env.(key) end)
{:error, {:http, 500, _}} = Shards.fetch(ref, 0, no_grant)
# A foreign project must not use this plan ID for multipart writes.
{:error, {:http, 404, _}} = HTTP.project_request(:post, "/tests/shards/upload/start", %{shard_plan_id: id}, [])
invalid = Keyword.put(opts, :environment, fn key -> if key == "TUIST_CACHE_SIGNING_GRANT", do: grant <> "x", else: env.(key) end)
{:ok, fallback} = Shards.create_plan(ref <> "-invalid", ["crate-a"], [], invalid)
{:ok, shard} = Shards.fetch(fallback["reference"], 0, invalid)
true = URI.parse(shard["download_url"]).host != "shard-storage.kura.svc.cluster.local"
IO.puts("PASS Cargo plan-ID upload/download bytes, project isolation, missing-grant denial and forged-grant Tigris fallback; plan_id=#{id}")
