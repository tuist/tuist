defmodule Tuist.Runners.PodSpec do
  @moduledoc """
  Builds Kubernetes Pod manifests for the runner shared pool.

  Pods are intentionally generic at create time — no JIT config,
  no customer label. The `Tuist.Runners.Dispatch` flow binds them
  to a customer at job-queued time by writing a row in
  `runner_assignments`; the Pod's startup script polls the
  dispatch endpoint and gets the JIT config back.

  Resource shape: Pod requests are sized so kube-scheduler packs
  exactly one runner Pod per Mac mini. With Node capacity
  cpu=8 / memory=16Gi, a single 4000m / 14Gi request leaves
  remaining capacity too small to fit a second Pod. The Tart VM
  inside the Pod is configured with the host's full resources by
  the runner image, so the consistent build-time guarantee holds:
  one VM per host, full host resources to that VM.
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
    - `:pool` — when set to a pool name string, the Pod gets the
      label `tuist.dev/runner-pool=<pool>` at create time. Used
      by the reconciler to differentiate pre-bound (`pool` set)
      from shared (`pool` nil) Pods via label selectors —
      `tuist.dev/runner=true,tuist.dev/runner-pool=<name>` for
      pre-bound count, `tuist.dev/runner=true,!tuist.dev/runner-pool`
      for shared.
  """
  def build(name, image, dispatch_url, dispatch_token, fleet_name, opts \\ []) do
    base_labels = %{
      "app.kubernetes.io/name" => "tuist-runner",
      "app.kubernetes.io/component" => "runner",
      # NetworkPolicy in templates/runners-namespace.yaml
      # selects on this label. Don't drop it.
      "tuist.dev/runner" => "true",
      # Pre-bound Pods carry their JIT from the moment the row is
      # written; their VM polls the dispatch endpoint and gets a
      # 200 immediately. Shared Pods sit at "idle" until the
      # `workflow_job: queued` webhook handler binds them.
      "tuist.dev/runner-state" => "idle"
    }

    labels =
      case Keyword.fetch(opts, :pool) do
        {:ok, pool} when is_binary(pool) -> Map.put(base_labels, "tuist.dev/runner-pool", pool)
        _ -> base_labels
      end

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
                "cpu" => "4000m",
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
  Stable Pod name for a freshly-spawned shared/burst runner.
  Generic — the dispatch flow picks any of them.
  """
  def generate_name do
    suffix =
      4
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "tuist-runner-#{suffix}"
  end

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
  reconciler's broad-count queries.
  """
  def selector_label, do: "tuist.dev/runner=true"

  @doc """
  Selector matching pre-bound Pods for a specific pool.
  """
  def pre_bound_selector(pool) when is_binary(pool) do
    "tuist.dev/runner=true,tuist.dev/runner-pool=#{pool}"
  end

  @doc """
  Selector matching shared (un-pool-labelled) Pods. The `!key`
  syntax is the Kubernetes label-selector negation —
  "label `tuist.dev/runner-pool` must NOT be present".
  """
  def shared_selector do
    "tuist.dev/runner=true,!tuist.dev/runner-pool"
  end

  @doc """
  Pool inventory check — is the cluster's view of a Pod still
  alive (Pending or Running)? Pods that have transitioned to
  Succeeded/Failed shouldn't count as warm capacity; the
  reconciler creates replacements for them on the next tick.
  """
  def alive?(%{"status" => %{"phase" => phase}}) when phase in ["Pending", "Running"], do: true
  def alive?(_), do: false
end
