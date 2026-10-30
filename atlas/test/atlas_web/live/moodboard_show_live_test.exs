defmodule AtlasWeb.MoodboardShowLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.MCP.ToolCase
  alias Atlas.Moodboard

  test "requires authentication and handles a missing resource", %{conn: conn} do
    id = Ecto.UUID.generate()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/library/moodboard/#{id}")
    {conn, _user} = log_in_user(conn)
    assert {:error, {:live_redirect, %{to: "/library/moodboard"}}} = live(conn, "/library/moodboard/#{id}")
  end

  test "separates personal notes, original text and extracted source content", %{conn: conn} do
    {conn, user} = log_in_user(conn)

    {:ok, resource} =
      Moodboard.create_resource(
        %{title: "An essay", url: unique_url(), description: "My personal reason", content: "A quote I picked"},
        user
      )

    {:ok, :ok} =
      Moodboard.apply_preview(
        resource.id,
        resource.preview_revision,
        {:ok,
         %{
           kind: "article",
           source_description: "Publisher summary",
           source_text: "<script>untrusted()</script> Article body"
         }}
      )

    {:ok, view, _html} = live(conn, "/library/moodboard/#{resource.id}")
    assert has_element?(view, "#moodboard-contributor-note", "My personal reason")
    assert has_element?(view, "#moodboard-original-text", "A quote I picked")
    assert has_element?(view, "#moodboard-source-summary", "Publisher summary")
    assert has_element?(view, "#moodboard-source-text", "Article body")
    refute has_element?(view, "#moodboard-source-text script")
    assert has_element?(view, "a#moodboard-open-source[target='_blank'][rel='noopener noreferrer']")
  end

  test "text-only resources have a readable detail page without an external source link", %{conn: conn} do
    {conn, user} = log_in_user(conn)

    {:ok, resource} =
      Moodboard.create_resource(%{title: "A principle", content: "Make the important thing obvious"}, user)

    {:ok, view, _html} = live(conn, "/library/moodboard/#{resource.id}")
    assert has_element?(view, "#moodboard-original-text", "Make the important thing obvious")
    refute has_element?(view, "#moodboard-open-source")
  end

  test "plays discovered videos without autoplay or iframe embedding, and respects image overrides", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, resource} = Moodboard.create_resource(%{title: "Motion study", url: unique_url()}, user)

    {:ok, :ok} =
      Moodboard.apply_preview(
        resource.id,
        resource.preview_revision,
        {:ok,
         %{
           preview_video_url: "https://video.example/clip.mp4",
           preview_image_url: "https://image.example/poster.jpg",
           kind: "video"
         }}
      )

    {:ok, view, _html} = live(conn, "/library/moodboard/#{resource.id}")
    assert has_element?(view, "video[controls][preload='none'][poster='https://image.example/poster.jpg']")
    refute has_element?(view, "video[autoplay]")
    refute has_element?(view, "iframe")
    {:ok, _} = Moodboard.update_resource(resource.id, %{image_url: "https://image.example/manual.png"}, user)
    send(view.pid, :refresh)
    refute has_element?(view, "video")
    assert has_element?(view, "img[src='https://image.example/manual.png']")
  end

  test "teammates can comment, only authors can remove comments, and content stays escaped", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    teammate = ToolCase.insert_user!()
    {:ok, resource} = Moodboard.create_resource(%{title: "Reference", url: unique_url()}, teammate)
    {:ok, theirs} = Moodboard.add_comment(resource.id, %{body: "I like this"}, teammate)
    {:ok, view, _html} = live(conn, "/library/moodboard/#{resource.id}")
    refute has_element?(view, "#delete-comment-#{theirs.id}")
    view |> form("#moodboard-comment-form", comment: %{body: "<script>Mine</script>"}) |> render_submit()
    {comments, false} = Moodboard.list_comments(user, resource.id)
    mine = Enum.find(comments, &(&1.author_id == user.id))
    assert has_element?(view, "#comment-#{mine.id}", "<script>Mine</script>")
    refute has_element?(view, "#comment-#{mine.id} script")
    render_hook(view, "delete_comment", %{"id" => theirs.id})
    assert has_element?(view, "#comment-#{theirs.id}")
    view |> element("#delete-comment-#{mine.id}") |> render_click()
    refute has_element?(view, "#comment-#{mine.id}")
  end

  test "discussion pages remain bounded and reconcile comments from other sessions", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, resource} = Moodboard.create_resource(%{title: "Reference", url: unique_url()}, user)
    {:ok, view, _html} = live(conn, "/library/moodboard/#{resource.id}")
    assert has_element?(view, "#moodboard-no-comments")
    for index <- 1..31, do: Moodboard.add_comment(resource.id, %{body: "Comment #{index}"}, user)
    send(view.pid, :refresh)
    refute has_element?(view, "#moodboard-no-comments")
    assert has_element?(view, "#moodboard-comment-pagination a", "Next")

    assert render(view) |> LazyHTML.from_document() |> LazyHTML.query("#moodboard-comments article") |> Enum.count() ==
             30

    view |> element("#moodboard-comment-pagination a", "Next") |> render_click()
    assert has_element?(view, "#moodboard-comment-pagination button[disabled]", "Next")
    assert has_element?(view, "#moodboard-comment-pagination a", "Prev")

    assert render(view) |> LazyHTML.from_document() |> LazyHTML.query("#moodboard-comments article") |> Enum.count() ==
             1

    view |> element("#moodboard-comment-pagination a", "Prev") |> render_click()
    assert has_element?(view, "#moodboard-comment-pagination a", "Next")
  end

  test "unavailable previews can be retried only by the contributor", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, resource} = Moodboard.create_resource(%{title: "Reference", url: unique_url()}, user)
    {:ok, :ok} = Moodboard.apply_preview(resource.id, resource.preview_revision, {:error, :unavailable})
    {:ok, view, _html} = live(conn, "/library/moodboard/#{resource.id}")
    assert has_element?(view, "#moodboard-refresh-preview")
    view |> element("#moodboard-refresh-preview") |> render_click()
    assert render(view) =~ "Finding a preview"
    assert Moodboard.get_resource(user, resource.id).preview_revision != resource.preview_revision
  end

  test "new comments jump to the last page and render Noora authors and timestamps", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, resource} = Moodboard.create_resource(%{title: "Reference", content: "A thought"}, user)
    for index <- 1..31, do: Moodboard.add_comment(resource.id, %{body: "Earlier #{index}"}, user)
    {:ok, view, _} = live(conn, ~p"/library/moodboard/#{resource.id}")
    view |> form("#moodboard-comment-form", comment: %{body: "My latest thought"}) |> render_submit()
    assert_patch(view, "/library/moodboard/#{resource.id}?comments_offset=30")
    assert has_element?(view, "#moodboard-comments article", "My latest thought")
    assert has_element?(view, "#moodboard-comments [data-scope='avatar']")
    assert has_element?(view, "#moodboard-comments time[datetime]")
    assert has_element?(view, "#moodboard-breadcrumb-list")
    assert has_element?(view, "[data-part='detail-side']", "Properties")
  end

  test "owners can edit on the detail page and deletion waits for the dialog to close", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, resource} = Moodboard.create_resource(%{title: "My reference", content: "Original", tags: ["type"]}, user)
    {:ok, view, _} = live(conn, ~p"/library/moodboard/#{resource.id}")
    view |> element("#moodboard-edit-resource") |> render_click()
    render_hook(view, "resource_modal_changed", %{"open" => true})

    render_hook(view, "save", %{
      "resource" => %{"title" => "Revised", "content" => "Still original", "tags" => "type, motion"}
    })

    assert has_element?(view, "h1", "Revised")
    assert Moodboard.get_resource(user, resource.id).tags == ["type", "motion"]
    render_hook(view, "delete", %{})
    assert_push_event(view, "close-modal", %{id: "moodboard-resource-modal"})
    assert Moodboard.get_resource(user, resource.id) == nil
    render_hook(view, "resource_modal_changed", %{"open" => false})
    assert_redirect(view, ~p"/library/moodboard")
  end

  test "other contributors cannot edit or remove a resource from detail events", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    teammate = ToolCase.insert_user!()
    {:ok, resource} = Moodboard.create_resource(%{title: "Theirs", content: "Original"}, teammate)
    {:ok, view, _} = live(conn, ~p"/library/moodboard/#{resource.id}")
    refute has_element?(view, "#moodboard-edit-resource")
    refute has_element?(view, "#moodboard-remove-resource")
    render_hook(view, "save", %{"resource" => %{"title" => "Stolen", "tags" => ""}})
    render_hook(view, "delete", %{})
    assert Moodboard.get_resource(user, resource.id).title == "Theirs"
  end

  test "posterless clips remain playable on their detail page", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, resource} = Moodboard.create_resource(%{title: "Clip", url: unique_url()}, user)

    {:ok, :ok} =
      Moodboard.apply_preview(
        resource.id,
        resource.preview_revision,
        {:ok, %{kind: "video", preview_video_url: "https://video.example/clip.mp4"}}
      )

    {:ok, view, _} = live(conn, ~p"/library/moodboard/#{resource.id}")
    assert has_element?(view, "video[controls][preload='none'][phx-mounted*='ignore_attrs']")
  end

  defp unique_url, do: "https://design.example/#{System.unique_integer([:positive])}"
end
