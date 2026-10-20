defmodule Tuist.Tests.Coverage.GapReasonsTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Tuist.Tests.Coverage.GapReasons

  test "keeps each reason's bit, so stored masks keep their meaning" do
    assert GapReasons.encode([]) == 0
    assert GapReasons.encode([:no_evidence]) == 1
    assert GapReasons.encode([:not_linked, :no_evidence, :not_linked]) == 0b101
    assert GapReasons.encode([:unbuilt_file_uncarried]) == 1 <<< 11
    assert GapReasons.encode([:evidence_expired, :overlapped]) == (1 <<< 12) + (1 <<< 13)
    assert GapReasons.decode(0b101) == [:no_evidence, :not_linked]
    assert GapReasons.decode(GapReasons.encode(GapReasons.all())) == GapReasons.all()
  end
end
