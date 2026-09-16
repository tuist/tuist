defmodule AtlasWeb.GTMEmailLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.GTM

  test "renders audiences and subscribers with the email navigation entry", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, audience} = GTM.create_email_audience(%{name: "Digest", description: "Product news"})
    {:ok, subscriber} = GTM.create_email_subscriber(%{email: "reader@example.com", source: "website"})
    {:ok, _membership} = GTM.add_email_audience_subscriber(audience, subscriber)

    {:ok, view, _html} = live(conn, ~p"/email")

    assert has_element?(view, "#email")
    assert has_element?(view, "#email-audiences-table", "Digest")
    assert has_element?(view, "#email-subscribers-table", "reader@example.com")
    assert has_element?(view, ~s(a[href="/email"] [data-selected]))
    refute has_element?(view, ~s(#sidebar-gtm a[href="/email"]))
    assert has_element?(view, "#new-email-subscriber-modal")
    assert has_element?(view, "#new-email-audience-modal")
  end

  test "searches audiences by name", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _matching} = GTM.create_email_audience(%{name: "Product digest", description: "Weekly"})
    {:ok, _other} = GTM.create_email_audience(%{name: "Marketing list", description: "Promotions"})

    {:ok, view, _html} = live(conn, ~p"/email")

    assert has_element?(view, "#email-audiences-table", "Product digest")
    assert has_element?(view, "#email-audiences-table", "Marketing list")

    view
    |> form("#email-audiences-search-form", %{"search" => %{"query" => "Product"}})
    |> render_change()

    assert has_element?(view, "#email-audiences-table", "Product digest")
    refute has_element?(view, "#email-audiences-table", "Marketing list")
  end

  test "filters subscribers by status via URL params", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_subscriber(%{email: "subscribed@example.com", source: "website", status: "subscribed"})
    {:ok, _} = GTM.create_email_subscriber(%{email: "pending@example.com", source: "website", status: "pending"})

    filter_params = %{"filter_subscribers_status_op" => "==", "filter_subscribers_status_val" => "pending"}
    {:ok, view, _html} = live(conn, ~p"/email?#{filter_params}")

    assert has_element?(view, "#email-subscribers-table", "pending@example.com")
    refute has_element?(view, "#email-subscribers-table", "subscribed@example.com")
    assert has_element?(view, "#subscribers_status")
  end

  test "filters subscribers by status through the filter dropdown", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_subscriber(%{email: "subscribed@example.com", source: "website", status: "subscribed"})
    {:ok, _} = GTM.create_email_subscriber(%{email: "pending@example.com", source: "website", status: "pending"})

    {:ok, view, _html} = live(conn, ~p"/email")

    render_click(view, "add_filter", %{"value" => "subscribers_status"})

    render_click(view, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "subscribers_status",
      "value" => "pending"
    })

    assert has_element?(view, "#email-subscribers-table", "pending@example.com")
    refute has_element?(view, "#email-subscribers-table", "subscribed@example.com")
  end

  test "keeps the subscribers search query when a filter is added", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_subscriber(%{email: "pending-reader@example.com", source: "website", status: "pending"})
    {:ok, _} = GTM.create_email_subscriber(%{email: "pending-writer@example.com", source: "website", status: "pending"})

    {:ok, view, _html} = live(conn, ~p"/email")

    view
    |> form("#email-subscribers-search-form", %{"search" => %{"query" => "reader"}})
    |> render_change()

    render_click(view, "add_filter", %{"value" => "subscribers_status"})

    render_click(view, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "subscribers_status",
      "value" => "pending"
    })

    assert has_element?(view, "#email-subscribers-table", "pending-reader@example.com")
    refute has_element?(view, "#email-subscribers-table", "pending-writer@example.com")
  end

  test "filters audiences by source through the filter dropdown", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_audience(%{name: "Loops digest", source_id: "loops"})
    {:ok, _} = GTM.create_email_audience(%{name: "Atlas digest", source_id: "atlas"})

    {:ok, view, _html} = live(conn, ~p"/email")

    render_click(view, "add_filter", %{"value" => "audiences_source"})

    render_click(view, "update_filter", %{
      "type" => "change_value",
      "payload_filter_id" => "audiences_source",
      "value" => "loops"
    })

    assert has_element?(view, "#email-audiences-table", "Loops digest")
    refute has_element?(view, "#email-audiences-table", "Atlas digest")
  end

  test "offers the audience presence filters even when no audience has a source", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_audience(%{name: "Digest"})

    {:ok, view, _html} = live(conn, ~p"/email")

    # The dropdown renders nothing when every filter has been rejected for
    # having no options, which is what happened when Source was the only one.
    # Its items live in a portal template, so match the markup rather than
    # selecting elements.
    html = render(view)
    assert html =~ ~s(data-value="audiences_subscribers")
    assert html =~ ~s(data-value="audiences_broadcasts")
    refute html =~ ~s(data-value="audiences_source")
  end

  test "filters audiences by whether they have subscribers", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, populated} = GTM.create_email_audience(%{name: "Populated digest"})
    {:ok, _empty} = GTM.create_email_audience(%{name: "Empty digest"})
    {:ok, subscriber} = GTM.create_email_subscriber(%{email: "reader@example.com", source: "website"})
    {:ok, _} = GTM.add_email_audience_subscriber(populated, subscriber)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/email?#{%{"filter_audiences_subscribers_op" => "==", "filter_audiences_subscribers_val" => "present"}}"
      )

    assert has_element?(view, "#email-audiences-table", "Populated digest")
    refute has_element?(view, "#email-audiences-table", "Empty digest")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/email?#{%{"filter_audiences_subscribers_op" => "==", "filter_audiences_subscribers_val" => "absent"}}"
      )

    assert has_element?(view, "#email-audiences-table", "Empty digest")
    refute has_element?(view, "#email-audiences-table", "Populated digest")
  end

  test "filters audiences by whether they have broadcasts", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "email-sender@tuist.dev"})
    {:ok, broadcast_audience} = GTM.create_email_audience(%{name: "Broadcast digest"})
    {:ok, _quiet} = GTM.create_email_audience(%{name: "Quiet digest"})
    {:ok, subscriber} = GTM.create_email_subscriber(%{email: "reader@example.com", source: "website"})
    {:ok, _} = GTM.add_email_audience_subscriber(broadcast_audience, subscriber)

    {:ok, _} =
      GTM.queue_email_broadcast(
        broadcast_audience,
        %{
          "subject" => "Product update",
          "body_markdown" => "Hello.",
          "from_name" => "Tuist",
          "from_email" => "pedro@tuist.dev"
        },
        user
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/email?#{%{"filter_audiences_broadcasts_op" => "==", "filter_audiences_broadcasts_val" => "present"}}"
      )

    assert has_element?(view, "#email-audiences-table", "Broadcast digest")
    refute has_element?(view, "#email-audiences-table", "Quiet digest")
  end

  test "applies the is-not operator to option filters", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_subscriber(%{email: "pending@example.com", source: "website", status: "pending"})
    {:ok, _} = GTM.create_email_subscriber(%{email: "subscribed@example.com", source: "website", status: "subscribed"})

    {:ok, view, _html} =
      live(conn, ~p"/email?#{%{"filter_subscribers_status_op" => "!=", "filter_subscribers_status_val" => "pending"}}")

    assert has_element?(view, "#email-subscribers-table", "subscribed@example.com")
    refute has_element?(view, "#email-subscribers-table", "pending@example.com")
  end

  test "scopes each section's source filter to its own table", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, _} = GTM.create_email_audience(%{name: "Loops digest", source_id: "loops"})
    {:ok, _} = GTM.create_email_audience(%{name: "Atlas digest", source_id: "atlas"})
    {:ok, _} = GTM.create_email_subscriber(%{email: "from-website@example.com", source: "website"})
    {:ok, _} = GTM.create_email_subscriber(%{email: "from-loops@example.com", source: "loops"})

    filter_params = %{
      "filter_audiences_source_op" => "==",
      "filter_audiences_source_val" => "loops",
      "filter_subscribers_source_op" => "==",
      "filter_subscribers_source_val" => "website"
    }

    {:ok, view, _html} = live(conn, ~p"/email?#{filter_params}")

    assert has_element?(view, "#email-audiences-table", "Loops digest")
    refute has_element?(view, "#email-audiences-table", "Atlas digest")
    assert has_element?(view, "#email-subscribers-table", "from-website@example.com")
    refute has_element?(view, "#email-subscribers-table", "from-loops@example.com")
  end

  test "paginates subscribers and resets to page 1 when a filter is added", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    for i <- 1..30 do
      {:ok, _} = GTM.create_email_subscriber(%{email: "reader-#{i}@example.com", source: "website"})
    end

    {:ok, _audience} = GTM.create_email_audience(%{name: "Digest"})

    {:ok, view, _html} = live(conn, ~p"/email?subscribers-page=2")

    # 30 subscribers is two pages, one audience is not, and a pagination
    # control for a single page is noise.
    assert has_element?(view, "#email-subscribers-pagination")
    refute has_element?(view, "#email-audiences-pagination")
  end

  test "creates a subscriber from the modal form", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "email-editor@tuist.dev"})
    {:ok, view, _html} = live(conn, ~p"/email")

    render_submit(view, "create_subscriber", %{
      "subscriber" => %{
        "email" => "new-reader@example.com",
        "first_name" => "New",
        "last_name" => "Reader",
        "source" => "dashboard",
        "user_group" => "developer"
      }
    })

    assert has_element?(view, "#email-subscribers-table", "new-reader@example.com")
    assert GTM.get_email_subscriber_by_email("new-reader@example.com")
  end

  test "creates a dynamic customer audience from the modal form", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "email-editor@tuist.dev"})
    {:ok, view, _html} = live(conn, ~p"/email")
    name = "Enterprise accounts #{System.unique_integer([:positive])}"

    render_submit(view, "create_audience", %{
      "audience" => %{
        "name" => name,
        "membership_type" => "dynamic",
        "rules" => %{
          "account_segment" => "customer",
          "hosting" => "self_hosted",
          "recipient_source" => "incident_contacts"
        }
      }
    })

    audience = GTM.get_email_audience_by_slug("enterprise-accounts-#{String.split(name, " ") |> List.last()}")
    assert audience.rules["recipient_source"] == "incident_contacts"
    assert_redirect(view, ~p"/email/audiences/#{audience.id}")

    {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

    assert has_element?(view, "#email-audience-widget-members", "Dynamic")
    assert has_element?(view, "#email-audience-members-table", "No matching contacts")
    refute has_element?(view, "#add-audience-member-modal")
  end

  test "deletes an unused manual audience from its detail page", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, audience} = GTM.create_email_audience(%{name: "Disposable #{System.unique_integer([:positive])}"})
    {:ok, index_view, _html} = live(conn, ~p"/email")

    refute has_element?(index_view, "#delete-email-audience-#{audience.id}")

    {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

    assert has_element?(view, "#email-delete-audience-card")
    assert has_element?(view, "#delete-email-audience-#{audience.id}")

    render_click(view, "delete_audience", %{"id" => audience.id})

    refute GTM.get_email_audience(audience.id)
  end

  test "adds a member and queues a broadcast from the audience page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "email-sender@tuist.dev"})
    {:ok, audience} = GTM.create_email_audience(%{name: "Digest"})
    {:ok, subscriber} = GTM.create_email_subscriber(%{email: "recipient@example.com", source: "dashboard"})

    {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

    render_submit(view, "add_subscriber", %{"membership" => %{"subscriber_id" => subscriber.id}})

    assert has_element?(view, "#email-audience-members-table", "recipient@example.com")

    render_submit(view, "queue_broadcast", %{
      "broadcast" => %{
        "subject" => "Product update",
        "body_markdown" => "Hello from Atlas.",
        "from_name" => "Tuist",
        "from_email" => "pedro@tuist.dev",
        "reply_to_email" => "pedro@tuist.dev"
      }
    })

    assert has_element?(view, "#email-broadcasts-table", "Product update")
    assert has_element?(view, "#email-broadcasts-table", "Pending")
  end

  describe "audience page" do
    setup %{conn: conn} do
      {conn, user} = log_in_user(conn, %{email: "email-sender@tuist.dev"})
      {:ok, audience} = GTM.create_email_audience(%{name: "Digest", slug: "digest"})
      %{conn: conn, user: user, audience: audience}
    end

    defp add_member(audience, email, status) do
      {:ok, subscriber} = GTM.create_email_subscriber(%{email: email, source: "website"})
      {:ok, _membership} = GTM.add_email_audience_subscriber(audience, subscriber)

      if status == "unsubscribed" do
        {:ok, _membership} = GTM.unsubscribe_email_audience_subscriber(audience, subscriber)
      end

      subscriber
    end

    test "shows the counts as widgets", %{conn: conn, audience: audience} do
      add_member(audience, "one@example.com", "subscribed")
      add_member(audience, "two@example.com", "unsubscribed")

      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

      assert has_element?(view, "#email-audience-widget-subscribed", "1")
      assert has_element?(view, "#email-audience-widget-members", "2")
      assert has_element?(view, "#email-audience-widget-broadcasts", "0")
    end

    test "renders the empty states inside the tables", %{conn: conn, audience: audience} do
      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

      # The empty state belongs to the table's slot; rendered beside the table
      # it lands outside the styled container and reads as unstyled text.
      assert has_element?(view, "#email-audience-members-table", "No members yet")
      assert has_element?(view, "#email-broadcasts-table", "No broadcasts yet")
    end

    test "paginates the members", %{conn: conn, audience: audience} do
      for index <- 1..30, do: add_member(audience, "member-#{index}@example.com", "subscribed")

      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")
      assert has_element?(view, "#email-members-pagination")
      assert has_element?(view, "#email-audience-members-table", "member-1@example.com")

      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}?members-page=2")
      refute has_element?(view, "#email-audience-members-table", "member-1@example.com")
    end

    test "loads add-member choices only when the modal opens", %{conn: conn, audience: audience} do
      {:ok, subscriber} =
        GTM.create_email_subscriber(%{email: "candidate@example.com", source: "website"})

      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

      refute subscriber.id in audience_member_option_values(view)

      render_hook(view, "add-audience-member-modal-open-changed", %{"open" => true})

      assert subscriber.id in audience_member_option_values(view)
    end

    test "searches the members", %{conn: conn, audience: audience} do
      add_member(audience, "keeper@example.com", "subscribed")
      add_member(audience, "other@example.com", "subscribed")

      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

      view
      |> form("#email-members-search-form", %{"search" => %{"query" => "keeper"}})
      |> render_change()

      assert has_element?(view, "#email-audience-members-table", "keeper@example.com")
      refute has_element?(view, "#email-audience-members-table", "other@example.com")
    end

    test "filters the members by membership status", %{conn: conn, audience: audience} do
      add_member(audience, "still-in@example.com", "subscribed")
      add_member(audience, "left@example.com", "unsubscribed")

      {:ok, view, _html} = live(conn, ~p"/email/audiences/#{audience.id}")

      render_click(view, "add_filter", %{"value" => "members_status"})

      render_click(view, "update_filter", %{
        "type" => "change_value",
        "payload_filter_id" => "members_status",
        "value" => "unsubscribed"
      })

      assert has_element?(view, "#email-audience-members-table", "left@example.com")
      refute has_element?(view, "#email-audience-members-table", "still-in@example.com")
    end
  end

  defp audience_member_option_values(view) do
    view
    |> element("#add-audience-member-modal-portal")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> tree_attribute_values("option", "value")
  end

  defp tree_attribute_values(nodes, tag, attribute) do
    Enum.flat_map(nodes, fn
      {^tag, attrs, children} ->
        [
          attrs |> List.keyfind(attribute, 0, {attribute, nil}) |> elem(1)
          | tree_attribute_values(children, tag, attribute)
        ]

      {_other_tag, _attrs, children} ->
        tree_attribute_values(children, tag, attribute)

      _text ->
        []
    end)
  end
end
