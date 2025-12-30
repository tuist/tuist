defmodule Cache.S3TransfersTest do
  use ExUnit.Case, async: false

  alias Cache.Repo
  alias Cache.S3Transfer
  alias Cache.S3Transfers
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "enqueue_cas_upload/3" do
    test "creates a new upload transfer" do
      {:ok, transfer} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")

      assert transfer.type == :upload
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :cas
      assert transfer.key == "account/project/cas/AB/CD/artifact123"
      assert transfer.inserted_at
    end

    test "does not create duplicate transfers" do
      {:ok, _transfer1} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      {:ok, _transfer2} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end

    test "allows same key for different types" do
      {:ok, upload} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")
      {:ok, download} = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")

      assert upload.id != download.id

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 2
    end
  end

  describe "enqueue_cas_download/3" do
    test "creates a new download transfer" do
      {:ok, transfer} = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")

      assert transfer.type == :download
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :cas
      assert transfer.key == "account/project/cas/AB/CD/artifact123"
      assert transfer.inserted_at
    end

    test "does not create duplicate transfers" do
      {:ok, _transfer1} =
        S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")

      {:ok, _transfer2} =
        S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/AB/CD/artifact123")

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end
  end

  describe "enqueue_module_upload/3" do
    test "creates a new upload transfer" do
      {:ok, transfer} =
        S3Transfers.enqueue_module_upload("account", "project", "account/project/module/builds/AB/CD/hash/name.zip")

      assert transfer.type == :upload
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :module
      assert transfer.key == "account/project/module/builds/AB/CD/hash/name.zip"
      assert transfer.inserted_at
    end
  end

  describe "enqueue_module_download/3" do
    test "creates a new download transfer" do
      {:ok, transfer} =
        S3Transfers.enqueue_module_download("account", "project", "account/project/module/builds/AB/CD/hash/name.zip")

      assert transfer.type == :download
      assert transfer.account_handle == "account"
      assert transfer.project_handle == "project"
      assert transfer.artifact_type == :module
      assert transfer.key == "account/project/module/builds/AB/CD/hash/name.zip"
      assert transfer.inserted_at
    end
  end

  describe "pending/2" do
    test "returns pending transfers of given type" do
      {:ok, _} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact1")
      {:ok, _} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact2")
      {:ok, _} = S3Transfers.enqueue_cas_download("account", "project", "account/project/cas/ar/ti/artifact3")

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
      {:ok, transfer} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")

      :ok = S3Transfers.delete(transfer.id)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end

    test "is idempotent" do
      {:ok, transfer} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/AB/CD/artifact123")

      :ok = S3Transfers.delete(transfer.id)
      :ok = S3Transfers.delete(transfer.id)

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 0
    end
  end

  describe "delete_all/1" do
    test "deletes multiple transfers by ids" do
      {:ok, t1} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact1")
      {:ok, t2} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact2")
      {:ok, t3} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact3")

      :ok = S3Transfers.delete_all([t1.id, t2.id])

      remaining = S3Transfers.pending(:upload, 10)
      assert length(remaining) == 1
      assert hd(remaining).id == t3.id
    end

    test "handles empty list" do
      {:ok, _} = S3Transfers.enqueue_cas_upload("account", "project", "account/project/cas/ar/ti/artifact1")

      :ok = S3Transfers.delete_all([])

      count = Repo.aggregate(S3Transfer, :count, :id)
      assert count == 1
    end
  end
end
