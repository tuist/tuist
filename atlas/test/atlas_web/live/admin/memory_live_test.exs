defmodule AtlasWeb.Admin.MemoryLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Memory

  test "renders the memory explorer and detail route for executives", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{role: :executive})
    {:ok, fact} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
    {:ok, preference} = Memory.create_node(%{kind: :preference, body: "Pat prefers Loom."})
    {:ok, edge} = Memory.create_edge(%{src_id: preference.id, dst_id: fact.id, kind: :related_to})
    {:ok, _bulletin} = Memory.upsert_bulletin(:global, "Acme renewal details matter.")

    {:ok, view, _html} = live(conn, ~p"/admin/memory")

    assert has_element?(view, "#admin-memory")
    assert has_element?(view, "#admin-memory-visible-count", "2 memories")
    assert has_element?(view, "#memory_nodes-#{fact.id}")
    assert has_element?(view, "#memory_nodes-#{preference.id}")
    assert has_element?(view, "#admin-memory-filters-dropdown")
    assert has_element?(view, ~s(#memory_nodes-#{preference.id} a[href="/admin/memory/#{preference.id}"]))
    assert has_element?(view, ~s(a[href="/admin/memory"]), "Memory")
    assert has_element?(view, "#admin-memory-bulletin-body", "Acme renewal details matter.")

    {:ok, detail, _html} = live(conn, ~p"/admin/memory/#{preference.id}")

    assert has_element?(detail, "#admin-memory[data-page='detail']")
    assert has_element?(detail, "#admin-memory-selected-kind", "Preference")
    assert has_element?(detail, "#admin-memory-node-form")
    assert has_element?(detail, "#outgoing_edges-#{edge.id}")
  end

  test "filters memories from URL params", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{role: :executive})
    {:ok, match} = Memory.create_node(%{kind: :preference, body: "Pat prefers Loom."})
    {:ok, forgotten} = Memory.create_node(%{kind: :preference, body: "Pat prefers Zoom."})
    {:ok, other} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})
    {:ok, _forgotten} = Memory.forget_node(forgotten)

    filter_params = %{
      "search" => "Pat",
      "filter_kind_op" => "==",
      "filter_kind_val" => "preference"
    }

    {:ok, view, _html} = live(conn, ~p"/admin/memory?#{filter_params}")

    assert has_element?(view, "#kind")
    assert has_element?(view, "#memory_nodes-#{match.id}")
    refute has_element?(view, "#memory_nodes-#{forgotten.id}")
    refute has_element?(view, "#memory_nodes-#{other.id}")

    forgotten_params =
      Map.merge(filter_params, %{
        "filter_status_op" => "==",
        "filter_status_val" => "forgotten"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/memory?#{forgotten_params}")

    assert has_element?(view, "#memory_nodes-#{forgotten.id}")
    refute has_element?(view, "#memory_nodes-#{match.id}")
  end

  test "updates, forgets, restores, and edits the bulletin", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{role: :executive})
    {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})

    {:ok, view, _html} = live(conn, ~p"/admin/memory/#{node.id}")

    render_submit(view, "save_node", %{
      "memory_node" => %{
        "kind" => "decision",
        "body" => "Acme renewal moved to Q4 2026.",
        "importance" => "0.85"
      }
    })

    assert %{kind: :decision, body: "Acme renewal moved to Q4 2026.", importance: 0.85} =
             Memory.get_node(node.id)

    assert has_element?(view, "#admin-memory-node-body", "Acme renewal moved to Q4 2026.")

    render_click(element(view, "#admin-memory-forget-node"))

    assert Memory.get_node(node.id).forgotten
    assert has_element?(view, "#admin-memory-restore-node")

    render_click(element(view, "#admin-memory-restore-node"))

    refute Memory.get_node(node.id).forgotten
    assert has_element?(view, "#admin-memory-forget-node")

    {:ok, index, _html} = live(conn, ~p"/admin/memory")

    render_submit(index, "save_bulletin", %{
      "bulletin" => %{"body" => "Acme has a Q4 renewal decision."}
    })

    assert %{body: "Acme has a Q4 renewal decision."} = Memory.get_bulletin(:global)
  end

  test "renders the memory explorer for employees", %{conn: conn} do
    {conn, _employee} = log_in_user(conn, %{role: :employee})
    {:ok, node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})

    {:ok, view, _html} = live(conn, ~p"/admin/memory")

    assert has_element?(view, "#admin-memory")
    assert has_element?(view, "#memory_nodes-#{node.id}")
    assert has_element?(view, ~s(a[href="/admin/memory"]), "Memory")
  end

  test "keeps the legacy admin memory URL available to authenticated users", %{conn: conn} do
    {conn, _employee} = log_in_user(conn, %{role: :employee})
    {:ok, _node} = Memory.create_node(%{kind: :fact, body: "Acme renews in Q3 2026."})

    {:ok, view, _html} = live(conn, ~p"/admin/memory")

    assert has_element?(view, "#admin-memory")
  end
end
