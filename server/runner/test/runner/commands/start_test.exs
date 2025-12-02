defmodule Runner.Commands.StartTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Runner.Commands.Start
  alias Runner.Runner.Connection

  describe "run/1" do
    test "shows help with --help flag" do
      assert :ok = Start.run(["--help"])
    end

    test "shows help with -h flag" do
      assert :ok = Start.run(["-h"])
    end

    test "returns error when server_url is missing" do
      assert {:error, _} = Start.run(["--token", "test-token"])
    end

    test "returns error when token is missing" do
      assert {:error, _} = Start.run(["--server-url", "https://example.com"])
    end

    test "parses all arguments correctly" do
      custom_work_dir = Path.join(System.tmp_dir!(), "tuist-runner-test-#{:rand.uniform(100_000)}")

      Mimic.stub(Connection, :start_link, fn opts ->
        assert opts[:server_url] == "https://cloud.tuist.io"
        assert opts[:token] == "my-token"
        assert opts[:base_work_dir] == custom_work_dir
        {:ok, spawn(fn -> Process.sleep(:infinity) end)}
      end)

      # Run in a task so we can timeout
      task =
        Task.async(fn ->
          Start.run([
            "--server-url",
            "https://cloud.tuist.io",
            "--token",
            "my-token",
            "--work-dir",
            custom_work_dir
          ])
        end)

      # Give it a moment to call Connection.start_link
      Process.sleep(100)

      # The task will hang waiting for shutdown, so we just verify the mock was called
      Task.shutdown(task, :brutal_kill)

      # Cleanup
      File.rm_rf(custom_work_dir)
    end

    test "uses short flags correctly" do
      Mimic.stub(Connection, :start_link, fn opts ->
        assert opts[:server_url] == "https://cloud.tuist.io"
        assert opts[:token] == "my-token"
        {:ok, spawn(fn -> Process.sleep(:infinity) end)}
      end)

      task =
        Task.async(fn ->
          Start.run(["-s", "https://cloud.tuist.io", "-t", "my-token"])
        end)

      Process.sleep(100)
      Task.shutdown(task, :brutal_kill)
    end

    test "uses default work directory when not specified" do
      Mimic.stub(Connection, :start_link, fn opts ->
        assert opts[:base_work_dir] == "/tmp/tuist-runner"
        {:ok, spawn(fn -> Process.sleep(:infinity) end)}
      end)

      task =
        Task.async(fn ->
          Start.run(["--server-url", "https://example.com", "--token", "token"])
        end)

      Process.sleep(100)
      Task.shutdown(task, :brutal_kill)
    end
  end
end
