defmodule Tuist.Storage.LocalS3Test do
  use ExUnit.Case, async: true

  alias Tuist.Storage.LocalS3

  describe "LocalS3 GenServer" do
    test "creates storage directory on start and cleans up on stop" do
      {:ok, pid} = LocalS3.start_link([])

      storage_dir = LocalS3.storage_directory()

      assert File.exists?(storage_dir)
      assert File.dir?(storage_dir)

      ref = Process.monitor(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      refute File.exists?(storage_dir)
    end

    test "handles termination with :normal reason" do
      {:ok, pid} = LocalS3.start_link([])
      storage_dir = LocalS3.storage_directory()

      assert File.exists?(storage_dir)

      ref = Process.monitor(pid)
      GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      refute File.exists?(storage_dir)
    end

    test "handles termination with :shutdown reason" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = LocalS3.start_link([])
      storage_dir = LocalS3.storage_directory()

      assert File.exists?(storage_dir)

      ref = Process.monitor(pid)
      GenServer.stop(pid, :shutdown)
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}

      refute File.exists?(storage_dir)

      Process.flag(:trap_exit, false)
    end

    test "storage_directory/0 returns correct path when GenServer is running" do
      {:ok, pid} = LocalS3.start_link([])

      public_dir = LocalS3.storage_directory()

      genserver_dir = GenServer.call(pid, :get_storage_dir)

      assert public_dir == genserver_dir
      assert File.exists?(public_dir)

      GenServer.stop(pid)
    end

    test "storage_directory/0 returns a valid path even when GenServer is not running" do
      case Process.whereis(LocalS3) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      storage_dir = LocalS3.storage_directory()
      assert is_binary(storage_dir)
      assert String.contains?(storage_dir, "tmp/local_storage_")
    end

    test "multiple start/stop cycles work correctly" do
      dirs =
        for _ <- 1..3 do
          {:ok, pid} = LocalS3.start_link([])
          dir = LocalS3.storage_directory()

          assert File.exists?(dir)

          ref = Process.monitor(pid)
          GenServer.stop(pid)
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

          refute File.exists?(dir)

          dir
        end

      assert length(Enum.uniq(dirs)) == 3
    end
  end
end
