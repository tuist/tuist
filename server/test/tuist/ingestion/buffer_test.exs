defmodule Tuist.Ingestion.BufferTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Ingestion.Buffer
  alias Tuist.IngestRepo

  setup do
    stub(IngestRepo, :query!, fn _sql, _params, _opts -> :ok end)
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
        flush_interval_ms: 10_000
      ]

      assert {:ok, pid} = Buffer.start_link(opts)

      state = :sys.get_state(pid)
      assert state.flush_interval_ms == 10_000
      assert state.max_buffer_size == 2048

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
        flush_interval_ms: 60_000
      ]

      {:ok, pid} = Buffer.start_link(opts)
      %{pid: pid}
    end

    test "does not call IngestRepo.query! when buffer is empty", %{pid: pid} do
      reject(IngestRepo, :query!, 3)

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
      assert state.flush_interval_ms == 30_000
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
        flush_interval_ms: 60_000
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
    test "insert/2 is a cast operation (non-blocking)" do
      opts = [
        name: :test_buffer_api,
        insert_sql: "INSERT INTO test_table FORMAT RowBinaryWithNamesAndTypes",
        insert_opts: [command: :insert],
        header: "test_header",
        max_buffer_size: 1000,
        flush_interval_ms: 60_000
      ]

      {:ok, pid} = Buffer.start_link(opts)

      assert is_pid(pid)
      assert Process.alive?(pid)

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
end
