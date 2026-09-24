defmodule Atlas.Memory.Workers.LinkNodeTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Memory
  alias Atlas.Memory.EdgeClassifier
  alias Atlas.Memory.Workers.LinkNode
  alias Atlas.Vector

  setup :verify_on_exit!

  test "creates edges based on the classifier's verdict for each candidate" do
    {:ok, new_node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q4 2026."})
    {:ok, related} = Memory.create_node(%{kind: :fact, body: "Acme is a customer."})
    {:ok, superseded} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})

    stub(Vector, :configured?, fn -> true end)

    stub(Vector, :search, fn _embedding, _opts ->
      {:ok,
       %{
         "results" => [
           %{"id" => "memory_node:#{new_node.id}", "score" => 1.0},
           %{"id" => "memory_node:#{related.id}", "score" => 0.82},
           %{"id" => "memory_node:#{superseded.id}", "score" => 0.78}
         ]
       }}
    end)

    expect(EdgeClassifier, :classify, fn ^new_node, candidates ->
      assert Enum.map(candidates, & &1.id) |> Enum.sort() ==
               Enum.sort([related.id, superseded.id])

      {:ok,
       [
         %{candidate_id: related.id, relation: :related_to},
         %{candidate_id: superseded.id, relation: :updates}
       ]}
    end)

    assert :ok = perform_job(LinkNode, %{"node_id" => new_node.id})

    assert [%{kind: :related_to, dst_id: dst1}, %{kind: :updates, dst_id: dst2}] =
             Memory.list_edges_by_src(new_node) |> Enum.sort_by(& &1.kind)

    assert dst1 == related.id
    assert dst2 == superseded.id
  end

  test "cancels when the vector service is not configured" do
    {:ok, new_node} = Memory.create_node(%{kind: :fact, body: "Acme renews."})

    stub(Vector, :configured?, fn -> false end)

    assert {:cancel, :vector_not_configured} =
             perform_job(LinkNode, %{"node_id" => new_node.id})
  end

  test "cancels when the node was forgotten between save and link" do
    {:ok, new_node} = Memory.create_node(%{kind: :fact, body: "Acme renews."})
    {:ok, _} = Memory.forget_node(new_node)

    assert {:cancel, :node_forgotten} =
             perform_job(LinkNode, %{"node_id" => new_node.id})
  end

  defp perform_job(worker, args) do
    worker.perform(%Oban.Job{args: args})
  end
end
