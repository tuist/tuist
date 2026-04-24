defmodule Tuist.Builds.ProcessorDispatcherTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Builds.ProcessorDispatcher

  setup :verify_on_exit!

  describe "pick_url/0" do
    test "returns the static processor_url when discovery is not configured" do
      stub(Tuist.Environment, :processor_discovery_url, fn -> nil end)
      stub(Tuist.Environment, :processor_url, fn -> "http://processor.example:4002" end)

      assert {:ok, "http://processor.example:4002"} = ProcessorDispatcher.pick_url()
    end

    test "returns nil when neither discovery nor static URL are configured" do
      stub(Tuist.Environment, :processor_discovery_url, fn -> nil end)
      stub(Tuist.Environment, :processor_url, fn -> nil end)

      assert {:ok, nil} = ProcessorDispatcher.pick_url()
    end

    test "falls back to the static URL when DNS returns no pods" do
      stub(Tuist.Environment, :processor_discovery_url, fn ->
        "http://headless.example:4002"
      end)

      stub(Tuist.Environment, :processor_url, fn -> "http://processor.example:4002" end)
      expect(ProcessorDispatcher, :resolve_pod_ips, fn _host -> [] end)

      assert {:ok, "http://processor.example:4002"} = ProcessorDispatcher.pick_url()
    end

    test "falls back to the discovery URL when DNS returns no pods and no static URL is set" do
      stub(Tuist.Environment, :processor_discovery_url, fn ->
        "http://headless.example:4002"
      end)

      stub(Tuist.Environment, :processor_url, fn -> nil end)
      expect(ProcessorDispatcher, :resolve_pod_ips, fn _host -> [] end)

      # Passing through the discovery URL keeps the webhook flow working: the
      # headless Service round-robins among pods at the DNS layer, so we get
      # at least one healthy replica even without per-pod selection.
      assert {:ok, "http://headless.example:4002"} = ProcessorDispatcher.pick_url()
    end

    test "picks the pod with the lowest in_flight count" do
      stub(Tuist.Environment, :processor_discovery_url, fn ->
        "http://headless.example:4002"
      end)

      stub(Tuist.Environment, :processor_url, fn -> nil end)

      expect(ProcessorDispatcher, :resolve_pod_ips, fn _host ->
        ["10.0.0.1", "10.0.0.2", "10.0.0.3"]
      end)

      stub(ProcessorDispatcher, :fetch_in_flight, fn
        "http://10.0.0.1:4002", _ -> {:ok, 5}
        "http://10.0.0.2:4002", _ -> {:ok, 2}
        "http://10.0.0.3:4002", _ -> {:ok, 7}
      end)

      assert {:ok, "http://10.0.0.2:4002"} = ProcessorDispatcher.pick_url()
    end

    test "ignores pods whose /stats probe fails" do
      stub(Tuist.Environment, :processor_discovery_url, fn ->
        "http://headless.example:4002"
      end)

      stub(Tuist.Environment, :processor_url, fn -> nil end)

      expect(ProcessorDispatcher, :resolve_pod_ips, fn _host ->
        ["10.0.0.1", "10.0.0.2"]
      end)

      stub(ProcessorDispatcher, :fetch_in_flight, fn
        "http://10.0.0.1:4002", _ -> :error
        "http://10.0.0.2:4002", _ -> {:ok, 4}
      end)

      assert {:ok, "http://10.0.0.2:4002"} = ProcessorDispatcher.pick_url()
    end

    test "falls back to the static URL when every stats probe fails" do
      stub(Tuist.Environment, :processor_discovery_url, fn ->
        "http://headless.example:4002"
      end)

      stub(Tuist.Environment, :processor_url, fn -> "http://processor.example:4002" end)

      expect(ProcessorDispatcher, :resolve_pod_ips, fn _host ->
        ["10.0.0.1", "10.0.0.2"]
      end)

      stub(ProcessorDispatcher, :fetch_in_flight, fn _url, _timeout -> :error end)

      assert {:ok, "http://processor.example:4002"} = ProcessorDispatcher.pick_url()
    end
  end
end
