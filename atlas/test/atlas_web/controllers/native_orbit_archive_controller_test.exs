defmodule AtlasWeb.NativeOrbitArchiveControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.OrbitFixtures
  import Ecto.Query

  alias Atlas.Authorization.UserRole
  alias Atlas.Orbit
  alias Atlas.Orbit.Attachments
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Thread
  alias Atlas.Push.Workers.Deliver
  alias Atlas.Repo

  test "only readable private/shared owners archive and restore; history and files remain protected" do
    owner = user_fixture(["finance:read"])
    member = user_fixture(["finance:read"])
    outsider = user_fixture(Atlas.Authorization.executive_scopes())
    {:ok, private, _} = Orbit.ensure_private(owner)
    {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Team", "participant_ids" => [member.id]})

    for thread <- [private, shared] do
      path = "/api/native/orbit/threads/#{thread.id}"
      attachment = attachment_fixture(owner, thread, "Preserved bytes")

      params = %{
        body: "Kept history",
        client_id: Ecto.UUID.generate(),
        attachment_ids: [attachment.id],
        address_agent: false
      }

      message = owner |> bearer() |> post(path <> "/messages", params) |> json_response(201)
      before = owner |> bearer() |> get(path <> "/messages") |> json_response(200)

      expected = if thread.kind == "shared", do: 403, else: 404
      assert member |> bearer() |> patch(path, %{status: "archived"}) |> json_response(expected)

      assert outsider |> bearer() |> patch(path, %{status: "archived"}) |> json_response(404) == %{
               "error" => "not_found"
             }

      archived = owner |> bearer() |> patch(path, %{status: "archived", owner_id: outsider.id}) |> json_response(200)
      assert archived["thread"]["status"] == "archived"
      assert archived["thread"]["owner_id"] == owner.id
      assert archived["thread"]["latest_seq"] > before["latest_seq"]
      assert owner |> bearer() |> patch(path, %{status: "archived"}) |> json_response(200) == archived

      history = owner |> bearer() |> get(path <> "/messages") |> json_response(200)
      assert history["messages"] == before["messages"]
      assert message["message"]["body"] == "Kept history"

      assert owner
             |> bearer()
             |> get(path <> "/attachments/#{attachment.id}")
             |> json_response(200)
             |> get_in(["attachment", "data"]) == Base.encode64("Preserved bytes")

      assert owner
             |> bearer()
             |> post(path <> "/messages", %{params | client_id: Ecto.UUID.generate()})
             |> json_response(409) == %{"error" => "archived"}

      assert {:error, :archived} = Attachments.upload(owner, thread, attachment_params())

      if thread.kind == "shared" do
        assert member |> bearer() |> get(path <> "/messages") |> json_response(200)
        assert member |> bearer() |> patch(path, %{status: "active"}) |> json_response(403)
      end

      restored = owner |> bearer() |> patch(path, %{status: "active"}) |> json_response(200)
      assert restored["thread"]["status"] == "active"
      assert restored["thread"]["latest_seq"] > archived["thread"]["latest_seq"]

      assert owner |> bearer() |> get(path <> "/messages") |> json_response(200) |> Map.fetch!("messages") ==
               before["messages"]
    end
  end

  test "status filter is validated, defaults active, and sorts all kinds before pagination" do
    owner = user_fixture()
    {:ok, private, _} = Orbit.ensure_private(owner)
    {:ok, shared} = Orbit.create_shared(owner, %{"title" => "Newer shared"})
    {:ok, archived} = Orbit.create_shared(owner, %{"title" => "Archive"})
    {:ok, _} = Orbit.set_status(owner, archived, "archived")
    Repo.update!(Ecto.Changeset.change(private, updated_at: ~U[2026-01-01 00:00:00.000000Z]))
    Repo.update!(Ecto.Changeset.change(shared, updated_at: ~U[2026-01-02 00:00:00.000000Z]))

    active = owner |> bearer() |> get("/api/native/orbit/threads") |> json_response(200)
    assert Enum.map(active["threads"]["items"], & &1["id"]) == [shared.id, private.id]
    assert active["threads"]["total_count"] == 2
    assert active["assistant"]["can_create_private"]
    archive = owner |> bearer() |> get("/api/native/orbit/threads?status=archived") |> json_response(200)
    assert Enum.map(archive["threads"]["items"], & &1["id"]) == [archived.id]

    assert owner
           |> bearer()
           |> get("/api/native/orbit/threads?status=archived&kind=private")
           |> json_response(200)
           |> get_in(["threads", "total_count"]) == 0

    {legacy, %{total_count: 3}} = Orbit.list_for_user(owner)
    assert hd(legacy).id == private.id

    for status <- ["deleted", "", ["active"], %{bad: "active"}] do
      assert owner |> bearer() |> get("/api/native/orbit/threads", %{status: status}) |> json_response(422)

      assert owner
             |> bearer()
             |> patch("/api/native/orbit/threads/#{private.id}", %{status: status})
             |> json_response(422)
    end
  end

  test "native pagination counts and orders only the requested status across kinds" do
    owner = user_fixture()
    {:ok, private, _} = Orbit.ensure_private(owner)
    {:ok, archived} = Orbit.create_shared(owner, %{"title" => "Archived"})
    {:ok, _} = Orbit.set_status(owner, archived, "archived")
    Repo.update!(Ecto.Changeset.change(private, updated_at: ~U[2026-01-01 00:00:00.000000Z]))

    shared =
      for day <- 2..27 do
        {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Day #{day}"})

        Repo.update!(
          Ecto.Changeset.change(thread, updated_at: DateTime.add(~U[2026-01-01 00:00:00.000000Z], day, :day))
        )
      end

    first = owner |> bearer() |> get("/api/native/orbit/threads?page=1") |> json_response(200)
    second = owner |> bearer() |> get("/api/native/orbit/threads?page=2") |> json_response(200)
    assert first["threads"]["total_count"] == 27
    assert first["threads"]["total_pages"] == 2
    ids = Enum.map(first["threads"]["items"] ++ second["threads"]["items"], & &1["id"])
    assert ids == Enum.map(Enum.reverse(shared), & &1.id) ++ [private.id]

    assert owner
           |> bearer()
           |> get("/api/native/orbit/threads?status=archived&page=2")
           |> json_response(200)
           |> get_in(["threads", "total_count"]) == 1
  end

  test "invalid IDs, absent threads, stale membership and ratcheted scope loss retain generic 404" do
    owner = user_fixture(["finance:read"])
    {:ok, thread, _} = Orbit.ensure_private(owner)

    for id <- ["invalid", Ecto.UUID.generate()] do
      assert owner |> bearer() |> patch("/api/native/orbit/threads/#{id}", %{status: "archived"}) |> json_response(404) ==
               %{"error" => "not_found"}
    end

    Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read"]))
    Repo.delete_all(from assignment in UserRole, where: assignment.user_id == ^owner.id)
    assert {:error, :not_found} = Orbit.set_status(owner, thread, "archived")

    assert owner
           |> bearer()
           |> patch("/api/native/orbit/threads/#{thread.id}", %{status: "active"})
           |> json_response(404)

    assert Repo.get!(Thread, thread.id).status == "active"
  end

  for status <- ["queued", "running"] do
    test "archive cancels #{status} work and restore never restarts it or its pending follow-up" do
      owner = user_fixture()
      {:ok, thread, _} = Orbit.ensure_private(owner)

      {:ok, _} =
        Repo.transaction(fn ->
          Orbit.append!(Orbit.lock!(thread.id), %{
            kind: "human",
            body: "First request",
            author_id: owner.id,
            address_agent: true
          })
        end)

      run =
        Repo.insert!(%Run{
          thread_id: thread.id,
          acting_user_id: owner.id,
          initiator_id: owner.id,
          trigger_seq: 1,
          status: unquote(status)
        })

      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 assert {:ok, _} = Orbit.set_status(owner, thread, "archived")
                 Repo.rollback(:rollback)
               end)

      assert Repo.get!(Thread, thread.id).status == "active"
      assert Repo.get!(Run, run.id).status == unquote(status)
      assert is_nil(Repo.get!(Run, run.id).cancel_requested_at)

      {:ok, _} =
        Repo.transaction(fn ->
          Orbit.append!(Orbit.lock!(thread.id), %{
            kind: "human",
            body: "Pending follow-up",
            author_id: owner.id,
            address_agent: true
          })
        end)

      path = "/api/native/orbit/threads/#{thread.id}"
      assert owner |> bearer() |> patch(path, %{status: "archived"}) |> json_response(200)
      assert Repo.get!(Run, run.id).cancel_requested_at
      assert Repo.get!(Run, run.id).status == "cancelled"
      assert owner |> bearer() |> patch(path, %{status: "active"}) |> json_response(200)
      assert :ok = Runs.execute(run.id)
      assert :stale = Runs.complete(run.id, 0, {:ok, "Must not appear"})
      assert Repo.aggregate(Run, :count) == 1
      assert :stale = Runs.complete(run.id, 0, {:ok, "Duplicate callback"})
      {:ok, thread} = Orbit.fetch(owner, thread.id)
      {messages, _} = Orbit.list_messages(thread)
      assert Enum.map(messages, & &1.body) == ["First request", "Pending follow-up"]
      refute_enqueued(worker: Deliver)
    end
  end
end
