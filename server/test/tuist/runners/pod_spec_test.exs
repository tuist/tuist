defmodule Tuist.Runners.PodSpecTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.PodSpec

  describe "build/6 — shared (no pool option)" do
    test "renders a Pod manifest without the pool label" do
      pod =
        PodSpec.build(
          "tuist-runner-abcd",
          "ghcr.io/tuist/tuist-runner@sha256:beefcafe",
          "https://staging.tuist.dev/api/internal/runners/dispatch",
          "secret-token-xyz",
          "tuist-test-tuist-runners-fleet"
        )

      assert pod["kind"] == "Pod"
      assert get_in(pod, ["metadata", "namespace"]) == "tuist-runners"
      assert get_in(pod, ["metadata", "labels", "tuist.dev/runner"]) == "true"
      assert get_in(pod, ["metadata", "labels", "tuist.dev/runner-state"]) == "idle"
      refute Map.has_key?(pod["metadata"]["labels"], "tuist.dev/runner-pool")

      assert get_in(pod, ["spec", "nodeSelector"]) == %{
               "kubernetes.io/os" => "darwin",
               "tuist.dev/runtime" => "tart",
               "tuist.dev/fleet" => "tuist-test-tuist-runners-fleet"
             }

      assert get_in(pod, ["spec", "restartPolicy"]) == "Never"

      [container] = pod["spec"]["containers"]
      assert container["image"] == "ghcr.io/tuist/tuist-runner@sha256:beefcafe"
      assert container["resources"]["requests"]["cpu"] == "4000m"
      assert container["resources"]["requests"]["memory"] == "14Gi"

      env = container["env"]

      assert Enum.any?(
               env,
               &match?(
                 %{
                   "name" => "TUIST_RUNNER_DISPATCH_URL",
                   "value" => "https://staging.tuist.dev/api/internal/runners/dispatch"
                 },
                 &1
               )
             )

      assert Enum.any?(env, &match?(%{"name" => "TUIST_RUNNER_DISPATCH_TOKEN", "value" => "secret-token-xyz"}, &1))

      assert Enum.any?(
               env,
               &match?(
                 %{"name" => "TUIST_RUNNER_POD_UID", "valueFrom" => %{"fieldRef" => %{"fieldPath" => "metadata.uid"}}},
                 &1
               )
             )
    end
  end

  describe "build/6 — pre-bound (pool option set)" do
    test "stamps tuist.dev/runner-pool=<pool> on the Pod" do
      pod =
        PodSpec.build(
          "tuist-runner-tuist-tuist-abcd",
          "ghcr.io/tuist/tuist-runner@sha256:beefcafe",
          "https://staging.tuist.dev/api/internal/runners/dispatch",
          "tok",
          "fleet",
          pool: "tuist-tuist"
        )

      assert get_in(pod, ["metadata", "labels", "tuist.dev/runner-pool"]) == "tuist-tuist"
      assert get_in(pod, ["metadata", "labels", "tuist.dev/runner"]) == "true"
    end
  end

  describe "selectors" do
    test "pre_bound_selector includes the pool name" do
      assert PodSpec.pre_bound_selector("tuist-tuist") ==
               "tuist.dev/runner=true,tuist.dev/runner-pool=tuist-tuist"
    end

    test "shared_selector negates the pool label" do
      assert PodSpec.shared_selector() ==
               "tuist.dev/runner=true,!tuist.dev/runner-pool"
    end
  end

  describe "generate_pool_name/1" do
    test "embeds the pool name in the Pod name" do
      name = PodSpec.generate_pool_name("tuist-tuist")
      assert String.starts_with?(name, "tuist-runner-tuist-tuist-")
      assert String.match?(name, ~r/^tuist-runner-tuist-tuist-[0-9a-f]{8}$/)
    end
  end

  describe "alive?/1" do
    test "Running and Pending count as alive" do
      assert PodSpec.alive?(%{"status" => %{"phase" => "Running"}})
      assert PodSpec.alive?(%{"status" => %{"phase" => "Pending"}})
    end

    test "Succeeded / Failed / Unknown don't count" do
      refute PodSpec.alive?(%{"status" => %{"phase" => "Succeeded"}})
      refute PodSpec.alive?(%{"status" => %{"phase" => "Failed"}})
      refute PodSpec.alive?(%{})
    end
  end

  describe "generate_name/0" do
    test "returns a tuist-runner-<8 hex chars> name" do
      name = PodSpec.generate_name()
      assert String.starts_with?(name, "tuist-runner-")
      assert String.match?(name, ~r/^tuist-runner-[0-9a-f]{8}$/)
    end
  end
end
