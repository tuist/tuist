defmodule TuistWeb.Helpers.StackFramesTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.StackFrames

  describe "parse_frames/1" do
    test "parses a single frame line" do
      assert StackFrames.parse_frames("0  AppTests  AppTests.example() + 6004") == [
               {"0", "AppTests", "AppTests.example() + 6004"}
             ]
    end

    test "parses multiple frame lines" do
      frames = """
      0  libswiftCore.dylib  _assertionFailure + 1065708
      1  AppTests            AppTests.example() (AppTests.swift:8) + 6004
      2  Testing             closure #1 in static Runner._runTestCase + 741037\
      """

      assert StackFrames.parse_frames(frames) == [
               {"0", "libswiftCore.dylib", "_assertionFailure + 1065708"},
               {"1", "AppTests", "AppTests.example() (AppTests.swift:8) + 6004"},
               {"2", "Testing", "closure #1 in static Runner._runTestCase + 741037"}
             ]
    end

    test "parses double-digit indices" do
      frames = """
       9  Testing  closure #2 + 734189
      10  Testing  specialized static Test.Case + 743349\
      """

      assert StackFrames.parse_frames(frames) == [
               {"9", "Testing", "closure #2 + 734189"},
               {"10", "Testing", "specialized static Test.Case + 743349"}
             ]
    end

    test "handles lines that don't match the expected format" do
      assert StackFrames.parse_frames("some unexpected line") == [
               {nil, nil, "some unexpected line"}
             ]
    end

    test "handles empty string" do
      assert StackFrames.parse_frames("") == []
    end

    test "handles image names with dots and hyphens" do
      frames = "0  libswift_Concurrency.dylib  TaskLocal.withValueImpl + 128269"

      assert StackFrames.parse_frames(frames) == [
               {"0", "libswift_Concurrency.dylib", "TaskLocal.withValueImpl + 128269"}
             ]
    end
  end
end
