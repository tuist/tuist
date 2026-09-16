defmodule AtlasWeb.SupportLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  import Phoenix.LiveViewTest

  alias Atlas.Inbox
  alias Atlas.Inbox.EmailParser
  alias Atlas.Support
  alias Atlas.Support.Workers.DeliverReply

  test "renders the support queue and the selected navigation item", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    thread = support_thread!()

    {:ok, view, _html} = live(conn, ~p"/support")

    assert has_element?(view, "#support")
    assert has_element?(view, "#support-needs-reply-tab")
    assert has_element?(view, "#support-filters-dropdown")
    assert has_element?(view, "#support-threads-table", thread.customer_email)
    assert has_element?(view, ~s(a[href="/support"] [data-selected]))
  end

  test "searches conversations without losing the current queue state", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    thread = support_thread!(subject: "Cache upload stalls")

    {:ok, view, _html} = live(conn, ~p"/support")

    view
    |> form("#support-search-form", %{"search" => %{"query" => "Cache upload"}})
    |> render_change()

    assert_patch(view, ~p"/support?q=Cache+upload")
    assert has_element?(view, "#support-threads-table", thread.subject)
  end

  test "uses the standard table empty state when a queue is empty", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    {:ok, view, _html} = live(conn, ~p"/support")

    assert has_element?(view, "#support-threads-table th", "Conversation")
    assert has_element?(view, "#support-threads-empty .noora-table-empty-state")
  end

  test "replaces the empty table body when a conversation enters the selected queue", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    thread = support_thread!()

    {:ok, view, _html} = live(conn, ~p"/support?status=waiting")

    assert has_element?(view, "#support-threads-empty")

    render_patch(view, ~p"/support?status=open")

    refute has_element?(view, "#support-threads-empty")
    assert has_element?(view, "#support-threads-table-body", thread.subject)
  end

  test "filters conversations assigned to the current user", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    assigned_thread = support_thread!()
    unassigned_thread = support_thread!()

    assert {:ok, _thread} = Support.assign(assigned_thread, user.id, user)

    params = %{"filter_owner_op" => "==", "filter_owner_val" => "mine"}
    {:ok, view, _html} = live(conn, ~p"/support?#{params}")

    assert has_element?(view, "#owner")
    assert has_element?(view, "#support-threads-table", assigned_thread.customer_email)
    refute has_element?(view, "#support-threads-table", unassigned_thread.customer_email)
  end

  test "adds the owner filter with a default comparison", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    {:ok, view, _html} = live(conn, ~p"/support")

    render_hook(view, "add_filter", %{"value" => "owner"})

    filter_params = %{"filter_owner_op" => "==", "filter_owner_val" => ""}
    assert_patch(view, ~p"/support?#{filter_params}")
    assert_push_event(view, "open-dropdown", %{id: "filter-owner-value-dropdown"})
  end

  test "lets a teammate assign, resolve, and respond to a conversation", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{name: "Support Teammate"})
    thread = support_thread!()

    {:ok, view, _html} = live(conn, ~p"/support/#{thread.id}")

    assert has_element?(view, "#support-composer-form")
    assert has_element?(view, "#support-composer-mode-reply[data-selected]")
    assert has_element?(view, "#support-assign-to-self")

    render_click(view, "assign_to_self")
    assert has_element?(view, "#support-assignment-form", user.name)

    render_click(view, "set_status", %{"status" => "resolved"})
    assert has_element?(view, "#support-reopen")

    view
    |> form("#support-composer-form", %{
      "composer" => %{"body" => "We are on it.", "reply_all" => "false"}
    })
    |> render_submit()

    assert_enqueued(worker: DeliverReply)
    assert Support.get_thread(thread.id).status == "waiting"
  end

  test "sends an agent reply through an unverified chat", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    assert {:ok, %{thread: thread}} =
             Support.receive_chat(%{
               "email" => "chat-#{System.unique_integer([:positive])}@example.com",
               "body" => "Help us."
             })

    {:ok, view, _html} = live(conn, ~p"/support/#{thread.id}")

    assert has_element?(view, "#support-chat-email-unverified", "Email unverified")
    refute has_element?(view, "#support-composer-add-attachment")

    view
    |> form("#support-composer-form", %{"composer" => %{"body" => "We are investigating this now."}})
    |> render_submit()

    [reply] =
      thread.id
      |> Support.get_thread()
      |> Map.fetch!(:messages)
      |> Enum.filter(&(&1.kind == "outbound"))

    assert reply.delivery_status == "delivered"
    assert reply.metadata["delivery_channel"] == "chat"
    refute_enqueued(worker: DeliverReply, args: %{"message_id" => reply.id})
  end

  test "assigns a conversation from the select component payload", %{conn: conn} do
    {conn, assignee} = log_in_user(conn, %{name: "Pedro Piñera Buendía"})
    thread = support_thread!()

    {:ok, view, _html} = live(conn, ~p"/support/#{thread.id}")

    render_hook(view, "assign", %{
      "items" => [%{"label" => assignee.name, "value" => assignee.id}],
      "value" => [assignee.id]
    })

    assert Support.get_thread(thread.id).owner_id == assignee.id
  end

  test "lets a teammate switch the composer to a private note", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    thread = support_thread!()

    {:ok, view, _html} = live(conn, ~p"/support/#{thread.id}")

    render_click(view, "set_composer_mode", %{"mode" => "note"})

    assert has_element?(view, "#support-composer-mode-note[data-selected]")
    assert has_element?(view, "#support-composer-submit", "Add private note")

    view
    |> form("#support-composer-form", %{"composer" => %{"body" => "Customer is preparing renewal."}})
    |> render_submit()

    assert has_element?(view, "#support-thread-messages", "Customer is preparing renewal.")
    assert has_element?(view, "#support-thread-messages [data-part='private-badge']", "Private")
  end

  test "shows uploaded files in the reply composer", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    thread = support_thread!()

    {:ok, view, _html} = live(conn, ~p"/support/#{thread.id}")

    upload =
      file_input(view, "#support-composer-form", :reply_attachment, [
        %{
          name: "diagnostics.txt",
          content: "Build 321 finished successfully."
        }
      ])

    render_upload(upload, "diagnostics.txt")

    assert has_element?(view, "#support-composer-attachments-status", "diagnostics.txt")

    view
    |> form("#support-composer-form", %{"composer" => %{"body" => "", "reply_all" => "false"}})
    |> render_submit()

    assert has_element?(view, "#support-composer-attachments-status", "diagnostics.txt")
    assert has_element?(view, "#support-composer-attachments-status button", "Remove")
  end

  test "renders inbound email in a sandboxed original-email preview", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    thread =
      support_thread!(
        body: """
        I am following up on this request.

        On Tue, Aug 25, 2026 at 4:20 PM Tuist Support <contact@tuist.dev> wrote:

        > How are you?
        >
        > --
        > Pedro Piñera

        --
        Pedro Piñera
        """
      )

    {:ok, view, _html} = live(conn, ~p"/support/#{thread.id}")

    message = thread.id |> Support.get_thread() |> then(&List.first(&1.messages))

    assert has_element?(
             view,
             "#support-message-original-#{message.id}[sandbox='allow-same-origin'][phx-hook='OriginalEmailPreview'][phx-update='ignore'][src='/support/messages/#{message.id}/original']"
           )
  end

  defp support_thread!(opts \\ []) do
    suffix = System.unique_integer([:positive])
    body = Keyword.get(opts, :body, "Please help with the dashboard.")
    subject = Keyword.get(opts, :subject, "Dashboard support request")

    raw_email = """
    Message-ID: <support-live-#{suffix}@example.com>
    From: Support customer <support-live-#{suffix}@example.com>
    To: contact@tuist.dev
    Subject: #{subject}

    #{body}
    """

    {:ok, inbox_email} =
      Inbox.persist_inbound(raw_email,
        envelope: %{"from" => "support-live-#{suffix}@example.com", "to" => "contact@tuist.dev"}
      )

    {:ok, %{thread: thread}} = Support.ingest_inbound(EmailParser.parse(raw_email), inbox_email.id)
    thread
  end
end
