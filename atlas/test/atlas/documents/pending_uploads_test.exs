defmodule Atlas.Documents.PendingUploadsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.Documents.Workers.ExpirePendingUploads
  alias Atlas.Documents.Workers.ProcessDocument
  alias Atlas.Repo
  alias Atlas.Users.User

  describe "create_pending_upload/2" do
    test "reserves a pending row and returns a bound presigned URL" do
      user = insert_user!()

      assert {:ok, %{document: document, upload_url: url, upload_expires_at: expires_at, required_headers: headers}} =
               Documents.create_pending_upload(%{
                 "original_filename" => "report.pdf",
                 "content_type" => "application/pdf",
                 "uploaded_by_id" => user.id
               })

      assert document.status == "pending_upload"
      assert document.original_filename == "report.pdf"
      assert document.content_type == "application/pdf"
      assert document.byte_size == nil
      assert document.checksum_sha256 == nil
      assert document.storage_key =~ "documents/pending/"
      assert String.ends_with?(document.storage_key, ".pdf")
      assert headers == %{"Content-Type" => "application/pdf"}
      assert is_binary(url) and url != ""
      assert DateTime.diff(expires_at, DateTime.utc_now(), :second) > 60
    end

    test "rejects a missing filename or content type" do
      assert {:error, :original_filename_required} =
               Documents.create_pending_upload(%{"content_type" => "application/pdf"})

      assert {:error, :content_type_required} =
               Documents.create_pending_upload(%{"original_filename" => "x.pdf"})
    end
  end

  describe "finalize_pending_upload/1" do
    test "promotes the row and enqueues ProcessDocument once the bytes have landed" do
      user = insert_user!()

      {:ok, %{document: document}} =
        Documents.create_pending_upload(%{
          "original_filename" => "handbook.pdf",
          "content_type" => "application/pdf",
          "uploaded_by_id" => user.id
        })

      # Simulate the client PUTting the bytes to the presigned URL.
      {:ok, _object} = Storage.put_object(document.storage_key, "hello world")

      assert {:ok, %Document{} = finalized} = Documents.finalize_pending_upload(document.id)
      assert finalized.status == "uploaded"
      assert finalized.byte_size == byte_size("hello world")
      assert finalized.checksum_sha256 == :crypto.hash(:sha256, "hello world") |> Base.encode16(case: :lower)
      assert finalized.upload_expires_at == nil

      assert_enqueued(worker: ProcessDocument, args: %{"document_id" => finalized.id})
    end

    test "refuses to finalize when the bytes are not in storage yet" do
      user = insert_user!()

      {:ok, %{document: document}} =
        Documents.create_pending_upload(%{
          "original_filename" => "handbook.pdf",
          "content_type" => "application/pdf",
          "uploaded_by_id" => user.id
        })

      assert {:error, :not_found} = Documents.finalize_pending_upload(document.id)

      assert Repo.get!(Document, document.id).status == "pending_upload"
      refute_enqueued(worker: ProcessDocument)
    end

    test "rejects and discards an upload larger than the document cap" do
      user = insert_user!()

      {:ok, %{document: document}} =
        Documents.create_pending_upload(%{
          "original_filename" => "huge.pdf",
          "content_type" => "application/pdf",
          "uploaded_by_id" => user.id
        })

      too_big = :binary.copy("x", 51 * 1024 * 1024)
      {:ok, _object} = Storage.put_object(document.storage_key, too_big)

      assert {:error, {:upload_too_large, size, max}} = Documents.finalize_pending_upload(document.id)
      assert size == byte_size(too_big)
      assert max == 50 * 1024 * 1024

      # The object is discarded so it does not linger in storage.
      assert {:error, _reason} = Storage.get_object(document.storage_key)
      # The row stays in pending_upload so the sweeper cleans it up later.
      assert Repo.get!(Document, document.id).status == "pending_upload"
      refute_enqueued(worker: ProcessDocument)
    end

    test "only one of two concurrent finalize calls claims the row and enqueues" do
      user = insert_user!()

      {:ok, %{document: document}} =
        Documents.create_pending_upload(%{
          "original_filename" => "shared.pdf",
          "content_type" => "application/pdf",
          "uploaded_by_id" => user.id
        })

      {:ok, _object} = Storage.put_object(document.storage_key, "bytes")

      # Use two Tasks against the shared DB sandbox to race the atomic
      # transition. Whichever loses must see :already_finalized rather than
      # silently double-enqueueing ProcessDocument.
      parent = self()
      Ecto.Adapters.SQL.Sandbox.allow(Atlas.Repo, parent, self())

      task1 =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Atlas.Repo, parent, self())
          Documents.finalize_pending_upload(document.id)
        end)

      task2 =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Atlas.Repo, parent, self())
          Documents.finalize_pending_upload(document.id)
        end)

      results = [Task.await(task1), Task.await(task2)]

      assert Enum.count(results, &match?({:ok, %Document{}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :already_finalized}, &1)) == 1

      assert [_only_one] = all_enqueued(worker: ProcessDocument)
    end

    test "returns a distinct error when the row was already finalized" do
      user = insert_user!()

      {:ok, %{document: document}} =
        Documents.create_pending_upload(%{
          "original_filename" => "handbook.pdf",
          "content_type" => "application/pdf",
          "uploaded_by_id" => user.id
        })

      {:ok, _object} = Storage.put_object(document.storage_key, "hi")
      {:ok, _finalized} = Documents.finalize_pending_upload(document.id)

      assert {:error, {:unexpected_status, "uploaded"}} = Documents.finalize_pending_upload(document.id)
    end
  end

  describe "delete_expired_pending_uploads/1" do
    test "sweeps rows past their expiry and best-effort deletes their objects" do
      user = insert_user!()

      {:ok, %{document: stale}} =
        Documents.create_pending_upload(
          %{
            "original_filename" => "stale.pdf",
            "content_type" => "application/pdf",
            "uploaded_by_id" => user.id
          },
          expires_in: 60
        )

      # Simulate the client uploading the bytes but never calling finalize.
      {:ok, _object} = Storage.put_object(stale.storage_key, "some bytes")

      {:ok, %{document: fresh}} =
        Documents.create_pending_upload(%{
          "original_filename" => "fresh.pdf",
          "content_type" => "application/pdf",
          "uploaded_by_id" => user.id
        })

      # Age the stale row past its expiry.
      Document
      |> where([document], document.id == ^stale.id)
      |> select([document], document)
      |> Repo.update_all(
        set: [upload_expires_at: DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)]
      )

      assert Documents.delete_expired_pending_uploads() == 1

      refute Repo.get(Document, stale.id)
      assert Repo.get(Document, fresh.id)
      assert {:error, _reason} = Storage.get_object(stale.storage_key)
    end
  end

  describe "ExpirePendingUploads worker" do
    test "delegates to the sweeper on perform/1" do
      assert :ok = perform_job(ExpirePendingUploads, %{})
    end
  end

  defp insert_user!(attrs \\ %{}) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
