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
          %Server{}
        )

      assert manifest["apiVersion"] == "kura.tuist.dev/v1alpha1"
      assert manifest["kind"] == "KuraInstance"
      assert manifest["metadata"]["name"] == "kura-tuist-eu-central-1"
      assert manifest["metadata"]["namespace"] == "kura"

      assert manifest["metadata"]["annotations"]["tuist.dev/kura-manifest-revision"] ==
               KubernetesController.manifest_revision() <> "+backfill"

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
      refute Map.has_key?(spec, "extensionScript")

      refute Map.has_key?(spec, "resources")
      refute Map.has_key?(spec, "podAnnotations")

      env = Map.new(spec["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_CONTROL_PLANE_URL"] == "https://tuist.dev"
      assert env["KURA_AUTH_TUIST_URL"] == "https://tuist.dev"

      # Paired with the URL on purpose. A node reads a blank URL as no
      # configuration and starts serving the cache unauthorized; with this set
      # it refuses to start, so the failure is visible rather than silent.
      assert env["KURA_AUTH_ENABLED"] == "true"
      assert env["KURA_CONTROL_PLANE_CLIENT_ID"] == "00000000-0000-0000-0000-000000000001"
      refute Map.has_key?(env, "KURA_CONTROL_PLANE_CLIENT_SECRET")

      refute Map.has_key?(env, "KURA_PEERS")

      # The verifier material lives in the kura-shared-secrets Kubernetes
      # Secret; the controller envFroms it into the pod. It must NEVER
      # appear in the spec, which anyone with list/watch on KuraInstance
      # can read. The signing secret must not reach a node at all — it
      # would let one mint what it verifies — and even the public half
      # belongs in the Secret rather than here.
      refute Map.has_key?(env, "KURA_AUTH_JWT_SECRET")
      refute Map.has_key?(env, "KURA_AUTH_JWT_PUBLIC_KEY")
    end

    test "reserves the Egress floor for enterprise accounts" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{
            egress_guaranteed_mbps: 25,
            pod_annotations: %{"kubernetes.io/egress-bandwidth" => "1500M"}
          }),
          %Server{}
        )

      spec = manifest["spec"]
      # Enterprise floor: bin-packed against the node's tuist.dev/egress-mbps capacity.
      assert spec["egressGuaranteedMbps"] == 25
      # Burst ceiling rides the pod annotation (everyone gets it).
      assert spec["podAnnotations"] == %{"kubernetes.io/egress-bandwidth" => "1500M"}
    end

    test "renders a zero egress floor for non-enterprise accounts" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{
            egress_guaranteed_mbps: 25,
            pod_annotations: %{"kubernetes.io/egress-bandwidth" => "1500M"}
          }),
          %Server{}
        )

      spec = manifest["spec"]
      # Zero keeps the effective value explicit without requesting the extended resource.
      assert spec["egressGuaranteedMbps"] == 0
      # The burst ceiling still applies.
      assert spec["podAnnotations"] == %{"kubernetes.io/egress-bandwidth" => "1500M"}
    end

    test "sizes the memory profile per tier on a box that governs memory" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      profile = fn plan ->
        stub(Tuist.Billing, :effective_plan, fn _ -> plan end)

        spec =
          "kura-tuist-eu-central-1"
          |> KubernetesController.manifest(
            "0.5.2",
            %Account{id: 1, name: "tuist"},
            eu_region(%{memory_governed: true, memory_ceiling_bin_packed: true}),
            %Server{},
            "return true"
          )
          |> Map.fetch!("spec")

        {spec["memoryFloorMib"], spec["memoryCeilingMib"], spec["memoryCeilingBinPacked"]}
      end

      # The floor is the standing reservation, so the tier that gets the larger
      # one is the tier that pays for a guarantee. The ceiling — how large a
      # burst Kura admits before shedding — moves with it.
      assert profile.(:enterprise) == {1024, 4096, true}
      assert profile.(:pro) == {512, 3072, true}
      assert profile.(:air) == {256, 768, true}
    end

    test "sizes a self-hosted deployment off its license rather than a subscription" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      # A self-hosted deployment has no subscriptions, so resolving a plan would
      # put every account on the standard profile. Its Enterprise license is the
      # entitlement, which is why the plan is never looked up here.
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      reject(&Tuist.Billing.effective_plan/1)

      spec =
        "kura-tuist-eu-central-1"
        |> KubernetesController.manifest(
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{memory_governed: true}),
          %Server{},
          "return true"
        )
        |> Map.fetch!("spec")

      assert {spec["memoryFloorMib"], spec["memoryCeilingMib"]} == {1024, 4096}
    end

    test "leaves the memory profile to the controller default on a box that does not govern memory" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      # A pod that requests tuist.dev/memory-ceiling-mib on a node pool the CAPI
      # provider does not patch never schedules, so an ungoverned region must
      # emit nothing at all rather than a profile the node cannot satisfy.
      reject(&Tuist.Billing.effective_plan/1)

      spec =
        "kura-tuist-eu-central-1"
        |> KubernetesController.manifest(
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(),
          %Server{},
          "return true"
        )
        |> Map.fetch!("spec")

      refute Map.has_key?(spec, "memoryFloorMib")
      refute Map.has_key?(spec, "memoryCeilingMib")
      refute Map.has_key?(spec, "memoryCeilingBinPacked")
    end

    test "arms the peer-view sync only for a self-hosting-capable account in a mesh region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      # The self-hosting-capable account can enroll a self-hosted peer, so its
      # pods sync the dynamic peer view and arm Kura's peer-view boot gate.
      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      entitled =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{}
        )

      entitled_env = Map.new(entitled["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      assert entitled_env["KURA_MESH_PEERS_SYNC"] == "true"

      # An account that cannot self-host has a fully static roster, so it must
      # not sync or arm the gate — it would otherwise block its own readiness on
      # a peer view it can never populate.
      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)

      non_entitled =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{}
        )

      non_entitled_env = Map.new(non_entitled["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      refute Map.has_key?(non_entitled_env, "KURA_MESH_PEERS_SYNC")
    end

    test "renders the backfill walker flag for every account, with a matching revision" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_BACKFILL_ENABLED"] == "true"

      # The env must move the revision or the reconciler would never apply it,
      # and the marker is the same one already-gated accounts carry, so they
      # stay byte-identical and are not rolled.
      assert manifest["metadata"]["annotations"]["tuist.dev/kura-manifest-revision"] ==
               KubernetesController.manifest_revision() <> "+backfill"
    end

    test "renders the backfill walker flag for the private runner-cache (co-located) region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      {:ok, region} = Regions.fetch("scw-fr-par-runners")

      manifest =
        KubernetesController.manifest(
          "kura-tuist-scw-fr-par-runners",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          region,
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_BACKFILL_ENABLED"] == "true"
    end

    test "hands the pod the country and subdivision its region's datacenter sits in" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{country: "FR", subdivision: "FR-IDF"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      assert env["KURA_NODE_COUNTRY"] == "FR"
      assert env["KURA_NODE_SUBDIVISION"] == "FR-IDF"
    end

    test "omits both location variables for a region that declares no datacenter location" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      refute Map.has_key?(env, "KURA_NODE_COUNTRY")
      refute Map.has_key?(env, "KURA_NODE_SUBDIVISION")
    end

    test "does not resolve entitlements when the region has no gated manifest fields" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      reject(&Tuist.Billing.effective_plan/1)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      refute Map.has_key?(env, "KURA_MESH_PEERS_SYNC")
      refute Map.has_key?(manifest["spec"], "egressGuaranteedMbps")
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
          %Server{}
        )

      assert meshed["spec"]["mesh"] == true

      unmeshed =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{}
        )

      refute Map.has_key?(unmeshed["spec"], "mesh")
    end

    test "arms peer-view sync only for a self-hosting-capable account in a mesh region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      region = eu_region(%{mesh: true})
      account = %Account{id: 1, name: "tuist"}
      external_peers = ["https://kura.acme.example:7443"]

      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      entitled =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          account,
          region,
          %Server{},
          external_peers
        )

      entitled_env = Map.new(entitled["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      assert entitled_env["KURA_MESH_PEERS_SYNC"] == "true"
      assert entitled["spec"]["meshExternalPeers"] == external_peers

      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)

      non_entitled =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          account,
          region,
          %Server{},
          external_peers
        )

      non_entitled_env = Map.new(non_entitled["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      refute Map.has_key?(non_entitled_env, "KURA_MESH_PEERS_SYNC")
      refute Map.has_key?(non_entitled["spec"], "meshExternalPeers")
    end

    test "resolves the subscription once for every entitlement-dependent manifest field" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      account = %Account{id: 1, name: "tuist"}

      expect(Tuist.Billing, :effective_plan, 1, fn ^account -> :enterprise end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          account,
          eu_region(%{mesh: true, egress_guaranteed_mbps: 25}),
          %Server{},
          ["https://kura.acme.example:7443"]
        )

      assert manifest["spec"]["meshExternalPeers"] == ["https://kura.acme.example:7443"]
      assert manifest["spec"]["egressGuaranteedMbps"] == 25

      assert Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})[
               "KURA_MESH_PEERS_SYNC"
             ] == "true"
    end

    test "withholds peer-view sync outside a mesh region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      refute Map.has_key?(env, "KURA_MESH_PEERS_SYNC")
    end

    test "emits the public peer host and external peers for a meshed region" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      bridged =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %Account{id: 1, name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{},
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
          %Server{}
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
          %Server{}
        )

      assert host_network["spec"]["meshPeerHostNetwork"] == true
      assert host_network["spec"]["meshPeerFailoverIp"] == "203.0.113.10"
      # The customer plane is host-network too, so each account resolves to its
      # own box via a per-account DNSEndpoint the controller publishes.
      assert host_network["spec"]["publicHostNetwork"] == true
      # The Hetzner peer LoadBalancer annotations drop out on host-network regions.
      refute Map.has_key?(host_network["spec"], "meshPublicPeerLoadBalancerAnnotations")

      hetzner =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{mesh: true}),
          %Server{}
        )

      refute Map.has_key?(hetzner["spec"], "meshPeerHostNetwork")
      refute Map.has_key?(hetzner["spec"], "meshPeerFailoverIp")
      # LB regions publish the customer host off the gateway Service/Ingress, so
      # the per-account DNSEndpoint (publicHostNetwork) stays off.
      refute Map.has_key?(hetzner["spec"], "publicHostNetwork")
    end

    test "withholds the customer host and pins the box for a moving-in warm-handoff target" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      region = eu_region(%{gateway: :host_network, mesh: true})

      moving_in =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1-m",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{move_phase: :moving_in, target_node: "box-2"}
        )

      # A warm-handoff target warms on the peer plane only: no customer host, so
      # the controller leaves its Ingress/DNS/Certificate unreconciled and the
      # source keeps sole ownership until the target is promoted.
      refute Map.has_key?(moving_in["spec"], "publicHost")
      refute Map.has_key?(moving_in["spec"], "grpcPublicHost")
      assert moving_in["spec"]["meshPublicPeerHost"] == "peer.tuist-eu-central-1.kura.tuist.dev"
      # And it is pinned to the destination box.
      assert moving_in["spec"]["nodeSelector"]["kubernetes.io/hostname"] == "box-2"

      steady_state =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{move_phase: :none}
        )

      # The steady-state (:none) server owns the customer host.
      assert is_binary(steady_state["spec"]["publicHost"])
      refute Map.get(steady_state["spec"]["nodeSelector"] || %{}, "kubernetes.io/hostname")

      moving_out =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1-source",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{move_phase: :moving_out}
        )

      assert moving_out["spec"]["meshPublicPeerHost"] == "peer.tuist-eu-central-1.kura.tuist.dev"
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
          %Server{}
        )

      assert tolerated["spec"]["tolerations"] == tolerations

      untolerated =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{}
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
          %Server{}
        )

      assert manifest["metadata"]["labels"]["tuist.dev/account"] == "bumble"

      spec = manifest["spec"]
      assert spec["accountHandle"] == "bumble"
      assert spec["tenantID"] == "bumble"
      assert spec["publicHost"] == "bumble-eu-central-1.kura.tuist.dev"
      assert spec["grpcPublicHost"] == "bumble-eu-central-1.kura.tuist.dev"
    end

    test "uses the shared regional ingress class and adds no dedicated-gateway annotation" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-us-east-1",
          "0.5.2",
          %{name: "tuist"},
          us_east_region(%{gateway: :host_network}),
          %Server{}
        )

      assert manifest["spec"]["ingressClassName"] == "kura-us-east"
      refute Map.has_key?(manifest["metadata"]["annotations"], "tuist.dev/kura-gateway")
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
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      assert env["KURA_CONTROL_PLANE_URL"] ==
               "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"

      assert env["KURA_AUTH_TUIST_URL"] ==
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
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      assert env["KURA_CONTROL_PLANE_URL"] == "https://tuist.dev"
      assert env["KURA_AUTH_TUIST_URL"] == "https://tuist.dev"
    end

    test "pins the CAS capacity to the region's declared storage size" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "50Gi"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      # 50Gi less the 8Gi tmp ceiling and one 512Mi segment, less 3% for the
      # index. Without this the runtime would size the ring from the node's whole
      # disk instead.
      assert env["KURA_CAS_CAPACITY_BYTES"] == "43223477125"
    end

    test "leaves a 20Gi volume room for staging and index alongside the ring" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-staging-runners-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "20Gi"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      capacity = String.to_integer(env["KURA_CAS_CAPACITY_BYTES"])

      assert capacity == 11_977_590_046

      # The reserves are fixed sizes, not a share, so the ring plus the tmp
      # ceiling plus a rotation has to stay inside the volume. A flat percentage
      # passes at 50Gi and overruns here, which on an enforced class is ENOSPC.
      tmp = 8 * 1024 * 1024 * 1024
      segment = 512 * 1024 * 1024
      assert capacity + tmp + segment < 20 * 1024 * 1024 * 1024
    end

    test "every registered region derives a budget Kura can honour" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      segment = 512 * 1024 * 1024
      floor = 5 * segment

      for region <- Enum.filter(Regions.all(), &(&1.provisioner == KubernetesController)) do
        # Building the manifest at all is the assertion for the sizes: an
        # unparseable quantity raises, so a typo in a spec fails here rather than
        # degrading to the statvfs budget in production.
        manifest =
          KubernetesController.manifest(
            "kura-tuist-#{region.id}-1",
            "0.5.2",
            # An empty subscription list keeps the plan lookup in memory, and
            # resolves to :air, which is the profile most regions render.
            %Account{id: 1, name: "tuist", subscriptions: []},
            region,
            %Server{}
          )

        env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

        case env["KURA_CAS_CAPACITY_BYTES"] do
          nil ->
            :ok

          value ->
            capacity = String.to_integer(value)
            envelope = envelope_bytes(region)
            # Absent means Kura's own 8Gi default, which is what a claim large
            # enough to keep it renders.
            tmp = staging_bytes(env)

            assert capacity < Integer.pow(2, 64), "#{region.id} declares a capacity Kura's u64 config rejects"
            assert capacity >= floor, "#{region.id} budgets under Kura's ring floor, which the runtime raises"

            assert tmp >= 2 * 1024 * 1024 * 1024,
                   "#{region.id} stages less than one max-size module upload, which Kura rejects outright"

            assert div(capacity, segment) * segment + tmp + segment <= envelope,
                   "#{region.id} overruns its declared envelope once staging and a rotation are reserved"
        end
      end
    end

    test "omits the CAS capacity when the budget would land under Kura's ring floor" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      # 6Gi clears the reserves, so a budget is derivable, but it comes to
      # ~2.4GiB and Kura clamps the ring up to its 2.5GiB floor. Emitting the
      # derived value would promise a ring the runtime does not honour, and the
      # floor plus the reserves overruns the volume.
      manifest =
        KubernetesController.manifest(
          "kura-tuist-under-floor-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "6Gi"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      refute Map.has_key?(env, "KURA_CAS_CAPACITY_BYTES")
    end

    test "emits a budget that Kura's ring floor does not raise" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-above-floor-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "12Gi"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
      capacity = String.to_integer(env["KURA_CAS_CAPACITY_BYTES"])
      tmp = staging_bytes(env)

      segment = 512 * 1024 * 1024
      floor = 5 * segment

      # Above the floor the clamp is a no-op, so the ring Kura resolves is the
      # segment count this budget buys and the reserves still hold.
      assert capacity >= floor
      assert div(capacity, segment) * segment + tmp + segment < 12 * 1024 * 1024 * 1024
    end

    test "raises rather than falling back to statvfs when a region's size cannot be parsed" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      assert_raise ArgumentError, ~r/unparseable storage quantity/, fn ->
        KubernetesController.manifest(
          "kura-tuist-typo-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "1.5Ti"}),
          %Server{}
        )
      end
    end

    test "omits the CAS capacity when the declared size cannot fit staging" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-tiny-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "2Gi"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      refute Map.has_key?(env, "KURA_CAS_CAPACITY_BYTES")
    end

    test "budgets the CAS from disk_envelope_size without moving the declared storage size" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-scw-fr-par-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "50Gi", disk_envelope_size: "200Gi"}),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      # Budgeted from the 200Gi override, not the 50Gi claim.
      assert env["KURA_CAS_CAPACITY_BYTES"] == "199452912517"

      # storageSize must stay at the claim: the controller patches live PVCs up to
      # spec.storageSize on every reconcile, and scw-local-nvme is not expandable,
      # so raising it would wedge every instance that already exists.
      assert manifest["spec"]["storageSize"] == "50Gi"
    end

    test "renders the instance's own claim over the region's" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "50Gi", replicas: 2}),
          %Server{storage_claim_size: "24Gi"}
        )

      assert manifest["spec"]["storageSize"] == "24Gi"

      # The replica count stays the region's.
      assert manifest["spec"]["replicas"] == 2
    end

    test "budgets the ring from the instance's claim, not the region's" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      # The ring each plan's claim leaves once the 8Gi staging ceiling, one
      # rotation segment and 3% for the index are reserved: 40 GiB, 20.5 GiB and
      # 5.3 GiB. A region-derived budget would hand all three the same ring and
      # let an Air instance overrun the claim its pod reserved.
      for {claim, ring_gib} <- [{"50Gi", 40.2}, {"30Gi", 20.8}, {"8Gi", 3.4}] do
        manifest =
          KubernetesController.manifest(
            "kura-tuist-eu-central-1",
            "0.5.2",
            %{name: "tuist"},
            eu_region(%{storage_size: "50Gi"}),
            %Server{storage_claim_size: claim}
          )

        env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})
        capacity = String.to_integer(env["KURA_CAS_CAPACITY_BYTES"])

        assert_in_delta capacity / (1024 * 1024 * 1024), ring_gib, 0.1

        # Whatever the claim, the ring plus staging plus one rotation stays
        # inside it.
        {claim_gib, "Gi"} = Integer.parse(claim)
        assert capacity + staging_bytes(env) + 512 * 1024 * 1024 < claim_gib * 1024 * 1024 * 1024
      end
    end

    test "keeps the envelope override ahead of the instance's claim" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-local-controller",
          "0.5.2",
          %{name: "tuist"},
          eu_region(%{storage_size: "50Gi", disk_envelope_size: "200Gi"}),
          %Server{storage_claim_size: "24Gi"}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      assert env["KURA_CAS_CAPACITY_BYTES"] == "199452912517"
      assert manifest["spec"]["storageSize"] == "24Gi"
    end

    test "omits the CAS capacity when the region declares no storage size" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)
      stub(Tuist.Environment, :kura_control_plane_client_id, fn -> nil end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          eu_region(),
          %Server{}
        )

      env = Map.new(manifest["spec"]["extraEnv"], &{&1["name"], &1["value"]})

      refute Map.has_key?(env, "KURA_CAS_CAPACITY_BYTES")
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
          %Server{}
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

      assert env["KURA_AUTH_TUIST_URL"] ==
               "http://host.docker.internal:8080"

      assert env["KURA_CONTROL_PLANE_CLIENT_ID"] == "00000000-0000-0000-0000-000000000001"
      refute Map.has_key?(env, "KURA_CONTROL_PLANE_CLIENT_SECRET")

      assert env["KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] == "http://127.0.0.1:4318/v1/traces"
    end
  end

  describe "manifest_revision/2" do
    test "matches the base revision when no self-hosted peers are enrolled" do
      # A non-hosted (self-hosted Tuist) deployment grants every feature, so the
      # account is sync-enabled and no marker is added — the base-revision case.
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      stub(Mesh, :self_hosted_peer_urls, fn _ -> [] end)

      assert KubernetesController.manifest_revision(%Server{account: %{name: "tuist"}}, eu_region(%{mesh: true})) ==
               KubernetesController.manifest_revision() <> "+backfill"
    end

    test "changes when a peer is enrolled, matching the rendered manifest annotation" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      region = eu_region(%{mesh: true})
      peers = ["https://kura.acme.example:7443"]
      stub(Mesh, :self_hosted_peer_urls, fn _ -> peers end)

      revision = KubernetesController.manifest_revision(%Server{account: %{name: "tuist"}}, region)
      refute revision == KubernetesController.manifest_revision()

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{},
          peers
        )

      assert manifest["metadata"]["annotations"]["tuist.dev/kura-manifest-revision"] == revision
    end

    test "is independent of the peer ordering" do
      region = eu_region(%{mesh: true})

      stub(Mesh, :self_hosted_peer_urls, fn _ -> ["https://b.example:7443", "https://a.example:7443"] end)
      sorted = KubernetesController.manifest_revision(%Server{account: %{name: "tuist"}}, region)

      stub(Mesh, :self_hosted_peer_urls, fn _ -> ["https://a.example:7443", "https://b.example:7443"] end)
      reordered = KubernetesController.manifest_revision(%Server{account: %{name: "tuist"}}, region)

      assert sorted == reordered
    end

    test "ignores peers for a region without the mesh enabled" do
      reject(&Mesh.self_hosted_peer_urls/1)

      assert KubernetesController.manifest_revision(%Server{account: %{name: "tuist"}}, eu_region()) ==
               KubernetesController.manifest_revision() <> "+backfill"
    end

    test "crosses a revision boundary on the claim so a change re-applies" do
      reject(&Mesh.self_hosted_peer_urls/1)
      account = %Account{id: 1, name: "tuist"}
      region = eu_region(%{storage_size: "50Gi", replicas: 2})

      # Without the claim in the revision, a claim that changed would alter what
      # the manifest renders while leaving the desired revision where it was, so
      # the reconciler would compare equal and never re-apply.
      legacy =
        KubernetesController.manifest_revision(
          %Server{account: account, storage_claim_size: "50Gi"},
          region
        )

      smaller =
        KubernetesController.manifest_revision(
          %Server{account: account, storage_claim_size: "24Gi"},
          region
        )

      refute legacy == smaller

      # An instance pinning nothing follows its region, so a region-level change
      # still moves it.
      assert KubernetesController.manifest_revision(%Server{account: account}, region) == legacy
    end

    test "leaves the revision alone for a region that declares no claim" do
      reject(&Mesh.self_hosted_peer_urls/1)

      # Self-hosted peers carry their own disk, so there is nothing to declare
      # and nothing to fold in.
      assert KubernetesController.manifest_revision(%Server{account: %{name: "tuist"}}, eu_region()) ==
               KubernetesController.manifest_revision() <> "+backfill"
    end

    test "crosses a revision boundary on the memory tier so an upgrade re-applies" do
      reject(&Mesh.self_hosted_peer_urls/1)
      account = %Account{id: 1, name: "tuist"}
      region = eu_region(%{memory_governed: true, memory_ceiling_bin_packed: true})
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      # Without the profile in the revision an account changing plan would keep
      # the memory profile its instance was created with until some unrelated
      # field happened to move.
      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)
      air = KubernetesController.manifest_revision(%Server{account: account}, region)

      stub(Tuist.Billing, :effective_plan, fn _ -> :pro end)
      pro = KubernetesController.manifest_revision(%Server{account: account}, region)

      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)
      enterprise = KubernetesController.manifest_revision(%Server{account: account}, region)

      assert Enum.uniq([air, pro, enterprise]) == [air, pro, enterprise]
      assert String.contains?(air, "+mem256-768")
      assert String.contains?(pro, "+mem512-3072")
      assert String.contains?(enterprise, "+mem1024-4096")
    end

    test "crosses a revision boundary on the bin-pack flag so both flip directions re-apply" do
      reject(&Mesh.self_hosted_peer_urls/1)
      account = %Account{id: 1, name: "tuist"}
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)

      # memory_ceiling_bin_packed is region config, not a property of the
      # account, so flipping it alone leaves the profile identical. Without its
      # own marker the rendered spec would gain or lose the extended-resource
      # request under an unchanged revision and live instances would never
      # re-apply — worst of all turning it off, which is the remedy when pods go
      # Pending because a node stopped advertising the budget.
      packed =
        KubernetesController.manifest_revision(
          %Server{account: account},
          eu_region(%{memory_governed: true, memory_ceiling_bin_packed: true})
        )

      unpacked =
        KubernetesController.manifest_revision(%Server{account: account}, eu_region(%{memory_governed: true}))

      assert packed != unpacked
      assert String.contains?(packed, "+mem1024-4096")
      assert String.contains?(unpacked, "+mem1024-4096")
      assert String.ends_with?(packed, "+binpack")
      refute String.contains?(unpacked, "+binpack")
    end

    test "crosses a revision boundary on the entitlement so a plan upgrade re-applies" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      stub(Tuist.Environment, :kura_control_plane_client_id, fn ->
        "00000000-0000-0000-0000-000000000001"
      end)

      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      # A non-self-hosting account can never enroll a self-hosted peer, so the
      # only thing separating the two revisions is the sync marker.
      stub(Mesh, :self_hosted_peer_urls, fn _ -> [] end)

      region = eu_region(%{mesh: true})
      account = %Account{id: 1, name: "tuist"}

      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)
      non_entitled = KubernetesController.manifest_revision(%Server{account: account}, region)

      stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)
      entitled = KubernetesController.manifest_revision(%Server{account: account}, region)

      # The upgrade crosses a revision boundary, so the reconciler re-applies
      # and arms the peer-view gate instead of leaving the instance ungated.
      refute non_entitled == entitled
      # The entitled revision stays byte-identical to the base plus the
      # unconditional backfill marker, so instances already running with sync
      # on are not rolled by this change.
      assert entitled == KubernetesController.manifest_revision() <> "+backfill"

      # The rendered manifest stamps the same revision the reconciler computes,
      # so the two never disagree and loop.
      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)

      manifest =
        KubernetesController.manifest(
          "kura-tuist-eu-central-1",
          "0.5.2",
          account,
          region,
          %Server{}
        )

      assert manifest["metadata"]["annotations"]["tuist.dev/kura-manifest-revision"] == non_entitled
    end

    test "does not load self-hosted peers without the entitlement" do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      stub(Tuist.Billing, :effective_plan, fn _ -> :air end)
      reject(&Mesh.self_hosted_peer_urls/1)

      revision =
        KubernetesController.manifest_revision(
          %Server{account: %Account{id: 1, name: "tuist"}},
          eu_region(%{mesh: true})
        )

      assert revision == KubernetesController.manifest_revision() <> "+nosync+backfill"
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
                 region: eu_region()
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
                 region: region
               })
    end

    test "applies only the KuraInstance, with no dedicated gateway" do
      stub(Tuist.Environment, :app_url, fn -> "https://tuist.dev" end)

      test_process = self()

      expect(Client, :apply, fn manifest, [] ->
        send(test_process, {:applied, manifest})
        {:ok, manifest}
      end)

      assert :ok =
               KubernetesController.rollout("kura-tuist-us-east-1", %{
                 image_tag: "0.5.2",
                 account: %{name: "tuist"},
                 server: %Server{},
                 region: us_east_region(%{gateway: :host_network})
               })

      assert_receive {:applied, %{"kind" => "KuraInstance"} = instance_manifest}
      refute Map.has_key?(instance_manifest["metadata"]["annotations"], "tuist.dev/kura-gateway")
      refute_receive {:applied, %{"kind" => "KuraGateway"}}
    end
  end

  describe "destroy/2" do
    test "deletes the KuraInstance and treats already-missing resources as gone" do
      expect(Client, :delete_kura_instance, fn "kura", "kura-tuist-eu-central-1", [] ->
        {:error, :not_found}
      end)

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

  # The size the region's budget is derived against: the envelope override where
  # the claim is a fiction, the claim itself otherwise.
  # The staging budget the instance runs with: the variable when the derivation
  # narrows it, and Kura's own default when it does not, which is why a large
  # claim renders no variable at all.
  defp staging_bytes(env) do
    case env["KURA_TMP_DIR_MAX_BYTES"] do
      nil -> 8 * 1024 * 1024 * 1024
      value -> String.to_integer(value)
    end
  end

  # A region that declares no claim of its own sizes each instance from its
  # account's plan, and the accounts these manifests render for resolve to air.
  defp envelope_bytes(%Regions{provisioner_config: config}) do
    size =
      config[:disk_envelope_size] || config[:storage_size] ||
        Regions.storage_profile(:air).claim_size

    {quantity, "Gi"} = Integer.parse(size)
    quantity * 1024 * 1024 * 1024
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
          %Server{}
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

      # Synthetic: no catalog region is cluster-DNS private today (the one that
      # was went with its node pool), but a private region that omits
      # `data_plane` still falls back to it, so the manifest builder has to keep
      # handling it.
      region = %Regions{
        id: "cluster-dns-runners",
        provisioner_config: %{
          cluster_id: "cluster-dns",
          private: true,
          private_url_template: "http://{instance}.kura.svc.cluster.local:4000",
          data_plane: :cluster_dns,
          client_cidrs: [],
          pod_annotations: %{},
          node_selector: %{"node.cluster.x-k8s.io/pool" => "kura-cluster-dns"},
          storage_class: "scw-local-nvme",
          replicas: 1
        }
      }

      spec =
        KubernetesController.manifest(
          "kura-tuist-cluster-dns",
          "0.5.2",
          %{name: "tuist"},
          region,
          %Server{}
        )["spec"]

      refute Map.has_key?(spec, "exposeNodePort")
      refute Map.has_key?(spec, "clientCIDRs")
      refute Map.has_key?(spec, "podAnnotations")
    end
  end

  describe "external_endpoint/2" do
    test "builds the node-published URL from the observed status" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-scw-fr-par", [] ->
        {:ok, %{"status" => %{"nodeAddress" => "172.16.0.2", "nodePortCache" => 30_080}}}
      end)

      assert KubernetesController.external_endpoint("kura-tuist-scw-fr-par", scaleway_region()) ==
               {:ok, "http://172.16.0.2:30080"}
    end

    test "falls back to the pre-rename nodePortHTTP field while old controllers run" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-scw-fr-par", [] ->
        {:ok, %{"status" => %{"nodeAddress" => "172.16.0.2", "nodePortHTTP" => 30_080}}}
      end)

      assert KubernetesController.external_endpoint("kura-tuist-scw-fr-par", scaleway_region()) ==
               {:ok, "http://172.16.0.2:30080"}
    end

    test "is not ready until the controller observed the full chain" do
      expect(Client, :get_kura_instance, fn "kura", "kura-tuist-scw-fr-par", [] ->
        {:ok, %{"status" => %{"nodePortCache" => 30_080}}}
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

  describe "internal_url/3" do
    test "renders the ref as the in-cluster Service name" do
      assert KubernetesController.internal_url("TUIST", scaleway_region(), "kura-tuist-scw-fr-par") ==
               "http://kura-tuist-scw-fr-par.kura.svc.cluster.local:4000"
    end

    test "keeps a moved server's -m ref — the Service is named after the ref, not the handle" do
      assert KubernetesController.internal_url("tuist", Regions.get("eu-central"), "kura-tuist-eu-central-1-m") ==
               "http://kura-tuist-eu-central-1-m.kura.svc.cluster.local:4000"
    end

    test "is nil for regions without an in-cluster template" do
      region = %Regions{id: "local-controller", provisioner_config: %{cluster_id: "local-controller"}}

      assert KubernetesController.internal_url("tuist", region, "kura-tuist-local") == nil
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
