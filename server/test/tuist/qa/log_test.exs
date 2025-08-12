defmodule Tuist.QA.LogTest do
  use ExUnit.Case, async: true

  alias Tuist.QA.Log

  describe "changeset/1" do
    test "normalizes fields correctly" do
      # Given
      datetime = DateTime.utc_now()
      attrs = %{level: "debug", timestamp: datetime, unknown_level: "unknown"}

      # When
      result = Log.changeset(attrs)

      # Then
      assert %{
               level: 0,
               timestamp: %NaiveDateTime{microsecond: {_, 6}}
             } = result
    end
  end

  describe "normalize_enums/1" do
    test "converts level integers to atoms" do
      # Given
      log = %Log{level: 2}

      # When
      result = Log.normalize_enums(log)

      # Then
      assert result.level == :warning
    end
  end
end
