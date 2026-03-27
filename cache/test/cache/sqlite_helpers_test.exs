defmodule Cache.SQLiteHelpersTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.SQLiteHelpers

  setup :set_mimic_from_context

  describe "busy_error?/1" do
    test "returns true for 'database is locked' message" do
      assert SQLiteHelpers.busy_error?(%Exqlite.Error{message: "database is locked"})
    end

    test "returns true for 'SQLITE_BUSY' message" do
      assert SQLiteHelpers.busy_error?(%Exqlite.Error{message: "SQLITE_BUSY (5)"})
    end

    test "returns true when message contains 'database is locked' among other text" do
      assert SQLiteHelpers.busy_error?(%Exqlite.Error{message: "error: database is locked (SQLITE_BUSY)"})
    end

    test "returns false for other Exqlite errors" do
      refute SQLiteHelpers.busy_error?(%Exqlite.Error{message: "disk I/O error"})
    end

    test "returns false for nil message" do
      refute SQLiteHelpers.busy_error?(%Exqlite.Error{message: nil})
    end

    test "returns false for non-Exqlite errors" do
      refute SQLiteHelpers.busy_error?(%RuntimeError{message: "database is locked"})
    end

    test "returns false for plain strings" do
      refute SQLiteHelpers.busy_error?("database is locked")
    end

    test "returns false for nil" do
      refute SQLiteHelpers.busy_error?(nil)
    end
  end

  describe "file_size/1" do
    test "returns size for existing file" do
      path = Path.join(System.tmp_dir!(), "sqlite_helpers_test_#{:erlang.unique_integer([:positive])}")

      try do
        File.write!(path, "hello")
        assert SQLiteHelpers.file_size(path) == 5
      after
        File.rm(path)
      end
    end

    test "returns 0 for non-existent file" do
      assert SQLiteHelpers.file_size("/tmp/nonexistent_#{:erlang.unique_integer([:positive])}") == 0
    end
  end

  describe "remaining_time/1" do
    test "returns positive remaining time when deadline is in the future" do
      deadline = System.monotonic_time(:millisecond) + 10_000
      remaining = SQLiteHelpers.remaining_time(deadline)
      assert remaining > 0
      assert remaining <= 10_000
    end

    test "returns 0 when deadline has passed" do
      deadline = System.monotonic_time(:millisecond) - 1_000
      assert SQLiteHelpers.remaining_time(deadline) == 0
    end
  end

  describe "db_path/2" do
    test "returns configured database path" do
      assert is_binary(SQLiteHelpers.db_path(Cache.KeyValueRepo))
    end

    test "returns fallback when repo has no database configured" do
      assert SQLiteHelpers.db_path(:nonexistent_repo, "fallback.sqlite") == "fallback.sqlite"
    end
  end

  describe "wal_file_size/1" do
    test "returns 0 when WAL file does not exist" do
      assert SQLiteHelpers.wal_file_size("/tmp/nonexistent_#{:erlang.unique_integer([:positive])}") == 0
    end
  end

  describe "with_repo_busy_timeout/3" do
    test "skips pragma changes when timeout matches repo default" do
      default_timeout = Cache.Config.repo_busy_timeout_ms(Cache.KeyValueRepo)

      expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)
      reject(&Cache.KeyValueRepo.query/1)

      result = SQLiteHelpers.with_repo_busy_timeout(Cache.KeyValueRepo, default_timeout, fn -> :ok end)
      assert result == :ok
    end

    test "sets and restores busy timeout when different from default" do
      expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)

      expect(Cache.KeyValueRepo, :query, 2, fn
        "PRAGMA busy_timeout = 0" -> {:ok, %{rows: []}}
        "PRAGMA busy_timeout = 30000" -> {:ok, %{rows: []}}
      end)

      result = SQLiteHelpers.with_repo_busy_timeout(Cache.KeyValueRepo, 0, fn -> :result end)
      assert result == :result
    end

    test "restores busy timeout even when function raises" do
      expect(Cache.KeyValueRepo, :checkout, fn fun -> fun.() end)

      expect(Cache.KeyValueRepo, :query, 2, fn
        "PRAGMA busy_timeout = 100" -> {:ok, %{rows: []}}
        "PRAGMA busy_timeout = 30000" -> {:ok, %{rows: []}}
      end)

      assert_raise RuntimeError, "boom", fn ->
        SQLiteHelpers.with_repo_busy_timeout(Cache.KeyValueRepo, 100, fn -> raise "boom" end)
      end
    end
  end
end
