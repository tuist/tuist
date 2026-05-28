defmodule Tuist.Kura.Provisioner.KubernetesControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  setup :set_mimic_from_context

  describe "manifest/6" do
    test "renders a KuraInstance without a per-account compute spec" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{},
          "return true"
        )

      assert manifest["apiVersion"] == "kura.tuist.dev/v1alpha1"
      assert manifest["kind"] == "KuraInstance"
      assert manifest["metadata"]["name"] == "kura-tuist-eu-central-1"
      assert manifest["metadata"]["namespace"] == "kura"

      spec = manifest["spec"]
      assert spec["accountHandle"] == "tuist"
      assert spec["tenantID"] == "tuist"
      assert spec["region"] == "eu-central"
      assert spec["image"] == "ghcr.io/tuist/kura:0.5.2"
      assert spec["publicHost"] == "tuist-eu-central-1.kura.tuist.dev"
      assert spec["grpcPublicHost"] == "grpc.tuist-eu-central-1.kura.tuist.dev"
      refute Map.has_key?(spec, "tlsSecretName")
      assert spec["storageClassName"] == "hcloud-volumes"
      assert spec["extensionScript"] == "return true"

      refute Map.has_key?(spec, "resources")
      refute Map.has_key?(spec, "podAnnotations")

      env = Map.new(spec["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_CONTROL_PLANE_URL"] == "https://tuist.dev"
      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] == "https://tuist.dev"
      assert env["KURA_CONTROL_PLANE_CLIENT_ID"] == "00000000-0000-0000-0000-000000000001"

      assert env["KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID"] ==
               "00000000-0000-0000-0000-000000000001"

      # Tuist platform secrets (JWT verifier) live in the
      # kura-shared-secrets Kubernetes Secret; the controller envFroms
      # them into the pod. They must NEVER appear in the spec, since
      # anyone with list/watch on KuraInstance would otherwise read the
      # global JWT signing secret.
      refute Map.has_key?(env, "KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET")
    end

    test "renders local controller overrides for kind testing" do
      stub(Tuist.Environment, :app_url, fn -> "http://localhost:8080" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-local-controller",
          "0.5.2",
          %{name: "tuist"},
          local_controller_region(),
          %Server{},
          "return true"
        )

      spec = manifest["spec"]
      assert spec["region"] == "local-controller"
      assert spec["replicas"] == 1
      assert spec["storageSize"] == "10Gi"
      assert spec["nodeSelector"] == %{"kubernetes.io/os" => "linux"}
      refute Map.has_key?(spec, "publicHost")
      refute Map.has_key?(spec, "grpcPublicHost")

      env = Map.new(spec["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_CONTROL_PLANE_URL"] == "http://host.docker.internal:8080"
      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] == "http://host.docker.internal:8080"
      assert env["KURA_CONTROL_PLANE_CLIENT_ID"] == "00000000-0000-0000-0000-000000000001"

      assert env["KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID"] ==
               "00000000-0000-0000-0000-000000000001"

      assert env["KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] == "http://127.0.0.1:4318/v1/traces"
    end
  end

  describe "rollout/2" do
    test "applies the KuraInstance without waiting for controller readiness" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      expect(Client, :apply, fn manifest ->
        assert manifest["metadata"]["name"] == "kura-tuist-eu-central-1"
        assert manifest["spec"]["image"] == "ghcr.io/tuist/kura:0.5.2"
        assert manifest["spec"]["globalPublicHost"] == "tuist.kura.tuist.dev"
        assert manifest["spec"]["globalGrpcPublicHost"] == "grpc.tuist.kura.tuist.dev"
        assert manifest["spec"]["cloudflarePoolLatitude"] == 50.4779
        assert manifest["spec"]["cloudflarePoolLongitude"] == 12.3713
        {:ok, manifest}
      end)

      assert :ok =
               KubernetesController.rollout("kura-tuist-eu-central-1", %{
                 image_tag: "0.5.2",
                 account: %{name: "tuist"},
                 server: %Server{},
                 region: eu_region(),
                 hook_script: "return true"
               })
    end

    test "passes regional Kubernetes client options through" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      region = us_east_region()
      client_opts = [mode: :kubeconfig, cluster_id: "us-east-1"]

      expect(Client, :apply, fn manifest, opts ->
        assert opts == client_opts
        assert manifest["metadata"]["name"] == "kura-tuist-us-east-1"
        assert manifest["spec"]["region"] == "us-east"
        {:ok, manifest}
      end)

      assert :ok =
               KubernetesController.rollout("kura-tuist-us-east-1", %{
                 image_tag: "0.5.2",
                 account: %{name: "tuist"},
                 server: %Server{},
                 region: region,
                 hook_script: "return true"
               })
    end
  end

  describe "destroy/2" do
    test "deletes the KuraInstance and treats already-missing resources as gone" do
      expect(Client, :delete_kura_instance, fn "kura", "kura-tuist-eu-central-1" -> {:error, :not_found} end)

      assert :ok = KubernetesController.destroy("kura-tuist-eu-central-1", eu_region())
    end
  end

  describe "public_url/3" do
    test "interpolates the production host template with the account handle" do
      assert KubernetesController.public_url("TUIST", eu_region(), "any-ref") ==
               "https://tuist-eu-central-1.kura.tuist.dev"
    end

    test "uses the configured public URL for local controller regions" do
      assert KubernetesController.public_url("TUIST", local_controller_region(), "any-ref") ==
               "http://localhost:4100"
    end
  end

  describe "grpc_public_url/3" do
    test "interpolates the gRPC host template with the account handle" do
      assert KubernetesController.grpc_public_url("TUIST", eu_region(), "any-ref") ==
               "grpcs://grpc.tuist-eu-central-1.kura.tuist.dev"
    end

    test "returns nil when the region has no gRPC host configured" do
      assert KubernetesController.grpc_public_url("TUIST", local_controller_region(), "any-ref") ==
               nil
    end
  end

  describe "global_public_url_for_handle/2" do
    test "interpolates the account-level production host template with the account handle" do
      assert KubernetesController.global_public_url_for_handle("TUIST", eu_region()) ==
               "https://tuist.kura.tuist.dev"
    end

    test "returns nil when the region has no global host configured" do
      assert KubernetesController.global_public_url_for_handle("TUIST", local_controller_region()) == nil
    end
  end

  describe "global_public_url/2" do
    test "returns the controller-observed global public URL" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-eu-central-1", opts ->
        assert opts == []

        {:ok, %{"status" => %{"globalPublicURL" => "https://tuist.kura.tuist.dev"}}}
      end)

      assert KubernetesController.global_public_url("kura-tuist-eu-central-1", eu_region()) ==
               "https://tuist.kura.tuist.dev"
    end

    test "returns nil before the controller reports a global public URL" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-eu-central-1", _opts ->
        {:ok, %{"status" => %{}}}
      end)

      assert KubernetesController.global_public_url("kura-tuist-eu-central-1", eu_region()) == nil
    end
  end

  describe "current_image_tag/2" do
    test "passes local Kubernetes client options through" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-local-controller", opts ->
        assert opts == [
                 mode: :kubeconfig,
                 kubeconfig_path: Path.expand("~/.kube/config"),
                 context: "kind-kura-dev-0"
               ]

        {:ok, %{"status" => %{"observedImage" => "ghcr.io/tuist/kura:sha-abcdef123456"}}}
      end)

      assert {:ok, "sha-abcdef123456"} =
               KubernetesController.current_image_tag("kura-tuist-local-controller", local_controller_region())
    end
  end

  describe "image_tag_from_image/1" do
    test "extracts the tag from a normal image reference" do
      assert KubernetesController.image_tag_from_image("ghcr.io/tuist/kura:0.5.2") == "0.5.2"
    end

    test "extracts the tag from an image reference that uses a registry port" do
      assert KubernetesController.image_tag_from_image("localhost:5001/tuist/kura:0.5.2") == "0.5.2"
    end

    test "returns nil when the image reference has no tag" do
      assert KubernetesController.image_tag_from_image("ghcr.io/tuist/kura") == nil
      assert KubernetesController.image_tag_from_image("ghcr.io/tuist/kura@sha256:abc123") == nil
    end

    test "extracts the tag from a reference that also has a digest" do
      assert KubernetesController.image_tag_from_image("ghcr.io/tuist/kura:sha-abcdef123456@sha256:abc123") ==
               "sha-abcdef123456"
    end
  end

  describe "resources_for/1" do
    test "does not expose per-account Kubernetes resources" do
      assert KubernetesController.resources_for(%Server{}) == %{}
    end
  end

  defp eu_region do
    %Regions{
      id: "eu-central",
      provisioner_config: %{
        cluster_id: "eu-central-1",
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        global_public_host_template: "{account_handle}.kura.tuist.dev",
        global_grpc_public_host_template: "grpc.{account_handle}.kura.tuist.dev",
        cloudflare_pool_latitude: 50.4779,
        cloudflare_pool_longitude: 12.3713,
        storage_class: "hcloud-volumes"
      }
    }
  end

  defp us_east_region do
    %Regions{
      id: "us-east",
      provisioner_config: %{
        cluster_id: "us-east-1",
        kubernetes_client: [mode: :kubeconfig, cluster_id: "us-east-1"],
        public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
        grpc_public_host_template: "grpc.{account_handle}-{cluster_id}.kura.tuist.dev",
        storage_class: "hcloud-volumes"
      }
    }
  end

  defp local_controller_region do
    %Regions{
      id: "local-controller",
      provisioner_config: %{
        cluster_id: "local-controller",
        kubernetes_client: [
          mode: :kubeconfig,
          kubeconfig_path: Path.expand("~/.kube/config"),
          context: "kind-kura-dev-0"
        ],
        node_selector: %{"kubernetes.io/os" => "linux"},
        otlp_traces_endpoint: "http://127.0.0.1:4318/v1/traces",
        public_url: "http://localhost:4100",
        replicas: 1,
        storage_size: "10Gi"
      }
    }
  end
end
