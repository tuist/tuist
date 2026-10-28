defmodule Tuist.OpenGraphImageRendererTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.OpenGraphImageRenderer

  # `capture_log/1` captures events from every process, so crash reports from
  # concurrently running async tests would leak into it. This handler forwards
  # only events logged by processes spawned on behalf of the test process.
  defmodule CallerLogHandler do
    @moduledoc false
    def log(event, %{config: %{test_pid: test_pid}}) do
      if test_pid in List.wrap(event.meta[:callers]) do
        send(test_pid, {:caller_log_event, event})
      end
    end
  end

  setup do
    if !Process.whereis(OpenGraphImageRenderer.TaskSupervisor) do
      start_supervised!({Task.Supervisor, name: OpenGraphImageRenderer.TaskSupervisor})
    end

    :ok
  end

  describe "render/2" do
    test "captures the requested canvas through a single browser session" do
      html = "<html><body>Sharing image</body></html>"
      browser = self()

      expect(BrowseChrome, :checkout, fn Tuist.OpenGraphImagePool, capture ->
        assert {{:ok, "image"}, :ok} = capture.(browser)
        {:ok, "image"}
      end)

      expect(BrowseChrome.Chrome, :capture, fn ^browser, ^html, opts ->
        assert opts == [width: 1920, height: 1080, quality: 95]
        {:ok, "image"}
      end)

      assert {:ok, "image"} = OpenGraphImageRenderer.render(html, "Sharing image")
    end

    test "removes a browser whose capture fails before falling back" do
      browser = self()

      expect(BrowseChrome, :checkout, fn Tuist.OpenGraphImagePool, capture ->
        assert {{:error, :browser_unavailable}, :remove} = capture.(browser)
        {:error, :browser_unavailable}
      end)

      expect(BrowseChrome.Chrome, :capture, fn ^browser, _html, _opts ->
        {:error, :browser_unavailable}
      end)

      assert {:fallback, image} = OpenGraphImageRenderer.render("<html></html>", "Tuist")
      assert is_binary(image)
    end
  end

  describe "run_render/2 when the browser pool checkout times out (Sentry TUIST-3R8)" do
    test "degrades to the fallback renderer without logging a task crash report" do
      # This is exactly the exit NimblePool.checkout! raises when every browser
      # in the pool stays busy past the checkout timeout.
      checkout_timeout = fn ->
        exit({:timeout, {NimblePool, :checkout, [OpenGraphImageRenderer]}})
      end

      :ok = :logger.add_handler(__MODULE__, CallerLogHandler, %{config: %{test_pid: self()}})
      on_exit(fn -> :logger.remove_handler(__MODULE__) end)

      log =
        capture_log(fn ->
          assert {:fallback, image} = OpenGraphImageRenderer.run_render("Tuist", checkout_timeout)
          assert is_binary(image)
        end)

      # The single, intended warning still surfaces the reason.
      assert log =~ "Headless browser Open Graph image rendering failed"
      # The noisy per-request crash report that floods Sentry must be gone.
      refute_received {:caller_log_event, _}
    end
  end

  describe "the browser pool in the test environment" do
    test "is not started" do
      assert Process.whereis(Tuist.OpenGraphImagePool) == nil,
             "the headless-browser pool must not start under `mix test` — CI runners have no " <>
               "Chrome, and `Browse.Pool.init_worker/1` raising `:chrome_not_found` makes " <>
               "NimblePool re-send itself `:init_worker` forever, flooding the suite output"
    end
  end
end
