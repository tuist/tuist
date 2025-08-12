defmodule Tuist.QA.LogTest do
  use ExUnit.Case, async: true

  alias Tuist.QA.Log

  describe "changeset/1" do
    test "normalizes fields correctly" do
      # Given
      datetime = DateTime.utc_now()
      attrs = %{type: "usage", timestamp: datetime, data: ~s({"test": "data"})}

      # When
      result = Log.changeset(attrs)

      # Then
      assert %{
               type: 0,
               timestamp: %NaiveDateTime{microsecond: {_, 6}},
               data: ~s({"test": "data"})
             } = result
    end
  end
end
