defmodule AtlasWeb.MoodboardLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.MCP.ToolCase
  alias Atlas.Moodboard

  test "requires sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/library/moodboard")
  end

  test "renders an empty board and can add a resource through the modal", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/library/moodboard")
    assert has_element?(view, "#moodboard-empty")
    assert has_element?(view, "a[href='/library/moodboard']", "Moodboard")

    view |> element("#moodboard-add") |> render_click()

    render_hook(view, "save", %{
      "resource" => %{
        "title" => "Type foundry",
        "url" => unique_url(),
        "description" => "A lovely specimen page",
        "tags" => "type, inspiration"
      }
    })

    assert {[resource], false} = Moodboard.list_resources(user)
    assert resource.tags == ["type", "inspiration"]
    assert has_element?(view, "#resource-#{resource.id} h2", "Type foundry")
    assert has_element?(view, "#resource-#{resource.id} a[target='_blank'][rel='noopener noreferrer']")
    refute has_element?(view, "#moodboard-empty")
  end

  test "renders image previews, escaped descriptions, and owner edit controls", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    other = ToolCase.insert_user!()

    {:ok, owned} =
      Moodboard.create_resource(
        %{
          title: "Mine",
          url: unique_url(),
          image_url: "https://images.example/a.png",
          description: "<script>alert(1)</script>"
        },
        user
      )

    {:ok, theirs} = Moodboard.create_resource(%{title: "Theirs", url: unique_url()}, other)
    {:ok, view, _html} = live(conn, ~p"/library/moodboard")

    assert has_element?(view, "#resource-media-#{owned.id}-image[loading='lazy'][referrerpolicy='no-referrer']")
    refute has_element?(view, "#resource-#{owned.id} script")
    assert has_element?(view, "#edit-resource-#{owned.id}")
    refute has_element?(view, "#edit-resource-#{theirs.id}")
    refute has_element?(view, "#resource-#{theirs.id} img")

    view |> element("#edit-resource-#{owned.id}") |> render_click()
    render_hook(view, "save", %{"resource" => %{"title" => "Updated", "url" => owned.url, "tags" => "type"}})
    assert has_element?(view, "#resource-#{owned.id} h2", "Updated")

    render_hook(view, "delete", %{})
    refute has_element?(view, "#resource-#{owned.id}")
    assert Moodboard.get_resource(user, owned.id) == nil
  end

  test "search and tag filters are reflected in the URL", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, matching} = Moodboard.create_resource(%{title: "Typography", url: unique_url(), tags: ["type"]}, user)
    {:ok, other} = Moodboard.create_resource(%{title: "Icons", url: unique_url(), tags: ["icons"]}, user)
    {:ok, view, _html} = live(conn, ~p"/library/moodboard?tag=type")

    assert has_element?(view, "#resource-#{matching.id}")
    refute has_element?(view, "#resource-#{other.id}")
    assert has_element?(view, "#moodboard-clear-tag")

    view |> element("#moodboard-clear-tag button") |> render_click()
    assert has_element?(view, "#resource-#{other.id}")

    view |> form("#moodboard-search", search: %{query: "Icons"}) |> render_change()
    assert has_element?(view, "#resource-#{other.id}")
    refute has_element?(view, "#resource-#{matching.id}")
  end

  test "refreshes contributions made outside the open page", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/library/moodboard")
    assert has_element?(view, "#moodboard-empty")
    {:ok, resource} = Moodboard.create_resource(%{title: "From MCP", url: unique_url()}, user)
    send(view.pid, :refresh_resources)
    assert has_element?(view, "#resource-#{resource.id}")
    refute has_element?(view, "#moodboard-empty")
  end

  test "invalid links keep the modal form errors and do not persist", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/library/moodboard")
    view |> element("#moodboard-add") |> render_click()
    render_hook(view, "save", %{"resource" => %{"title" => "Unsafe", "url" => "javascript:alert(1)", "tags" => ""}})
    assert {[], false} = Moodboard.list_resources(user)

    document =
      view
      |> render()
      |> String.replace("<template", "<div")
      |> String.replace("</template>", "</div>")
      |> LazyHTML.from_fragment()

    assert Enum.any?(LazyHTML.query(document, "#moodboard-resource-form [data-error='must be a public HTTPS URL']"))
  end

  test "crafted edit events cannot change someone else's contribution", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    other = ToolCase.insert_user!()
    {:ok, resource} = Moodboard.create_resource(%{title: "Theirs", url: unique_url()}, other)
    {:ok, view, _html} = live(conn, ~p"/library/moodboard")
    render_hook(view, "edit", %{"id" => resource.id})
    render_hook(view, "delete", %{})
    assert Moodboard.get_resource(user, resource.id).title == "Theirs"
  end

  test "shared pagination traverses a full board and retains filters", %{conn: conn} do
    {conn, user} = log_in_user(conn)

    for index <- 1..25 do
      {:ok, _} = Moodboard.create_resource(%{title: "Reference #{index}", url: unique_url(), tags: ["motion"]}, user)
    end

    {:ok, view, _} = live(conn, ~p"/library/moodboard?tag=motion")
    assert render(view) |> LazyHTML.from_document() |> LazyHTML.query("#moodboard-grid article") |> Enum.count() == 24
    assert has_element?(view, "#moodboard-pagination button[disabled]", "Prev")
    view |> element("#moodboard-pagination a", "Next") |> render_click()
    assert_patch(view, "/library/moodboard?offset=24&tag=motion")
    assert render(view) |> LazyHTML.from_document() |> LazyHTML.query("#moodboard-grid article") |> Enum.count() == 1
    assert has_element?(view, "#moodboard-pagination button[disabled]", "Next")
    view |> element("#moodboard-pagination a", "Prev") |> render_click()
    assert render(view) |> LazyHTML.from_document() |> LazyHTML.query("#moodboard-grid article") |> Enum.count() == 24
    assert {:ok, _, _} = live(conn, ~p"/library/moodboard?offset=24")
  end

  test "literal domain and tag searches work without embeddings and idle search does not re-embed", %{conn: conn} do
    {conn, user} = log_in_user(conn)

    {:ok, resource} =
      Moodboard.create_resource(
        %{title: "A reference", url: "https://radix-ui.com/primitives", tags: ["typography"]},
        user
      )

    Mimic.stub(Atlas.Vector, :configured?, fn -> false end)
    {:ok, view, _} = live(conn, ~p"/library/moodboard?search=radix-ui.com")
    assert has_element?(view, "#resource-#{resource.id}")
    view |> form("#moodboard-search", search: %{query: "typo"}) |> render_change()
    assert has_element?(view, "#resource-#{resource.id}")
    assert has_element?(view, "#moodboard-clear-search", "typo")
    Mimic.stub(Atlas.Vector, :configured?, fn -> flunk("idle search refreshed embeddings") end)
    send(view.pid, :refresh_resources)
    assert has_element?(view, "#resource-#{resource.id}")
    view |> element("#moodboard-clear-search button") |> render_click()
    refute has_element?(view, "#moodboard-clear-search")
  end

  test "posterless videos keep a readable grid fallback and broken media retain hidden state", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, video} = Moodboard.create_resource(%{title: "A clip", url: unique_url()}, user)

    {:ok, :ok} =
      Moodboard.apply_preview(
        video.id,
        video.preview_revision,
        {:ok, %{kind: "video", preview_video_url: "https://video.example/clip.mp4"}}
      )

    {:ok, image} =
      Moodboard.create_resource(
        %{title: "A picture", url: unique_url(), image_url: "https://image.example/picture.png"},
        user
      )

    {:ok, view, _} = live(conn, ~p"/library/moodboard")
    refute has_element?(view, "#resource-#{video.id} video")
    assert has_element?(view, "#resource-#{video.id} [data-part='preview-fallback']", "design.example")
    assert has_element?(view, "#resource-#{image.id} img[phx-mounted*='ignore_attrs'][phx-mounted*='hidden']")
    assert has_element?(view, "button#moodboard-add[data-part='trigger']")
    refute has_element?(view, "[aria-hidden='true'][data-part='trigger']")
  end

  defp unique_url, do: "https://design.example/#{System.unique_integer([:positive])}"
end
