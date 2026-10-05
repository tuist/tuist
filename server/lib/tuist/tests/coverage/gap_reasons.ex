defmodule Tuist.Tests.Coverage.GapReasons do
  @moduledoc """
  Why some of a commit's reported coverage is unknown: the reasons its
  skipped tests (and the files no run compiled) could not be carried forward
  (`Tuist.Tests.Coverage.Reported`), or a scheme it measured that does not
  count (`Tuist.Tests.Coverage.Commits`), stored as a bitmask on
  `coverage_commits.gap_reasons`. The bitmask says which reasons occur, not
  how often; the tests behind each are computed again on demand.

  Bits are assigned once and never reused, so a stored mask keeps its meaning:
  append new reasons at the end.

  - `no_evidence`: the test has no per-test evidence in any ancestor run that
    collected evidence for its target (no `.coverageAttribution` trait, or
    the test didn't run there).
  - `collection_off`: no ancestor run collected evidence at all.
  - `not_linked`: ancestor runs collected evidence, but none for the test's
    target: the target doesn't link TestCoverageAttribution. A target whose
    evidence only expired reads as this too when other evidence is live.
  - `test_failed`: the test failed in the run its evidence comes from.
  - `evidence_without_lines`: the evidence names files but not the lines.
  - `executed_file_changed`: a file the test executed changed since.
  - `tracked_file_changed`: a tracked file changed since.
  - `listing_missing`: the commit's or the source commit's file listing is
    missing, so what changed cannot be told.
  - `no_ancestor`: the commit has no repository or no ancestor run to carry
    from.
  - `unbuilt_file_changed`: a file an ancestor measured changed, and no run
    at the commit compiled it.
  - `unbuilt_file_unknown`: what the runs didn't compile is unknown (no
    listing, or no ancestor measured the schemes).
  - `unbuilt_file_uncarried`: a file no run at the commit compiled is
    unchanged, but tests whose coverage wasn't carried covered some of it.
  - `evidence_expired`: ancestor runs collected evidence, but all of it is
    past the coverage file retention
    (`Tuist.Environment.coverage_retention_days/1`).
  - `overlapped`: an ancestor run recorded the test only as overlapping
    another test of its process (Swift Testing running in parallel), so
    nothing could be attributed to it.
  - `dirty_run_excluded`: a scheme's coverage only came from runs on a dirty
    checkout, which measured code that is not the commit's and never count.
  """
  import Bitwise

  @reasons [
    :no_evidence,
    :collection_off,
    :not_linked,
    :test_failed,
    :evidence_without_lines,
    :executed_file_changed,
    :tracked_file_changed,
    :listing_missing,
    :no_ancestor,
    :unbuilt_file_changed,
    :unbuilt_file_unknown,
    :unbuilt_file_uncarried,
    :evidence_expired,
    :overlapped,
    :dirty_run_excluded
  ]

  @bits @reasons |> Enum.with_index() |> Map.new(fn {reason, index} -> {reason, 1 <<< index} end)

  @doc "Every reason, in bit order."
  def all, do: @reasons

  @doc "The mask holding the given reasons."
  def encode(reasons), do: reasons |> Enum.uniq() |> Enum.reduce(0, &(Map.fetch!(@bits, &1) ||| &2))

  @doc "The reasons a mask holds, in bit order."
  def decode(mask) when is_integer(mask), do: Enum.filter(@reasons, &((mask &&& Map.fetch!(@bits, &1)) != 0))
end
