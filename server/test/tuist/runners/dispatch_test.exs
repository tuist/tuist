defmodule Tuist.Runners.DispatchTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.Dispatch

  describe "pool_summary_by_name/1" do
    test "returns name + dispatch_label + runner_labels from the CR" do
      stub(Client, :get_runner_pool, fn _ns, "linux-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "linux-pool"},
           "spec" => %{
             "dispatchLabel" => "tuist-linux-ubuntu-22-04",
             "runnerLabels" => ["self-hosted", "Linux", "X64"]
           }
         }}
      end)

      assert {:ok,
              %{
                name: "linux-pool",
                dispatch_label: "tuist-linux-ubuntu-22-04",
                runner_labels: ["self-hosted", "Linux", "X64"]
              }} = Dispatch.pool_summary_by_name("linux-pool")
    end

    test "falls back to the macOS triple when runnerLabels is absent" do
      stub(Client, :get_runner_pool, fn _ns, "macos-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "macos-pool"},
           "spec" => %{"dispatchLabel" => "tuist-macos"}
         }}
      end)

      assert {:ok, %{runner_labels: ["self-hosted", "macOS", "ARM64"]}} =
               Dispatch.pool_summary_by_name("macos-pool")
    end

    test "falls back to the macOS triple when runnerLabels is empty" do
      stub(Client, :get_runner_pool, fn _ns, "macos-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "macos-pool"},
           "spec" => %{"dispatchLabel" => "tuist-macos", "runnerLabels" => []}
         }}
      end)

      assert {:ok, %{runner_labels: ["self-hosted", "macOS", "ARM64"]}} =
               Dispatch.pool_summary_by_name("macos-pool")
    end

    test "filters non-string and empty entries from runnerLabels" do
      stub(Client, :get_runner_pool, fn _ns, "mixed-pool" ->
        {:ok,
         %{
           "metadata" => %{"name" => "mixed-pool"},
           "spec" => %{
             "dispatchLabel" => "tuist-mixed",
             "runnerLabels" => ["self-hosted", "", nil, "Linux", "X64"]
           }
         }}
      end)

      assert {:ok, %{runner_labels: ["self-hosted", "Linux", "X64"]}} =
               Dispatch.pool_summary_by_name("mixed-pool")
    end

    test "returns :no_dispatch_label when the CR has no dispatchLabel" do
      stub(Client, :get_runner_pool, fn _ns, "broken-pool" ->
        {:ok, %{"metadata" => %{"name" => "broken-pool"}, "spec" => %{}}}
      end)

      assert {:error, :no_dispatch_label} = Dispatch.pool_summary_by_name("broken-pool")
    end

    test "propagates K8s client errors" do
      stub(Client, :get_runner_pool, fn _ns, _name -> {:error, :not_found} end)

      assert {:error, :not_found} = Dispatch.pool_summary_by_name("missing-pool")
    end
  end

  describe "match_pool/1" do
    test "returns the pool whose dispatchLabel matches one of the requested labels" do
      stub(Client, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "macos-pool"},
             "spec" => %{
               "dispatchLabel" => "tuist-macos",
               "runnerLabels" => ["self-hosted", "macOS", "ARM64"]
             }
           },
           %{
             "metadata" => %{"name" => "linux-pool"},
             "spec" => %{
               "dispatchLabel" => "tuist-linux",
               "runnerLabels" => ["self-hosted", "Linux", "X64"]
             }
           }
         ]}
      end)

      assert {:ok,
              %{
                name: "linux-pool",
                dispatch_label: "tuist-linux",
                runner_labels: ["self-hosted", "Linux", "X64"]
              }} = Dispatch.match_pool(["self-hosted", "tuist-linux"])
    end

    test "returns :no_matching_pool when no dispatchLabel intersects" do
      stub(Client, :list_runner_pools, fn _ns ->
        {:ok,
         [
           %{
             "metadata" => %{"name" => "macos-pool"},
             "spec" => %{"dispatchLabel" => "tuist-macos"}
           }
         ]}
      end)

      assert {:error, :no_matching_pool} = Dispatch.match_pool(["ubuntu-latest"])
    end

    test "returns :no_pools when no RunnerPool CRs exist" do
      stub(Client, :list_runner_pools, fn _ns -> {:ok, []} end)

      assert {:error, :no_pools} = Dispatch.match_pool(["tuist-macos"])
    end
  end
end
