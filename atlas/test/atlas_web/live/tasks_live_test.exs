defmodule AtlasWeb.TasksLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Tasks

  test "creates an assigned task and shows it in the owner's list", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/tasks")

    assert has_element?(view, "#add-task-button")
    assert has_element?(view, "#tasks-empty")
    assert render(view) =~ ~s(id="task-form")

    render_hook(view, "save", %{
      "task" => %{
        "title" => "Review proposal",
        "assignee_id" => user.id,
        "due_on" => "2026-10-01",
        "remind_at" => ""
      }
    })

    assert has_element?(view, "#tasks-table tbody tr")
    assert has_element?(view, "#task-actions-#{hd(Tasks.list_tasks(assignee_id: user.id)).id}")
    assert has_element?(view, "#tasks-table", "Oct 1, 2026")

    assert [%{title: "Review proposal", due_on: ~D[2026-10-01]}] =
             Tasks.list_tasks(assignee_id: user.id, status: "open")
  end

  test "keeps task search and filters in the page address", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {_other_conn, teammate} = log_in_user(build_conn(), %{name: "Teammate"})

    {:ok, matching} =
      Tasks.create_task(%{title: "Review proposal", assignee_id: user.id, due_on: ~D[2026-10-01]}, user)

    {:ok, other} = Tasks.create_task(%{title: "Call customer", assignee_id: teammate.id}, user)

    params = %{
      "q" => "proposal",
      "filter_assignee_id_op" => "==",
      "filter_assignee_id_val" => user.id
    }

    {:ok, view, _html} = live(conn, ~p"/tasks?#{params}")

    assert has_element?(view, "#tasks-filters-dropdown")
    assert has_element?(view, "#tasks-active-filters")
    assert has_element?(view, "#tasks-search[value='proposal']")
    assert has_element?(view, "#tasks-table", matching.title)
    assert has_element?(view, "#tasks-table", "Oct 1, 2026")
    refute has_element?(view, "#tasks-table", other.title)

    render_change(view, "search", %{"search" => %{"query" => "customer"}})

    assert_patch(view, ~p"/tasks?#{Map.put(params, "q", "customer")}")
    assert has_element?(view, "#tasks-empty")

    render_patch(view, ~p"/tasks?q=customer")
    assert has_element?(view, "#tasks-table", other.title)

    render_patch(
      view,
      ~p"/tasks?#{%{"filter_assignee_id_op" => "!=", "filter_assignee_id_val" => user.id}}"
    )

    assert has_element?(view, "#tasks-table", other.title)
    refute has_element?(view, "#tasks-table", matching.title)
  end
end
