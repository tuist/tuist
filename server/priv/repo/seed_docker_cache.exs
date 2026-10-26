# Synthetic Docker cache data for local UI previews, never production measurements.
# Run after the standard seeds with: mix run priv/repo/seed_docker_cache.exs
import Ecto.Query

alias Tuist.Accounts
alias Tuist.Repo
alias Tuist.Runners.CacheVolumes.Measurement
alias Tuist.Runners.CacheVolumes.Usage
alias Tuist.Runners.CacheVolumes.Volume
alias Tuist.Runners.JobSteps
alias Tuist.Runners.WorkflowJob

if Mix.env() != :dev, do: raise("Docker cache seeds are only supported in development")

organization = Accounts.get_organization_by_handle("tuist") || raise "Run priv/repo/seeds.exs first"
account_id = organization.account.id
now = DateTime.utc_now()
gb = 1_000_000_000

image = fn id, references, size, hours_ago ->
  digest = "sha256:" <> String.duplicate(id <> "0", 32)
  name = references |> hd() |> String.replace(~r/:[^:\/]+$/, "")

  %{
    "id" => "sha256:" <> String.duplicate(id, 64),
    "references" => references ++ [name <> "@" <> digest],
    "size_bytes" => size,
    "last_used_at" => now |> DateTime.add(-hours_ago, :hour) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  }
end

repositories = [
  %{
    repository: "tuist/android-app",
    repository_id: 900_001,
    workflow: "PR Checks",
    job: "unit-tests",
    jobs: 42,
    cold_every: 7,
    saved_bytes: trunc(6.8 * gb),
    build_cache_bytes: trunc(2.1 * gb),
    images: [
      image.(
        "a",
        ["ghcr.io/acme/android-build:jdk-21-android-36", "ghcr.io/acme/android-build:latest"],
        trunc(4.9 * gb),
        1
      ),
      image.("b", ["postgres:16"], 451_304_147, 1),
      image.("c", ["redis:7-alpine"], 41_211_520, 30)
    ]
  },
  %{
    repository: "tuist/web",
    repository_id: 900_002,
    workflow: "CI",
    job: "e2e",
    jobs: 12,
    cold_every: 12,
    saved_bytes: trunc(1.4 * gb),
    build_cache_bytes: 312_000_000,
    images: [
      image.("d", ["node:22-bookworm"], 1_120_000_000, 3),
      image.("b", ["postgres:16"], 451_304_147, 3)
    ]
  },
  %{repository: "tuist/scripts", repository_id: 900_003, state: :waiting},
  %{repository: "tuist/legacy-service", repository_id: 900_004, state: :cleared}
]

# Reruns replace what this script seeded and nothing else.
seeded_ids = Enum.map(repositories, &to_string(&1.repository_id))

seeded_volumes =
  Repo.all(
    from(v in Volume,
      where: v.account_id == ^account_id and v.key == "docker" and v.scope_id in ^seeded_ids,
      select: v.id
    )
  )

seeded_jobs =
  Repo.all(from(u in Usage, where: u.volume_id in ^seeded_volumes, select: u.workflow_job_id))

Repo.delete_all(from(m in Measurement, join: u in Usage, on: u.id == m.usage_id, where: u.volume_id in ^seeded_volumes))
Repo.delete_all(from(u in Usage, where: u.volume_id in ^seeded_volumes))
Repo.delete_all(from(v in Volume, where: v.id in ^seeded_volumes))
Repo.delete_all(from(j in WorkflowJob, where: j.workflow_job_id in ^seeded_jobs))

timestamp = DateTime.truncate(now, :second)

steps = fn workflow_job_id, started_at, initialize_ms ->
  [
    {"Set up job", 2_000},
    {"Set up runner", 4_000},
    {"Initialize containers", initialize_ms},
    {"Run tests", 240_000},
    {"Stop containers", 1_000},
    {"Complete job", 1_000}
  ]
  |> Enum.with_index(1)
  |> Enum.map_reduce(started_at, fn {{name, ms}, number}, at ->
    completed_at = DateTime.add(at, ms, :millisecond)

    {%{
       workflow_job_id: workflow_job_id,
       account_id: account_id,
       number: number,
       name: name,
       status: "completed",
       conclusion: "success",
       started_at: at,
       completed_at: completed_at
     }, completed_at}
  end)
  |> elem(0)
end

