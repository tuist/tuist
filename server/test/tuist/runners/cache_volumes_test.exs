defmodule Tuist.Runners.CacheVolumesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.Workers.ExecutionLookupWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Environment, :runner_cache_volumes_enabled?, fn _ -> true end)
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

  defp publish_report(node, id, sizes \\ %{}) do
    usage = Repo.get!(Usage, id)
    digest = :sha |> :crypto.hash(id) |> Base.encode16(case: :lower)
    content = :sha256 |> :crypto.hash(id) |> Base.encode16(case: :lower)

    if usage.status != "published" do
      CacheVolumes.image(node, id, %{"operation" => "publish", "image_digest" => digest, "content_digest" => content})
    end

    CacheVolumes.report(node, id, Map.merge(report("sealed"), sizes))
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

  defp main_identity, do: Map.merge(identity(), %{default_branch: "main", writer_branch: "main"})

  defp branch_identity(branch), do: Map.merge(main_identity(), %{trusted: false, writer_branch: branch})

  defp set_policy(profile, attrs) do
    {:ok, profile} = Profiles.update(Repo.get!(Profile, profile.id), attrs)
    profile
  end

  test "allocations carry the size the host creates the volume at", %{job: job} do
    assert {:ok, %{volume_bytes: 20_000_000_000}} = CacheVolumes.allocate_for_job(job, identity(), attrs("custom"))

    assert {:ok, %{volume_bytes: 30_000_000_000}} =
             CacheVolumes.allocate_for_job(job, identity(), Map.put(attrs("xcode"), :key, "tuist-xcode"))
  end

  test "Linux allocation remains idempotent with the platform conflict target", %{job: job} do
    {:ok, use} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    volume = Repo.get!(Volume, Repo.get!(Usage, use.id).volume_id)
    fields = [:account_id, :provider, :provider_instance, :scope_id, :key, :platform, :architecture, :uid]

    row =
      volume
      |> Map.take(fields ++ [:repository_id, :repository, :inserted_at, :updated_at])
      |> Map.put(:id, Ecto.UUID.generate())

    assert {0, _} = Repo.insert_all(Volume, [row], on_conflict: :nothing, conflict_target: fields)
    assert Repo.get!(Volume, volume.id).platform == "linux"
  end

  test "macOS identities are separate while existing Linux UUIDs and built-in heads survive", %{
    job: job,
    account: account
  } do
    {:ok, linux} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    builtin = VolumeHeads.reserved_tuist_cache()
    assert {:ok, _} = VolumeHeads.bump_head(account.id, "node", String.duplicate("a", 40), 0, builtin)
    {:ok, mac} = CacheVolumes.allocate_for_job(job, identity(), Map.put(attrs(), :platform, "macos"))
    refute mac.scope == linux.scope
    assert length(CacheVolumes.list(account.id).volumes) == 2
    mac_volume = Repo.get!(Volume, Repo.get!(Usage, mac.id).volume_id)
    assert mac_volume.platform == "macos"
    assert String.starts_with?(CacheVolumes.storage_name(mac_volume), "macos-")
    assert VolumeHeads.valid_storage_volume_name?(CacheVolumes.storage_name(mac_volume))
    refute VolumeHeads.valid_volume_name?(CacheVolumes.storage_name(mac_volume))
    {:ok, again} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    assert again.id == linux.id
    assert {:ok, _} = CacheVolumes.report("node", mac.id, report())
    complete(job)
    assert {:ok, %{action: "seal"}} = CacheVolumes.report("node", mac.id, report())
    CacheVolumes.delete(account.id, mac_volume.id)

    assert {:error, :conflict} =
             CacheVolumes.image("node", mac.id, %{
               "operation" => "publish",
               "image_digest" => String.duplicate("b", 40),
               "content_digest" => String.duplicate("c", 64)
             })

    assert VolumeHeads.get_head(account.id, builtin).generation == 1
  end

  test "allocation derives macOS from the executed session, ignoring guest platform", %{account: account, job: job} do
    Repo.insert!(%Buildkite.Installation{
      account_id: account.id,
      organization_slug: "org",
      stack_key: "mac-#{account.id}",
      agent_token: "test"
    })

    Repo.insert!(%Buildkite.Job{
      account_id: account.id,
      job_uuid: Ecto.UUID.generate(),
      workflow_job_id: job.workflow_job_id,
      build_uuid: Ecto.UUID.generate(),
      build_number: 42,
      organization_slug: "org",
      pipeline_slug: "pipeline",
      queue_key: "queue",
      cache_volume_identity: %{
        "provider" => "buildkite",
        "provider_instance" => "org-id",
        "scope_id" => "pipeline-id",
        "trusted" => true
      }
    })

    Repo.insert!(
      struct(
        WorkflowJob,
        Map.merge(job, %{provider: "buildkite", status: "running", fleet_name: "macos", enqueued_at: DateTime.utc_now()})
      )
    )

    session =
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: job.workflow_job_id,
        executed_workflow_job_id: job.workflow_job_id,
        fleet_name: "macos",
        pod_name: "mac-pod",
        node_name: "mac-node",
        platform: :macos,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: DateTime.utc_now()
      })

    params = %{
      "pod_name" => "mac-pod",
      "pod_uid" => "mac-uid",
      "node_name" => "mac-node",
      "key" => "gradle",
      "architecture" => "arm64",
      "uid" => 501,
      "platform" => "linux"
    }

    expect(Environment, :runner_cache_volumes_enabled?, fn :macos -> false end)
    assert {:error, :unavailable} = CacheVolumes.allocate(params)
    expect(Environment, :runner_cache_volumes_enabled?, fn :macos -> true end)
    assert {:ok, use} = CacheVolumes.allocate(params)
    assert Repo.get!(Volume, Repo.get!(Usage, use.id).volume_id).platform == "macos"
    Repo.update!(Ecto.Changeset.change(session, ended_at: DateTime.utc_now()))
    assert {:error, :unavailable} = CacheVolumes.allocate(params)
  end

  test "the executed binding admits a job whose own row has not reached running yet", %{account: account, job: job} do
    Repo.insert!(%Buildkite.Installation{
      account_id: account.id,
      organization_slug: "org",
      stack_key: "linux-#{account.id}",
      agent_token: "test"
    })

    Repo.insert!(%Buildkite.Job{
      account_id: account.id,
      job_uuid: Ecto.UUID.generate(),
      workflow_job_id: job.workflow_job_id,
      build_uuid: Ecto.UUID.generate(),
      build_number: 42,
      organization_slug: "org",
      pipeline_slug: "pipeline",
      queue_key: "queue",
      cache_volume_identity: %{
        "provider" => "buildkite",
        "provider_instance" => "org-id",
        "scope_id" => "pipeline-id",
        "trusted" => true
      }
    })

    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      executed_workflow_job_id: job.workflow_job_id,
      fleet_name: "linux",
      pod_name: "displaced-pod",
      node_name: "node",
      platform: :linux,
      vcpus: 2,
      memory_gb: 8,
      billing_multiplier: 10_000,
      started_at: DateTime.utc_now()
    })

    params = %{
      "pod_name" => "displaced-pod",
      "pod_uid" => "displaced-uid",
      "node_name" => "node",
      "key" => "gradle",
      "architecture" => "amd64",
      "uid" => 1001
    }

    assert {:error, :pending} = CacheVolumes.allocate(params)
    refute_enqueued(worker: ExecutionLookupWorker)

    row =
      Repo.insert!(
        struct(
          WorkflowJob,
          Map.merge(job, %{
            provider: "buildkite",
            status: "claimed",
            pod_name: "other-pod",
            fleet_name: "linux",
            enqueued_at: DateTime.utc_now()
          })
        )
      )

    assert {:ok, _} = CacheVolumes.allocate(params)

    row = Repo.update!(Ecto.Changeset.change(row, status: "queued", pod_name: nil))
    assert {:ok, _} = CacheVolumes.allocate(params)

    Repo.update!(Ecto.Changeset.change(row, status: "completed"))
    assert {:error, :unavailable} = CacheVolumes.allocate(params)
  end

  for platform <- [:linux, :macos] do
    @session_platform platform
    test "only an open #{@session_platform} session waiting for execution attribution is retryable", %{
      account: account,
      job: job
    } do
      session =
        Repo.insert!(%RunnerSession{
          account_id: account.id,
          workflow_job_id: job.workflow_job_id,
          fleet_name: "linux",
          pod_name: "pending-pod",
          node_name: "node",
          platform: @session_platform,
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

      expect(Environment, :runner_cache_volumes_enabled?, fn platform ->
        assert platform == @session_platform
        false
      end)

      assert {:error, :unavailable} = CacheVolumes.allocate(params)
      assert {:error, :pending} = CacheVolumes.allocate(params)
      assert_enqueued(worker: ExecutionLookupWorker, args: %{session_id: session.id})
      assert {:error, :unavailable} = CacheVolumes.allocate(%{params | "node_name" => "other"})
      assert {:error, :unavailable} = CacheVolumes.allocate(%{params | "pod_name" => "unknown"})
      assert CacheVolumes.list(account.id).volumes == []

      Repo.update!(Ecto.Changeset.change(session, ended_at: DateTime.utc_now()))
      assert {:error, :unavailable} = CacheVolumes.allocate(params)
    end
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

  test "local replicas validate against the current head after private branches are reclaimed, from any host", %{
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
    assert {:ok, %{generation: 2}} = CacheVolumes.image("other-node", next.id, %{"operation" => "retain"})
    CacheVolumes.delete(account.id, volume(account).id)
    assert {:error, :conflict} = CacheVolumes.image("node", next.id, %{"operation" => "retain"})
  end

  test "a host refreshes a stale local master to the current head", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    assert {:ok, _} = CacheVolumes.report("node", first.id, %{"state" => "deleted"})
    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next", "other-node"))
    assert {:ok, %{action: "keep"}} = publish_report("other-node", next.id)
    head = Repo.get!(Usage, next.id)
    name = CacheVolumes.storage_name(volume(account))

    expect(Runners, :volume_master_download_url, 2, fn account_id, ^name, digest, content ->
      assert {account_id, digest, content} == {account.id, head.image_digest, head.content_digest}
      {:ok, "https://1.1.1.1/image"}
    end)

    assert {:ok, %{generation: 2, image_digest: image_digest, content_digest: content_digest}} =
             CacheVolumes.image("node", first.id, %{"operation" => "retain"})

    assert image_digest == head.image_digest
    assert content_digest == head.content_digest

    assert {:ok, %{generation: 2, content_digest: ^content_digest, download_url: "https://1.1.1.1/image"}} =
             CacheVolumes.image("node", first.id, %{"operation" => "download", "generation" => 2})

    assert {:error, :conflict} = CacheVolumes.image("node", first.id, %{"operation" => "download", "generation" => 3})
    assert {:error, :conflict} = CacheVolumes.image("node", first.id, %{"operation" => "download", "generation" => 1})

    assert {:ok, %{generation: 2, download_url: "https://1.1.1.1/image"}} =
             CacheVolumes.image("third-node", first.id, %{"operation" => "download", "generation" => 2})

    assert {:error, :not_found} =
             CacheVolumes.image("third-node", first.id, %{
               "operation" => "upload",
               "image_digest" => String.duplicate("b", 40),
               "content_digest" => String.duplicate("c", 64)
             })

    CacheVolumes.delete(account.id, volume(account).id)
    assert {:error, :conflict} = CacheVolumes.image("node", first.id, %{"operation" => "download", "generation" => 2})
  end

  test "lists the saved heads of macOS custom volumes used on the given hosts", %{job: job, account: account} do
    {:ok, linux} = CacheVolumes.allocate_for_job(job, identity(), attrs("linux"))
    {:ok, mac} = CacheVolumes.allocate_for_job(job, identity(), Map.put(attrs("mac"), :platform, "macos"))

    {:ok, unsaved} =
      CacheVolumes.allocate_for_job(job, identity(), Map.put(%{attrs("unsaved") | key: "other"}, :platform, "macos"))

    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", linux.id)
    assert {:ok, %{action: "keep"}} = publish_report("node", mac.id)
    since = DateTime.add(DateTime.utc_now(), -60, :second)
    published = Repo.get!(Usage, mac.id)
    mac_volume = Repo.get!(Volume, published.volume_id)
    scope = CacheVolumes.scope(mac_volume)
    account_id = account.id

    assert [
             %{
               kind: "custom",
               id: id,
               account_id: ^account_id,
               scope: ^scope,
               generation: 1,
               image_digest: image_digest,
               content_digest: content_digest,
               volume_bytes: 20_000_000_000
             }
           ] = CacheVolumes.recent_macos_heads(["other-node", "node"], since, 8)

    assert {id, image_digest, content_digest} == {mac.id, published.image_digest, published.content_digest}
    refute Repo.get!(Usage, unsaved.id).status == "published"
    assert [] = CacheVolumes.recent_macos_heads(["other-node"], since, 8)
    assert [] = CacheVolumes.recent_macos_heads(["node"], DateTime.add(DateTime.utc_now(), 60, :second), 8)

    CacheVolumes.delete(account.id, mac_volume.id)
    assert [] = CacheVolumes.recent_macos_heads(["node"], since, 8)
  end

  test "records the older generation a host mounted, and only that", %{job: job} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    {:ok, second} = CacheVolumes.allocate_for_job(job, identity(), attrs("second"))
    assert {:ok, %{action: "keep"}} = publish_report("node", second.id)
    {:ok, stale} = CacheVolumes.allocate_for_job(job, identity(), attrs("stale"))
    {:ok, current} = CacheVolumes.allocate_for_job(job, identity(), attrs("current"))
    assert stale.base_generation == 2

    assert {:ok, _} = CacheVolumes.report("node", stale.id, Map.put(report("active", false), "mounted_generation", 1))
    assert {:ok, _} = CacheVolumes.report("node", stale.id, Map.put(report("active", false), "mounted_generation", 0))
    assert %Usage{mounted_generation: 1} = stale = Repo.get!(Usage, stale.id)
    assert CacheVolumes.older_copy?(stale)

    for generation <- [2, 5, "1"] do
      assert {:ok, _} =
               CacheVolumes.report("node", current.id, Map.put(report("active", false), "mounted_generation", generation))
    end

    assert %Usage{mounted_generation: nil} = current = Repo.get!(Usage, current.id)
    refute CacheVolumes.older_copy?(current)
  end

  test "a job's download keeps its own base after the head advances", %{job: job, account: account} do
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("first"))
    complete(job)
    assert {:ok, %{action: "keep"}} = publish_report("node", first.id)
    {:ok, live} = CacheVolumes.allocate_for_job(job, identity(), attrs("live"))
    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next", "other-node"))
    assert {:ok, %{action: "keep"}} = publish_report("other-node", next.id)
    name = CacheVolumes.storage_name(volume(account))
    assert %{generation: 2} = VolumeHeads.get_head(account.id, name)

    expect(Runners, :volume_master_download_url, fn _account_id, ^name, digest, content ->
      assert {digest, content} == {live.image_digest, live.content_digest}
      {:ok, "https://1.1.1.1/image"}
    end)

    assert {:ok, %{generation: 1, download_url: "https://1.1.1.1/image"}} =
             CacheVolumes.image("node", live.id, %{"operation" => "download", "generation" => 1})
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

  defp report_size(node, id, size, capacity \\ 2048),
    do:
      CacheVolumes.report(
        node,
        id,
        Map.merge(report("active", false), %{"size_bytes" => size, "capacity_bytes" => capacity})
      )

  test "a nearly full saved snapshot that a clone ran out of space on starts a fresh lineage", %{
    job: job,
    account: account
  } do
    {:ok, full} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    {:ok, running} = CacheVolumes.allocate_for_job(job, identity(), attrs("running"))
    complete(job)
    publish_report("node", full.id, %{"size_bytes" => 1639, "capacity_bytes" => 2048})
    {:ok, filled} = CacheVolumes.allocate_for_job(job, identity(), attrs("filled"))
    assert filled.parent_id == full.id
    assert {:ok, %{action: "hold"}} = report_size("node", filled.id, 2028)

    {:ok, fresh} = CacheVolumes.allocate_for_job(job, identity(), attrs("fresh"))

    assert is_nil(fresh.parent_id)
    assert fresh.base_generation == 0
    refute fresh.scope == full.scope
    assert is_nil(volume(account).head_id)
    assert {:ok, %{action: "delete"}} = publish_report("node", running.id)
    assert {:ok, %{action: "seal"}} = CacheVolumes.report("node", fresh.id, report())
  end

  test "a nearly full saved snapshot keeps chaining warm while its clones have room", %{job: job} do
    complete(job)
    {:ok, first} = CacheVolumes.allocate_for_job(job, identity(), attrs("job-0"))
    publish_report("node", first.id, %{"size_bytes" => 1741, "capacity_bytes" => 2048})

    Enum.reduce(1..4, first, fn n, parent ->
      {:ok, use} = CacheVolumes.allocate_for_job(job, identity(), attrs("job-#{n}"))
      assert use.parent_id == parent.id
      assert use.base_generation > 0
      assert use.scope == first.scope
      assert {:ok, %{action: "keep"}} = publish_report("node", use.id, %{"size_bytes" => 1741, "capacity_bytes" => 2048})
      use
    end)
  end

  test "a saved snapshot below the fill limit stays the parent even when a clone ran out of space", %{job: job} do
    {:ok, saved} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", saved.id, %{"size_bytes" => 1638, "capacity_bytes" => 2048})
    {:ok, filled} = CacheVolumes.allocate_for_job(job, identity(), attrs("filled"))
    report_size("node", filled.id, 2048)

    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next"))

    assert next.parent_id == saved.id
    assert next.scope == saved.scope
  end

  test "a clone that stayed below the out-of-space limit keeps the saved snapshot", %{job: job} do
    {:ok, saved} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", saved.id, %{"size_bytes" => 1900, "capacity_bytes" => 2048})
    {:ok, roomy} = CacheVolumes.allocate_for_job(job, identity(), attrs("roomy"))
    report_size("node", roomy.id, 2027)

    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next"))

    assert next.parent_id == saved.id
  end

  test "a saved snapshot with unknown size stays the parent", %{job: job} do
    {:ok, saved} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    complete(job)
    publish_report("node", saved.id, %{"size_bytes" => nil, "capacity_bytes" => nil})

    {:ok, next} = CacheVolumes.allocate_for_job(job, identity(), attrs("next"))

    assert next.parent_id == saved.id
  end

  test "statistics report the saved snapshot's size separately from retained copies", %{job: job, account: account} do
    {:ok, saved} = CacheVolumes.allocate_for_job(job, identity(), attrs())
    {:ok, _clone} = CacheVolumes.allocate_for_job(job, identity(), attrs("clone"))
    complete(job)
    publish_report("node", saved.id, %{"size_bytes" => 1700, "capacity_bytes" => 2048})
    id = volume(account).id

    assert %{saved_bytes: 1700, saved_capacity_bytes: 2048} = CacheVolumes.statistics([id])[id]
    assert CacheVolumes.full?(1639, 2048)
    refute CacheVolumes.full?(1638, 2048)
    refute CacheVolumes.full?(nil, 2048)
    refute CacheVolumes.full?(1024, 0)
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

  describe "runner profile writer policy" do
    setup %{account: account, job: job} do
      other_account = AccountsFixtures.account_fixture()
      stub(Catalog, :shapes, fn _ -> [%{vcpus: 4, memory_gb: 16}] end)

      # Limited to the default branch, so each test can widen it explicitly.
      profile =
        Repo.insert!(%Profile{
          account_id: account.id,
          name: "ci-#{System.unique_integer([:positive])}",
          platform: :linux,
          vcpus: 4,
          memory_gb: 16,
          cache_writer_all_branches: false
        })

      %{
        profile: profile,
        other_account: other_account,
        job: Map.put(job, :requested_dispatch_label, Profile.dispatch_label(profile))
      }
    end

    test "by default every successful job from the repository saves, forks never", %{job: job, account: account} do
      profile =
        Repo.insert!(%Profile{account_id: account.id, name: "default-policy", platform: :linux, vcpus: 4, memory_gb: 16})

      job = %{job | requested_dispatch_label: Profile.dispatch_label(profile)}

      for {identity, pod} <- [
            {main_identity(), "main"},
            {branch_identity("feature/x"), "feature"},
            {branch_identity("release/1.0"), "release"}
          ] do
        assert {:ok, %{can_publish: true}} = CacheVolumes.allocate_for_job(job, identity, attrs(pod))
      end

      fork = %{branch_identity("feature/x") | same_repository: false, writer_branch: nil}
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, fork, attrs("fork"))

      assert {:ok, %{can_publish: false}} =
               CacheVolumes.allocate_for_job(job, branch_identity(nil), attrs("pull-request-target"))
    end

    test "limiting a profile to specific branches revokes pending saves from other branches", %{
      job: job,
      account: account
    } do
      profile =
        Repo.insert!(%Profile{account_id: account.id, name: "limited", platform: :linux, vcpus: 4, memory_gb: 16})

      job = %{job | requested_dispatch_label: Profile.dispatch_label(profile)}
      {:ok, main} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("main"))
      {:ok, feature} = CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("feature"))
      assert main.can_publish and feature.can_publish

      set_policy(profile, %{cache_writer_all_branches: false})

      assert Repo.get!(Usage, main.id).can_publish
      refute Repo.get!(Usage, feature.id).can_publish

      assert {:ok, %{can_publish: false}} =
               CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("feature-again"))
    end

    test "jobs without a profile follow the default policy", %{job: job} do
      for label <- ["shape-linux-4vcpu-16gb", ""] do
        legacy = %{job | requested_dispatch_label: label}

        assert {:ok, %{can_publish: true}} =
                 CacheVolumes.allocate_for_job(legacy, branch_identity("feature"), attrs("feature-#{label}"))

        fork = %{branch_identity("feature") | same_repository: false, writer_branch: nil}
        assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(legacy, fork, attrs("fork-#{label}"))
      end
    end

    test "deleting a narrowed profile falls back to the default policy", %{job: job, profile: profile} do
      {:ok, feature} = CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("feature"))
      refute feature.can_publish
      {:ok, release} = CacheVolumes.allocate_for_job(job, branch_identity("release"), attrs("release"))
      profile = set_policy(profile, %{cache_writer_branches: ["release"]})
      {:ok, release_again} = CacheVolumes.allocate_for_job(job, branch_identity("release"), attrs("release-again"))
      assert release_again.can_publish
      refute Repo.get!(Usage, release.id).can_publish

      assert {:ok, _} = Profiles.delete(profile)

      assert Repo.get!(Usage, release_again.id).can_publish
      assert {:ok, %{can_publish: true}} = CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("after"))
    end

    test "a profile narrowed to the default branch saves only that branch", %{
      job: job,
      account: account,
      profile: profile
    } do
      assert {:ok, %{can_publish: true} = main} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("main"))

      assert %{writer_profile_id: profile_id, writer_default_branch: true, writer_branch: "main"} =
               Repo.get!(Usage, main.id)

      assert profile_id == profile.id
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("pr"))

      legacy = %{job | requested_dispatch_label: "shape-linux-4vcpu-16gb"}

      assert {:ok, %{can_publish: true} = legacy_use} =
               CacheVolumes.allocate_for_job(legacy, main_identity(), attrs("legacy"))

      assert is_nil(Repo.get!(Usage, legacy_use.id).writer_profile_id)

      assert volume(account).default_branch == "main"
    end

    test "a matching verified branch saves only when its job succeeds", %{
      job: job,
      account: account,
      profile: profile
    } do
      branch_identity = branch_identity("codex/volume-test")
      requested = attrs()
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, branch_identity, requested)
      set_policy(profile, %{cache_writer_branches: ["codex/volume-test"]})
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, branch_identity, requested)

      assert {:ok, %{can_publish: true} = permitted} =
               CacheVolumes.allocate_for_job(job, branch_identity, attrs("new"))

      assert Repo.get!(Usage, permitted.id).writer_profile_id == profile.id

      fork = %{branch_identity | same_repository: false, writer_branch: nil}
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, fork, attrs("fork"))
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, branch_identity("other"), attrs("other"))

      complete(job, "failure")
      assert {:ok, %{action: "delete"}} = publish_report("node", permitted.id)
      assert is_nil(volume(account).head_id)
    end

    test "additional branches match * patterns and the default branch can be turned off", %{job: job, profile: profile} do
      set_policy(profile, %{cache_writer_branches: ["release/*"]})
      assert {:ok, %{can_publish: true}} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("main"))

      assert {:ok, %{can_publish: true}} =
               CacheVolumes.allocate_for_job(job, branch_identity("release/1.0"), attrs("release"))

      assert {:ok, %{can_publish: false}} =
               CacheVolumes.allocate_for_job(job, branch_identity("releases"), attrs("releases"))

      set_policy(profile, %{cache_writer_default_branch: false})
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("off-main"))

      assert {:ok, %{can_publish: true}} =
               CacheVolumes.allocate_for_job(job, branch_identity("release/2.0"), attrs("off-release"))

      set_policy(profile, %{cache_writer_branches: ["*"]})

      for {identity, pod} <- [{main_identity(), "any-main"}, {branch_identity("feature/x"), "any-feature"}] do
        assert {:ok, %{can_publish: true}} = CacheVolumes.allocate_for_job(job, identity, attrs(pod))
      end

      assert {:ok, %{can_publish: false}} =
               CacheVolumes.allocate_for_job(job, branch_identity(nil), attrs("pull-request-target"))

      set_policy(profile, %{cache_writer_branches: []})
      assert is_nil(Repo.get!(Profile, profile.id).cache_writer_branches)
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("none"))
    end

    test "jobs outside the profile follow the default policy, not the profile's", %{
      job: job,
      profile: profile,
      other_account: other
    } do
      set_policy(profile, %{cache_writer_default_branch: false, cache_writer_branches: nil})
      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("profile"))

      for {label, pod} <- [{"shape-linux-4vcpu-16gb", "legacy"}, {"", "unlabelled"}] do
        assert {:ok, %{can_publish: true}} =
                 CacheVolumes.allocate_for_job(
                   %{job | requested_dispatch_label: label},
                   branch_identity("feature"),
                   attrs(pod)
                 )
      end

      other_job = %{job | account_id: other.id, workflow_job_id: System.unique_integer([:positive])}

      assert {:ok, %{can_publish: true}} =
               CacheVolumes.allocate_for_job(other_job, branch_identity("feature"), attrs("other-account"))

      buildkite =
        Map.merge(branch_identity("feature"), %{provider: "buildkite", provider_instance: "org", scope_id: "pipeline"})

      assert {:ok, %{can_publish: false}} = CacheVolumes.allocate_for_job(job, buildkite, attrs("buildkite"))
    end

    test "narrowing the policy revokes pending saves it no longer allows", %{job: job, profile: profile} do
      set_policy(profile, %{cache_writer_branches: ["*"]})
      {:ok, main} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("main"))
      {:ok, feature} = CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("feature"))
      {:ok, release} = CacheVolumes.allocate_for_job(job, branch_identity("release/1.0"), attrs("release"))

      set_policy(profile, %{cache_writer_branches: ["feature", "release/*"]})
      assert Repo.get!(Usage, main.id).can_publish
      assert Repo.get!(Usage, feature.id).can_publish
      assert Repo.get!(Usage, release.id).can_publish

      set_policy(profile, %{cache_writer_default_branch: false})
      refute Repo.get!(Usage, main.id).can_publish
      assert Repo.get!(Usage, feature.id).can_publish
      assert Repo.get!(Usage, release.id).can_publish

      set_policy(profile, %{cache_writer_default_branch: true, cache_writer_branches: nil})
      refute Repo.get!(Usage, feature.id).can_publish
      refute Repo.get!(Usage, release.id).can_publish
      {:ok, main} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("main-again"))
      assert main.can_publish
    end

    test "turning off the default branch revokes pending saves allocated before uses recorded their profile", %{
      job: job,
      account: account,
      profile: profile
    } do
      {:ok, legacy} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("legacy"))

      Repo.update!(
        Ecto.Changeset.change(Repo.get!(Usage, legacy.id),
          writer_profile_id: nil,
          writer_branch: nil,
          writer_default_branch: false
        )
      )

      pool_job = %{
        job
        | workflow_job_id: System.unique_integer([:positive]),
          requested_dispatch_label: "shape-linux-4vcpu-16gb"
      }

      {:ok, unrelated} = CacheVolumes.allocate_for_job(pool_job, main_identity(), attrs("pool"))

      for executed <- [job, pool_job] do
        Repo.insert!(%WorkflowJob{
          workflow_job_id: executed.workflow_job_id,
          workflow_run_id: executed.workflow_run_id,
          account_id: account.id,
          fleet_name: "test",
          status: "running",
          requested_dispatch_label: executed.requested_dispatch_label,
          enqueued_at: DateTime.utc_now()
        })
      end

      set_policy(profile, %{cache_writer_branches: ["release/*"]})
      assert Repo.get!(Usage, legacy.id).can_publish

      set_policy(profile, %{cache_writer_default_branch: false})
      refute Repo.get!(Usage, legacy.id).can_publish
      assert Repo.get!(Usage, unrelated.id).can_publish
      complete(job)
      assert {:ok, %{action: "delete"}} = publish_report("node", legacy.id)
    end

    test "additions and reordering keep pending saves; deleting the profile falls back to the default policy",
         %{job: job, account: account, profile: profile} do
      legacy = %{job | requested_dispatch_label: ""}
      {:ok, legacy_main} = CacheVolumes.allocate_for_job(legacy, main_identity(), attrs("legacy-main"))
      {:ok, main} = CacheVolumes.allocate_for_job(job, main_identity(), attrs("main"))
      profile = set_policy(profile, %{cache_writer_branches: ["feature", "retained"]})
      {:ok, removed} = CacheVolumes.allocate_for_job(job, branch_identity("feature"), attrs("removed"))
      {:ok, retained} = CacheVolumes.allocate_for_job(job, branch_identity("retained"), attrs("retained"))

      for branches <- [["retained", "feature"], ["new", "feature", "retained"]] do
        set_policy(profile, %{cache_writer_branches: branches})

        for use <- [legacy_main, main, removed, retained], do: assert(Repo.get!(Usage, use.id).can_publish)
      end

      profile = set_policy(profile, %{cache_writer_branches: ["retained"]})
      refute Repo.get!(Usage, removed.id).can_publish
      assert Repo.get!(Usage, retained.id).can_publish

      assert {:ok, _} = Profiles.delete(profile)
      assert Repo.get!(Usage, legacy_main.id).can_publish
      assert Repo.get!(Usage, main.id).can_publish
      assert Repo.get!(Usage, retained.id).can_publish
      refute Repo.get!(Usage, removed.id).can_publish
      complete(job)
      assert {:ok, %{action: "keep"}} = publish_report("node", main.id)
      assert volume(account).head_id == main.id
    end
  end

  describe "allocate_checkout/1" do
    setup %{account: account, job: job} do
      job = Map.merge(job, %{head_sha: String.duplicate("a", 40), head_branch: "feature"})

      Repo.insert!(
        struct(
          WorkflowJob,
          Map.merge(job, %{provider: "github", status: "running", fleet_name: "macos", enqueued_at: DateTime.utc_now()})
        )
      )

      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: job.workflow_job_id,
        executed_workflow_job_id: job.workflow_job_id,
        fleet_name: "macos",
        pod_name: "mac-pod",
        node_name: "mac-node",
        platform: :macos,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: DateTime.utc_now()
      })

      installation = %{installation_id: "99", client_url: nil}
      stub(FeatureFlags, :runner_cached_checkouts_enabled?, fn _ -> true end)
      stub(VCS, :get_github_app_installation_for_account, fn _ -> {:ok, installation} end)
      stub(VCS, :installation_api_url, fn _ -> "https://api.github.com" end)

      stub(GitHubClient, :get_workflow_run, fn _ ->
        {:ok,
         %{
           "id" => job.workflow_run_id,
           "run_attempt" => job.run_attempt,
           "head_branch" => "main",
           "event" => "push",
           "repository" => %{"id" => 123},
           "head_repository" => %{"id" => 123}
         }}
      end)

      stub(GitHubClient, :get_repository, fn _, _ ->
        {:ok, %{"id" => 123, "full_name" => job.repository, "default_branch" => "main"}}
      end)

      params = %{
        "pod_name" => "mac-pod",
        "pod_uid" => "mac-uid",
        "node_name" => "mac-node",
        "architecture" => "arm64",
        "uid" => 501
      }

      %{job: job, params: params}
    end

    test "allocates the repository's checkout volume with what the host needs to build its master", %{
      account: account,
      job: job,
      params: params
    } do
      assert {:ok, checkout} = CacheVolumes.allocate_checkout(params)

      assert checkout.clone_url == "https://github.com/org/repo"
      assert checkout.default_branch == "main"
      assert checkout.commit == job.head_sha
      refute checkout.default_branch_job
      refute Map.has_key?(checkout, :token)
      assert checkout.generation == Repo.get!(Volume, Repo.get!(Usage, checkout.id).volume_id).generation
      assert volume(account).key == "checkout"
      assert volume(account).platform == "macos"
    end

    test "never lets a use of the checkout volume publish, even from the default branch", %{params: params} do
      assert {:ok, %{can_publish: false} = checkout} = CacheVolumes.allocate_checkout(params)
      refute Repo.get!(Usage, checkout.id).can_publish
    end

    test "marks a job on the default branch", %{job: job, params: params} do
      WorkflowJob |> Repo.get!(job.workflow_job_id) |> Ecto.Changeset.change(head_branch: "main") |> Repo.update!()

      assert {:ok, %{default_branch_job: true}} = CacheVolumes.allocate_checkout(params)
    end

    test "the host publishes its master once, under a use whose job is already gone", %{params: params} do
      {:ok, checkout} = CacheVolumes.allocate_checkout(params)
      assert {:ok, %{action: "delete"}} = CacheVolumes.report("mac-node", checkout.id, report())
      CacheVolumes.report("mac-node", checkout.id, report("deleted"))
      digest = String.duplicate("b", 40)
      content = String.duplicate("c", 64)
      publish = %{"operation" => "publish", "image_digest" => digest, "content_digest" => content}

      assert {:error, :not_found} = CacheVolumes.image("other-node", checkout.id, publish)
      assert {:ok, %{generation: 1}} = CacheVolumes.image("mac-node", checkout.id, publish)
      assert {:ok, %{generation: 1}} = CacheVolumes.image("mac-node", checkout.id, publish)

      assert {:error, :conflict} =
               CacheVolumes.image("mac-node", checkout.id, %{publish | "content_digest" => String.duplicate("d", 64)})

      assert {:ok, %{base_generation: 1, image_digest: ^digest, content_digest: ^content}} =
               CacheVolumes.allocate_checkout(%{params | "pod_uid" => "next-uid"})
    end

    test "a published checkout use releases its branch and is never prefetched", %{params: params} do
      since = DateTime.add(DateTime.utc_now(), -60, :second)
      {:ok, checkout} = CacheVolumes.allocate_checkout(params)

      publish = %{
        "operation" => "publish",
        "image_digest" => String.duplicate("b", 40),
        "content_digest" => String.duplicate("c", 64)
      }

      assert {:ok, %{generation: 1}} = CacheVolumes.image("mac-node", checkout.id, publish)
      assert {:ok, %{action: "delete"}} = CacheVolumes.report("mac-node", checkout.id, report())
      assert [] = CacheVolumes.recent_macos_heads(["mac-node"], since, 8)
    end

    test "follows the setting of the profile the job was dispatched to", %{account: account, job: job, params: params} do
      profile =
        Repo.insert!(%Profile{
          account_id: account.id,
          name: "mac",
          platform: :macos,
          vcpus: 6,
          memory_gb: 14,
          cached_checkouts: false
        })

      WorkflowJob
      |> Repo.get!(job.workflow_job_id)
      |> Ecto.Changeset.change(requested_dispatch_label: Profile.dispatch_label(profile))
      |> Repo.update!()

      assert {:error, :unavailable} = CacheVolumes.allocate_checkout(params)

      profile |> Ecto.Changeset.change(cached_checkouts: true) |> Repo.update!()
      assert {:ok, _} = CacheVolumes.allocate_checkout(params)
    end

    test "is unavailable unless the account has cached checkouts", %{params: params} do
      stub(FeatureFlags, :runner_cached_checkouts_enabled?, fn _ -> false end)
      assert {:error, :unavailable} = CacheVolumes.allocate_checkout(params)
    end

    test "is unavailable for GitHub Enterprise Server installations", %{params: params} do
      stub(VCS, :installation_api_url, fn _ -> "https://ghes.example.com/api/v3" end)
      assert {:error, :unavailable} = CacheVolumes.allocate_checkout(params)
    end

    test "is pending until the executed job is known", %{account: account, params: params} do
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: "macos",
        pod_name: "waiting-pod",
        node_name: "mac-node",
        platform: :macos,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: 10_000,
        started_at: DateTime.utc_now()
      })

      assert {:error, :pending} = CacheVolumes.allocate_checkout(%{params | "pod_name" => "waiting-pod"})
    end

    test "the reserved name cannot be requested as a custom volume", %{params: params} do
      assert {:error, :unavailable} = CacheVolumes.allocate(Map.put(params, "key", "checkout"))
      assert {:ok, _} = CacheVolumes.allocate(Map.put(params, "key", "checkouts"))
    end
  end
end
