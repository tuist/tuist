defmodule Atlas.Orbit.AttachmentsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.OrbitFixtures

  alias Atlas.Authorization.Roles
  alias Atlas.Documents.Storage
  alias Atlas.Orbit
  alias Atlas.Orbit.Attachment
  alias Atlas.Orbit.Attachments
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Workers.CleanupAttachments
  alias Atlas.Repo
  alias Atlas.TestSupport.Documents.Storage, as: TestStorage

  setup do
    owner = user_fixture(["accounts:read"])
    member = user_fixture(["accounts:read"])
    {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Files", "participant_ids" => [member.id]})
    %{owner: owner, member: member, thread: thread}
  end

  test "stages sanitized metadata and private bytes outside the document library", %{owner: owner, thread: thread} do
    attachment = attachment_fixture(owner, thread, "Secret bytes", %{"filename" => "../../x\\report\u202e\r\n.txt"})
    assert attachment.filename == "report.txt"
    assert attachment.status == "pending" and is_nil(attachment.message_id)
    assert attachment.user_id == owner.id and attachment.thread_id == thread.id
    assert attachment.storage_key == "orbit/threads/#{thread.id}/attachments/#{attachment.id}"
    assert_in_delta DateTime.diff(attachment.expires_at, DateTime.utc_now()), 86_400, 10
    assert {:ok, %{body: "Secret bytes"}} = Storage.get_object(attachment.storage_key)

    assert Attachments.metadata(attachment) == %{
             id: attachment.id,
             filename: "report.txt",
             content_type: "text/plain",
             byte_size: 12
           }

    assert Repo.aggregate("documents", :count) == 0
  end

  test "enforces the decoded and encoded 5MiB limits and validates metadata", %{owner: owner, thread: thread} do
    bytes = :binary.copy("x", Attachments.max_bytes())
    assert {:ok, attachment} = Attachments.upload(owner, thread, attachment_params(bytes))
    assert attachment.byte_size == 5_242_880

    invalid = [
      attachment_params(bytes <> "x"),
      attachment_params("", %{}),
      attachment_params("x", %{"data" => "not base64!"}),
      attachment_params("x", %{"filename" => "../"}),
      attachment_params("x", %{"filename" => []}),
      attachment_params("x", %{"content_type" => "text/plain\r\nInjected: x"}),
      attachment_params("x", %{"content_type" => "invalid"}),
      attachment_params("x", %{"client_id" => "bad"}),
      attachment_params("x") |> Map.delete("client_id"),
      %{}
    ]

    for params <- invalid do
      assert {:error, {:invalid_field, :attachment}} = Attachments.upload(owner, thread, params)
    end

    assert Repo.aggregate(Attachment, :count) == 1
  end

  test "a lost upload response retries the immutable uploader/thread identity without rewriting storage", context do
    %{owner: owner, member: member, thread: thread} = context
    params = attachment_params("Original bytes")
    assert {:ok, original} = Attachments.upload(owner, thread, params)

    for changed <- [
          Map.put(params, "data", Base.encode64("Different bytes")),
          Map.put(params, "filename", "different.txt"),
          Map.put(params, "content_type", "application/json")
        ] do
      assert {:error, {:invalid_field, :client_id}} = Attachments.upload(owner, thread, changed)
    end

    {:ok, other} = Orbit.create_shared(owner, %{"title" => "Other"})
    assert {:ok, foreign} = Attachments.upload(member, thread, params)
    assert {:ok, cross_thread} = Attachments.upload(owner, other, params)
    assert length(Enum.uniq([original.id, foreign.id, cross_thread.id])) == 3
    stub(Storage, :put_object, fn _, _, _ -> flunk("completed upload was written twice") end)
    assert {:ok, replay} = Attachments.upload(owner, thread, params)
    assert replay.id == original.id
    assert {:ok, _, :created} = post(owner, thread, [original.id])
    assert {:ok, attached_replay} = Attachments.upload(owner, thread, params)
    assert attached_replay.id == original.id and attached_replay.status == "attached"
    assert Repo.aggregate(Attachment, :count) == 3
    assert {:ok, _, "Original bytes"} = Attachments.read(owner, thread.id, original.id)
  end

  test "storage success followed by a lost transaction response resumes the same reservation", context do
    %{owner: owner, thread: thread} = context
    params = attachment_params("Durable object bytes")

    stub(Storage, :put_object, fn key, bytes, opts ->
      assert {:ok, _} = TestStorage.put_object(key, bytes, opts)
      raise "simulated worker loss before pending commit"
    end)

    assert_raise RuntimeError, "simulated worker loss before pending commit", fn ->
      Attachments.upload(owner, thread, params)
    end

    [reservation] = Repo.all(Attachment)
    assert reservation.status == "uploading"
    assert {:ok, %{body: "Durable object bytes"}} = TestStorage.get_object(reservation.storage_key)
    stub(Storage, :put_object, &TestStorage.put_object/3)
    assert {:ok, recovered} = Attachments.upload(owner, thread, params)
    assert recovered.id == reservation.id and recovered.status == "pending"
    assert Repo.aggregate(Attachment, :count) == 1
  end

  @tag :tmp_dir
  test "overlapping matching uploads converge on one attachment", %{owner: owner, thread: thread, tmp_dir: tmp_dir} do
    params = attachment_params()
    path = Path.join(tmp_dir, "object")

    stub(Storage, :put_object, fn _key, bytes, _opts ->
      File.write!(path, bytes)
      {:ok, %{}}
    end)

    tasks = for _ <- 1..4, do: Task.async(fn -> Attachments.upload(owner, thread, params) end)
    ids = for task <- tasks, {:ok, attachment} = Task.await(task), do: attachment.id
    assert length(Enum.uniq(ids)) == 1
    assert Repo.aggregate(Attachment, :count) == 1
    assert File.read!(path) == Base.decode64!(params["data"])
  end

  test "a storage read that outlives membership/scope revocation or pending deletion returns no bytes", context do
    %{owner: owner, member: member} = context

    for boundary <- [:membership, :scopes, :discard] do
      {:ok, thread} = Orbit.create_shared(owner, %{"title" => "Read fence", "participant_ids" => [member.id]})
      attachment = attachment_fixture(member, thread)

      stub(Storage, :get_object, fn key ->
        result = TestStorage.get_object(key)

        case boundary do
          :membership -> Orbit.remove_participant(owner, thread, member.id)
          :scopes -> Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read"]))
          :discard -> Attachments.discard(member, thread, attachment.id)
        end

        result
      end)

      assert {:error, :not_found} = Attachments.read(member, thread.id, attachment.id)
    end
  end

  test "pending bytes are uploader-only; claiming shares them with the authorized audience", context do
    %{owner: owner, member: member, thread: thread} = context
    attachment = attachment_fixture(member, thread)
    assert {:error, :not_found} = Attachments.read(owner, thread.id, attachment.id)
    assert {:ok, _, "Private attachment contents"} = Attachments.read(member, thread.id, attachment.id)
    assert {:error, :not_found} = Attachments.discard(owner, thread, attachment.id)

    assert {:ok, message, :created} = post(member, thread, [attachment.id])
    assert message.body == "" and Enum.map(message.attachments, & &1.id) == [attachment.id]
    assert Repo.reload!(attachment).message_id == message.id
    assert {:ok, _, "Private attachment contents"} = Attachments.read(owner, thread.id, attachment.id)
    assert {:error, :not_found} = Attachments.discard(member, thread, attachment.id)
    assert {:error, {:invalid_field, :attachment_ids}} = post(member, thread, [attachment.id])
    assert Repo.aggregate(Message, :count) == 1
  end

  test "replay returns the original attachments without claiming or validating replacement sources", context do
    %{owner: owner, member: member, thread: thread} = context
    first = attachment_fixture(owner, thread)
    second = attachment_fixture(owner, thread)
    foreign = attachment_fixture(member, thread)
    client_id = Ecto.UUID.generate()
    assert {:ok, original, :created} = post(owner, thread, [second.id, first.id], client_id)
    fresh = attachment_fixture(owner, thread)
    assert {:ok, replay, :existing} = post(owner, thread, [foreign.id, fresh.id], client_id)
    assert replay.id == original.id
    assert Enum.map(replay.attachments, & &1.id) == [second.id, first.id]
    assert Repo.reload!(fresh).status == "pending"
    assert Repo.reload!(foreign).status == "pending"
    assert Repo.aggregate(Message, :count) == 1
  end

  test "a mixed invalid claim rolls back the message, sequence, and every attachment", context do
    %{owner: owner, member: member, thread: thread} = context
    good = attachment_fixture(owner, thread)
    foreign = attachment_fixture(member, thread)
    {:ok, other} = Orbit.create_shared(owner, %{"title" => "Other"})
    cross_thread = attachment_fixture(owner, other)
    expired = attachment_fixture(owner, thread)
    Repo.update!(Ecto.Changeset.change(expired, expires_at: DateTime.add(DateTime.utc_now(), -1)))

    for invalid <- [foreign.id, cross_thread.id, expired.id, Ecto.UUID.generate()] do
      assert {:error, {:invalid_field, :attachment_ids}} = post(owner, thread, [good.id, invalid])
      assert Repo.reload!(good).status == "pending"
      assert Repo.reload!(thread).last_seq == 0
      assert Repo.aggregate(Message, :count) == 0
    end

    assert {:error, :not_found} = Attachments.read(owner, other.id, good.id)
    assert {:error, :not_found} = Attachments.discard(owner, other, good.id)
    assert {:error, :not_found} = Attachments.read(owner, thread.id, expired.id)
  end

  test "rejects duplicate, malformed, non-list and more than four attachment IDs", %{owner: owner, thread: thread} do
    attachment = attachment_fixture(owner, thread)
    invalid = [[attachment.id, attachment.id], ["bad"], nil, "bad", List.duplicate(Ecto.UUID.generate(), 5)]

    for ids <- invalid do
      assert {:error, {:invalid_field, :attachment_ids}} = post(owner, thread, ids)
    end

    assert {:error, {:invalid_field, :body}} = post(owner, thread, [])
    assert Repo.aggregate(Message, :count) == 0
  end

  test "accepts all four files atomically and preserves caller ordering", %{owner: owner, thread: thread} do
    ids = for _ <- 1..4, do: attachment_fixture(owner, thread).id
    assert {:ok, message, :created} = post(owner, thread, Enum.reverse(ids))
    assert Enum.map(message.attachments, & &1.id) == Enum.reverse(ids)
    assert Repo.aggregate(from(a in Attachment, where: a.status == "attached"), :count) == 4
    {[history], _} = Orbit.list_messages(thread)
    assert Enum.map(history.attachments, & &1.id) == Enum.reverse(ids)
  end

  test "authorization is refreshed for upload, claim, download, and pending deletion", context do
    %{owner: owner, member: member, thread: thread} = context
    attachment = attachment_fixture(member, thread)
    :ok = Orbit.remove_participant(owner, thread, member.id)
    assert {:error, :not_found} = Attachments.upload(member, thread, attachment_params())
    assert {:error, :not_found} = post(member, thread, [attachment.id])
    assert {:error, :not_found} = Attachments.read(member, thread.id, attachment.id)
    assert {:error, :not_found} = Attachments.discard(member, thread, attachment.id)

    owned = attachment_fixture(owner, thread)
    thread = Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["accounts:read"]))
    {:ok, _} = Roles.update_role(Roles.get_role_by_slug("test-#{owner.id}"), %{scopes: []})
    assert {:error, :not_found} = Attachments.upload(owner, thread, attachment_params())
    assert {:error, :not_found} = post(owner, thread, [owned.id])
    assert {:error, :not_found} = Attachments.read(owner, thread.id, owned.id)
    assert {:error, :not_found} = Attachments.discard(owner, thread, owned.id)
  end

  test "archived threads reject uploads and claims but retain authorized history downloads", context do
    %{owner: owner, thread: thread} = context
    attachment = attachment_fixture(owner, thread)
    assert {:ok, _, :created} = post(owner, thread, [attachment.id])
    Repo.update!(Ecto.Changeset.change(thread, status: "archived"))
    assert {:error, :archived} = Attachments.upload(owner, thread, attachment_params())
    assert {:error, :archived} = post(owner, thread, [attachment.id])
    assert {:ok, _, _} = Attachments.read(owner, thread.id, attachment.id)
  end

  test "pending DELETE queues durable cleanup and storage errors preserve its ledger", %{owner: owner, thread: thread} do
    attachment = attachment_fixture(owner, thread)
    assert :ok = Attachments.discard(owner, thread, attachment.id)
    assert Repo.reload!(attachment).status == "deleting"
    assert {:error, :not_found} = Attachments.read(owner, thread.id, attachment.id)
    assert_enqueued(worker: CleanupAttachments)

    stub(Storage, :delete_object, fn _key -> {:error, :unavailable} end)
    assert {:error, :storage_unavailable} = perform_job(CleanupAttachments, %{})
    assert Repo.get!(Attachment, attachment.id).status == "deleting"
    assert {:ok, _} = TestStorage.get_object(attachment.storage_key)
    stub(Storage, :delete_object, &TestStorage.delete_object/1)
    assert :ok = perform_job(CleanupAttachments, %{})
    assert Repo.get(Attachment, attachment.id) == nil
    assert {:error, :not_found} = TestStorage.get_object(attachment.storage_key)
    assert :ok = perform_job(CleanupAttachments, %{})
  end

  test "failed or interrupted writes leave reclaimable rows, never document-library entries", context do
    %{owner: owner, thread: thread} = context

    stub(Storage, :put_object, fn key, bytes, opts ->
      TestStorage.put_object(key, bytes, opts)
      {:error, :transport_disconnected_after_write}
    end)

    assert {:error, :storage_unavailable} = Attachments.upload(owner, thread, attachment_params())
    [attachment] = Repo.all(Attachment)
    assert attachment.status == "deleting"
    assert_enqueued(worker: CleanupAttachments)
    assert :ok = perform_job(CleanupAttachments, %{})
    assert {:error, :not_found} = Storage.get_object(attachment.storage_key)
    assert Repo.aggregate(Attachment, :count) == 0
  end

  test "sweeps expired pending/uploading rows but never an attached message's live object", context do
    %{owner: owner, thread: thread} = context
    pending = attachment_fixture(owner, thread)
    uploading = attachment_fixture(owner, thread)
    attached = attachment_fixture(owner, thread)
    assert {:ok, _, :created} = post(owner, thread, [attached.id])
    expired = DateTime.add(DateTime.utc_now(), -86_401)
    Repo.update_all(Attachment, set: [expires_at: expired])
    Repo.update!(Ecto.Changeset.change(Repo.reload!(uploading), status: "uploading"))
    assert :ok = perform_job(CleanupAttachments, %{})
    assert [%Attachment{id: id}] = Repo.all(Attachment)
    assert id == attached.id
    assert {:ok, _} = Storage.get_object(attached.storage_key)
    assert {:error, :not_found} = Storage.get_object(pending.storage_key)
    assert {:error, :not_found} = Storage.get_object(uploading.storage_key)
  end

  test "thread/message deletion preserves a cleanup ledger instead of leaking objects", %{owner: owner, thread: thread} do
    attachment = attachment_fixture(owner, thread)
    assert {:ok, message, :created} = post(owner, thread, [attachment.id])
    Repo.delete!(message)
    assert Repo.reload!(attachment).message_id == nil
    assert :ok = perform_job(CleanupAttachments, %{})
    assert {:error, :not_found} = Storage.get_object(attachment.storage_key)

    orphan = attachment_fixture(owner, thread)
    Repo.delete!(thread)
    assert Repo.reload!(orphan).thread_id == nil
    assert :ok = perform_job(CleanupAttachments, %{})
    assert Repo.aggregate(Attachment, :count) == 0
    assert {:error, :not_found} = Storage.get_object(orphan.storage_key)
  end

  defp post(user, thread, ids, client_id \\ Ecto.UUID.generate()) do
    Orbit.post_message(user, thread, %{
      "client_id" => client_id,
      "attachment_ids" => ids,
      "address_agent" => false
    })
  end
end
