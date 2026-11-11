defmodule Tuist.IngestRepo.Migrations.AddOutOfMemoryToRunnerJobMachineMetrics do
  use Ecto.Migration

  # What the runner VM's kernel killed for running out of memory during
  # the job, as of the sample. The job page reports a non-zero count as
  # "ran out of memory" and names the victim.
  #
  #   * `oom_kill_count`: processes killed since the job started (the
  #     `oom_kill` counter in the guest's /proc/vmstat).
  #   * `oom_victim_*`: the process killed last, its anonymous memory
  #     and its Docker container and image, read from the kernel log by
  #     the dind sidecar. Only cache-volume pools run that sidecar, so
  #     elsewhere a sample can carry kills but no victim. The container
  #     is empty when the process ran in no container, and
  #     `docker-build` for a BuildKit build step.
  #
  # Rows written before these columns existed read as 0 and '', the same
  # as a sampler that cannot measure them (macOS).
  def change do
    alter table(:runner_job_machine_metrics) do
      add :oom_kill_count, :Int64, default: 0
      add :oom_victim_process, :String, default: ""
      add :oom_victim_memory_bytes, :Int64, default: 0
      add :oom_victim_container, :String, default: ""
      add :oom_victim_image, :String, default: ""
    end
  end
end
