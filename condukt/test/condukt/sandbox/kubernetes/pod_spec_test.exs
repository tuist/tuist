defmodule Condukt.Sandbox.Kubernetes.PodSpecTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.Kubernetes.PodSpec
  alias Condukt.Sandbox.NetworkPolicy.K8s.Manifests

  defp config(overrides \\ %{}) do
    Map.merge(
      %{
        pod_name: "pod-1",
        namespace: "agents",
        image: "debian:bookworm-slim",
        cwd: "/workspace",
        labels: %{"app" => "condukt"},
        annotations: %{"condukt/session" => "s1"},
        env: %{},
        resources: %{},
        service_account: nil,
        active_deadline_seconds: nil
      },
      overrides
    )
  end

  # PodSpec only pattern-matches keys off the net map; their contents
  # are opaque sentinels here (the real shapes are exercised in the
  # Manifests tests). The point is that PodSpec wires them into the
  # right places.
  defp net_fixture do
    %{
      init_container: %{"name" => "condukt-egress-init"},
      sidecar_container: %{"name" => "condukt-egress"},
      secret_volume: %{"name" => "condukt-net", "secret" => %{"secretName" => "condukt-net-s1"}},
      workspace_volume_mounts: [
        %{"name" => "condukt-net", "mountPath" => "/etc/condukt/ca.pem", "readOnly" => true}
      ]
    }
  end

  defp workspace_container(manifest) do
    Enum.find(manifest["spec"]["containers"], &(&1["name"] == PodSpec.container_name()))
  end

  describe "build/1 without a network policy" do
    test "produces a single workspace container with only the workspace volume mount" do
      manifest = PodSpec.build(config())

      assert manifest["apiVersion"] == "v1"
      assert manifest["kind"] == "Pod"
      assert manifest["metadata"]["name"] == "pod-1"
      assert manifest["metadata"]["namespace"] == "agents"
      assert manifest["metadata"]["labels"] == %{"app" => "condukt"}

      assert [container] = manifest["spec"]["containers"]
      assert container["name"] == "agent"
      assert container["image"] == "debian:bookworm-slim"
      assert container["command"] == ["sleep", "infinity"]
      assert container["workingDir"] == "/workspace"

      assert container["volumeMounts"] == [
               %{"name" => "condukt-workspace", "mountPath" => "/workspace"}
             ]

      assert manifest["spec"]["volumes"] == [
               %{"name" => "condukt-workspace", "emptyDir" => %{}}
             ]

      refute Map.has_key?(manifest["spec"], "initContainers")
      assert manifest["spec"]["restartPolicy"] == "Always"
    end

    test "omits env when the env map is empty" do
      manifest = PodSpec.build(config())
      refute Map.has_key?(workspace_container(manifest), "env")
    end

    test "maps the operator env map verbatim when present" do
      manifest = PodSpec.build(config(%{env: %{"FOO" => "bar"}}))

      assert workspace_container(manifest)["env"] == [%{"name" => "FOO", "value" => "bar"}]
    end

    test "wires resources, service account, and active deadline when present" do
      manifest =
        PodSpec.build(
          config(%{
            resources: %{"limits" => %{"cpu" => "1"}},
            service_account: "condukt-runner",
            active_deadline_seconds: 3600
          })
        )

      assert workspace_container(manifest)["resources"] == %{"limits" => %{"cpu" => "1"}}
      assert manifest["spec"]["serviceAccountName"] == "condukt-runner"
      assert manifest["spec"]["activeDeadlineSeconds"] == 3600
    end
  end

  describe "build/1 with a network policy (:net)" do
    test "adds the egress sidecar as a second container" do
      net = net_fixture()
      manifest = PodSpec.build(config(%{net: net}))

      containers = manifest["spec"]["containers"]
      assert length(containers) == 2
      assert Enum.map(containers, & &1["name"]) == ["agent", "condukt-egress"]
      assert List.last(containers) == net.sidecar_container
    end

    test "adds the init container under initContainers" do
      net = net_fixture()
      manifest = PodSpec.build(config(%{net: net}))

      assert manifest["spec"]["initContainers"] == [net.init_container]
    end

    test "appends the secret volume after the workspace volume" do
      net = net_fixture()
      manifest = PodSpec.build(config(%{net: net}))

      assert manifest["spec"]["volumes"] == [
               %{"name" => "condukt-workspace", "emptyDir" => %{}},
               net.secret_volume
             ]
    end

    test "appends the net workspace volume mounts to the workspace container" do
      net = net_fixture()
      manifest = PodSpec.build(config(%{net: net}))

      assert workspace_container(manifest)["volumeMounts"] ==
               [%{"name" => "condukt-workspace", "mountPath" => "/workspace"}] ++
                 net.workspace_volume_mounts
    end

    test "injects the CA env vars, with operator env last so it can override" do
      manifest = PodSpec.build(config(%{net: net_fixture(), env: %{"FOO" => "bar"}}))

      env = workspace_container(manifest)["env"]
      assert env == Manifests.workspace_ca_env() ++ [%{"name" => "FOO", "value" => "bar"}]
      assert List.last(env) == %{"name" => "FOO", "value" => "bar"}
    end

    test "injects the CA env vars even when the operator env is empty" do
      manifest = PodSpec.build(config(%{net: net_fixture()}))

      assert workspace_container(manifest)["env"] == Manifests.workspace_ca_env()
    end
  end
end
