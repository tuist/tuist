defmodule AtlasWeb.SessionsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Agents.Sessions.Event, as: AgentSessionEvent
  alias Atlas.Agents.Sessions.Session, as: AgentSession
  alias Atlas.Repo
  alias Condukt.SessionID

  test "lists recent agent sessions newest first", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "sessions-list@example.com"})

    account = insert_account!(%{account_key: "sessions:list", name: "Sessions List"})
    older = insert_session!(%{agent: "Older", started_at: ~U[2026-05-01 10:00:00.000000Z], account_id: account.id})
    newer = insert_session!(%{agent: "Newer", started_at: ~U[2026-05-08 10:00:00.000000Z], account_id: account.id})

    {:ok, _view, html} = live(conn, ~p"/admin/sessions")

    assert html =~ "Sessions"
    assert html =~ "Older"
    assert html =~ "Newer"
    # Newer must appear before older in document order.
    assert :binary.match(html, "Newer") < :binary.match(html, "Older")

    assert html =~ account.name

    # Ensure detail links point at the right session ids.
    assert html =~ ~s(href="/admin/sessions/#{newer.id}")
    assert html =~ ~s(href="/admin/sessions/#{older.id}")
  end

  test "paginates the sessions list when there are more than one page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "sessions-paginate@example.com"})

    base = ~U[2026-05-01 10:00:00.000000Z]

    sessions =
      for i <- 0..20 do
        insert_session!(%{
          agent: "Agent#{String.pad_leading(Integer.to_string(i), 2, "0")}",
          started_at: DateTime.add(base, i, :minute)
        })
      end

    [oldest | _] = sessions
    newest = List.last(sessions)

    {:ok, view, html} = live(conn, ~p"/admin/sessions")

    assert html =~ "Agent20"
    refute html =~ "Agent00"
    assert html =~ ~s(href="/admin/sessions/#{newest.id}")
    refute html =~ ~s(href="/admin/sessions/#{oldest.id}")

    # Pagination control is rendered with a link to page 2.
    assert html =~ "noora-pagination-group"
    assert html =~ "page=2"

    {:ok, _view, html_page_two} = live(conn, ~p"/admin/sessions?page=2")

    assert html_page_two =~ "Agent00"
    refute html_page_two =~ "Agent20"
    assert html_page_two =~ ~s(href="/admin/sessions/#{oldest.id}")

    # Smoke test that the in-place page navigation also works through the pagination control.
    assert view |> render_patch(~p"/admin/sessions?page=2") =~ "Agent00"
  end

  test "does not render the pagination control when results fit in one page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "sessions-no-pagination@example.com"})

    insert_session!(%{agent: "OnlyOne"})

    {:ok, _view, html} = live(conn, ~p"/admin/sessions")

    refute html =~ "noora-pagination-group"
  end

  test "renders the empty state when no sessions exist", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "sessions-empty@example.com"})

    {:ok, _view, html} = live(conn, ~p"/admin/sessions")

    assert html =~ "No agent sessions yet"
  end

  test "session detail page shows prompt, status, and event timeline", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "session-detail@example.com"})

    account = insert_account!(%{account_key: "sessions:detail", name: "Detail Account"})

    session =
      insert_session!(%{
        agent: "Atlas.Accounts.Agents.EmailEventAgent",
        prompt: "Process this inbound email about renewal terms.",
        account_id: account.id,
        status: "succeeded",
        duration_ms: 1_200,
        result: %{"status" => "captured", "event_id" => "evt-1"}
      })

    insert_event!(session, %{
      type: "tool_call",
      name: "find_account",
      phase: "stop",
      duration_ms: 80,
      occurred_at: ~U[2026-05-08 10:00:01.000000Z],
      metadata: %{"tool" => "find_account", "status" => "ok"}
    })

    {:ok, _view, html} = live(conn, ~p"/admin/sessions/#{session.id}")

    assert html =~ "EmailEventAgent"
    assert html =~ "Process this inbound email about renewal terms."
    assert html =~ "Succeeded"
    assert html =~ "captured"
    assert html =~ "find_account"
    assert html =~ ~s(href="/commercial/sales/accounts/#{account.id}")
  end

  test "session detail page renders the transcript when llm_turn events exist", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "session-transcript@example.com"})

    session =
      insert_session!(%{
        agent: "Atlas.Test.Agent",
        prompt: "What's the weather?",
        status: "succeeded",
        duration_ms: 800
      })

    insert_event!(session, %{
      type: "llm_turn",
      name: "turn 0",
      phase: "start",
      occurred_at: ~U[2026-05-08 10:00:01.000000Z],
      metadata: %{
        "turn" => 0,
        "messages" => [%{"role" => "user", "content" => "What's the weather?"}]
      }
    })

    insert_event!(session, %{
      type: "llm_turn",
      name: "turn 0",
      phase: "stop",
      duration_ms: 600,
      occurred_at: ~U[2026-05-08 10:00:01.500000Z],
      metadata: %{
        "turn" => 0,
        "finish_reason" => "stop",
        "usage" => %{"input_tokens" => 8, "output_tokens" => 12},
        "assistant_message" => %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "It's sunny."}]
        }
      }
    })

    {:ok, _view, html} = live(conn, ~p"/admin/sessions/#{session.id}")

    assert html =~ "Activity"
    assert html =~ "Turn 0"
    assert html =~ "What&#39;s the weather?"
    assert html =~ "It&#39;s sunny."
    assert html =~ "↑ 8 / ↓ 12 tokens"
  end

  test "session detail page interleaves tool_call and lifecycle items in the activity feed", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "session-activity@example.com"})

    session = insert_session!(%{agent: "Atlas.Test.Agent", status: "succeeded", duration_ms: 500})

    insert_event!(session, %{
      type: "run",
      phase: "start",
      occurred_at: ~U[2026-05-08 10:00:00.000000Z],
      metadata: %{}
    })

    insert_event!(session, %{
      type: "tool_call",
      name: "find_account",
      phase: "start",
      occurred_at: ~U[2026-05-08 10:00:01.000000Z],
      metadata: %{
        "tool" => "find_account",
        "tool_call_id" => "call_a",
        "args" => %{"emails" => ["a@example.com"]}
      }
    })

    insert_event!(session, %{
      type: "tool_call",
      name: "find_account",
      phase: "stop",
      duration_ms: 60,
      occurred_at: ~U[2026-05-08 10:00:01.060000Z],
      metadata: %{
        "tool" => "find_account",
        "tool_call_id" => "call_a",
        "status" => "ok",
        "result" => %{"found" => true}
      }
    })

    insert_event!(session, %{
      type: "run",
      phase: "stop",
      duration_ms: 500,
      occurred_at: ~U[2026-05-08 10:00:00.500000Z],
      metadata: %{}
    })

    {:ok, _view, html} = live(conn, ~p"/admin/sessions/#{session.id}")

    assert html =~ "Activity"
    # tool_call card
    assert html =~ "find_account"
    assert html =~ "a@example.com"
    # lifecycle marker for the run
    assert html =~ "Run"
  end

  test "session detail page redirects when the id is unknown", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "session-missing@example.com"})

    assert {:error, {:live_redirect, %{to: "/admin/sessions"}}} =
             live(conn, ~p"/admin/sessions/#{SessionID.generate()}")
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "sessions-test:#{System.unique_integer([:positive])}",
      name: "Sessions Test",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_session!(attrs) do
    defaults = %{
      id: SessionID.generate(),
      agent: "Atlas.Test.Agent",
      prompt: "test prompt",
      status: "running",
      started_at: DateTime.utc_now()
    }

    merged = Map.merge(defaults, attrs)

    %{
      id: merged.id,
      agent: merged.agent,
      prompt: merged.prompt,
      status: "running",
      started_at: merged.started_at,
      account_id: merged[:account_id]
    }
    |> AgentSession.create_changeset()
    |> Repo.insert!()
    |> AgentSession.finalize_changeset(%{
      status: merged.status,
      finished_at: merged[:finished_at] || DateTime.add(merged.started_at, merged[:duration_ms] || 0, :millisecond),
      duration_ms: merged[:duration_ms],
      result: merged[:result],
      error: merged[:error]
    })
    |> Repo.update!()
  end

  defp insert_event!(session, attrs) do
    attrs
    |> Map.put(:agent_session_id, session.id)
    |> AgentSessionEvent.changeset()
    |> Repo.insert!()
  end
end
