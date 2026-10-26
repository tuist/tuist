defmodule Tuist.Runners.DockerCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.DockerCache
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

  test "lists each repository's data root with the images its saved head keeps" do
    account = AccountsFixtures.account_fixture()
    saved = volume(account, "org/android")
    waiting = volume(account, "org/web")
    _custom = volume(account, "org/android", "gradle")

    head =
      volume_use(saved, %{
        status: "published",
        size_bytes: 6_000_000_000,
        finished_at: ~U[2026-10-24 09:00:00.000000Z],
        attached_at: ~U[2026-10-24 08:00:00.000000Z],
        warm: false,
        docker_images: %{
          "images" => [
            %{
              "id" => "sha256:" <> String.duplicate("a", 64),
              "references" => ["ghcr.io/org/build:jdk-21", "ghcr.io/org/build:latest"],
              "size_bytes" => 5_000_000_000,
              "last_used_at" => "2026-10-24T08:00:00Z"
            }
          ],
          "build_cache_bytes" => 1_000
        }
      })

    saved |> Ecto.Changeset.change(head_id: head.id) |> Repo.update!()
    volume_use(saved, %{attached_at: ~U[2026-10-24 11:00:00.000000Z], warm: true})
    volume_use(saved, %{attached_at: ~U[2026-10-01 11:00:00.000000Z], warm: true})

    assert [%{repository: "org/android"} = android, %{repository: "org/web"}] =
             DockerCache.repositories(account.id, @period)

    assert android.status == :ready
    assert android.image_count == 1
    assert android.saved_bytes == 6_000_000_000
    assert android.build_cache_bytes == 1_000
    assert android.last_saved_at == ~U[2026-10-24 09:00:00.000000Z]
    assert {android.uses, android.hits, android.hit_rate} == {2, 1, 50.0}
    assert [%{reference: "ghcr.io/org/build:jdk-21", other_references: ["ghcr.io/org/build:latest"]}] = android.images
    analytics = DockerCache.analytics(account.id, nil, @period)
    assert analytics.activity.uses == 2
    assert analytics.activity.hit_rate == 50.0
    assert %{reused_ms: nil, cold_ms: nil, points: [_ | _]} = analytics.steps

    assert %{status: :waiting, images: []} = DockerCache.repository(account.id, waiting.id, @period)
  end

  test "counts a job whose guest could not mount the saved data root as a miss" do
    account = AccountsFixtures.account_fixture()
    saved = volume(account, "org/android")
    volume_use(saved, %{attached_at: ~U[2026-10-24 11:00:00.000000Z], warm: true})

    volume_use(saved, %{
      attached_at: ~U[2026-10-24 12:00:00.000000Z],
      warm: true,
      docker_images: %{"images" => [], "build_cache_bytes" => 0, "reset" => true}
    })

    assert %{uses: 2, hit_rate: 50.0} = DockerCache.analytics(account.id, nil, @period).activity
    assert [%{uses: 2, hits: 1}] = DockerCache.repositories(account.id, @period)
  end

  test "never reads another account's data root" do
    account = AccountsFixtures.account_fixture()
    other = volume(AccountsFixtures.account_fixture(), "other/repo")
    assert DockerCache.repositories(account.id, @period) == []
    assert is_nil(DockerCache.repository(account.id, other.id, @period))
  end
end
