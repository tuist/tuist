defmodule Pulse.RendezvousTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Rendezvous
  alias Pulse.Storage.S3.CompactionOwnership

  test "stable assignment vectors pin the cluster scoring format" do
    members = [:a@host, :b@host, :c@host]
    assert Rendezvous.owner(["tenant", "metrics"], members) == :b@host
    assert Rendezvous.owner(["tenant", "logs"], members) == :c@host
  end

  test "production compaction key vectors are stable" do
    members = [:a@host, :b@host, :c@host]

    expected = [
      :c@host,
      :a@host,
      :c@host,
      :a@host,
      :b@host,
      :c@host,
      :b@host,
      :b@host,
      :a@host,
      :a@host,
      :b@host,
      :a@host,
      :a@host,
      :c@host,
      :c@host,
      :b@host,
      :c@host,
      :a@host,
      :b@host,
      :c@host
    ]

    for {member, number} <- Enum.with_index(expected, 1) do
      assert Rendezvous.owner(["compaction", "tenant-#{number}", "metrics"], members) == member
      assert CompactionOwnership.owner("tenant-#{number}", "metrics", members) == member
    end
  end

  test "key field boundaries cannot alias tenants, signals or rule identities" do
    members = [:a@host, :b@host, :c@host]

    assert Enum.any?(1..100, fn i ->
             Rendezvous.owner(["tenant-#{i}", "ab", "c"], members) !=
               Rendezvous.owner(["tenant-#{i}", "a", "bc"], members)
           end)

    assert Rendezvous.owner(["tenant", "metrics"], []) == nil
    assert Rendezvous.owner(["tenant", "rule", "latency"], [:a@host]) == :a@host
  end
end
