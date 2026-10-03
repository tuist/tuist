defmodule Atlas.GTM.Outreach.TopicsTest do
  use ExUnit.Case, async: true

  alias Atlas.GTM.Outreach.Topics

  test "curated queries focus on mobile scale signals and avoid stale Bazel searches" do
    queries = Topics.curated_queries()

    refute Enum.any?(queries, &String.contains?(String.downcase(&1.query), "bazel"))
    assert Enum.any?(queries, &(&1.source == "brave" and &1.metadata["topic"] == "iOS at scale"))
    assert Enum.any?(queries, &(&1.source == "github" and &1.metadata["topic"] == "Tuist public projects"))

    assert Enum.all?(queries, fn query ->
             query.metadata["topic_source"] == "curated" and is_list(query.metadata["signals"])
           end)
  end
end
