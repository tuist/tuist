defmodule Tuist.Runners.PodSpec do
  @moduledoc """
  Builds Kubernetes Pod manifests for runner Pods.

  Every Pod is pool-bound at create time — there's no "generic"
  shared pool that gets bound at dispatch. Both the reconciler
  (steady-state `min_warm` refill) and the dispatch webhook
  (on-demand burst Pod) walk the same `build/6` path, with the
  pool's name passed via the `pool:` keyword. The Pod gets a
  `tuist.dev/runner-pool=<name>` label which the reconciler's
  list query keys off when counting alive pre-bound Pods.

  Resource shape: Pod requests double as both the kube-scheduler
  one-Pod-per-host constraint AND the source-of-truth for the
  VM's CPU/memory at deploy time. tart-kubelet reads the first
  container's `resources.requests` (limits preferred when set)
  and calls `tart set --cpu --memory` between clone and run, so
  the VM is sized to whatever this manifest declares.

  Sizing for the Scaleway M4-S host (8 vCPU / 16 GB):

    - `cpu: 8000m` (= 8 cores) — give the VM the whole host.
    - `memory: 14Gi` — the M4-S has 16 GB total but Apple's
      Virtualization.framework reserves ~2 GB for the host
      kernel + tart-kubelet + helpers. Asking for 16 fails with
      `memorySize > maximumAllowedMemorySize`; 14 leaves a
      comfortable margin and is what the customer's VM gets.

  Two consequences fall out:

    1. After one such Pod schedules, remaining Node capacity is
       cpu=0 / memory=2Gi. No second runner fits. One VM per
       host, predictable build times.
    2. The runner Tart image is built small (4 vCPU / 8 GB) so
       it builds on the M1-M `vm-image-builder` host where a
       16 GB VM would exceed its `maximumAllowedMemorySize`.
       Image size at build time is decoupled from VM size at
       deploy time.
  """

  @namespace "tuist-runners"

  @doc """
  Returns a Pod manifest map ready to POST to the API server.

  `image` is the OCI URI for the runner Tart image, ideally
  digest-pinned (`ghcr.io/tuist/tuist-runner@sha256:…`). The
  digest is resolved server-side once per release and threaded
  through the chart's runtime env so a server-side bug can't
  smuggle in an arbitrary image at Pod-create time.

  `dispatch_url` is the public endpoint the VM polls for its JIT
  config. `dispatch_token` is the per-Pod random token the VM
  presents when polling — the matching SHA-256 hash is persisted
  in `runner_assignments.dispatch_token_hash` by the dispatch
  flow.

  `opts`:
    - `:pool` — pool name string. Required. Stamps
      `tuist.dev/runner-pool=<pool>` on the Pod so the
      reconciler's list selector
      `tuist.dev/runner=true,tuist.dev/runner-pool=<name>`
      counts alive pre-bound capacity per pool.
  """
  def build(name, image, dispatch_url, dispatch_token, fleet_name, opts \\ []) do
    pool = Keyword.fetch!(opts, :pool)

    labels = %{
      "app.kubernetes.io/name" => "tuist-runner",
      "app.kubernetes.io/component" => "runner",
      # NetworkPolicy in templates/runners-namespace.yaml
      # selects on this label. Don't drop it.
      "tuist.dev/runner" => "true",
      "tuist.dev/runner-pool" => pool
    }

    %{
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" => %{
        "name" => name,
        "namespace" => @namespace,
        "labels" => labels
      },
      "spec" => %{
        # Mac mini only, runners fleet only. The fleet label is
        # what guarantees runner Pods don't land on the xcresult
        # fleet (substrate isolation between customer workloads
        # and internal queue consumers).
        "nodeSelector" => %{
          "kubernetes.io/os" => "darwin",
          "tuist.dev/runtime" => "tart",
          "tuist.dev/fleet" => fleet_name
        },
        "tolerations" => [
          %{"key" => "tuist.dev/macos", "operator" => "Exists", "effect" => "NoSchedule"}
        ],
        # No restart: ephemeral runner. After the in-VM
        # `./run.sh --jitconfig` exits the Pod is Completed and
        # the reconciler creates a replacement on the next tick.
        "restartPolicy" => "Never",
        "containers" => [
          %{
            "name" => "runner",
            "image" => image,
            # Pod-level resource request shapes the scheduler so
            # exactly one runner Pod fits per Mac mini. See
            # module-level docstring.
            "resources" => %{
              "requests" => %{
                "cpu" => "8000m",
                "memory" => "14Gi"
              }
            },
            "env" => [
              %{"name" => "TUIST_RUNNER_DISPATCH_URL", "value" => dispatch_url},
              %{"name" => "TUIST_RUNNER_DISPATCH_TOKEN", "value" => dispatch_token},
              # The Pod's UID is needed by the VM to identify
              # itself when polling. The k8s downward API is the
              # standard way to surface it without baking the
              # value into the manifest before metadata.uid is
              # known (the API server assigns uid on POST).
              %{
                "name" => "TUIST_RUNNER_POD_UID",
                "valueFrom" => %{
                  "fieldRef" => %{"fieldPath" => "metadata.uid"}
                }
              },
              %{
                "name" => "TUIST_RUNNER_POD_NAME",
                "valueFrom" => %{
                  "fieldRef" => %{"fieldPath" => "metadata.name"}
                }
              }
            ]
          }
        ]
      }
    }
  end

  def namespace, do: @namespace

  @doc """
  Stable Pod name for a freshly-spawned pre-bound runner.
  Carries the pool name in the prefix for at-a-glance
  identification in `kubectl get pods`. Pool binding is also
  recorded in Postgres + on the Pod's `tuist.dev/runner-pool`
  label for the reconciler's selector queries.
  """
  def generate_pool_name(pool) when is_binary(pool) do
    suffix =
      4
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "tuist-runner-#{pool}-#{suffix}"
  end

  @doc """
  Selector matching every runner Pod we create. Used by the
  watcher's namespace-wide watch.
  """
  def selector_label, do: "tuist.dev/runner=true"

  @doc """
  Selector matching pre-bound Pods for a specific pool.
  """
  def pre_bound_selector(pool) when is_binary(pool) do
    "tuist.dev/runner=true,tuist.dev/runner-pool=#{pool}"
  end

  @doc """
  Pool inventory check — is the cluster's view of a Pod still
  alive (Pending or Running) AND not in mid-deletion? Pods that
  have transitioned to Succeeded/Failed shouldn't count as warm
  capacity; the reconciler creates replacements for them on the
  next tick. Pods with `deletionTimestamp` set are also out —
  they're on their way out, even if the phase is still Running
  (it stays Running until tart-kubelet's VM teardown finalizer
  resolves, which can take indefinitely on a wedged host).
  Without the deletion check, a stuck-Terminating Pod blocks
  the reconciler from spawning a replacement.
  """
  def alive?(%{"metadata" => %{"deletionTimestamp" => ts}}) when is_binary(ts) and ts != "", do: false

  def alive?(%{"status" => %{"phase" => phase}}) when phase in ["Pending", "Running"], do: true

  def alive?(_), do: false
end
