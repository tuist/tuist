defmodule AtlasWeb.GTMLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.GTM
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.SocialChannelIdea
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.Repo
  alias Atlas.Users.User

  defp insert_user!(email) do
    %User{}
    |> User.changeset(%{email: email, name: "Atlas User"})
    |> Repo.insert!()
  end

  test "renders the content list with the GTM sidebar entry", %{conn: conn} do
    user = insert_user!("gtm-list@example.com")
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Caching deep dive", "description" => "How caching works."})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/content")

    assert has_element?(view, "#gtm-content")
    assert has_element?(view, "#gtm-content [data-part='header'] [data-part='title']", "Content")
    assert has_element?(view, "#new-idea-modal")
    assert has_element?(view, "#new-idea-modal [data-part='trigger']", "New idea")
    assert has_element?(view, "#sidebar-gtm")
    assert has_element?(view, ~s(#sidebar-gtm a[href="/gtm/content"]), "Content")
    assert has_element?(view, ~s(#sidebar-gtm a[href="/gtm/social"]), "Social")
    assert has_element?(view, ~s(#sidebar-gtm a[href="/gtm/outreach"]), "Outreach")
    assert has_element?(view, ~s(#sidebar-gtm a[href="/gtm/content"] [data-selected]))
    assert has_element?(view, "#gtm-ideas-table", "Caching deep dive")
    assert has_element?(view, ~s(#gtm-ideas-table a[href="/gtm/content/#{idea.id}"]), "Caching deep dive")
  end

  test "renders the social idea list", %{conn: conn} do
    user = insert_user!("gtm-social-list@example.com")

    {:ok, idea} =
      GTM.create_social_channel_idea(%{
        "title" => "Share the cache chart",
        "description" => "Short launch angle."
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/social")

    assert has_element?(view, "#gtm-social")
    assert has_element?(view, "#gtm-social [data-part='header'] [data-part='title']", "Social")
    assert has_element?(view, "#new-social-idea-modal")
    assert has_element?(view, "#new-social-idea-modal [data-part='trigger']", "New social idea")
    assert has_element?(view, ~s(#sidebar-gtm a[href="/gtm/social"] [data-selected]))
    assert has_element?(view, "#gtm-social-ideas-table", "Share the cache chart")
    assert has_element?(view, ~s(#gtm-social-ideas-table a[href="/gtm/social/#{idea.id}"]), "Share the cache chart")
    assert has_element?(view, "#social-idea-actions-#{idea.id}")
  end

  test "captures a new social idea from the modal and shows it in the list", %{conn: conn} do
    user = insert_user!("gtm-social-create@example.com")
    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/social")

    render_submit(view, "create_social_idea", %{
      "social_channel_idea" => %{
        "title" => "Turn launch note into a short post",
        "description" => "Use the registry announcement."
      }
    })

    assert has_element?(view, "#gtm-social-ideas-table", "Turn launch note into a short post")

    idea = Repo.get_by!(SocialChannelIdea, title: "Turn launch note into a short post")
    assert idea.author_id == user.id
    assert idea.description == "Use the registry announcement."

    {:ok, detail, _html} = live(conn, ~p"/gtm/social/#{idea.id}")
    assert has_element?(detail, "#gtm-social-idea [data-part='idea-title']", "Turn launch note into a short post")
    assert has_element?(detail, "#edit-social-idea-modal [data-part='trigger']", "Edit idea")
    assert has_element?(detail, "#gtm-social-idea [data-part='social-idea-details-card']")
    assert has_element?(detail, "#gtm-social-idea [data-part='social-metadata-row']", "Status")
    refute has_element?(detail, "#gtm-social-idea [data-part='conversation-side']")
    assert has_element?(detail, "#gtm-social-idea [data-part='post-revisions-card']")
    assert has_element?(detail, "#gtm-social-idea form#social-post-revision-form")
  end

  test "updates a social idea description without touching its derived status", %{conn: conn} do
    user = insert_user!("gtm-social-status@example.com")
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Movable social idea"})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/social/#{idea.id}")

    # Status is derived from the idea's post revisions, so even a submitted status is
    # ignored: the description updates but the status stays "idea".
    render_submit(view, "save_social_idea", %{
      "social_channel_idea" => %{
        title: "Movable social idea",
        status: "approved",
        description: "Ready to post."
      }
    })

    updated = GTM.get_social_channel_idea(idea.id)
    assert updated.status == "idea"
    assert updated.description == "Ready to post."
  end

  test "adds and approves a social post revision from the detail page", %{conn: conn} do
    user = insert_user!("gtm-social-revision@example.com")
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Iterate social post"})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/social/#{idea.id}")

    # The composer is inline in the revisions card, so submit the real form.
    view
    |> form("#social-post-revision-form", %{
      "social_post_revision" => %{
        "body" => "Draft post text for the launch.",
        "notes" => "First pass."
      }
    })
    |> render_submit()

    revision = Repo.get_by!(SocialPostRevision, social_channel_idea_id: idea.id)
    assert revision.author_id == user.id
    assert revision.revision_number == 1
    assert revision.body == "Draft post text for the launch."
    assert has_element?(view, "#social-post-revision-#{revision.id}", "Draft post text for the launch.")
    assert has_element?(view, "#social-post-revision-#{revision.id}[data-part='post-revision-card']")
    assert has_element?(view, "#social-post-revision-#{revision.id} [data-part='post-revision-content']")

    render_click(view, "approve_social_post_revision", %{"id" => revision.id})

    assert GTM.get_social_channel_idea(idea.id).status == "approved"
    assert Repo.get!(SocialPostRevision, revision.id).status == "approved"
    assert has_element?(view, "#gtm-social-idea", "Approved")
    assert has_element?(view, "#gtm-social-idea", "Revision 1")
  end

  test "deletes a social idea from the row menu", %{conn: conn} do
    user = insert_user!("gtm-social-delete@example.com")
    {:ok, idea} = GTM.create_social_channel_idea(%{"title" => "Delete from row"})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/social")

    assert has_element?(view, "#social-idea-actions-#{idea.id}")

    render_click(view, "delete_social_idea", %{"id" => idea.id})

    refute GTM.get_social_channel_idea(idea.id)
    refute has_element?(view, "#gtm-social-ideas-table", "Delete from row")
  end

  test "redirects to the social list when the social idea is missing", %{conn: conn} do
    user = insert_user!("gtm-social-missing@example.com")
    conn = init_test_session(conn, %{"user_id" => user.id})

    assert {:error, {:live_redirect, %{to: "/gtm/social"}}} =
             live(conn, ~p"/gtm/social/#{Ecto.UUID.generate()}")
  end

  test "captures a new idea from the modal and shows it in the list", %{conn: conn} do
    user = insert_user!("gtm-create@example.com")
    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/content")

    # The capture form lives inside the modal portal, so submit the event by name
    # rather than selecting the form (Floki cannot reach into the portal template).
    render_submit(view, "create_idea", %{
      "blog_post_idea" => %{"title" => "Why monorepos win", "description" => "The build graph angle."}
    })

    assert has_element?(view, "#gtm-ideas-table", "Why monorepos win")

    idea = Repo.get_by!(BlogPostIdea, title: "Why monorepos win")
    assert idea.author_id == user.id

    {:ok, detail, _html} = live(conn, ~p"/gtm/content/#{idea.id}")
    assert has_element?(detail, "#gtm-idea [data-part='idea-title']", "Why monorepos win")
  end

  test "adds a follow-up comment on the detail page", %{conn: conn} do
    user = insert_user!("gtm-comment@example.com")
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Needs follow-up"})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/content/#{idea.id}")

    refute has_element?(view, "#idea-comments [data-part='comment']")

    view
    |> form("#idea-comment-form", comment: %{body: "Let us add a benchmark section."})
    |> render_submit()

    assert has_element?(view, "#idea-comments", "Let us add a benchmark section.")

    idea = GTM.get_blog_post_idea(idea.id)
    assert [%{author: %{email: "gtm-comment@example.com"}}] = idea.comments
  end

  test "updates an idea status", %{conn: conn} do
    user = insert_user!("gtm-status@example.com")
    {:ok, idea} = GTM.create_blog_post_idea(%{"title" => "Movable idea"})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/gtm/content/#{idea.id}")

    view
    |> form("#idea-details-form",
      blog_post_idea: %{title: "Movable idea", status: "published"}
    )
    |> render_submit()

    assert GTM.get_blog_post_idea(idea.id).status == "published"
  end

  test "redirects to the list when the idea is missing", %{conn: conn} do
    user = insert_user!("gtm-missing@example.com")
    conn = init_test_session(conn, %{"user_id" => user.id})

    assert {:error, {:live_redirect, %{to: "/gtm/content"}}} =
             live(conn, ~p"/gtm/content/#{Ecto.UUID.generate()}")
  end
end
