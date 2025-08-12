defmodule Tuist.QA.Logs.BufferTest do
  use ExUnit.Case, async: true

  alias Tuist.QA.Log
  alias Tuist.QA.Logs.Buffer

  describe "insert/1" do
    test "successfully encodes and returns log struct" do
      # Given
      log_attrs = %{
        project_id: 123,
        qa_run_id: UUIDv7.generate(),
        message: "Test log message",
        level: "info",
        timestamp: DateTime.utc_now(),
        inserted_at: DateTime.utc_now()
      }

      log_attrs = Log.changeset(log_attrs)
      log = struct(Log, log_attrs)

      # When
      result = Buffer.insert(log)

      # Then
      assert {:ok, ^log} = result
    end
  end
end
