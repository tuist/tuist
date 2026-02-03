defmodule Cache.S3TransfersTest do
  use ExUnit.Case, async: false

  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3Transfers
  alias Cache.S3TransfersBuffer
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    if pid = Process.whereis(S3TransfersBuffer) do
      Sandbox.allow(Repo, self(), pid)
      S3TransfersBuffer.reset()
    end

    Repo.delete_all(S3Transfer)

    :ok
  end

  describe "enqueue_cas_upload/3" do
    test "creates a new upload transfer" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      transfer = Repo.get_by!(S3Transfer, key: "account/project/cas/AB/CD/artifact123", type: :upload)

      assert transfer.type == :upload
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :xcode_cas
      assert transfer.key == "account/project/cas/AB/CD/artifact123"
      assert transfer.inserted_at
    end

    test "does not create duplicate transfers" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end

    test "allows same key for different types" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      transfers = Repo.all(S3Transfer)
      assert Enum.uniq_by(transfers, & &1.id) == transfers

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 2
    end
  end

  describe "enqueue_cas_download/3" do
    test "creates a new download transfer" do
      :ok = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      transfer = Repo.get_by!(S3Transfer, key: "account/project/cas/AB/CD/artifact123", type: :download)

      assert transfer.type == :download
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :xcode_cas
      assert transfer.key == "account/project/cas/AB/CD/artifact123"
      assert transfer.inserted_at
    end

    test "does not create duplicate transfers" do
      :ok = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end
  end

  describe "enqueue_module_upload/3" do
    test "creates a new upload transfer" do
      :ok =
        S3Transfers.enqueue_module_upload("account", "project", "account/project/module/builds/AB/CD/hash/name.zip")

      :ok = S3TransfersBuffer.flush()

      transfer =
        Repo.get_by!(S3Transfer,
          key: "account/project/module/builds/AB/CD/hash/name.zip",
          type: :upload
        )

      assert transfer.type == :upload
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :xcode_module
      assert transfer.key == "account/project/module/builds/AB/CD/hash/name.zip"
      assert transfer.inserted_at
    end
  end

  describe "enqueue_module_download/3" do
    test "creates a new download transfer" do
      :ok =
        S3Transfers.enqueue_module_download("account", "project", "account/project/module/builds/AB/CD/hash/name.zip")

      :ok = S3TransfersBuffer.flush()

      transfer =
        Repo.get_by!(S3Transfer,
          key: "account/project/module/builds/AB/CD/hash/name.zip",
          type: :download
        )

      assert transfer.type == :download
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :xcode_module
      assert transfer.key == "account/project/module/builds/AB/CD/hash/name.zip"
      assert transfer.inserted_at
    end
  end

  describe "enqueue_registry_upload/1" do
    test "creates a new upload transfer with sentinel handles" do
      key = "registry/swift/apple/parser/1.0.0/source_archive.zip"

      :ok = S3Transfers.enqueue_registry_upload(key)
      :ok = S3TransfersBuffer.flush()

      transfer = Repo.get_by!(S3Transfer, key: key, type: :upload)

      assert transfer.type == :upload
      assert transfer.account_handle == "registry"
      assert transfer.project_handle == "registry"
      assert transfer.artifact_type == :registry
      assert transfer.key == key
      assert transfer.inserted_at
    end

    test "does not create duplicate transfers" do
      key = "registry/swift/apple/parser/1.0.0/source_archive.zip"

      :ok = S3Transfers.enqueue_registry_upload(key)
      :ok = S3Transfers.enqueue_registry_upload(key)
      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end
  end

  describe "enqueue_registry_download/1" do
    test "creates a new download transfer with sentinel handles" do
      key = "registry/swift/apple/parser/1.0.0/source_archive.zip"

      :ok = S3Transfers.enqueue_registry_download(key)
      :ok = S3TransfersBuffer.flush()

      transfer = Repo.get_by!(S3Transfer, key: key, type: :download)

      assert transfer.type == :download
      assert transfer.account_handle == "registry"
      assert transfer.project_handle == "registry"
      assert transfer.artifact_type == :registry
      assert transfer.key == key
      assert transfer.inserted_at
    end

    test "does not create duplicate transfers" do
      key = "registry/swift/apple/parser/1.0.0/source_archive.zip"

      :ok = S3Transfers.enqueue_registry_download(key)
      :ok = S3Transfers.enqueue_registry_download(key)
      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end
  end

  describe "pending/2" do
    test "returns pending transfers of given type" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact1")
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact2")
      :ok = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/ar/ti/artifact3")
      :ok = S3TransfersBuffer.flush()

      uploads = S3Transfers.pending(:upload, 10)
      downloads = S3Transfers.pending(:download, 10)

      assert length(uploads) == 2
      assert length(downloads) == 1

      assert Enum.all?(uploads, fn t -> t.type == :upload end)
      assert Enum.all?(downloads, fn t -> t.type == :download end)
    end

    test "respects limit" do
      for i <- 1..5 do
        S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact#{i}")
      end

      :ok = S3TransfersBuffer.flush()

      transfers = S3Transfers.pending(:upload, 3)
      assert length(transfers) == 3
    end

    test "returns empty list when no pending transfers" do
      transfers = S3Transfers.pending(:upload, 10)
      assert transfers == []
    end
  end

  describe "delete/1" do
    test "deletes a transfer by id" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      transfer = Repo.get_by!(S3Transfer, key: "account/project/cas/AB/CD/artifact123", type: :upload)

      S3Transfers.delete(transfer.id)
      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end

    test "is idempotent" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      :ok = S3TransfersBuffer.flush()

      transfer = Repo.get_by!(S3Transfer, key: "account/project/cas/AB/CD/artifact123", type: :upload)

      S3Transfers.delete(transfer.id)
      S3Transfers.delete(transfer.id)
      :ok = S3TransfersBuffer.flush()

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end
  end

  describe "delete_all/1" do
    test "deletes multiple transfers by ids" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact1")
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact2")
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact3")
      :ok = S3TransfersBuffer.flush()

      [t1, t2 | _] = S3Transfers.pending(:upload, 10)

      S3Transfers.delete_all([t1.id, t2.id])
      :ok = S3TransfersBuffer.flush()

      remaining = S3Transfers.pending(:upload, 10)
      assert length(remaining) == 1
      assert Enum.any?(remaining, fn transfer -> transfer.key == "account/project/cas/ar/ti/artifact3" end)
    end

    test "handles empty list" do
      :ok = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact1")
      :ok = S3TransfersBuffer.flush()

      S3Transfers.delete_all([])

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end
  end
end
