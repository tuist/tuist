defmodule Atlas.Moodboard.ProjectionTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.MCP.ToolCase, only: [insert_user!: 0]

  alias Atlas.Audit.Activity
  alias Atlas.Moodboard
  alias Atlas.Moodboard.Comment
  alias Atlas.Moodboard.Preview
  alias Atlas.Moodboard.PreviewWorker
  alias Atlas.Moodboard.Resource
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Search.Record
  alias Atlas.Vector

  setup :verify_on_exit!

  test "original text needs no URL, is indexed immediately, and enqueues no preview" do
    user = insert_user!()

    assert {:ok, resource} =
             Moodboard.create_resource(
               %{title: "A thought", content: "Clarity over decoration", description: "Our next review"},
               user
             )

    assert resource.url == nil
    assert resource.kind == "text"
    assert resource.preview_status == "ready"
    assert Repo.get_by!(Record, source_type: "moodboard_resource", source_id: resource.id).body =~ "Clarity"
    refute Repo.exists?(from j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker")
    assert {:error, changeset} = Moodboard.create_resource(%{title: "Empty", content: " "}, user)
    assert errors_on(changeset).content

    assert {:error, changeset} =
             Moodboard.create_resource(%{title: "Huge", content: String.duplicate("a", 20_001)}, user)

    assert errors_on(changeset).content
  end

  test "previews run outside saving and retain personal notes and manual image overrides" do
    user = insert_user!()

    {:ok, resource} =
      Moodboard.create_resource(
        attrs(%{description: "My reason", image_url: "https://images.example/manual.png"}),
        user
      )

    job = Repo.one!(from j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker")
    assert Map.keys(job.args) |> Enum.sort() == ["resource_id", "revision"]

    expect(Preview, :fetch, fn url ->
      assert url == resource.url
      refute Repo.in_transaction?()

      {:ok, edited} =
        Moodboard.update_resource(resource.id, %{image_url: "https://images.example/new-override.png"}, user)

      assert edited.preview_revision == resource.preview_revision

      {:ok,
       %{
         kind: "video",
         source_text: "Readable article",
         source_description: "Fetched summary",
         preview_image_url: "https://images.example/auto.png",
         preview_video_url: "https://videos.example/demo.mp4"
       }}
    end)

    assert :ok = PreviewWorker.perform(job)
    assert :ok = PreviewWorker.perform(job)
    updated = Moodboard.get_resource(user, resource.id)
    assert updated.description == "My reason"
    assert updated.image_url == "https://images.example/new-override.png"
    assert updated.source_text == "Readable article"
    assert updated.preview_status == "ready"
    assert updated.preview_fetched_at
    assert Repo.get_by!(Record, source_id: resource.id).body =~ "Readable article"
    assert Repo.aggregate(from(r in Record, where: r.source_id == ^resource.id), :count) == 1
  end

  test "edits reload under the resource lock so a just-finished preview stays in the search projection" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    {:ok, comment} = Moodboard.add_comment(resource.id, %{body: "A discussion"}, user)
    stale = Repo.get!(Resource, resource.id)

    expect(Repo, :get, fn Resource, id ->
      assert id == resource.id

      assert {:ok, :ok} =
               Moodboard.apply_preview(
                 id,
                 resource.preview_revision,
                 {:ok, %{source_text: "Newly fetched source", kind: "article"}}
               )

      stale
    end)

    assert {:ok, updated} = Moodboard.update_resource(resource.id, %{title: "New title"}, user)
    assert updated.preview_status == "ready"
    assert updated.source_text == "Newly fetched source"
    assert Repo.get_by!(Record, source_id: resource.id).body =~ "Newly fetched source"
    assert Repo.get_by!(Record, source_id: comment.id).title == "New title"
  end

  test "changed URLs and deleted resources fence stale results, and failures do not fail saves" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    {:ok, changed} = Moodboard.update_resource(resource.id, %{url: "https://design.example/changed"}, user)
    assert changed.preview_revision != resource.preview_revision
    assert {:ok, :ok} = Moodboard.apply_preview(resource.id, resource.preview_revision, {:ok, %{source_text: "Stale"}})
    assert Moodboard.get_resource(user, resource.id).source_text == nil
    assert {:ok, :ok} = Moodboard.apply_preview(resource.id, changed.preview_revision, {:error, :unavailable})
    assert Moodboard.get_resource(user, resource.id).preview_status == "unavailable"
    assert {:ok, refreshed} = Moodboard.refresh_preview(resource.id, user)
    assert refreshed.preview_status == "pending"
    {:ok, _} = Moodboard.delete_resource(resource.id, user)
    assert {:ok, :ok} = Moodboard.apply_preview(resource.id, refreshed.preview_revision, {:ok, %{source_text: "Late"}})

    assert :ok =
             PreviewWorker.perform(%Oban.Job{
               args: %{"resource_id" => resource.id, "revision" => refreshed.preview_revision}
             })

    refute Repo.get_by(Record, source_id: resource.id)
  end

  test "resource, audit, preview job and search projection roll back and retry as one committed effect" do
    user = insert_user!()
    attrs = attrs()

    assert {:error, :abort} =
             Repo.transaction(fn ->
               {:ok, resource} = Moodboard.create_resource(attrs, user)
               assert Repo.get_by(Record, source_id: resource.id)
               Repo.rollback(:abort)
             end)

    refute Repo.get_by(Resource, url: attrs.url)

    refute Repo.exists?(
             from j in Oban.Job, where: j.worker in ["Atlas.Moodboard.PreviewWorker", "Atlas.Search.VectorWorker"]
           )

    refute Repo.exists?(from a in Activity, where: a.action == "moodboard_resource.created")
    assert {:ok, resource} = Moodboard.create_resource(attrs, user)
    assert Repo.aggregate(from(r in Record, where: r.source_id == ^resource.id), :count) == 1
    assert Repo.aggregate(from(j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker"), :count) == 1
  end

  test "comments are shared, author-owned, bounded and individually searchable" do
    user = insert_user!()
    teammate = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)

    assert {:ok, comment} =
             Moodboard.add_comment(resource.id, %{body: "  Choreography through progressive disclosure  "}, teammate)

    assert comment.body == "Choreography through progressive disclosure"
    assert comment.author_id == teammate.id
    assert {[listed], false} = Moodboard.list_comments(user, resource.id)
    assert listed.id == comment.id
    stub(Vector, :configured?, fn -> false end)
    assert {[found], false} = Moodboard.search_resources(user, "Choreography")
    assert found.id == resource.id
    assert {:error, :forbidden} = Moodboard.delete_comment(comment.id, user)
    assert {:error, :authentication_required} = Moodboard.add_comment(resource.id, %{body: "x"}, nil)
    assert {:error, :authentication_required} = Moodboard.delete_comment(comment.id, nil)
    assert {:error, changeset} = Moodboard.add_comment(resource.id, %{body: String.duplicate("x", 4001)}, user)
    assert errors_on(changeset).body
    assert {:ok, _} = Moodboard.delete_comment(comment.id, teammate)
    refute Repo.get_by(Record, source_type: "moodboard_comment", source_id: comment.id)
    assert {[], false} = Moodboard.list_comments(user, resource.id)
  end

  test "comment rollback and resource deletion remove projections and preserve no orphan discussions" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)

    assert {:error, :abort} =
             Repo.transaction(fn ->
               {:ok, comment} = Moodboard.add_comment(resource.id, %{body: "Rolled back"}, user)
               assert Repo.get_by(Record, source_id: comment.id)
               Repo.rollback(:abort)
             end)

    assert {[], false} = Moodboard.list_comments(user, resource.id)
    {:ok, comment} = Moodboard.add_comment(resource.id, %{body: "Committed once"}, user)
    assert Repo.aggregate(from(r in Record, where: r.source_id == ^comment.id), :count) == 1
    {:ok, _} = Moodboard.delete_resource(resource.id, user)
    refute Repo.get(Comment, comment.id)
    refute Repo.get_by(Record, source_id: comment.id)
    refute Repo.get_by(Record, source_id: resource.id)
  end

  test "semantic resource and comment hits hydrate to one authoritative resource" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(%{tags: ["motion"]}), user)
    {:ok, comment} = Moodboard.add_comment(resource.id, %{body: "Timing"}, user)
    record = Repo.get_by!(Record, source_id: comment.id)
    stub(Vector, :configured?, fn -> true end)

    stub(Vector, :search, fn _embedding, _opts ->
      {:ok, %{"results" => [%{"vector" => %{"id" => "search_record:#{record.id}"}, "score" => 0.95}]}}
    end)

    assert {[found], false} = Moodboard.search_resources(user, "fluid choreography", tag: "motion")
    assert found.id == resource.id
    assert {[], false} = Moodboard.search_resources(user, "fluid choreography", tag: "other")
    {:ok, record} = Search.index_moodboard_resource(resource, embed?: false)
    assert record.source_type == "moodboard_resource"
  end

  test "user deletion clears comment attribution without losing shared conversation" do
    user = insert_user!()
    teammate = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), teammate)
    {:ok, comment} = Moodboard.add_comment(resource.id, %{body: "Keep this thought"}, user)
    Repo.delete!(user)
    assert {[listed], false} = Moodboard.list_comments(teammate, resource.id)
    assert listed.id == comment.id
    assert listed.author_id == nil
    assert listed.author == nil
  end

  test "preview persistence cleans controls and rejects invalid media without leaving pending status" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    job = Repo.one!(from j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker")
    expect(Preview, :fetch, fn _ -> {:ok, %{source_text: "a\0b", source_title: "C\0D", kind: "article"}} end)
    assert :ok = PreviewWorker.perform(job)
    assert %{preview_status: "ready", source_text: "ab", source_title: "CD"} = Moodboard.get_resource(user, resource.id)
    {:ok, refreshed} = Moodboard.refresh_preview(resource.id, user)

    assert {:ok, :ok} =
             Moodboard.apply_preview(
               resource.id,
               refreshed.preview_revision,
               {:ok, %{preview_image_url: "https://127.0.0.1/secret"}}
             )

    assert Moodboard.get_resource(user, resource.id).preview_status == "unavailable"
  end

  test "retryable preview persistence failures become unavailable on the last attempt" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    job = Repo.one!(from j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker")
    stub(Preview, :fetch, fn _ -> {:ok, %{source_text: "Safe article", kind: "article"}} end)
    stub(Repo, :update, &Mimic.call_original(Repo, :update, [&1]))
    expect(Repo, :update, fn _ -> raise Postgrex.Error, message: "remote private failure" end)
    assert {:error, :preview_persistence_failed} = PreviewWorker.perform(%{job | attempt: 1})
    assert Moodboard.get_resource(user, resource.id).preview_status == "pending"
    expect(Repo, :update, fn _ -> raise Postgrex.Error, message: "remote private failure" end)
    assert :ok = PreviewWorker.perform(%{job | attempt: job.max_attempts})
    assert Moodboard.get_resource(user, resource.id).preview_status == "unavailable"
  end

  test "pending refresh requests are debounced and previews use a separate bounded queue" do
    user = insert_user!()
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    assert {:ok, refreshed} = Moodboard.refresh_preview(resource.id, user)
    assert refreshed.preview_revision == resource.preview_revision
    assert Repo.aggregate(from(j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker"), :count) == 1
    job = Repo.one!(from j in Oban.Job, where: j.worker == "Atlas.Moodboard.PreviewWorker")
    assert job.queue == "moodboard"
    assert Repo.get_by!(Activity, target_id: resource.id).metadata["path"] == "/library/moodboard/#{resource.id}"
  end

  test "user text containing NUL is rejected before reaching PostgreSQL" do
    user = insert_user!()

    for field <- [:title, :description, :content] do
      assert {:error, changeset} = Moodboard.create_resource(Map.put(attrs(), field, "a\0b"), user)
      assert errors_on(changeset)[field]
    end

    assert {:error, changeset} = Moodboard.create_resource(attrs(%{tags: ["a\0b"]}), user)
    assert errors_on(changeset).tags
    {:ok, resource} = Moodboard.create_resource(attrs(), user)
    assert {:error, changeset} = Moodboard.add_comment(resource.id, %{body: "a\0b"}, user)
    assert errors_on(changeset).body
  end

  defp attrs(overrides \\ %{}),
    do: Map.merge(%{title: "Reference", url: "https://design.example/#{System.unique_integer([:positive])}"}, overrides)
end
