defmodule AtlasWeb.EmailMailboxLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.MailboxFixtures
  import Phoenix.LiveViewTest

  describe "inbox" do
    test "lists received emails linked to their support conversation", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      thread = insert_support_thread!(%{customer_email: "ada@example.com", subject: "Cache misses on CI"})
      insert_inbound_message!(thread)

      {:ok, view, _html} = live(conn, ~p"/outbound/email/inbox")

      assert has_element?(view, "#email-inbox-tab[data-selected]")
      assert has_element?(view, "#email-inbox-table", "Cache misses on CI")
      assert has_element?(view, "#email-inbox-table", "ada@example.com")
      assert has_element?(view, ~s(#email-inbox-table a[href="/commercial/support/#{thread.id}"]))
    end

    test "searches by sender", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      insert_inbound_message!(insert_support_thread!(%{customer_email: "ada@example.com", subject: "Registry"}))
      insert_inbound_message!(insert_support_thread!(%{customer_email: "grace@example.com", subject: "Previews"}))

      {:ok, view, _html} = live(conn, ~p"/outbound/email/inbox")

      view
      |> form("#email-inbox-search-form", %{"search" => %{"query" => "grace"}})
      |> render_change()

      assert has_element?(view, "#email-inbox-table", "Previews")
      refute has_element?(view, "#email-inbox-table", "Registry")
    end
  end

  describe "outbox" do
    test "lists deliveries and support replies", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      insert_delivery!(%{recipient_email: "billing@acme.example", subject: "Your Tuist pricing is changing"})
      insert_support_reply!(insert_support_thread!(%{subject: "Cache misses on CI"}))

      {:ok, view, _html} = live(conn, ~p"/outbound/email/outbox")

      assert has_element?(view, "#email-outbox-tab[data-selected]")
      assert has_element?(view, "#email-outbox-table", "Your Tuist pricing is changing")
      assert has_element?(view, "#email-outbox-table", "billing@acme.example")
      assert has_element?(view, "#email-outbox-table", "Re: Cache misses on CI")
    end

    test "filters by kind via URL params", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      insert_delivery!(%{subject: "Your Tuist pricing is changing"})
      insert_support_reply!(insert_support_thread!(%{subject: "Cache misses on CI"}))

      filter_params = %{"filter_kind_op" => "==", "filter_kind_val" => "support_reply"}
      {:ok, view, _html} = live(conn, ~p"/outbound/email/outbox?#{filter_params}")

      assert has_element?(view, "#email-outbox-table", "Re: Cache misses on CI")
      refute has_element?(view, "#email-outbox-table", "Your Tuist pricing is changing")
    end

    test "searches by recipient", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      insert_delivery!(%{recipient_email: "billing@acme.example", subject: "Acme notice"})
      insert_delivery!(%{recipient_email: "billing@globex.example", subject: "Globex notice"})

      {:ok, view, _html} = live(conn, ~p"/outbound/email/outbox")

      view
      |> form("#email-outbox-search-form", %{"search" => %{"query" => "globex"}})
      |> render_change()

      assert has_element?(view, "#email-outbox-table", "Globex notice")
      refute has_element?(view, "#email-outbox-table", "Acme notice")
    end
  end

  describe "sent email" do
    test "shows the recipient, status, and body of a direct email", %{conn: conn} do
      {conn, _user} = log_in_user(conn)

      delivery =
        insert_delivery!(%{
          recipient_email: "billing@acme.example",
          subject: "Your Tuist pricing is changing",
          metadata: %{"body_markdown" => "Your price changes on **22 October**."}
        })

      {:ok, view, _html} = live(conn, ~p"/outbound/email/outbox/#{delivery.id}")

      assert has_element?(view, "h1", "Your Tuist pricing is changing")
      assert has_element?(view, "[data-part='email-details-card']", "billing@acme.example")
      assert has_element?(view, "#sent-email-status", "Sent")
      assert has_element?(view, "#sent-email-body strong", "22 October")
    end

    test "shows the delivery error of a failed email", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      delivery = insert_delivery!(%{status: "failed", delivered_at: nil, error: "{:mailgun, 400}"})

      {:ok, view, _html} = live(conn, ~p"/outbound/email/outbox/#{delivery.id}")

      assert has_element?(view, "#sent-email-status", "Failed")
      assert has_element?(view, "#sent-email-error", "{:mailgun, 400}")
    end

    test "links a support reply to its conversation", %{conn: conn} do
      {conn, _user} = log_in_user(conn)
      thread = insert_support_thread!()
      reply = insert_support_reply!(thread)

      {:ok, view, _html} = live(conn, ~p"/outbound/email/outbox/#{reply.id}")

      assert has_element?(view, ~s(#sent-email-conversation-button[href="/commercial/support/#{thread.id}"]))
    end

    test "redirects to the outbox for an unknown email", %{conn: conn} do
      {conn, _user} = log_in_user(conn)

      assert {:error, {:live_redirect, %{to: "/outbound/email/outbox"}}} =
               live(conn, ~p"/outbound/email/outbox/#{Ecto.UUID.generate()}")
    end
  end

  test "the audiences page links to the inbox and outbox", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    {:ok, view, _html} = live(conn, ~p"/outbound/email")

    assert has_element?(view, "#email-audiences-tab[data-selected]")
    assert has_element?(view, ~s(#email-inbox-tab[href="/outbound/email/inbox"]))
    assert has_element?(view, ~s(#email-outbox-tab[href="/outbound/email/outbox"]))
  end
end
