defmodule Tuist.Runners.PodSpecTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.PodSpec

  describe "build/5" do
    test "renders a Pod manifest with the runners-fleet selector + dispatch env" do
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
      assert Enum.any?(env, &match?(%{"name" => "TUIST_RUNNER_DISPATCH_URL", "value" => "https://staging.tuist.dev/api/internal/runners/dispatch"}, &1))
      assert Enum.any?(env, &match?(%{"name" => "TUIST_RUNNER_DISPATCH_TOKEN", "value" => "secret-token-xyz"}, &1))
      assert Enum.any?(env, &match?(%{"name" => "TUIST_RUNNER_POD_UID", "valueFrom" => %{"fieldRef" => %{"fieldPath" => "metadata.uid"}}}, &1))
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
