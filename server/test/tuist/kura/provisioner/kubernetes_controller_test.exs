defmodule Tuist.Kura.Provisioner.KubernetesControllerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Mesh
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

      assert manifest["metadata"]["annotations"]["tuist.dev/kura-manifest-revision"] ==
               KubernetesController.manifest_revision()

      spec = manifest["spec"]
      assert spec["accountHandle"] == "tuist"
      assert spec["tenantID"] == "tuist"
      assert spec["region"] == "eu-central"
      assert spec["image"] == "ghcr.io/tuist/kura:0.5.2"
      assert spec["publicHost"] == "tuist-eu-central-1.kura.tuist.dev"
      # gRPC co-hosts on the single public host: grpcPublicHost == publicHost.
      assert spec["grpcPublicHost"] == "tuist-eu-central-1.kura.tuist.dev"
      assert spec["ingressClassName"] == "kura-eu-central"
      refute Map.has_key?(spec, "peerTLSSecretName")
      refute Map.has_key?(spec, "tlsSecretName")
      assert spec["storageClassName"] == "hcloud-volumes"
      assert spec["nodeSelector"] == %{"node.cluster.x-k8s.io/pool" => "kura"}
      assert spec["extensionScript"] == "return true"

      refute Map.has_key?(spec, "resources")
      refute Map.has_key?(spec, "podAnnotations")

      env = Map.new(spec["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_CONTROL_PLANE_URL"] == "https://tuist.dev"
      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] == "https://tuist.dev"
      assert env["KURA_CONTROL_PLANE_CLIENT_ID"] == "00000000-0000-0000-0000-000000000001"
      refute Map.has_key?(env, "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID")

      refute Map.has_key?(env, "KURA_PEERS")

      # Tuist platform secrets (JWT verifier) live in the
      # kura-shared-secrets Kubernetes Secret; the controller envFroms
      # them into the pod. They must NEVER appear in the spec, since
      # anyone with list/watch on KuraInstance would otherwise read the
      # global JWT signing secret.
      refute Map.has_key?(env, "KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET")
    end

    test "reserves the Egress floor for enterprise accounts" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :get_current_active_subscription, fn _ -> %{plan: :enterprise} end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{
            egress_guaranteed_mbps: 25,
            pod_annotations: %{"kubernetes.io/egress-bandwidth" => "1500M"}
          }),
          %Server{},
          "return true"
        )

      spec = manifest["spec"]
      # Enterprise floor: bin-packed against the node's tuist.dev/egress-mbps capacity.
      assert spec["egressGuaranteedMbps"] == 25
      # Burst ceiling rides the pod annotation (everyone gets it).
      assert spec["podAnnotations"] == %{"kubernetes.io/egress-bandwidth" => "1500M"}
    end

    test "withholds the egress floor from non-enterprise accounts (burst ceiling only)" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :get_current_active_subscription, fn _ -> %{plan: :air} end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{
            egress_guaranteed_mbps: 25,
            pod_annotations: %{"kubernetes.io/egress-bandwidth" => "1500M"}
          }),
          %Server{},
          "return true"
        )

      spec = manifest["spec"]
      # No floor for the bursty default tenant ...
      refute Map.has_key?(spec, "egressGuaranteedMbps")
      # ... but the burst ceiling still applies.
      assert spec["podAnnotations"] == %{"kubernetes.io/egress-bandwidth" => "1500M"}
    end

    test "emits the mesh flag only when the region enables the per-account peer mesh" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      meshed =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{},
          "return true"
        )

      assert meshed["spec"]["mesh"] == true

      unmeshed =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{},
          "return true"
        )

      refute Map.has_key?(unmeshed["spec"], "mesh")
    end

    test "emits the public peer host and external peers for a meshed region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      bridged =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{},
          "return true",
          nil,
          ["https://kura.acme.example:7443"]
        )

      assert bridged["spec"]["meshPublicPeerHost"] == "peer.tuist-eu-central-1.kura.tuist.dev"
      assert bridged["spec"]["meshExternalPeers"] == ["https://kura.acme.example:7443"]

      assert bridged["spec"]["meshPublicPeerLoadBalancerAnnotations"] == %{
               "load-balancer.hetzner.cloud/location" => "fsn1",
               "load-balancer.hetzner.cloud/node-selector" => "node.cluster.x-k8s.io/pool=kura"
             }

      unbridged =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{},
          "return true"
        )

      refute Map.has_key?(unbridged["spec"], "meshPublicPeerHost")
      refute Map.has_key?(unbridged["spec"], "meshExternalPeers")
    end

    test "fronts the public peer plane with host-network + failover IP on a bare-metal region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      host_network =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{mesh: true, gateway: :host_network, hetzner_location: nil, failover_ip: "203.0.113.10"}),
          %Server{},
          "return true"
        )

      assert host_network["spec"]["meshPeerHostNetwork"] == true
      assert host_network["spec"]["meshPeerFailoverIp"] == "203.0.113.10"
      # The Hetzner peer LoadBalancer annotations drop out on host-network regions.
      refute Map.has_key?(host_network["spec"], "meshPublicPeerLoadBalancerAnnotations")

      hetzner =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{},
          "return true"
        )

      refute Map.has_key?(hetzner["spec"], "meshPeerHostNetwork")
      refute Map.has_key?(hetzner["spec"], "meshPeerFailoverIp")
    end

    test "omits external peers for a meshed region with no self-hosted nodes" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{},
          "return true",
          nil,
          []
        )

      assert manifest["spec"]["meshPublicPeerHost"] == "peer.tuist-eu-central-1.kura.tuist.dev"
      refute Map.has_key?(manifest["spec"], "meshExternalPeers")
    end

    test "emits tolerations only when the region declares them" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      tolerations = [%{"key" => "tuist.dev/runner-cache", "operator" => "Exists", "effect" => "NoSchedule"}]

      tolerated =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{tolerations: tolerations}),
          %Server{},
          "return true"
        )

      assert tolerated["spec"]["tolerations"] == tolerations

      untolerated =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{},
          "return true"
        )

      refute Map.has_key?(untolerated["spec"], "tolerations")
    end

    test "normalizes account handles for DNS-label KuraInstance fields" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-bumble-eu-central-1",
          "0.5.2",
          %{name: "Bumble"},
          eu_region(),
          %Server{},
          "return true"
        )

      assert manifest["metadata"]["labels"]["tuist.dev/account"] == "bumble"

      spec = manifest["spec"]
      assert spec["accountHandle"] == "bumble"
      assert spec["tenantID"] == "bumble"
      assert spec["publicHost"] == "bumble-eu-central-1.kura.tuist.dev"
      assert spec["grpcPublicHost"] == "bumble-eu-central-1.kura.tuist.dev"
    end

    test "uses an opaque dedicated gateway class when the account is assigned to dedicated Kura ingress" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      region =
        us_east_region(%{
          dedicated_gateway_account_handles: ["tuist"]
        })

      manifest =
        KubernetesController.manifest(
          "kura-tuist-us-east-1",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{},
          "return true"
        )

      gateway_name = manifest["metadata"]["annotations"]["tuist.dev/kura-gateway"]

      assert String.starts_with?(gateway_name, "kgw-")
      refute String.contains?(gateway_name, "tuist")
      assert manifest["spec"]["ingressClassName"] == "kura-us-east-#{gateway_name}"

      gateway_manifest =
        KubernetesController.gateway_manifest(
          %{name: gateway_name, ingress_class_name: manifest["spec"]["ingressClassName"]},
          %{name: "tuist"},
          region
        )

      assert gateway_manifest["kind"] == "KuraGateway"
      assert gateway_manifest["metadata"]["name"] == gateway_name
      assert gateway_manifest["spec"]["region"] == "us-east"
      assert gateway_manifest["spec"]["ingressClassName"] == "kura-us-east-#{gateway_name}"
      assert gateway_manifest["spec"]["nodeSelector"] == %{"node.cluster.x-k8s.io/pool" => "kura-us-east"}

      annotations = gateway_manifest["spec"]["loadBalancerAnnotations"]
      assert annotations["load-balancer.hetzner.cloud/location"] == "ash"
      assert annotations["load-balancer.hetzner.cloud/uses-proxyprotocol"] == "true"
      assert String.starts_with?(annotations["load-balancer.hetzner.cloud/name"], "tuist-kgw-")
      refute String.contains?(annotations["load-balancer.hetzner.cloud/name"], "tuist-us")

      refute Map.has_key?(gateway_manifest["spec"], "hostNetwork")
    end

    test "uses the shared regional ingress class (no dedicated gateway) for a dedicated account on a host-network region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      # tuist is a dedicated-gateway account, but on a host-network (bare-metal)
      # region a second per-account host-network gateway can't bind the box's
      # :443, so the account falls back to the shared regional gateway.
      region =
        us_east_region(%{
          gateway: :host_network,
          dedicated_gateway_account_handles: ["tuist"]
        })

      manifest =
        KubernetesController.manifest(
          "kura-tuist-us-east-1",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{},
          "return true"
        )

      assert manifest["spec"]["ingressClassName"] == "kura-us-east"
      refute Map.has_key?(manifest["metadata"]["annotations"], "tuist.dev/kura-gateway")
    end

    test "renders a host-network gateway without Hetzner LoadBalancer annotations on bare-metal regions" do
      region =
        us_east_region(%{
          gateway: :host_network,
          dedicated_gateway_account_handles: ["tuist"]
        })

      gateway_manifest =
        KubernetesController.gateway_manifest(
          %{name: "kgw-test-us-east", ingress_class_name: "kura-us-east-kgw-test-us-east"},
          %{name: "tuist"},
          region
        )

      assert gateway_manifest["spec"]["hostNetwork"] == true
      refute Map.has_key?(gateway_manifest["spec"], "loadBalancerAnnotations")
    end

    test "propagates the region tolerations onto the gateway so it schedules on tainted bare-metal nodes" do
      tolerations = [%{"key" => "tuist.dev/kura-cache", "operator" => "Exists", "effect" => "NoSchedule"}]

      gateway_manifest =
        KubernetesController.gateway_manifest(
          %{name: "kgw-test-us-east", ingress_class_name: "kura-us-east-kgw-test-us-east"},
          %{name: "tuist"},
          us_east_region(%{gateway: :host_network, tolerations: tolerations})
        )

      assert gateway_manifest["spec"]["tolerations"] == tolerations
    end

    test "omits gateway tolerations when the region declares none" do
      gateway_manifest =
        KubernetesController.gateway_manifest(
          %{name: "kgw-test-us-east", ingress_class_name: "kura-us-east-kgw-test-us-east"},
          %{name: "tuist"},
          us_east_region(%{gateway: :host_network})
        )

      refute Map.has_key?(gateway_manifest["spec"], "tolerations")
    end

    test "uses the region-configured Tuist server URL for managed eu-central Kura instances" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{
            tuist_base_url: "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"
          }),
          %Server{},
          "return true"
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      assert env["KURA_CONTROL_PLANE_URL"] ==
               "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"

      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] ==
               "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"
    end

    test "falls back to the app URL when the region has no configured Tuist server URL" do
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

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      assert env["KURA_CONTROL_PLANE_URL"] == "https://tuist.dev"
      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] == "https://tuist.dev"
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
      refute Map.has_key?(spec, "ingressClassName")
      refute Map.has_key?(spec, "publicHost")
      refute Map.has_key?(spec, "grpcPublicHost")

      env = Map.new(spec["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_CONTROL_PLANE_URL"] == "http://host.docker.internal:8080"

      assert env["KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL"] ==
               "http://host.docker.internal:8080"

      assert env["KURA_CONTROL_PLANE_CLIENT_ID"] == "00000000-0000-0000-0000-000000000001"
      refute Map.has_key?(env, "KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID")

      assert env["KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] == "http://127.0.0.1:4318/v1/traces"
    end
  end

  describe "manifest_revision/2" do
    test "matches the base revision when no self-hosted peers are enrolled" do
      stub(Mesh, :self_hosted_peer_urls, fn _ -> [] end)

      assert KubernetesController.manifest_revision(%{name: "tuist"}, eu_region(%{mesh: true})) ==
               KubernetesController.manifest_revision()
    end

    test "changes when a peer is enrolled, matching the rendered manifest annotation" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      region = eu_region(%{mesh: true})
      peers = ["https://kura.acme.example:7443"]
      stub(Mesh, :self_hosted_peer_urls, fn _ -> peers end)

      revision = KubernetesController.manifest_revision(%{name: "tuist"}, region)
      refute revision == KubernetesController.manifest_revision()

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{},
          "return true",
          nil,
          peers
        )

      assert manifest["metadata"]["annotations"]["tuist.dev/kura-manifest-revision"] == revision
    end

    test "is independent of the peer ordering" do
      region = eu_region(%{mesh: true})

      stub(Mesh, :self_hosted_peer_urls, fn _ -> ["https://b.example:7443", "https://a.example:7443"] end)
      sorted = KubernetesController.manifest_revision(%{name: "tuist"}, region)

      stub(Mesh, :self_hosted_peer_urls, fn _ -> ["https://a.example:7443", "https://b.example:7443"] end)
      reordered = KubernetesController.manifest_revision(%{name: "tuist"}, region)

      assert sorted == reordered
    end

    test "ignores peers for a region without the mesh enabled" do
      reject(&Mesh.self_hosted_peer_urls/1)

      assert KubernetesController.manifest_revision(%{name: "tuist"}, eu_region()) ==
               KubernetesController.manifest_revision()
    end
  end

  describe "rollout/2" do
    test "applies the KuraInstance without waiting for controller readiness" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      expect(Client, :apply, fn manifest, [] ->
        assert manifest["metadata"]["name"] == "kura-tuist-eu-central-1"
        assert manifest["spec"]["image"] == "ghcr.io/tuist/kura:0.5.2"
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

    test "applies managed US regions with the in-cluster Kubernetes client" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      region = us_east_region()

      expect(Client, :apply, fn manifest, [] ->
        assert manifest["metadata"]["name"] == "kura-tuist-us-east-1"
        assert manifest["spec"]["region"] == "us-east"
        assert manifest["spec"]["ingressClassName"] == "kura-us-east"
        assert manifest["spec"]["nodeSelector"] == %{"node.cluster.x-k8s.io/pool" => "kura-us-east"}
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

    test "applies a dedicated KuraGateway before the KuraInstance when the account is assigned to dedicated ingress" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      region =
        us_east_region(%{
          dedicated_gateway_account_handles: ["tuist"]
        })

      test_process = self()

      expect(Client, :apply, 2, fn manifest, [] ->
        send(test_process, {:applied, manifest})
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

      assert_receive {:applied, %{"kind" => "KuraGateway"} = gateway_manifest}
      assert_receive {:applied, %{"kind" => "KuraInstance"} = instance_manifest}

      assert instance_manifest["metadata"]["annotations"]["tuist.dev/kura-gateway"] ==
               gateway_manifest["metadata"]["name"]

      assert instance_manifest["spec"]["ingressClassName"] ==
               gateway_manifest["spec"]["ingressClassName"]
    end
  end

  describe "destroy/2" do
    test "deletes the KuraInstance and treats already-missing resources as gone" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-eu-central-1", [] ->
        {:error, :not_found}
      end)

      expect(Client, :delete_kura_instance, fn "kura", "kura-tuist-eu-central-1", [] ->
        {:error, :not_found}
      end)

      assert :ok = KubernetesController.destroy("kura-tuist-eu-central-1", eu_region())
    end

    test "deletes an assigned dedicated KuraGateway before deleting the KuraInstance" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-us-east-1", [] ->
        {:ok,
         %{
           "metadata" => %{
             "annotations" => %{"tuist.dev/kura-gateway" => "kgw-abc123-us-east"}
           }
         }}
      end)

      expect(Client, :delete_kura_gateway, fn "kura", "kgw-abc123-us-east", [] ->
        :ok
      end)

      expect(Client, :delete_kura_instance, fn "kura", "kura-tuist-us-east-1", [] ->
        :ok
      end)

      assert :ok = KubernetesController.destroy("kura-tuist-us-east-1", us_east_region())
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
               "grpcs://tuist-eu-central-1.kura.tuist.dev"
    end

    test "returns nil when the region has no gRPC host configured" do
      assert KubernetesController.grpc_public_url("TUIST", local_controller_region(), "any-ref") ==
               nil
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
               KubernetesController.current_image_tag(
                 "kura-tuist-local-controller",
                 local_controller_region()
               )
    end
  end

  describe "image_tag_from_image/1" do
    test "extracts the tag from a normal image reference" do
      assert KubernetesController.image_tag_from_image("ghcr.io/tuist/kura:0.5.2") == "0.5.2"
    end

    test "extracts the tag from an image reference that uses a registry port" do
      assert KubernetesController.image_tag_from_image("localhost:5001/tuist/kura:0.5.2") ==
               "0.5.2"
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

  defp eu_region(extra_config \\ %{}) do
    %Regions{
      id: "eu-central",
      provisioner_config:
        Map.merge(
          %{
            cluster_id: "eu-central-1",
            hetzner_location: "fsn1",
            public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
            grpc_public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
            peer_public_host_template: "peer.{account_handle}-{cluster_id}.kura.tuist.dev",
            ingress_class_name: "kura-eu-central",
            storage_class: "hcloud-volumes",
            node_selector: %{"node.cluster.x-k8s.io/pool" => "kura"}
          },
          extra_config
        )
    }
  end

  defp us_east_region(extra_config \\ %{}) do
    %Regions{
      id: "us-east",
      provisioner_config:
        Map.merge(
          %{
            cluster_id: "us-east-1",
            hetzner_location: "ash",
            public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
            grpc_public_host_template: "{account_handle}-{cluster_id}.kura.tuist.dev",
            ingress_class_name: "kura-us-east",
            storage_class: "hcloud-volumes",
            node_selector: %{"node.cluster.x-k8s.io/pool" => "kura-us-east"}
          },
          extra_config
        )
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

  describe "manifest/6 for a private runner-cache region" do
    test "marks the instance private and omits public/ingress fields" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      spec =
        KubernetesController.manifest(
          "kura-tuist-scw-fr-par",
          "0.5.2",
          %{name: "tuist"},
          scaleway_region(),
          %Server{},
          "return true"
        )["spec"]

      assert spec["private"] == true
      assert spec["storageClassName"] == "scw-bssd"
      assert spec["replicas"] == 1
      assert spec["nodeSelector"] == %{"node.cluster.x-k8s.io/pool" => "kura-scw-fr-par"}
      # No public endpoint, no ingress, no cert — runners reach the
      # pod by Kubernetes Service DNS over the cluster's internal net.
      refute Map.has_key?(spec, "publicHost")
      refute Map.has_key?(spec, "grpcPublicHost")
      refute Map.has_key?(spec, "ingressClassName")

      # Node-port data plane: the controller publishes http/grpc at the
      # node boundary, admits the PN client subnet through the instance
      # NetworkPolicy, and caps per-account egress on the shared NIC.
      assert spec["exposeNodePort"] == true
      assert spec["clientCIDRs"] == ["172.16.0.0/22"]
      assert spec["podAnnotations"] == %{"kubernetes.io/egress-bandwidth" => "750M"}
    end

    test "omits node-port fields for cluster-DNS private regions" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      region = %Regions{
        id: "hetzner-staging-runners",
        provisioner_config: %{
          cluster_id: "staging",
          private: true,
          private_url_template: "http://{instance}.kura.svc.cluster.local:4000",
          data_plane: :cluster_dns,
          client_cidrs: [],
          pod_annotations: %{},
          node_selector: %{"node.cluster.x-k8s.io/pool" => "kura"},
          storage_class: "hcloud-volumes",
          replicas: 1
        }
      }

      spec =
        KubernetesController.manifest(
          "kura-tuist-staging",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{},
          "return true"
        )["spec"]

      refute Map.has_key?(spec, "exposeNodePort")
      refute Map.has_key?(spec, "clientCIDRs")
      refute Map.has_key?(spec, "podAnnotations")
    end
  end

  describe "external_endpoint/2" do
    test "builds the node-published URL from the observed status" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-scw-fr-par", [] ->
        {:ok, %{"status" => %{"nodeAddress" => "172.16.0.2", "nodePortHTTP" => 30_080}}}
      end)

      assert KubernetesController.external_endpoint("kura-tuist-scw-fr-par", scaleway_region()) ==
               {:ok, "http://172.16.0.2:30080"}
    end

    test "is not ready until the controller observed the full chain" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-scw-fr-par", [] ->
        {:ok, %{"status" => %{"nodePortHTTP" => 30_080}}}
      end)

      assert KubernetesController.external_endpoint("kura-tuist-scw-fr-par", scaleway_region()) ==
               {:error, :node_port_endpoint_not_ready}
    end

    test "propagates client errors" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-scw-fr-par", [] ->
        {:error, :timeout}
      end)

      assert KubernetesController.external_endpoint("kura-tuist-scw-fr-par", scaleway_region()) ==
               {:error, :timeout}
    end
  end

  describe "public_url/3 for a private region" do
    test "returns the in-cluster Service DNS URL built from private_url_template" do
      assert KubernetesController.public_url("TUIST", scaleway_region(), "any-ref") ==
               "http://kura-tuist-scw-fr-par.kura.svc.cluster.local:4000"
    end
  end

  defp scaleway_region do
    %Regions{
      id: "scw-fr-par-runners",
      provisioner_config: %{
        cluster_id: "scw-fr-par",
        private: true,
        private_url_template: "http://{instance}.kura.svc.cluster.local:4000",
        data_plane: :node_port,
        client_cidrs: ["172.16.0.0/22"],
        pod_annotations: %{"kubernetes.io/egress-bandwidth" => "750M"},
        node_selector: %{"node.cluster.x-k8s.io/pool" => "kura-scw-fr-par"},
        storage_class: "scw-bssd",
        replicas: 1
      }
    }
  end
end
