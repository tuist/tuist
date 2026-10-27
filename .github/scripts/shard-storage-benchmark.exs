alias TuistEx.Analytics.{HTTP, Shards, ShardUpload}
alias TuistEx.HTTP, as: RawHTTP

defmodule ShardBenchmark do
  def timed(fun) do
    start = System.monotonic_time(:microsecond)
    value = fun.()
    {value, (System.monotonic_time(:microsecond) - start) / 1_000_000}
  end

  def ok({:ok, value}), do: value
  def ok(:ok), do: :ok
  def ok({:error, {:http, status, _}}), do: raise("HTTP #{status}")
  def ok({:error, {:http, status}}), do: raise("HTTP #{status}")
  def ok(_), do: raise("operation failed; details suppressed to protect signed URLs")

  def hash(file) do
    file |> File.stream!(1_048_576) |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1)) |> :crypto.hash_final() |> Base.encode16(case: :lower)
  end

  def run do
    grant = System.fetch_env!("TUIST_CACHE_SIGNING_GRANT")
    true = byte_size(grant) > 30
    output = System.fetch_env!("BENCHMARK_OUTPUT")
    File.mkdir_p!(output)
    rows = Path.join(output, "transfers.jsonl")
    ref_base = "shard-perf-#{System.fetch_env!("GITHUB_RUN_ID")}-#{System.fetch_env!("GITHUB_RUN_ATTEMPT")}"
    Enum.each([64, 512], fn mib ->
      Enum.each(1..5, fn round ->
      source = Path.join(output, "source")
      File.mkdir_p!(source)
      payload = Path.join(source, "payload")
      File.open!(payload, [:write, :binary], fn io ->
        Enum.each(1..mib, fn _ -> IO.binwrite(io, :crypto.strong_rand_bytes(1_048_576)) end)
      end)
      expected = hash(payload)
      archive = Path.join(output, "payload.tar.gz")
      :ok = Shards.archive(source, archive)
      bytes = File.stat!(archive).size
      archive_hash = hash(archive)
        modes = if rem(round, 2) == 1, do: [:tigris_serial, :tigris_parallel, :garage_parallel], else: [:garage_parallel, :tigris_parallel, :tigris_serial]
        Enum.each(modes, fn mode ->
          environment = fn
            "TUIST_CACHE_SIGNING_GRANT" -> if mode == :garage_parallel, do: grant, else: nil
            name -> System.get_env(name)
          end
          opts = [environment: environment, shard_total: 2]
          ref = "#{ref_base}-#{mib}-#{round}-#{mode}"
          {plan, plan_s} = timed(fn -> ok(Shards.create_plan(ref, ["Fixture.One", "Fixture.Two"], [], opts)) end)
          {%{"data" => %{"upload_id" => upload}}, start_s} = timed(fn -> ok(HTTP.project_request(:post, "/tests/shards/upload/start", %{reference: ref}, opts)) end)
          chunks = File.stream!(archive, 64 * 1_048_576)
          callback = fn chunk, number ->
            with {:ok, %{"data" => %{"url" => url}}} <- HTTP.project_request(:post, "/tests/shards/upload/generate-url", %{reference: ref, upload_id: upload, part_number: number}, opts) do
              host = URI.parse(url).host
              local? = host == "shard-storage.kura.svc.cluster.local"
              if local? != (mode == :garage_parallel), do: raise("backend selection mismatch")
              RawHTTP.put_binary(url, chunk)
            end
          end
          {parts, transfer_s} = timed(fn ->
            if mode == :tigris_serial do
              chunks |> Stream.with_index(1) |> Enum.map(fn {chunk, n} -> %{part_number: n, etag: ok(callback.(chunk, n))} end)
            else
              ok(ShardUpload.upload(chunks, callback))
            end
          end)
          {_, complete_s} = timed(fn -> ok(HTTP.project_request(:post, "/tests/shards/upload/complete", %{reference: ref, upload_id: upload, parts: parts}, opts)) end)
          {shard, lookup_s} = timed(fn -> ok(Shards.fetch(ref, 0, opts)) end)
          url = shard["download_url"]
          true = is_binary(url)
          downloaded = Path.join(output, "download.tar.gz")
          {_, download_s} = timed(fn -> ok(RawHTTP.download(url, downloaded)) end)
          true = hash(downloaded) == archive_hash
          extracted = Path.join(output, "extracted")
          {_, extract_s} = timed(fn -> ok(Shards.extract(downloaded, extracted)) end)
          true = hash(Path.join(extracted, "payload")) == expected
          row = %{mode: mode, round: round, payload_mib: mib, archive_bytes: bytes, plan_id: plan["id"], reference: ref, plan_create_s: plan_s, shard_lookup_s: lookup_s, finished_at: DateTime.to_iso8601(DateTime.utc_now()), upload_start_s: start_s, upload_transfer_s: transfer_s, upload_complete_s: complete_s, upload_total_s: start_s + transfer_s + complete_s, download_s: download_s, extract_s: extract_s, sha256: archive_hash, verified: true}
          File.write!(rows, JSON.encode!(row) <> "\n", [:append])
          IO.puts(JSON.encode!(row))
          File.rm!(downloaded)
          File.rm_rf!(extracted)
        end)
      File.rm!(archive)
      File.rm_rf!(source)
      end)
    end)
  end
end
ShardBenchmark.run()
