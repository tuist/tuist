defmodule Tuist.Ingestion.BufferTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Ingestion.Buffer
  alias Tuist.IngestRepo

  setup do
    stub(IngestRepo, :query, fn _sql, _params, _opts -> {:ok, :result} end)
    :ok
  end

  describe "start_link/1" do
    test "starts buffer with required options" do
      opts = [
        name: :test_buffer,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header"
      ]

      assert {:ok, pid} = Buffer.start_link(opts)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "uses provided optional parameters over defaults" do
      opts = [
        name: :test_buffer_custom,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 2048,
        retained_buffer_size: 4096,
        flush_interval_ms: 10_000
      ]

      assert {:ok, pid} = Buffer.start_link(opts)

      state = :sys.get_state(pid)
      assert state.flush_interval_ms == 10_000
      assert state.max_buffer_size == 2048
      assert state.retained_buffer_size == 4096

      GenServer.stop(pid)
    end
  end

  describe "flush/1 - empty buffer" do
    setup do
      opts = [
        name: :test_buffer_flush,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 1000,
        flush_interval_ms: 60_000,
        sync_writes: false
      ]

      {:ok, pid} = Buffer.start_link(opts)
      %{pid: pid}
    end

    test "does not call IngestRepo.query when buffer is empty", %{pid: pid} do
      reject(IngestRepo, :query, 3)

      assert Buffer.flush(pid) == :ok

      state = :sys.get_state(pid)
      assert state.buffer == []
      assert state.buffer_size == 0

      GenServer.stop(pid)
    end

    test "returns :ok for manual flush", %{pid: pid} do
      assert Buffer.flush(pid) == :ok
      GenServer.stop(pid)
    end
  end

  describe "compile_time_prepare/1" do
    defmodule TestSchema do
      @moduledoc false
      use Ecto.Schema

      @primary_key {:id, Ch, type: "Int64", autogenerate: false}
      schema "test_table" do
        field(:name, Ch, type: "String")
        field(:age, Ch, type: "Int32")
        field(:active, Ch, type: "Bool")
      end
    end

    test "prepares schema metadata correctly" do
      result = Tuist.Ingestion.Bufferable.compile_time_prepare(TestSchema)

      assert result.fields == [:id, :name, :age, :active]
      assert is_list(result.types)
      assert is_list(result.encoding_types)
      assert is_binary(result.header)

      assert result.insert_sql ==
               "INSERT INTO test_table (id, name, age, active) FORMAT RowBinaryWithNamesAndTypes"

      assert result.insert_opts == [
               command: :insert,
               encode: false,
               source: "test_table",
               cast_params: []
             ]
    end
  end

  describe "initialization" do
    test "initializes with correct state structure" do
      opts = [
        name: :test_buffer_init,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert, encode: false],
        header: "test_header",
        max_buffer_size: 512,
        flush_interval_ms: 30_000
      ]

      {:ok, pid} = Buffer.start_link(opts)

      state = :sys.get_state(pid)

      assert state.buffer == []
      assert state.buffer_size == 0
      assert state.name == :test_buffer_init
      assert state.insert_sql == "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes"
      assert state.insert_opts == [command: :insert, encode: false]
      assert state.header == "test_header"
      assert state.max_buffer_size == 512
      assert state.retained_buffer_size == 1024
      assert state.flush_interval_ms == 30_000
      refute state.flush_deferred?
      assert is_reference(state.timer)

      GenServer.stop(pid)
    end

    test "sets trap_exit flag" do
      opts = [
        name: :test_buffer_trap_exit,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header"
      ]

      {:ok, pid} = Buffer.start_link(opts)

      process_info = Process.info(pid, :trap_exit)
      assert process_info == {:trap_exit, true}

      GenServer.stop(pid)
    end
  end

  describe "timer management" do
    test "creates timer on startup" do
      opts = [
        name: :test_buffer_timer_startup,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 1000,
        flush_interval_ms: 60_000,
        sync_writes: false
      ]

      {:ok, pid} = Buffer.start_link(opts)

      state = :sys.get_state(pid)
      assert is_reference(state.timer)
      assert state.flush_interval_ms == 60_000
      assert state.max_buffer_size == 1000

      GenServer.stop(pid)
    end

    test "timer is recreated after manual flush" do
      opts = [
        name: :test_buffer_timer_recreate,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 1000,
        flush_interval_ms: 60_000
      ]

      {:ok, pid} = Buffer.start_link(opts)

      initial_state = :sys.get_state(pid)
      initial_timer = initial_state.timer

      Buffer.flush(pid)

      new_state = :sys.get_state(pid)
      new_timer = new_state.timer

      assert initial_timer != new_timer
      assert is_reference(new_timer)

      GenServer.stop(pid)
    end
  end

  describe "configuration validation" do
    test "requires name parameter" do
      opts = [
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header"
      ]

      assert_raise KeyError, fn ->
        Buffer.start_link(opts)
      end
    end
  end

  describe "GenServer API" do
    test "insert/2 acknowledges that the row was buffered" do
      opts = [
        name: :test_buffer_api,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 1000,
        flush_interval_ms: 60_000,
        sync_writes: false
      ]

      {:ok, pid} = Buffer.start_link(opts)
      Mimic.allow(IngestRepo, self(), pid)

      assert :ok = Buffer.insert!(pid, "row")
      assert :sys.get_state(pid).buffer_size == 3

      GenServer.stop(pid)
    end

    test "flush/1 is a call operation (blocking)" do
      opts = [
        name: :test_buffer_flush_api,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 1000,
        flush_interval_ms: 60_000
      ]

      {:ok, pid} = Buffer.start_link(opts)

      assert Buffer.flush(pid) == :ok

      GenServer.stop(pid)
    end
  end

  describe "user memory pressure" do
    test "keeps buffered rows when ClickHouse rejects the flush" do
      error = %Ch.Error{code: 241, message: "Memory limit (for user) exceeded"}

      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:error, error} end)

      opts = [
        name: :test_buffer_memory_pressure,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        buffer: ["row"],
        max_buffer_size: 1000,
        flush_interval_ms: 60_000,
        user_memory_retries: 0
      ]

      assert {:ok, pid} = Buffer.start_link(opts)
      Mimic.allow(IngestRepo, self(), pid)
      assert {:error, ^error} = Buffer.flush(pid)

      state = :sys.get_state(pid)
      assert state.buffer == ["row"]
      assert state.buffer_size == 3
      assert state.flush_deferred?
      assert Process.alive?(pid)

      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:ok, :result} end)

      assert :ok = Buffer.flush(pid)
      assert :sys.get_state(pid).buffer == []

      GenServer.stop(pid)
    end

    test "bounds retained rows and applies producer backpressure during sustained pressure" do
      error = %Ch.Error{code: 241, message: "Memory limit (for user) exceeded"}
      counter = :counters.new(1, [])

      stub(IngestRepo, :query, fn _sql, _params, _opts ->
        :counters.add(counter, 1, 1)
        {:error, error}
      end)

      opts = [
        name: :test_buffer_bounded_memory_pressure,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 3,
        retained_buffer_size: 6,
        flush_interval_ms: 60_000,
        user_memory_retries: 0,
        sync_writes: false
      ]

      assert {:ok, pid} = Buffer.start_link(opts)
      Mimic.allow(IngestRepo, self(), pid)

      assert :ok = Buffer.insert!(pid, "one")
      assert :ok = Buffer.insert!(pid, "two")

      raised_error =
        assert_raise Ch.Error, fn ->
          Buffer.insert!(pid, "three")
        end

      assert raised_error.code == error.code
      assert raised_error.message == error.message

      state = :sys.get_state(pid)
      assert state.buffer_size == 6
      assert state.flush_deferred?
      assert :counters.get(counter, 1) == 2

      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:ok, :result} end)
      assert :ok = Buffer.flush(pid)

      GenServer.stop(pid)
    end

    test "bounds retained rows when synchronous writes are enabled" do
      error = %Ch.Error{code: 241, message: "Memory limit (for user) exceeded"}

      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:error, error} end)

      opts = [
        name: :test_buffer_bounded_sync_memory_pressure,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 3,
        retained_buffer_size: 6,
        flush_interval_ms: 60_000,
        user_memory_retries: 0,
        sync_writes: true
      ]

      assert {:ok, pid} = Buffer.start_link(opts)
      Mimic.allow(IngestRepo, self(), pid)

      for row <- ["one", "two", "three"] do
        assert_raise Ch.Error, fn ->
          Buffer.insert!(pid, row)
        end
      end

      state = :sys.get_state(pid)
      assert state.buffer_size == 6
      assert state.flush_deferred?

      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:ok, :result} end)
      assert :ok = Buffer.flush(pid)

      GenServer.stop(pid)
    end

    test "does not retain a row after a non-transient flush error" do
      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:error, :unexpected} end)

      opts = [
        name: :test_buffer_non_transient_error,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 3,
        flush_interval_ms: 60_000,
        user_memory_retries: 0,
        sync_writes: false
      ]

      assert {:ok, pid} = Buffer.start_link(opts)
      Mimic.allow(IngestRepo, self(), pid)

      assert_raise RuntimeError,
                   "ClickHouse ingestion buffer rejected an insert: :unexpected",
                   fn ->
                     Buffer.insert!(pid, "row")
                   end

      assert :sys.get_state(pid).buffer_size == 0
      assert Process.alive?(pid)

      stub(IngestRepo, :query, fn _sql, _params, _opts -> {:ok, :result} end)
      GenServer.stop(pid)
    end

    test "flushes a single row larger than the retention limit without retaining it" do
      opts = [
        name: :test_buffer_oversized_row,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 3,
        retained_buffer_size: 6,
        flush_interval_ms: 60_000,
        sync_writes: false
      ]

      assert {:ok, pid} = Buffer.start_link(opts)
      Mimic.allow(IngestRepo, self(), pid)

      assert :ok = Buffer.insert!(pid, "oversized")
      assert :sys.get_state(pid).buffer_size == 0

      GenServer.stop(pid)
    end
  end
end
