defmodule Tuist.Accounts.Workers.DeleteAccountArtifactsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Workers.DeleteAccountArtifactsWorker
  alias Tuist.Artifacts
  alias Tuist.Artifacts.Package
  alias Tuist.Artifacts.Publication
  alias Tuist.Environment
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(Storage, :delete_all_objects, fn _prefix, _actor -> :ok end)
    :ok
  end

  test "rescans uploads completing after erasure, even when the uploading replica dies" do
    for lost_writer? <- [false, true] do
      user = AccountsFixtures.user_fixture()
      project = [account_id: user.account.id] |> ProjectsFixtures.project_fixture() |> Repo.preload(:account)
      key = Package.digest("publication")
      digest = Package.digest("payload")
      object_key = Package.storage_key(project, key, digest)
      {:ok, objects} = Agent.start_link(fn -> [] end)
      parent = self()

      stub(Storage, :list_objects, fn _, _, _ -> {:ok, %{body: %{contents: Agent.get(objects, & &1)}}} end)
      stub(Storage, :delete_objects, fn _, _ -> Agent.update(objects, fn _ -> [] end) end)

      stub(Storage, :upload_file, fn _, ^object_key, _ ->
        assert Artifacts.uploads_pending?(user.account.id)
        Accounts.delete_account!(user.account)
        [job] = all_enqueued(worker: DeleteAccountArtifactsWorker, args: %{account_id: user.account.id})
        assert {:snooze, 30} = DeleteAccountArtifactsWorker.perform(job)
        # The storage service completes after cleanup has passed this key.
        Agent.update(objects, fn _ -> [%{key: object_key}] end)
        send(parent, {:cleanup_job, job.id})
        if lost_writer?, do: throw(:replica_lost), else: {:ok, %{}}
      end)

      if lost_writer? do
        assert catch_throw(Artifacts.put_content(project, key, digest, "unused")) == :replica_lost
      else
        assert :ok = Artifacts.put_content(project, key, digest, "unused")
      end

      assert_receive {:cleanup_job, job_id}
      job = Repo.get!(Oban.Job, job_id)
      expected = if lost_writer?, do: {:snooze, 30}, else: :ok
      assert ^expected = DeleteAccountArtifactsWorker.perform(job)
      assert Agent.get(objects, & &1) == []
      assert Artifacts.uploads_pending?(user.account.id) == lost_writer?
      # A stale actor may not start another write after account deletion.
      assert {:error, :expired} = Artifacts.put_content(project, key, digest, "unused")
    end
  end

  test "retries failed deletion after the account is gone, using its encrypted custom storage actor" do
    user = AccountsFixtures.user_fixture()

    account =
      user
      |> Accounts.get_account_from_user()
      |> Account.s3_storage_changeset(%{
        s3_bucket_name: "deleted-account-bucket",
        s3_access_key_id: "DELETED_ACCOUNT_ACCESS_KEY",
        s3_secret_access_key: "DELETED_ACCOUNT_SECRET_KEY",
        s3_region: "eu-west-1",
        s3_endpoint: "https://storage.example.com:9000"
      })
      |> Repo.update!()

    project = ProjectsFixtures.project_fixture(account_id: account.id)
    key = Package.digest("committed")
    committed = Package.storage_key(project, key, Package.digest("content"))
    incomplete = Package.storage_key(project, Package.digest("incomplete"), Package.digest("uncommitted content"))

    publication = Repo.insert!(%Publication{project_id: project.id, key: key, intent: %{}, contents: %{}})
    Repo.insert_all("artifact_uploads", [%{account_id: account.id, inserted_at: DateTime.utc_now()}])
    Accounts.delete_account!(account)
    assert Accounts.get_account_by_id(account.id) == {:error, :not_found}
    assert Repo.get(Publication, publication.id) == nil
    [job] = all_enqueued(worker: DeleteAccountArtifactsWorker, args: %{account_id: account.id})

    assert Enum.sort(Map.keys(job.args)) == ["account_id", "encrypted_storage"]
    serialized_args = JSON.encode!(job.args)
    refute serialized_args =~ account.s3_access_key_id
    refute serialized_args =~ account.s3_secret_access_key
    refute serialized_args =~ account.s3_bucket_name

    # Exercise real Storage actor routing, not only a mock accepting an Account.
    # Custom S3 must still override an Azure default after the account is gone.
    stub(Environment, :object_storage_provider, fn -> :azure_blob end)

    expect(ExAws, :request, 5, fn operation, config ->
      assert operation.bucket == account.s3_bucket_name
      assert config.access_key_id == account.s3_access_key_id
      assert config.secret_access_key == account.s3_secret_access_key
      assert config.region == account.s3_region
      assert config.host == "storage.example.com"
      assert config.port == 9000
      assert config.scheme == "https://"

      {:ok, %{body: %{contents: [%{key: committed}, %{key: incomplete}], is_truncated: false}}}
    end)

    expect(Storage, :delete_objects, 4, fn keys, actor ->
      assert keys == [committed, incomplete]
      assert actor.id == account.id
      assert actor.s3_secret_access_key == account.s3_secret_access_key
      {:error, {:provider_error, account.s3_secret_access_key}}
    end)

    for attempt <- 1..4 do
      if attempt > 1, do: Oban.retry_job(job.id)
      assert %{failure: 0, snoozed: 1, success: 0} = Oban.drain_queue(queue: :storage_retention)
      failed = Repo.get!(Oban.Job, job.id)
      assert failed.state == "scheduled"
      assert failed.args == job.args
      assert failed.max_attempts > failed.attempt
      assert failed.errors == []
    end

    query = from j in Oban.Job, where: j.id == ^job.id
    Repo.update_all(query, set: [inserted_at: DateTime.add(DateTime.utc_now(), -3, :hour)])
    assert {:ok, []} = Oban.Engine.prune_jobs(Oban.config(), query, max_age: 1, limit: 100)
    assert Repo.get!(Oban.Job, job.id).args == job.args

    expect(Storage, :delete_objects, fn keys, actor ->
      assert keys == [committed, incomplete]
      assert actor.s3_bucket_name == account.s3_bucket_name
      :ok
    end)

    assert :ok = Oban.retry_job(job.id)
    assert %{failure: 0, snoozed: 1, success: 0} = Oban.drain_queue(queue: :storage_retention)
    assert Repo.get!(Oban.Job, job.id).state == "scheduled"
    assert Artifacts.uploads_pending?(account.id)
  end

  test "deletes only artifact objects in the exact account-owned namespace" do
    account = %Account{id: 12, name: "deleted"}
    digest = Package.digest("content")
    owned = "12/42/artifacts/#{digest}/#{digest}"

    objects =
      Enum.map(
        [
          owned,
          "123/42/artifacts/#{digest}/#{digest}",
          "13/42/artifacts/#{digest}/#{digest}",
          "12/42/previews/#{digest}/#{digest}",
          "12/42/artifacts/not-a-digest/#{digest}",
          "12/../artifacts/#{digest}/#{digest}",
          "12/42/artifacts/#{digest}/#{digest}/extra",
          "runner-volume-masters/12/master"
        ],
        &%{key: &1}
      )

    expect(Storage, :list_objects, fn "12/", %Account{id: 12}, _opts ->
      {:ok, %{body: %{contents: objects}}}
    end)

    expect(Storage, :delete_objects, fn [^owned], %Account{id: 12} -> :ok end)
    assert :ok = account |> new_job() |> DeleteAccountArtifactsWorker.perform()
  end

  test "persists pagination only after deletion succeeds and retries the same failed page" do
    account = %Account{id: 12, name: "deleted"}
    job = account |> DeleteAccountArtifactsWorker.new_cleanup() |> Oban.insert!()
    job = Repo.get!(Oban.Job, job.id)
    digest = Package.digest("content")
    object_key = "12/42/artifacts/#{digest}/#{digest}"

    expect(Storage, :list_objects, 2, fn "12/", _actor, opts ->
      assert opts[:continuation_token] == nil
      {:ok, %{body: %{contents: [%{key: object_key}], is_truncated: true, next_continuation_token: "page-2"}}}
    end)

    expect(Storage, :delete_objects, fn [^object_key], _actor -> {:error, :unavailable} end)
    assert {:snooze, 300} = DeleteAccountArtifactsWorker.perform(job)
    assert Repo.get!(Oban.Job, job.id).args["continuation_token"] == nil

    expect(Storage, :delete_objects, fn [^object_key], _actor -> :ok end)
    assert {:snooze, 0} = DeleteAccountArtifactsWorker.perform(%{job | attempt: 2})
    next_page = Repo.get!(Oban.Job, job.id)
    assert next_page.args["continuation_token"] == "page-2"
    assert next_page.args["encrypted_storage"] == job.args["encrypted_storage"]

    expect(Storage, :list_objects, fn "12/", _actor, opts ->
      assert opts[:continuation_token] == "page-2"
      {:ok, %{body: %{contents: [], is_truncated: false}}}
    end)

    expect(Storage, :delete_objects, fn [], _actor -> :ok end)
    assert :ok = DeleteAccountArtifactsWorker.perform(next_page)
  end

  test "list failures, exceptions and invalid encrypted snapshots are retryable without leaking secrets" do
    job = new_job(%Account{id: 12})
    expect(Storage, :list_objects, fn _, _, _ -> {:error, :unavailable} end)
    assert {:snooze, 300} = DeleteAccountArtifactsWorker.perform(job)

    expect(Storage, :list_objects, fn _, _, _ -> raise "sensitive provider error" end)
    assert {:snooze, 300} = DeleteAccountArtifactsWorker.perform(job)

    reject(&Storage.list_objects/3)
    invalid = put_in(job.args["encrypted_storage"], "tampered")
    assert {:snooze, 300} = DeleteAccountArtifactsWorker.perform(invalid)

    wrong_account = put_in(job.args["account_id"], 123)
    assert {:snooze, 300} = DeleteAccountArtifactsWorker.perform(wrong_account)
  end

  defp new_job(account) do
    changeset = DeleteAccountArtifactsWorker.new_cleanup(account)
    args = Map.new(changeset.changes.args, fn {key, value} -> {to_string(key), value} end)
    %Oban.Job{args: args}
  end
end
