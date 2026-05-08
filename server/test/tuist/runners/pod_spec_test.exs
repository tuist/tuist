defmodule Tuist.Runners.PodSpecTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.PodSpec

  describe "build/6" do
    test "renders a pool-bound Pod manifest" do
      pod =
        PodSpec.build(
          "tuist-runner-tuist-abcd",
          "ghcr.io/tuist/tuist-runner@sha256:beefcafe",
          "https://staging.tuist.dev/api/internal/runners/dispatch",
          "secret-token-xyz",
          "tuist-test-tuist-runners-fleet",
          pool: "tuist"
        )

      assert pod["kind"] == "Pod"
      assert get_in(pod, ["metadata", "namespace"]) == "tuist-runners"
      assert get_in(pod, ["metadata", "labels", "tuist.dev/runner"]) == "true"
      assert get_in(pod, ["metadata", "labels", "tuist.dev/runner-pool"]) == "tuist"

      assert get_in(pod, ["spec", "nodeSelector"]) == %{
               "kubernetes.io/os" => "darwin",
               "tuist.dev/runtime" => "tart",
               "tuist.dev/fleet" => "tuist-test-tuist-runners-fleet"
             }

      assert get_in(pod, ["spec", "restartPolicy"]) == "Never"

      [container] = pod["spec"]["containers"]
      assert container["image"] == "ghcr.io/tuist/tuist-runner@sha256:beefcafe"
      assert container["resources"]["requests"]["cpu"] == "8000m"
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

    test "raises when pool is missing" do
      assert_raise KeyError, fn ->
        PodSpec.build("name", "image", "url", "token", "fleet")
      end
    end
  end

  describe "selectors" do
    test "pre_bound_selector includes the pool name" do
      assert PodSpec.pre_bound_selector("tuist") ==
               "tuist.dev/runner=true,tuist.dev/runner-pool=tuist"
    end
  end

  describe "generate_pool_name/1" do
    test "embeds the pool name in the Pod name" do
      name = PodSpec.generate_pool_name("tuist")
      assert String.starts_with?(name, "tuist-runner-tuist-")
      assert String.match?(name, ~r/^tuist-runner-tuist-[0-9a-f]{8}$/)
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

    test "Pods with deletionTimestamp set are not alive even if phase is Running" do
      refute PodSpec.alive?(%{
               "metadata" => %{"deletionTimestamp" => "2026-05-07T10:00:00Z"},
               "status" => %{"phase" => "Running"}
             })
    end
  end
end
