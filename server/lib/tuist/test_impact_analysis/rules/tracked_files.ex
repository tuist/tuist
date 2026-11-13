defmodule Tuist.TestImpactAnalysis.Rules.TrackedFiles do
  @moduledoc """
  Rule 1. Decides nothing: when a changed file is one of the project's
  tracked files (its build system's dependency pins and manifests, project
  and build settings, test plans, toolchain version), whose change can
  affect any test without showing in coverage, selection can't happen. It
  aborts with `:tracked_file_changed` and the first such path, in path
  order, and the client runs default selective testing, whose target hashes
  include them. Coverage carry stops at the same files.
  """
  @behaviour Tuist.TestImpactAnalysis.Rule

  alias Tuist.TestImpactAnalysis.Input

  @impl true
  def name, do: :tracked_files

  @impl true
  def decide(input, state) do
    case Enum.find(Input.changed_paths(input), &Input.tracked?(input, &1)) do
      nil -> {state, :continue}
      path -> {state, {:abort, :tracked_file_changed, path}}
    end
  end
end
