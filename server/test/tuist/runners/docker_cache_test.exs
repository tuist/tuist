defmodule Tuist.Runners.DockerCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.DockerCache
  alias Tuist.Runners.JobSteps
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @period {~U[2026-10-18 00:00:00Z], ~U[2026-10-25 00:00:00Z]}

  defp volume(account, repository, key \\ "docker") do
    Repo.insert!(%Volume{
      account_id: account.id,
      repository_id: System.unique_integer([:positive]),
      scope_id: Integer.to_string(System.unique_integer([:positive])),
      repository: repository,
      key: key,
      architecture: "amd64",
      uid: 0,
      last_used_at: ~U[2026-10-24 10:00:00.000000Z]
    })
  end

  defp volume_use(volume, attrs) do
    Repo.insert!(
      struct(
        Usage,
        Map.merge(
          %{
            volume_id: volume.id,
            generation: volume.generation,
            pod_name: "pod",
            pod_uid: Ecto.UUID.generate(),
            node_name: "node",
            workflow_job_id: System.unique_integer([:positive]),
            workflow_run_id: 1,
            can_publish: true
          },
          attrs
        )
      )
    )
  end

  defp save(volume, images) do
    head =
      volume_use(volume, %{
        status: "published",
        finished_at: ~U[2026-10-24 09:00:00.000000Z],
        docker_images: %{"images" => images, "build_cache_bytes" => 0}
      })

    volume |> Ecto.Changeset.change(head_id: head.id) |> Repo.update!()
  end

  defp initialize_containers(account, use, ms) do
    JobSteps.record([
      %{
        workflow_job_id: use.workflow_job_id,
        account_id: account.id,
        number: 2,
        name: "Initialize containers",
        status: "completed",
        conclusion: "success",
        started_at: ~U[2026-10-24 11:00:00.000000Z],
        completed_at: DateTime.add(~U[2026-10-24 11:00:00.000000Z], ms, :millisecond)
      }
    ])
  end

  test "names the saved images by the first tag jobs used, or by repository and short digest" do
    account = AccountsFixtures.account_fixture()
    saved = volume(account, "org/app")

    save(saved, [
      %{
        "id" => "sha256:" <> String.duplicate("a", 64),
        "references" => ["ghcr.io/org/build:jdk-21", "ghcr.io/org/build:latest"],
        "size_bytes" => 5_000_000_000,
        "last_used_at" => "2026-10-24T08:00:00Z"
      },
      %{
        "id" => "sha256:" <> String.duplicate("c", 64),
        "references" => ["localhost:5000/team/app@sha256:" <> String.duplicate("b", 64)],
        "size_bytes" => 1
      }
    ])

    assert [
             %{name: "ghcr.io/org/build:jdk-21", size_bytes: 5_000_000_000, last_used_at: ~U[2026-10-24 08:00:00Z]},
             %{name: "localhost:5000/team/app@sha256:bbbbbbbbbbbb"}
           ] = DockerCache.images(account.id, saved.id)
  end

  test "has no images while nothing is saved, after a clear, or for another account" do
    account = AccountsFixtures.account_fixture()
    waiting = volume(account, "org/web")
    cleared = volume(account, "org/old")
    save(cleared, [%{"id" => "sha256:" <> String.duplicate("a", 64), "references" => ["postgres:16"], "size_bytes" => 1}])
    cleared |> Ecto.Changeset.change(deleted_at: ~U[2026-10-24 12:00:00.000000Z]) |> Repo.update!()
    other = volume(AccountsFixtures.account_fixture(), "other/repo")
    save(other, [%{"id" => "sha256:" <> String.duplicate("a", 64), "references" => ["postgres:16"], "size_bytes" => 1}])

    assert DockerCache.images(account.id, waiting.id) == []
    assert DockerCache.images(account.id, cleared.id) == []
    assert DockerCache.images(account.id, other.id) == []
  end

  test "times Initialize containers separately for jobs from saved images and cold ones" do
    account = AccountsFixtures.account_fixture()
    saved = volume(account, "org/app")
    attached = ~U[2026-10-24 11:00:00.000000Z]
    reused = volume_use(saved, %{attached_at: attached, warm: true})
    cold = volume_use(saved, %{attached_at: attached, warm: false})
    # A saved data root the guest could not mount started empty: cold.
    reset = volume_use(saved, %{attached_at: attached, warm: true, docker_images: %{"images" => [], "reset" => true}})

    initialize_containers(account, reused, 3_000)
    initialize_containers(account, cold, 40_000)
    initialize_containers(account, reset, 50_000)

    steps = DockerCache.steps(account.id, saved.id, @period)

    assert %{avg: 3_000, p50: 3_000, p99: 3_000} = steps.reused
    assert %{avg: 45_000, p50: 40_000, p99: 50_000} = steps.cold
    assert [%{avg: 3_000}] = Enum.reject(steps.points, &is_nil(&1.avg))
    assert %{reused: %{avg: nil}} = DockerCache.steps(account.id, volume(account, "org/web").id, @period)
  end
end
