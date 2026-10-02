defmodule Tuist.Runners.CacheVolumesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()

    %{
      account: account,
      job: %{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        workflow_run_id: 321,
        run_attempt: 1,
        repository: "org/repo"
      }
    }
  end

  defp identity, do: %{repository_id: 123, trusted: true, same_repository: true}

  defp attrs(pod \\ "pod", node \\ "node"),
    do: %{pod_name: pod, pod_uid: pod, node_name: node, key: "gradle/caches", architecture: "amd64", uid: 1001}

  defp report(state \\ "active", gone \\ true),
    do: %{
      "state" => state,
      "gone" => gone,
      "warm" => false,
      "size_bytes" => 1024,
      "capacity_bytes" => 2048,
      "attach_ms" => 10
    }

  defp publish_report(node, id) do
    usage = Repo.get!(Usage, id)
    digest = :sha |> :crypto.hash(id) |> Base.encode16(case: :lower)
    content = :sha256 |> :crypto.hash(id) |> Base.encode16(case: :lower)

    if usage.status != "published" do
      CacheVolumes.image(node, id, %{"operation" => "publish", "image_digest" => digest, "content_digest" => content})
    end

    CacheVolumes.report(node, id, report("sealed"))
  end

  defp complete(job, conclusion \\ "success") do
    Repo.insert!(%JobCompletion{
      workflow_job_id: job.workflow_job_id,
      account_id: job.account_id,
      conclusion: conclusion,
      completed_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  defp volume(account), do: hd(CacheVolumes.list(account.id).volumes)

  test "only an open Linux session waiting for execution attribution is retryable", %{account: account, job: job} do
    session =
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: job.workflow_job_id,
        fleet_name: "linux",
        pod_name: "pending-pod",
        node_name: "node",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: DateTime.utc_now()
      })

    params = %{
      "pod_name" => "pending-pod",
      "pod_uid" => "uid",
      "node_name" => "node",
      "key" => "gradle",
      "architecture" => "amd64",
      "uid" => 1001
    }

    assert {:error, :pending} = CacheVolumes.allocate(params)
    assert {:error, :unavailable} = CacheVolumes.allocate(%{params | "node_name" => "other"})
    assert {:error, :unavailable} = CacheVolumes.allocate(%{params | "pod_name" => "unknown"})
    assert CacheVolumes.list(account.id).volumes == []

    Repo.update!(Ecto.Changeset.change(session, ended_at: DateTime.utc_now()))
    assert {:error, :unavailable} = CacheVolumes.allocate(params)
  end

  test "custom Linux names never become valid macOS dispatch names", %{job: job, account: account} do
    {:ok, _} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    name = CacheVolumes.storage_name(volume(account))
    assert VolumeHeads.valid_storage_volume_name?(name)
    refute VolumeHeads.valid_volume_name?(name)
  end

  test "only one concurrent base can publish through the shared macOS HEAD", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    {:ok, stale} = CacheVolumes.allocate_for_job(job, identity(), attrs("stale"))
    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    assert {:ok, %{action: "delete"}} = publish_report("node", stale.id)
    assert volume(account).head_id == first.id
    name = CacheVolumes.storage_name(volume(account))
    assert %{generation: 1} = VolumeHeads.get_head(account.id, name)
    {:ok, warm} = CacheVolumes.allocate_for_job(job, identity(), attrs("warm"))
    assert warm.base_generation == 1
    assert warm.content_digest == Repo.get!(Usage, first.id).content_digest
  end

  test "sealed reports alone cannot publish and cleared images cannot be retried", %{job: job, account: account} do
    {:ok, use} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    assert {:ok, %{action: "delete"}} = CacheVolumes.report("node", use.id, report("sealed"))
    assert is_nil(volume(account).head_id)
    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next"))
    assert {:ok, %{action: "keep"}} = publish_report("node", next.id)
    saved = Repo.get!(Usage, next.id)
    params = %{"operation" => "publish", "image_digest" => saved.image_digest, "content_digest" => saved.content_digest}
    assert {:ok, %{generation: 1}} = CacheVolumes.image("node", next.id, params)
    assert {:error, :not_found} = CacheVolumes.image("other-node", next.id, params)
    old_name = CacheVolumes.storage_name(volume(account))
    CacheVolumes.delete(account.id, volume(account).id)
    assert {:error, :conflict} = CacheVolumes.image("node", next.id, params)
    assert is_nil(VolumeHeads.get_head(account.id, old_name))
    {:ok, cold} = CacheVolumes.allocate_for_job(job, identity(), attrs("cold"))
    assert cold.base_generation == 0
    assert is_nil(cold.content_digest)
  end

  test "local replicas validate against the current head after private branches are reclaimed", %{
    job: job,
    account: account
  } do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    assert {:ok, %{generation: 1}} = CacheVolumes.image("node", first.id, %{"operation" => "retain"})
    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next"))
    assert {:ok, %{action: "keep"}} = publish_report("node", next.id)
    assert {:ok, _} = CacheVolumes.report("node", first.id, %{"state" => "deleted"})
    assert {:ok, %{generation: 2}} = CacheVolumes.image("node", first.id, %{"operation" => "retain"})
    assert {:error, :not_found} = CacheVolumes.image("other-node", next.id, %{"operation" => "retain"})
    CacheVolumes.delete(account.id, volume(account).id)
    assert {:error, :conflict} = CacheVolumes.image("node", next.id, %{"operation" => "retain"})
  end

  test "provider and instance namespaces cannot collide, and each preserves warm reuse", %{job: job} do
    scopes = [
      %{provider: "github", provider_instance: "github.com", scope_id: "123", repository_id: 123, trusted: true},
      %{provider: "gitlab", provider_instance: "gitlab.com", scope_id: "123", repository_id: 123, trusted: true},
      %{provider: "gitlab", provider_instance: "self-managed", scope_id: "123", repository_id: 123, trusted: true},
      %{
        provider: "buildkite",
        provider_instance: "organization",
        scope_id: "pipeline:repo",
        repository_id: nil,
        trusted: true
      }
    ]

    uses =
      for {scope, index} <- Enum.with_index(scopes) do
        scoped_job = %{job | workflow_job_id: job.workflow_job_id + index}
        {:ok, first} = CacheVolumes.allocate_for_job(scoped_job, scope, attrs("provider-#{index}"))
        complete(scoped_job)
        assert {:ok, %{action: "seal"}} = CacheVolumes.report("node", first.id, report())
        assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
        {:ok, second} = CacheVolumes.allocate_for_job(scoped_job, scope, attrs("provider-#{index}-warm"))
        assert second.parent_id == first.id
        first.scope
      end

    assert length(Enum.uniq(uses)) == 4
  end

  test "job volumes include mounted volumes once and scope both account and job identity", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    {:ok, retry} = CacheVolumes.allocate_for_job(job, identity(), attrs("retry"))
    {:ok, unmounted} = CacheVolumes.allocate_for_job(job, identity(), %{attrs("unmounted") | key: "unused"})

    {:ok, other_job} =
      CacheVolumes.allocate_for_job(%{job | workflow_job_id: job.workflow_job_id + 1}, identity(), attrs("other-job"))

    {:ok, other_run} =
      CacheVolumes.allocate_for_job(%{job | workflow_run_id: job.workflow_run_id + 1}, identity(), attrs("other-run"))

    other_account = AccountsFixtures.account_fixture()

    {:ok, other_tenant} =
      CacheVolumes.allocate_for_job(%{job | account_id: other_account.id}, identity(), attrs("other-account"))

    for {use, at} <- [
          {first, ~U[2026-09-22 10:00:00.000000Z]},
          {retry, ~U[2026-09-22 11:00:00.000000Z]},
          {other_job, ~U[2026-09-22 12:00:00.000000Z]},
          {other_run, ~U[2026-09-22 12:00:00.000000Z]},
          {other_tenant, ~U[2026-09-22 12:00:00.000000Z]}
        ] do
      Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, use.id), attached_at: at))
    end

    assert [usage] = CacheVolumes.for_job(account.id, job.workflow_run_id, job.workflow_job_id)
    assert usage.id == retry.id
    assert usage.volume.key == "gradle/caches"
    assert usage.volume.account_id == account.id
    refute usage.id == unmounted.id
    assert [] = CacheVolumes.for_job(account.id, -1, job.workflow_job_id)
    assert [] = CacheVolumes.for_job(AccountsFixtures.account_fixture().id, job.workflow_run_id, job.workflow_job_id)

    Repo.update!(Ecto.Changeset.change(usage, deleted_at: DateTime.utc_now()))
    assert [%{id: id}] = CacheVolumes.for_job(account.id, job.workflow_run_id, job.workflow_job_id)
    assert id == retry.id
  end

  test "inventory sorts the full account result before paginating and preserves search", %{job: job, account: account} do
    volumes =
      for index <- 1..22 do
        key = "cache-#{String.pad_leading(to_string(index), 2, "0")}"
        {:ok, use} = CacheVolumes.allocate_for_job(job, identity(), %{attrs("pod-#{index}") | key: key})
        usage = Repo.get!(Usage, use.id)
        Repo.update!(Ecto.Changeset.change(usage, size_bytes: index * 1024, capacity_bytes: (23 - index) * 2048))

        Repo.update!(
          Ecto.Changeset.change(Repo.get!(Volume, usage.volume_id),
            last_used_at: DateTime.add(~U[2026-09-22 00:00:00.000000Z], index)
          )
        )
      end

    for {sort_by, direction, expected} <- [
          {"volume", "asc", volumes},
          {"volume", "desc", Enum.reverse(volumes)},
          {"used_space", "desc", Enum.reverse(volumes)},
          {"used_space", "asc", volumes},
          {"capacity", "desc", volumes},
          {"capacity", "asc", Enum.reverse(volumes)},
          {"last_used", "desc", Enum.reverse(volumes)}
        ] do
      options = [sort_by: sort_by, sort_order: direction]
      assert %{volumes: first, more?: true} = CacheVolumes.list(account.id, "", 1, options)
      assert %{volumes: second, more?: false} = CacheVolumes.list(account.id, "", 2, options)
      assert length(first) == 20
      assert length(second) == 2
      assert Enum.map(first ++ second, & &1.id) == Enum.map(expected, & &1.id)
    end

    assert %{volumes: [found], more?: false} = CacheVolumes.list(account.id, "cache-22", 1, sort_by: "used_space")
    assert found.id == List.last(volumes).id
    assert %{volumes: []} = CacheVolumes.list(AccountsFixtures.account_fixture().id, "", 1, sort_by: "capacity")

    first = CacheVolumes.list(account.id, "", 1, sort_by: "repository", sort_order: "asc")
    second = CacheVolumes.list(account.id, "", 2, sort_by: "repository", sort_order: "asc")
    ids = Enum.map(first.volumes ++ second.volumes, & &1.id)
    assert ids == Enum.sort(Enum.map(volumes, & &1.id))
  end

  test "size sorting sums retained copies and keeps unknown values last", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    {:ok, second} = CacheVolumes.allocate_for_job(job, identity(), attrs("second"))
    {:ok, single} = CacheVolumes.allocate_for_job(job, identity(), %{attrs("single") | key: "single"})
    {:ok, empty} = CacheVolumes.allocate_for_job(job, identity(), %{attrs("empty") | key: "empty"})
    {:ok, unknown} = CacheVolumes.allocate_for_job(job, identity(), %{attrs("unknown") | key: "unknown"})

    for {use, size} <- [{first, 100}, {second, 100}, {single, 150}] do
      Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, use.id), size_bytes: size, capacity_bytes: size * 2))
    end

    unknown_volume = Repo.get!(Volume, Repo.get!(Usage, unknown.id).volume_id)
    Repo.update!(Ecto.Changeset.change(unknown_volume, head_id: unknown.id))

    assert Enum.map(CacheVolumes.list(account.id, "", 1, sort_by: "used_space").volumes, & &1.key) ==
             ["gradle/caches", "single", "empty", "unknown"]

    assert Enum.map(CacheVolumes.list(account.id, "", 1, sort_by: "used_space", sort_order: "asc").volumes, & &1.key) ==
             ["empty", "single", "gradle/caches", "unknown"]

    Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, second.id), deleted_at: DateTime.utc_now()))
    assert hd(CacheVolumes.list(account.id, "", 1, sort_by: "used_space").volumes).key == "single"
    Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, empty.id), deleted_at: DateTime.utc_now()))
    assert hd(CacheVolumes.list(account.id, "", 1, sort_by: "capacity", sort_order: "asc").volumes).key == "empty"
  end

  test "keys support repository prefixes but never become paths" do
    assert CacheVolumes.valid_key?("org/repo-gradle-v1")
    refute CacheVolumes.valid_key?("")
    refute CacheVolumes.valid_key?("x\nInjected")
    refute CacheVolumes.valid_key?(String.duplicate("x", 201))
  end

  test "GitHub identity grants PR reads separately from publication", %{job: job} do
    run = %{
      "id" => 321,
      "run_attempt" => 1,
      "repository" => %{"id" => 123, "full_name" => "org/repo", "default_branch" => "main"},
      "head_repository" => %{"id" => 123},
      "head_branch" => "main",
      "event" => "push"
    }

    assert {:ok, %{trusted: true}} = CacheVolumes.run_identity(job, run)

    for event <- ["pull_request", "pull_request_target", "merge_group"] do
      assert {:ok, %{trusted: false}} = CacheVolumes.run_identity(job, %{run | "event" => event})
    end

    assert {:ok, %{trusted: false, same_repository: false}} =
             CacheVolumes.run_identity(job, %{run | "head_repository" => %{"id" => 999}})

    assert {:error, _} = CacheVolumes.run_identity(job, %{run | "id" => 322})
    assert {:error, _} = CacheVolumes.run_identity(job, %{run | "run_attempt" => 2})
  end

  test "allocation retries are idempotent and different users are isolated", %{job: job, account: account} do
    assert {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert {:ok, ^first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert length(CacheVolumes.history(account.id, volume(account).id)) == 1
    assert {:ok, other} = CacheVolumes.allocate_for_job(job, identity(), %{attrs() | uid: 0})
    refute other.scope == first.scope
  end

  test "only successful completed jobs may publish; repeated reports don't resurrect old heads", %{
    job: job,
    account: account
  } do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert {:ok, %{action: "hold"}} = CacheVolumes.report("node", first.id, report("active", false))
    assert {:ok, %{action: "wait"}} = CacheVolumes.report("node", first.id, report())
    complete(job)
    assert {:ok, %{action: "seal"}} = CacheVolumes.report("node", first.id, report())
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    assert volume(account).head_id == first.id
    {:ok, second} = CacheVolumes.allocate_for_job(job, identity(), attrs("pod2", "other-node"))
    assert second.parent_id == first.id
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    assert {:ok, %{action: "keep"}} = publish_report("other-node", second.id)
    assert {:ok, %{action: "delete"}} = publish_report("node", first.id)
    assert volume(account).head_id == second.id
  end

  test "acknowledging an unmounted allocation releases its retired parent", %{job: job, account: account} do
    {:ok, parent} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", parent.id)
    {:ok, rejected} = CacheVolumes.allocate_for_job(job, identity(), attrs("rejected"))
    {:ok, replacement} = CacheVolumes.allocate_for_job(job, identity(), attrs("replacement"))
    assert rejected.parent_id == parent.id
    assert {:ok, %{action: "keep"}} = publish_report("node", replacement.id)
    assert volume(account).head_id == replacement.id
    assert {:ok, %{action: "keep"}} = publish_report("node", parent.id)

    assert {:ok, %{action: "forget"}} = CacheVolumes.report("node", rejected.id, %{"state" => "deleted"})
    assert {:ok, %{action: "forget"}} = CacheVolumes.report("node", rejected.id, %{"state" => "deleted"})
    rejected_use = Repo.get!(Usage, rejected.id)
    assert rejected_use.status == "discarded"
    assert rejected_use.finished_at
    assert rejected_use.deleted_at
    assert is_nil(rejected_use.attached_at)
    assert {:ok, %{action: "delete"}} = publish_report("node", parent.id)
  end

  test "PR clones consume the shared parent but are discarded", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", first.id)
    {:ok, pr} = CacheVolumes.allocate_for_job(job, %{identity() | trusted: false}, attrs("pr"))
    assert pr.parent_id == first.id
    refute pr.can_publish
    assert {:ok, %{action: "delete"}} = CacheVolumes.report("node", pr.id, report())
    assert volume(account).head_id == first.id
  end

  test "failed jobs never replace the parent", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job, "failure")
    assert {:ok, %{action: "delete"}} = publish_report("node", clone.id)
    assert is_nil(volume(account).head_id)
  end

  test "delete invalidates running clones and new uses start a fresh generation", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    assert {:ok, _} = CacheVolumes.delete(account.id, volume(account).id)
    assert {:ok, %{action: "hold"}} = CacheVolumes.report("node", clone.id, report("active", false))
    assert {:ok, %{action: "delete"}} = publish_report("node", clone.id)
    {:ok, fresh} = CacheVolumes.allocate_for_job(job, identity(), attrs("new"))
    assert is_nil(fresh.parent_id)
    refute fresh.scope == clone.scope
    assert {:ok, %{action: "forget"}} = CacheVolumes.report("node", clone.id, %{"state" => "deleted"})
    assert is_nil(volume(account).head_id)
  end

  test "tenant and node boundaries apply to every operation", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    other = AccountsFixtures.account_fixture()
    id = volume(account).id
    assert is_nil(CacheVolumes.get(other.id, id))
    assert {:error, :not_found} = CacheVolumes.delete(other.id, id)
    assert [] = CacheVolumes.history(other.id, id)
    assert {:error, :not_found} = CacheVolumes.report("foreign", clone.id, report())
  end

  test "same-repository PRs and forks cannot publish cache updates", %{job: job} do
    {:ok, same_repo_pr} = CacheVolumes.allocate_for_job(job, %{identity() | trusted: false}, attrs("pr"))
    refute same_repo_pr.can_publish

    {:ok, fork} =
      CacheVolumes.allocate_for_job(job, %{identity() | trusted: false, same_repository: false}, attrs("fork"))

    refute fork.can_publish
  end

  test "analytics deduplicate reports and preserve unknown attachment state", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert %{uses: 0, hits: 0} = CacheVolumes.statistics([volume(account).id])[volume(account).id]
    for _ <- 1..3, do: CacheVolumes.report("node", clone.id, %{report("active", false) | "warm" => true})
    stats = CacheVolumes.statistics([volume(account).id])[volume(account).id]
    assert stats.reported_at
    use = Repo.get!(Usage, clone.id)
    Repo.update!(Ecto.Changeset.change(use, last_reported_at: ~U[2020-01-01 00:00:00.000000Z]))
    CacheVolumes.report("node", clone.id, %{report("active", false) | "warm" => true})
    assert DateTime.after?(Repo.get!(Usage, clone.id).last_reported_at, ~U[2020-01-01 00:00:00.000000Z])
    assert stats.uses == 1 and stats.hits == 1 and stats.active == 1
    assert Decimal.equal?(stats.retained_bytes, 1024)
    assert {:error, :invalid_report} = CacheVolumes.report("node", clone.id, Map.put(report(), "size_bytes", -1))
  end

  test "only the first successful mount of each job refreshes last used", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert is_nil(volume(account).last_used_at)
    assert {:ok, _} = CacheVolumes.report("node", first.id, report("active", false))
    assert volume(account).last_used_at

    previous_mount = DateTime.add(DateTime.utc_now(), -86_400)
    Repo.update!(Ecto.Changeset.change(volume(account), last_used_at: previous_mount))
    assert {:ok, ^first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert {:ok, _} = CacheVolumes.report("node", first.id, report("active", false))
    assert volume(account).last_used_at == previous_mount

    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next"))
    assert volume(account).last_used_at == previous_mount
    assert {:ok, _} = CacheVolumes.report("node", next.id, report("active", false))
    assert DateTime.after?(volume(account).last_used_at, previous_mount)
    mounted = volume(account).last_used_at
    complete(job)
    publish_report("node", next.id)
    assert volume(account).last_used_at == mounted
  end

  test "sweep evicts at seven days and preserves volumes mounted within the window", %{job: job, account: account} do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, -7 * 86_400)
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", first.id)
    idle = volume(account)
    Repo.update!(Ecto.Changeset.change(idle, last_used_at: threshold))
    {:ok, recent} = CacheVolumes.allocate_for_job(job, identity(), %{attrs("recent") | key: "recent"})
    CacheVolumes.report("node", recent.id, report("active", false))
    recent_volume = Repo.get!(Volume, Repo.get!(Usage, recent.id).volume_id)
    Repo.update!(Ecto.Changeset.change(recent_volume, last_used_at: DateTime.add(threshold, 1)))

    assert {:ok, 1} = CacheVolumes.expire_inactive(now)
    expired = Repo.get!(Volume, idle.id)
    assert expired.deleted_at == now
    assert expired.generation == idle.generation + 1
    assert is_nil(expired.head_id)
    assert is_nil(Repo.get!(Usage, first.id).deleted_at)
    assert is_nil(Repo.get!(Volume, recent_volume.id).deleted_at)
    assert {:ok, 0} = CacheVolumes.expire_inactive(now)
    assert {:ok, %{action: "delete"}} = publish_report("node", first.id)
    assert Repo.get!(Volume, idle.id).last_used_at == threshold
  end

  test "evicted live copies are held until fenced and cannot resurrect the cache", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    CacheVolumes.report("node", first.id, report("active", false))
    idle = volume(account)
    Repo.update!(Ecto.Changeset.change(idle, last_used_at: DateTime.add(DateTime.utc_now(), -8 * 86_400)))
    assert :ok = Tuist.Runners.Workers.CacheVolumeCleanupWorker.perform(%Oban.Job{args: %{"action" => "evict"}})
    assert {:ok, %{action: "hold"}} = CacheVolumes.report("node", first.id, report("active", false))
    complete(job)
    assert {:ok, %{action: "delete"}} = publish_report("node", first.id)
    assert is_nil(Repo.get!(Volume, idle.id).head_id)

    {:ok, fresh} = CacheVolumes.allocate_for_job(job, identity(), attrs("fresh"))
    assert is_nil(fresh.parent_id)
    refute fresh.scope == first.scope
    assert is_nil(volume(account).last_used_at)
    CacheVolumes.report("node", fresh.id, report("active", false))
    assert volume(account).last_used_at
    assert is_nil(volume(account).deleted_at)
  end

  test "agent reports enforce idle eviction even before the sweep runs", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", first.id)
    idle = volume(account)
    Repo.update!(Ecto.Changeset.change(idle, last_used_at: DateTime.add(DateTime.utc_now(), -8 * 86_400)))
    assert {:ok, %{action: "delete"}} = publish_report("node", first.id)
    assert volume(account).deleted_at
    assert volume(account).generation == idle.generation + 1
  end

  test "idle expiration changes generation before reuse", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", first.id)
    Repo.update!(Ecto.Changeset.change(volume(account), last_used_at: DateTime.add(DateTime.utc_now(), -8 * 86_400)))
    {:ok, fresh} = CacheVolumes.allocate_for_job(job, identity(), attrs("later"))
    assert is_nil(fresh.parent_id)
    refute fresh.scope == first.scope
  end

  test "deletion acknowledgement retains history", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, %{identity() | trusted: false}, attrs())
    CacheVolumes.report("node", clone.id, report())
    CacheVolumes.report("node", clone.id, %{"state" => "deleted"})

    assert %Usage{deleted_at: deleted_at, status: "discarded"} =
             hd(CacheVolumes.history(account.id, volume(account).id))

    assert deleted_at
    assert %Volume{} = CacheVolumes.get(account.id, volume(account).id)
  end

  test "admission caps new keys without preventing retries", %{job: job} do
    for n <- 1..8 do
      assert {:ok, _} = CacheVolumes.allocate_for_job(job, identity(), %{attrs() | key: "cache-#{n}"})
    end

    assert {:ok, _} = CacheVolumes.allocate_for_job(job, identity(), %{attrs() | key: "cache-1"})
    assert {:error, :capacity} = CacheVolumes.allocate_for_job(job, identity(), %{attrs() | key: "cache-9"})
  end

  test "history cleanup removes only old acknowledged deletions", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    old = DateTime.add(DateTime.utc_now(), -91 * 86_400)
    use = Repo.get!(Usage, clone.id)
    Repo.update!(Ecto.Changeset.change(use, inserted_at: DateTime.truncate(old, :second)))
    assert :ok = CacheVolumes.prune_history()
    assert Repo.get(Usage, clone.id)
    Repo.update!(Ecto.Changeset.change(use, deleted_at: old))
    assert :ok = CacheVolumes.prune_history()
    assert is_nil(Repo.get(Usage, clone.id))
    assert %Volume{} = volume(account)
  end

  test "size changes are preserved, retries deduplicated, and deletion closes storage", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    id = volume(account).id
    metrics = report("active", false)
    for _ <- 1..3, do: CacheVolumes.report("node", clone.id, metrics)
    assert [first] = CacheVolumes.size_history(account.id, id)
    assert first.measurement.size_bytes == 1024

    CacheVolumes.report("node", clone.id, %{metrics | "size_bytes" => 1536})
    assert [grown, original] = CacheVolumes.size_history(account.id, id)
    assert grown.measurement.size_bytes == 1536
    assert original.measurement.id == first.measurement.id

    CacheVolumes.delete(account.id, id)
    assert Decimal.equal?(CacheVolumes.storage_summary(account.id).retained_bytes, 1536)
    assert length(CacheVolumes.size_history(account.id, id)) == 2

    for _ <- 1..2, do: CacheVolumes.report("node", clone.id, %{"state" => "deleted"})
    assert [deleted, _, _] = CacheVolumes.size_history(account.id, id)
    assert deleted.measurement.deleted
    assert deleted.measurement.size_bytes == 0
    assert deleted.measurement.capacity_bytes == 0
    assert CacheVolumes.storage_summary(account.id).retained_copies == 0
    assert [] = CacheVolumes.size_history(AccountsFixtures.account_fixture().id, id)
  end

  test "account totals include all keys and mark missing sizes instead of silently treating them as zero", %{
    job: job,
    account: account
  } do
    {:ok, measured} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    {:ok, missing} = CacheVolumes.allocate_for_job(job, identity(), %{attrs() | key: "other"})
    CacheVolumes.report("node", measured.id, report("active", false))
    other = AccountsFixtures.account_fixture()
    {:ok, foreign} = CacheVolumes.allocate_for_job(%{job | account_id: other.id}, identity(), attrs())
    CacheVolumes.report("node", foreign.id, report("active", false))

    totals = CacheVolumes.storage_summary(account.id)
    assert totals.volumes == 2
    assert totals.retained_copies == 2
    assert totals.unmeasured_copies == 1
    assert totals.unmeasured_capacity_copies == 1
    assert Decimal.equal?(totals.retained_bytes, 1024)
    assert Decimal.equal?(totals.retained_capacity_bytes, 2048)
    assert length(CacheVolumes.list(account.id, "gradle").volumes) == 1
    assert CacheVolumes.storage_summary(account.id) == totals

    CacheVolumes.report("node", missing.id, %{report("active", false) | "size_bytes" => nil})
    unknown_id = Repo.get!(Usage, missing.id).volume_id
    assert [unknown] = CacheVolumes.size_history(account.id, unknown_id)
    assert is_nil(unknown.measurement.size_bytes)
    assert CacheVolumes.storage_summary(account.id).unmeasured_copies == 1
    assert CacheVolumes.storage_summary(account.id).unmeasured_capacity_copies == 0
  end

  test "volume storage history and recent jobs are scoped and bounded", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    {:ok, other} = CacheVolumes.allocate_for_job(job, identity(), Map.put(attrs("other"), :key, "other"))
    CacheVolumes.report("node", first.id, report())
    CacheVolumes.report("node", other.id, %{report() | "size_bytes" => 8192})
    volume_id = Repo.get!(Usage, first.id).volume_id
    now = DateTime.add(DateTime.utc_now(), 1, :second)
    assert List.last(CacheVolumes.storage_history(account.id, now, volume_id)).used_bytes == 1024
    assert CacheVolumes.storage_history(AccountsFixtures.account_fixture().id, now, volume_id) == []

    for n <- 1..7 do
      {:ok, _} = CacheVolumes.allocate_for_job(job, identity(), attrs("recent-#{n}"))
    end

    recent = CacheVolumes.history(account.id, volume_id, 1, 5)
    assert length(recent) == 5
    assert Enum.all?(recent, &(&1.volume_id == volume_id))
    assert CacheVolumes.history(AccountsFixtures.account_fixture().id, volume_id, 1, 5) == []
  end

  test "history keeps uses when job names are missing and scopes names to account and run", %{job: job, account: account} do
    {:ok, _} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    volume_id = volume(account).id
    assert [usage] = CacheVolumes.history(account.id, volume_id)
    assert is_nil(usage.job_name)
    assert is_nil(usage.workflow_name)

    metadata =
      Repo.insert!(%WorkflowJob{
        workflow_job_id: job.workflow_job_id,
        workflow_run_id: job.workflow_run_id,
        account_id: account.id,
        fleet_name: "test",
        status: "completed",
        job_name: "Build and test",
        workflow_name: "Continuous integration",
        enqueued_at: DateTime.utc_now()
      })

    assert [%{job_name: "Build and test", workflow_name: "Continuous integration"}] =
             CacheVolumes.history(account.id, volume_id)

    metadata = Repo.update!(Ecto.Changeset.change(metadata, workflow_run_id: job.workflow_run_id + 1))
    assert [%{job_name: nil, workflow_name: nil}] = CacheVolumes.history(account.id, volume_id)

    Repo.update!(
      Ecto.Changeset.change(metadata,
        account_id: AccountsFixtures.account_fixture().id,
        workflow_run_id: job.workflow_run_id
      )
    )

    assert [%{job_name: nil, workflow_name: nil}] = CacheVolumes.history(account.id, volume_id)
  end

  test "usage analytics count mounts in the period and preserve missing cache results", %{job: job, account: account} do
    mounts = [
      {~U[2026-09-21 10:15:00.000000Z], true},
      {~U[2026-09-21 10:45:00.000000Z], false},
      {~U[2026-09-21 11:15:00.000000Z], nil},
      {~U[2026-09-21 13:15:00.000000Z], false},
      {nil, true}
    ]

    volume_id =
      mounts
      |> Enum.with_index()
      |> Enum.map(fn {{attached_at, warm}, n} ->
        {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs("mount-#{n}"))
        usage = Repo.get!(Usage, clone.id)

        Repo.update!(
          Ecto.Changeset.change(usage, attached_at: attached_at, warm: warm, inserted_at: ~U[2026-09-01 00:00:00Z])
        )

        usage.volume_id
      end)
      |> hd()

    {:ok, other} = CacheVolumes.allocate_for_job(job, identity(), Map.put(attrs("other"), :key, "other"))

    Repo.update!(
      Ecto.Changeset.change(Repo.get!(Usage, other.id), attached_at: ~U[2026-09-21 10:00:00.000000Z], warm: false)
    )

    period = {~U[2026-09-21 10:00:00Z], ~U[2026-09-21 12:00:00Z]}
    analytics = CacheVolumes.usage_analytics(account.id, volume_id, period)
    assert analytics.uses == 3
    assert analytics.hit_rate == 50.0
    account_analytics = CacheVolumes.usage_analytics(account.id, period)
    assert account_analytics.uses == 4
    assert account_analytics.hit_rate == 33.3
    assert Enum.map(account_analytics.points, & &1.hit_rate) == [33.3, nil, nil]
    other_account_analytics = CacheVolumes.usage_analytics(AccountsFixtures.account_fixture().id, period)
    assert other_account_analytics.uses == 0
    assert is_nil(other_account_analytics.hit_rate)
    assert Enum.map(analytics.points, & &1.uses) == [2, 1, 0]
    assert Enum.map(analytics.points, & &1.hit_rate) == [50.0, nil, nil]
    other_account = CacheVolumes.usage_analytics(AccountsFixtures.account_fixture().id, volume_id, period)
    assert other_account.uses == 0
    assert is_nil(other_account.hit_rate)
    daily = CacheVolumes.usage_analytics(account.id, volume_id, {~U[2026-09-19 00:00:00Z], ~U[2026-09-22 00:00:00Z]})
    assert daily.uses == 4
    assert Enum.map(daily.points, & &1.uses) == [0, 0, 4, 0]
  end

  test "storage history carries prior sizes, replaces reports, and subtracts confirmed deletions", %{
    job: job,
    account: account
  } do
    now = ~U[2026-09-22 12:30:00.000000Z]
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())

    Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, clone.id), inserted_at: ~U[2026-09-01 11:00:00Z]))

    insert_measurement = fn at, size, deleted ->
      Repo.insert!(%Measurement{
        usage_id: clone.id,
        observed_at: at,
        size_bytes: size,
        capacity_bytes: if(deleted, do: 0, else: 8192),
        deleted: deleted
      })
    end

    insert_measurement.(~U[2026-09-01 12:00:00.000000Z], 1024, false)
    insert_measurement.(~U[2026-09-21 12:05:00.000000Z], 2048, false)
    insert_measurement.(~U[2026-09-21 12:10:00.000000Z], 4096, false)
    insert_measurement.(~U[2026-09-22 11:05:00.000000Z], 0, true)
    insert_measurement.(~U[2026-09-23 12:00:00.000000Z], 9999, false)
    points = CacheVolumes.storage_history(account.id, now)
    assert Enum.map(points, & &1.volumes) == [1, 1, 0, 0]
    assert Enum.map(points, & &1.used_bytes) == [1024, 4096, 0, 0]
    assert Enum.map(points, & &1.capacity_bytes) == [8192, 8192, 0, 0]
    assert hd(points).at == DateTime.add(now, -7 * 86_400)
    assert List.last(points).at == now
    assert CacheVolumes.storage_history(AccountsFixtures.account_fixture().id, now) == []

    period = {~U[2026-09-21 12:06:00.000000Z], ~U[2026-09-21 12:08:00.000000Z]}
    historical = CacheVolumes.storage_history(account.id, period)
    assert Enum.map(historical, & &1.used_bytes) == [2048, 2048]
    assert hd(historical).at == elem(period, 0)
    assert List.last(historical).at == elem(period, 1)
    assert CacheVolumes.storage_history(account.id, {~U[2026-08-01 00:00:00Z], ~U[2026-08-02 00:00:00Z]}) == []
  end

  test "storage history sums concurrent copies and preserves entirely unmeasured fields", %{job: job, account: account} do
    now = ~U[2026-09-22 12:30:00.000000Z]
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    {:ok, second} = CacheVolumes.allocate_for_job(job, identity(), attrs("second"))
    Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, first.id), inserted_at: ~U[2026-09-22 10:00:00Z]))
    Repo.update!(Ecto.Changeset.change(Repo.get!(Usage, second.id), inserted_at: ~U[2026-09-22 11:00:00Z]))

    Repo.insert!(%Measurement{
      usage_id: first.id,
      observed_at: ~U[2026-09-22 10:05:00.000000Z],
      size_bytes: nil,
      capacity_bytes: 8192
    })

    Repo.insert!(%Measurement{
      usage_id: first.id,
      observed_at: ~U[2026-09-22 11:05:00.000000Z],
      size_bytes: 1024,
      capacity_bytes: 8192
    })

    Repo.insert!(%Measurement{
      usage_id: second.id,
      observed_at: ~U[2026-09-22 11:10:00.000000Z],
      size_bytes: 2048,
      capacity_bytes: 8192
    })

    points = CacheVolumes.storage_history(account.id, now)
    assert Enum.map(points, & &1.volumes) == [1, 1, 1]
    assert Enum.map(points, & &1.used_bytes) == [nil, 3072, 3072]
    assert Enum.map(points, & &1.capacity_bytes) == [8192, 16_384, 16_384]
  end

  test "volume history includes unmeasured allocations without treating missing sizes as zero", %{
    job: job,
    account: account
  } do
    {:ok, _} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    points = CacheVolumes.storage_history(account.id)
    assert List.last(points).volumes == 1
    assert is_nil(List.last(points).used_bytes)
    assert is_nil(List.last(points).capacity_bytes)
  end

  test "invalid reports leave size history unchanged and pruning follows usage retention", %{job: job, account: account} do
    {:ok, clone} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    id = volume(account).id
    CacheVolumes.report("node", clone.id, report("active", false))
    assert {:error, :invalid_report} = CacheVolumes.report("node", clone.id, %{report() | "size_bytes" => -1})
    assert [_] = CacheVolumes.size_history(account.id, id)
    use = Repo.get!(Usage, clone.id)
    Repo.update!(Ecto.Changeset.change(use, deleted_at: DateTime.add(DateTime.utc_now(), -91 * 86_400)))
    CacheVolumes.prune_history()
    assert [] = CacheVolumes.size_history(account.id, id)
  end
end
