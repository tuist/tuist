defmodule Tuist.OpenGraphImageRendererTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Tuist.OpenGraphImageRenderer

  setup do
    if !Process.whereis(OpenGraphImageRenderer.TaskSupervisor) do
      start_supervised!({Task.Supervisor, name: OpenGraphImageRenderer.TaskSupervisor})
    end

    :ok
  end

  describe "run_render/2 when the browser pool checkout times out (Sentry TUIST-3R8)" do
    test "degrades to the fallback renderer without logging a task crash report" do
      # This is exactly the exit NimblePool.checkout! raises when every browser
      # in the pool stays busy past the checkout timeout.
      checkout_timeout = fn ->
        exit({:timeout, {NimblePool, :checkout, [OpenGraphImageRenderer]}})
      end

      log =
        capture_log(fn ->
          assert {:fallback, image} = OpenGraphImageRenderer.run_render("Tuist", checkout_timeout)
          assert is_binary(image)
        end)

      # The single, intended warning still surfaces the reason.
      assert log =~ "Headless browser Open Graph image rendering failed"
      # The noisy per-request crash report that floods Sentry must be gone.
      refute log =~ "terminating"
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
