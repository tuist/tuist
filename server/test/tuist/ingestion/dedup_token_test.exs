defmodule Tuist.Ingestion.DedupTokenTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Ingestion.DedupToken

  # DedupToken skips the token in the test environment because ClickHouse's
  # insert_deduplication_token interacts badly with Ecto's SQL sandbox: the
  # row would be acknowledged but invisible to the same session's subsequent
  # SELECT. Every test in this file has to opt back into the production
  # branch by stubbing Environment.test?/0 to `false`.
  setup :verify_on_exit!

  setup do
    stub(Environment, :test?, fn -> false end)
    :ok
  end

  describe "insert_all_opts/2" do
    test "returns a namespaced insert_deduplication_token when every event carries an event_id" do
      events = [
        %{event_id: "01930c0e-6e2a-7a91-9a1c-000000000001"},
        %{event_id: "01930c0e-6e2a-7a91-9a1c-000000000002"}
      ]

      opts = DedupToken.insert_all_opts(events, "gradle-cache-events")

      assert [settings: [insert_deduplication_token: token]] = opts

      assert String.starts_with?(token, "gradle-cache-events:")

      hash = token |> String.split(":") |> List.last()
      assert String.length(hash) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, hash)
    end

    test "produces the same token for the same event_ids in any order" do
      forward =
        DedupToken.insert_all_opts(
          [%{event_id: "a"}, %{event_id: "b"}, %{event_id: "c"}],
          "reapi-cache-events"
        )

      reversed =
        DedupToken.insert_all_opts(
          [%{event_id: "c"}, %{event_id: "b"}, %{event_id: "a"}],
          "reapi-cache-events"
        )

      assert forward == reversed
    end

    test "produces different tokens for different event_id sets under the same namespace" do
      first =
        DedupToken.insert_all_opts([%{event_id: "a"}, %{event_id: "b"}], "reapi-cache-events")

      second =
        DedupToken.insert_all_opts([%{event_id: "a"}, %{event_id: "c"}], "reapi-cache-events")

      assert first != second
    end

    test "produces different tokens for the same event_ids under different namespaces" do
      gradle = DedupToken.insert_all_opts([%{event_id: "a"}], "gradle-cache-events")
      reapi = DedupToken.insert_all_opts([%{event_id: "a"}], "reapi-cache-events")

      assert gradle != reapi
    end

    test "returns an empty option list when no event carries an event_id (old Kura)" do
      events = [%{cache_key: "k1"}, %{cache_key: "k2"}]

      assert DedupToken.insert_all_opts(events, "gradle-cache-events") == []
    end

    test "returns an empty option list for a partial batch (mixed old/new Kura)" do
      events = [%{event_id: "01930c0e-6e2a-7a91-9a1c-000000000001"}, %{cache_key: "k2"}]

      assert DedupToken.insert_all_opts(events, "gradle-cache-events") == []
    end

    test "returns an empty option list for an empty batch" do
      assert DedupToken.insert_all_opts([], "gradle-cache-events") == []
    end
  end

  describe "insert_all_opts/2 under the test environment" do
    test "skips the token so the Ecto SQL sandbox stays consistent" do
      stub(Environment, :test?, fn -> true end)

      events = [%{event_id: "01930c0e-6e2a-7a91-9a1c-000000000001"}]

      assert DedupToken.insert_all_opts(events, "gradle-cache-events") == []
    end
  end
end
