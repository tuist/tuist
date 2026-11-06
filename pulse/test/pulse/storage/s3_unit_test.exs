defmodule Pulse.Storage.S3UnitTest do
  # Pure-Elixir tests of Pulse.Storage.S3's pre-network guards and key
  # construction. Anything that actually talks to an S3 endpoint lives in
  # s3_test.exs behind the `:integration` tag.

  use Pulse.Test.Case, async: true

  alias Pulse.Record.Log
  alias Pulse.Storage.S3

  describe "tenant validation" do
    test "rejects adversarial tenant names before touching the object store" do
      for bad <- ["", "../evil", "foo/bar", "foo bar", String.duplicate("a", 200)] do
        assert {:error, {:invalid_tenant, ^bad}} = S3.append(:logs, bad, [%Log{timestamp_ns: 1}])
        assert {:error, {:invalid_tenant, ^bad}} = S3.query(:logs, bad, [])
      end
    end

    test "rejects adversarial tenant names even for empty batches" do
      # Prior version bailed early on `[]` and returned :ok, letting an
      # attacker probe the auth surface with a no-op payload.
      assert {:error, {:invalid_tenant, "../evil"}} = S3.append(:logs, "../evil", [])
      assert {:error, {:invalid_tenant, ""}} = S3.append(:logs, "", [])
    end

    test "accepts common tenant name shapes" do
      for good <- ["default", "customer-42", "team.alpha", "svc_web"] do
        assert :ok = S3.append(:logs, good, [])
      end
    end
  end

  describe "encode failures" do
    test "returns an error tuple instead of raising on non-UTF-8 body bytes" do
      record = %Log{timestamp_ns: 1, body: <<0xFF, 0xFE>>}

      assert {:error, {:encode_failed, _}} = S3.append(:logs, "default", [record])
    end
  end

  describe "object key construction" do
    test "with an idempotency key, the same call maps to the same key" do
      k1 = S3.object_key("acme", "logs", 100, 200, "payload", "req-1")
      k2 = S3.object_key("acme", "logs", 100, 200, "payload", "req-1")
      assert k1 == k2
    end

    test "with an idempotency key, different keys map to different objects" do
      k1 = S3.object_key("acme", "logs", 100, 200, "payload", "req-1")
      k2 = S3.object_key("acme", "logs", 100, 200, "payload", "req-2")
      refute k1 == k2
    end

    test "without an idempotency key, identical payloads still map to distinct objects" do
      # This is the "two legitimate producers happen to have identical bytes"
      # case Codex flagged in review 2: content-addressing alone would
      # silently drop one. With no idempotency key we always take a random
      # suffix so distinct calls always land on distinct objects.
      k1 = S3.object_key("acme", "logs", 100, 200, "payload", nil)
      k2 = S3.object_key("acme", "logs", 100, 200, "payload", nil)
      refute k1 == k2
    end

    test "an empty-string idempotency key is treated as absent" do
      # Prevents a client that sends `Idempotency-Key: ` from accidentally
      # collapsing every batch onto one key.
      k1 = S3.object_key("acme", "logs", 100, 200, "payload", "")
      k2 = S3.object_key("acme", "logs", 100, 200, "payload", "")
      refute k1 == k2
    end

    test "the same idempotency key with different content produces different objects" do
      # A caller who reuses an idempotency key with a different payload is
      # almost certainly buggy. We must not silently overwrite the earlier
      # write with the newer one; distinct content should land on distinct
      # keys.
      k1 = S3.object_key("acme", "logs", 100, 200, "payload-a", "req-1")
      k2 = S3.object_key("acme", "logs", 100, 200, "payload-b", "req-1")
      refute k1 == k2
    end

    test "the idempotency key is scoped by tenant" do
      # A shared idempotency key across tenants must not collide.
      k1 = S3.object_key("alpha", "logs", 100, 200, "p", "req-1")
      k2 = S3.object_key("beta", "logs", 100, 200, "p", "req-1")
      refute String.replace(k1, "alpha", "beta") == k2
    end

    test "different tenants never share a prefix" do
      k1 = S3.object_key("alpha", "logs", 100, 200, "p", "req-1")
      k2 = S3.object_key("beta", "logs", 100, 200, "p", "req-1")
      refute String.starts_with?(k1, "tenants/beta/")
      refute String.starts_with?(k2, "tenants/alpha/")
    end

    test "the key path carries the v4 schema version and signal/date/hour partitioning" do
      # v4 is the current write format (partitioned Parquet with
      # `signal=/date=/hour=` folders). A future format change bumps to
      # v5/ so old objects can be migrated at their own pace rather than
      # orphaned. Guarding the prefix at the key level catches an
      # accidental removal of either the versioning or the partitioning.
      key = S3.object_key("acme", "logs", 100, 200, "p", "req-1")
      assert String.starts_with?(key, "tenants/acme/v4/signal=logs/")
      assert key =~ ~r|/date=\d{4}-\d{2}-\d{2}/hour=\d{2}/|
    end

    test "keys sort chronologically by min_ts within a tenant" do
      k_early = S3.object_key("acme", "logs", 100, 200, "p", "req-1")
      k_late = S3.object_key("acme", "logs", 200, 300, "p", "req-1")
      assert k_early < k_late
    end

    test "the key basename includes both min_ts and max_ts so query can prune at LIST time" do
      # The zero-padded `[min_ts, max_ts]` bounds in the basename are the
      # whole point of the layout — they let `query/3` skip GETs on
      # segments outside the requested time range. Guard the shape so a
      # refactor cannot silently regress the query short-circuit.
      key = S3.object_key("acme", "logs", 42, 999, "p", "req-1")

      assert Path.basename(key) =~ ~r|^00000000000000000042-00000000000000000999-|
    end
  end

  # Segment parsing and time pruning now live in
  # `Pulse.Storage.S3.Manifest.Segment` / `Pulse.Storage.S3.Manifest` and
  # are covered directly in `test/pulse/storage/s3/manifest_test.exs`.

  describe "caller_content_hash" do
    test "identical caller-provided records produce the same fingerprint" do
      records = [
        %Log{timestamp_ns: 1, service: "api", body: "hello"},
        %Log{timestamp_ns: 2, service: "web", body: "world"}
      ]

      assert {:ok, h1} = S3.caller_content_hash(:logs, records)
      assert {:ok, h2} = S3.caller_content_hash(:logs, records)
      assert h1 == h2
    end

    test "two calls with observed_timestamp_ns left nil produce the same fingerprint" do
      # This is the retry-safety case: OTLP callers commonly omit
      # `observedTimeUnixNano`. Two retries both arrive with nil, both hash
      # to the same value, and the idempotency-key path deduplicates. The
      # normalizer fills in a wall clock later, but that happens AFTER the
      # fingerprint is computed.
      r = [%Log{timestamp_ns: 1, body: "same"}]

      assert {:ok, h1} = S3.caller_content_hash(:logs, r)
      assert {:ok, h2} = S3.caller_content_hash(:logs, r)
      assert h1 == h2
    end

    test "a caller-set observed_timestamp_ns IS part of the fingerprint" do
      # If the caller explicitly declares an observed timestamp, that is
      # part of the record they authored. A "retry" that changes it is a
      # distinct write; silently overwriting the earlier value would lose
      # data.
      no_obs = [%Log{timestamp_ns: 1, body: "same"}]
      with_obs_a = [%Log{timestamp_ns: 1, observed_timestamp_ns: 100, body: "same"}]
      with_obs_b = [%Log{timestamp_ns: 1, observed_timestamp_ns: 200, body: "same"}]

      {:ok, h_none} = S3.caller_content_hash(:logs, no_obs)
      {:ok, h_a} = S3.caller_content_hash(:logs, with_obs_a)
      {:ok, h_b} = S3.caller_content_hash(:logs, with_obs_b)

      refute h_none == h_a
      refute h_a == h_b
    end

    test "every caller-controlled field influences the fingerprint" do
      base = [%Log{timestamp_ns: 1, service: "api", body: "same"}]
      diff_body = [%Log{timestamp_ns: 1, service: "api", body: "different"}]
      diff_service = [%Log{timestamp_ns: 1, service: "web", body: "same"}]
      diff_ts = [%Log{timestamp_ns: 2, service: "api", body: "same"}]

      {:ok, h_base} = S3.caller_content_hash(:logs, base)
      {:ok, h_body} = S3.caller_content_hash(:logs, diff_body)
      {:ok, h_service} = S3.caller_content_hash(:logs, diff_service)
      {:ok, h_ts} = S3.caller_content_hash(:logs, diff_ts)

      refute h_base == h_body
      refute h_base == h_service
      refute h_base == h_ts
    end

    test "a map with keys inserted in different orders produces the same fingerprint" do
      # `:erlang.term_to_binary(_, [:deterministic])` sorts map keys before
      # encoding. Without that, two logically-equal records could hash
      # differently just because the caller inserted attributes in a
      # different order — which would defeat idempotent retries across
      # heterogeneous producers.
      order_a = %{"a" => 1, "b" => 2, "c" => 3}
      order_b = order_a |> Map.delete("a") |> Map.put("a", 1)

      r_a = [%Log{timestamp_ns: 1, attributes: order_a}]
      r_b = [%Log{timestamp_ns: 1, attributes: order_b}]

      {:ok, h_a} = S3.caller_content_hash(:logs, r_a)
      {:ok, h_b} = S3.caller_content_hash(:logs, r_b)
      assert h_a == h_b
    end

    test "a non-UTF-8 body still fingerprints without crashing" do
      # `:erlang.term_to_binary` handles any Elixir term, including binaries
      # that are not valid UTF-8. The stored payload's `encode/1` still
      # surfaces `:encode_failed` at write time — we just don't need to
      # trip that path here.
      assert {:ok, _} = S3.caller_content_hash(:logs, [%Log{timestamp_ns: 1, body: <<255>>}])
    end
  end

  describe "attribute sanitization" do
    test "coerces non-string map keys to strings recursively" do
      assert {:ok, sanitized} =
               S3.sanitize_map(%{
                 :status => 200,
                 "nested" => %{404 => "missing", :ref => "abc"},
                 "list" => [%{true => 1}]
               })

      assert Map.has_key?(sanitized, "status")
      assert sanitized["nested"] == %{"404" => "missing", "ref" => "abc"}
      assert sanitized["list"] == [%{"true" => 1}]
    end

    test "rejects rather than collapses keys that stringify to the same value" do
      # A previous version silently dropped one value on collision. Codex
      # flagged the risk (map size decreases without a diagnostic). Now we
      # return an explicit error so the caller can surface it.
      assert {:error, {:attribute_key_collision, _}} =
               S3.sanitize_map(%{1 => "int", "1" => "string"})
    end
  end
end
