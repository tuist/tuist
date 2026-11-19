defmodule Tuist.Repo.Migrations.AddGuaranteedCpuMilliToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The CPU, in millicores, a Linux agent sandbox's creator picked to be
      # guaranteed; NULL is the default quarter core.
      add :guaranteed_cpu_milli, :integer
    end
  end
end
