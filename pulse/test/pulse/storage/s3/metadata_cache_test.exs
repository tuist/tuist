defmodule Pulse.Storage.S3.MetadataCacheTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Runtime
  alias Pulse.Storage.S3.MetadataCache

  setup do
    start_supervised!(MetadataCache)
    :ok
  end

  test "decoded heap occupancy triggers eviction independently of encoded byte accounting" do
    data = List.duplicate({1, 2}, 150_000)
    for n <- 1..4, do: assert(:ok = MetadataCache.put(%{"k" => "page-#{n}", "b" => 64}, data))
    table = Runtime.table(MetadataCache)
    assert :ets.info(table, :memory) * :erlang.system_info(:wordsize) <= 16_777_216
    assert :ets.info(table, :size) < 4
  end

  test "cached references do not pin the root from which they were decoded" do
    root = :binary.copy("x", 524_288)
    key = binary_part(root, 100, 128)
    nested = binary_part(root, 400, 256)
    ref = %{"k" => key, "b" => 64, "q" => %{"b" => nested, "s" => [nested]}}
    data = %{"entries" => [%{"k" => nested}]}
    assert :ok = MetadataCache.put(ref, data)
    assert {:ok, ^data} = MetadataCache.get(ref)
    [{stored_key, stored_ref, stored_data, _, _}] = :ets.lookup(Runtime.table(MetadataCache), key)
    assert :binary.referenced_byte_size(stored_key) == byte_size(stored_key)
    assert :binary.referenced_byte_size(stored_ref["k"]) == byte_size(stored_ref["k"])
    assert :binary.referenced_byte_size(stored_ref["q"]["b"]) == 256
    assert :binary.referenced_byte_size(hd(stored_ref["q"]["s"])) == 256
    assert :binary.referenced_byte_size(hd(stored_data["entries"])["k"]) == 256
  end
end
