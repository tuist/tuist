defmodule Tuist.IngestRepo.Migrations.AddDependenciesToXcodeTargets do
  use Ecto.Migration

  def change do
    alter table(:xcode_targets) do
      # Names of the targets this target directly depends on. Used to compute a
      # module's downstream blast radius (how many other modules it invalidates
      # when it changes). Populated once the CLI sends graph edges; empty for
      # older clients.
      add :dependencies, :"Array(String)", default: fragment("[]")
    end
  end
end