for {seed, index} <- Enum.with_index(repositories) do
  volume =
    Repo.insert!(%Volume{
      account_id: account_id,
      repository_id: seed.repository_id,
      provider: "github",
      provider_instance: "github.com",
      scope_id: to_string(seed.repository_id),
      repository: seed.repository,
      default_branch: "main",
      key: "docker",
      platform: "linux",
      architecture: "amd64",
      uid: 0,
      last_used_at: if(Map.get(seed, :jobs), do: DateTime.add(now, -(index * 40 + 5), :minute)),
      deleted_at: if(Map.get(seed, :state) == :cleared, do: DateTime.add(now, -2, :day)),
      inserted_at: DateTime.add(timestamp, -9, :day),
      updated_at: timestamp
    })

  if Map.get(seed, :jobs) do
    workflow_job_base = 7_000_000_000 + seed.repository_id * 1_000

    uses =
      for n <- 0..(seed.jobs - 1) do
        # Spread the jobs over the last week, oldest first; the first one started
        # the volume empty, and every `cold_every`-th one landed on a cold host.
        attached_at = DateTime.add(now, -trunc((seed.jobs - n) * 7 * 24 * 60 / seed.jobs), :minute)
        warm = n != 0 and rem(n, seed.cold_every) != 0
        workflow_job_id = workflow_job_base + n
        initialize_ms = if warm, do: 4_200 + rem(n * 373, 2_400), else: 44_000 + rem(n * 911, 9_000)

        Repo.insert!(%WorkflowJob{
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          provider: "github",
          fleet_name: "linux-8vcpu-16gb",
          status: "completed",
          conclusion: "success",
          platform: "linux",
          vcpus: 8,
          memory_gb: 16,
          repository: seed.repository,
          workflow_run_id: workflow_job_base + 500 + n,
          workflow_name: seed.workflow,
          job_name: "#{seed.job} (#{rem(n, 4) + 1})",
          head_branch: if(rem(n, 5) == 0, do: "main", else: "feature/change-#{n}"),
          enqueued_at: DateTime.add(attached_at, -20, :second),
          started_at: DateTime.add(attached_at, -8, :second),
          completed_at: DateTime.add(attached_at, 260, :second)
        })

        JobSteps.record(steps.(workflow_job_id, DateTime.add(attached_at, -6, :second), initialize_ms))

        Repo.insert!(%Usage{
          volume_id: volume.id,
          generation: volume.generation,
          base_generation: if(n == 0, do: 0, else: 1),
          workflow_job_id: workflow_job_id,
          workflow_run_id: workflow_job_base + 500 + n,
          pod_name: "tuist-runner-pool-linux-8vcpu-16gb-runner-#{n}",
          pod_uid: Ecto.UUID.generate(),
          node_name: "runners-linux-1",
          can_publish: rem(n, 5) == 0,
          writer_default_branch: rem(n, 5) == 0,
          status: "discarded",
          warm: warm,
          size_bytes: seed.saved_bytes,
          capacity_bytes: 100 * gb,
          volume_bytes: 100 * gb,
          attach_ms: if(warm, do: 24, else: 61),
          attached_at: attached_at,
          last_reported_at: DateTime.add(attached_at, 300, :second),
          finished_at: DateTime.add(attached_at, 300, :second),
          deleted_at: DateTime.add(attached_at, 400, :second),
          inserted_at: DateTime.truncate(attached_at, :second),
          updated_at: DateTime.truncate(attached_at, :second)
        })
      end

    # The saved head: the newest default-branch job's data root and its inventory.
    head_source = uses |> Enum.filter(& &1.writer_default_branch) |> List.last()

    head =
      head_source
      |> Ecto.Changeset.change(
        status: "published",
        published_generation: 1,
        deleted_at: nil,
        image_digest: String.duplicate("e", 40),
        content_digest: String.duplicate("f", 64),
        docker_images: %{"images" => seed.images, "build_cache_bytes" => seed.build_cache_bytes}
      )
      |> Repo.update!()

    # Every job's copy reports its size while it runs; the host deletes all but
    # the saved head's after the job.
    for use <- uses do
      Repo.insert!(%Measurement{
        usage_id: use.id,
        size_bytes: seed.saved_bytes,
        capacity_bytes: 100 * gb,
        observed_at: DateTime.add(use.attached_at, 120, :second)
      })

      if use.id != head.id do
        Repo.insert!(%Measurement{usage_id: use.id, deleted: true, observed_at: use.deleted_at})
      end
    end

    volume |> Ecto.Changeset.change(head_id: head.id) |> Repo.update!()
  end
end

base_url = "/tuist/runners"

IO.puts("""

Seeded image cache data for the `tuist` organization.
Log in to your dev server as tuistrocks@tuist.dev / tuistrocks, then open:
  #{base_url}/volumes/#{Repo.one!(from(v in Volume, where: v.account_id == ^account_id and v.key == "docker" and v.scope_id == "900001", select: v.id))}
  #{base_url}/volumes
  #{base_url}/profiles
""")
