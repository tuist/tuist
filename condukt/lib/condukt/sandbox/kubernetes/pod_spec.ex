defmodule Condukt.Sandbox.Kubernetes.PodSpec do
  @moduledoc false

  alias Condukt.Sandbox.NetworkPolicy.K8s.Manifests

  # Builds the Pod manifest map handed to `K8s.Client.create/1`.
  #
  # Choices baked in:
  #
  # - `restartPolicy: Always` so K8s restarts the keepalive container on
  #   crash. The workspace `emptyDir` volume survives container restarts.
  # - One `emptyDir` volume mounted at the session cwd so repo clones and
  #   in-progress edits persist across container restarts within the same pod.
  # - `command: ["sleep", "infinity"]` keepalive so the pod never exits on its
  #   own. All real work happens via `kubectl exec`-style streaming.
  # - `activeDeadlineSeconds` as a K8s-side hard ceiling for abandoned pods.
  #
  # When `:net` is non-nil (already resolved from the
  # `:network_policy` option), the pod gains the network-policy init
  # container, sidecar container, and Secret volume. The workspace
  # container picks up an additional read-only volume mount that
  # exposes the per-session CA so untouched images cooperate with the
  # MITM at startup.

  @workspace_volume "condukt-workspace"
  @container_name "agent"

  def build(
        %{
          pod_name: pod_name,
          namespace: namespace,
          image: image,
          cwd: cwd,
          labels: labels,
          annotations: annotations,
          env: env,
          resources: resources,
          service_account: service_account,
          active_deadline_seconds: deadline
        } = config
      ) do
    net = Map.get(config, :net)

    container =
      %{
        "name" => @container_name,
        "image" => image,
        "command" => ["sleep", "infinity"],
        "workingDir" => cwd,
        "volumeMounts" => workspace_volume_mounts(net, cwd)
      }
      |> put_env(env, net)
      |> maybe_put_resources(resources)

    spec = %{
      "restartPolicy" => "Always",
      "containers" => containers_for(container, net),
      "volumes" => volumes_for(net)
    }

    spec =
      case net do
        nil -> spec
        %{init_container: init} -> Map.put(spec, "initContainers", [init])
      end

    %{
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" => %{
        "name" => pod_name,
        "namespace" => namespace,
        "labels" => labels,
        "annotations" => annotations
      },
      "spec" =>
        spec
        |> maybe_put_active_deadline(deadline)
        |> maybe_put_service_account(service_account)
    }
  end

  def container_name, do: @container_name

  defp containers_for(workspace, nil), do: [workspace]
  defp containers_for(workspace, %{sidecar_container: sidecar}), do: [workspace, sidecar]

  defp volumes_for(nil) do
    [%{"name" => @workspace_volume, "emptyDir" => %{}}]
  end

  defp volumes_for(%{secret_volume: secret_volume}) do
    [%{"name" => @workspace_volume, "emptyDir" => %{}}, secret_volume]
  end

  defp workspace_volume_mounts(nil, cwd) do
    [%{"name" => @workspace_volume, "mountPath" => cwd}]
  end

  defp workspace_volume_mounts(%{workspace_volume_mounts: extra}, cwd) when is_list(extra) do
    [%{"name" => @workspace_volume, "mountPath" => cwd} | extra]
  end

  # Workspace env is the merge of two sources:
  #
  #   1. NetworkPolicy CA env vars (NODE_EXTRA_CA_CERTS, REQUESTS_CA_BUNDLE,
  #      SSL_CERT_FILE, PIP_CERT, CURL_CA_BUNDLE, GIT_SSL_CAINFO), injected
  #      when `:net` is configured so untouched base images cooperate
  #      with the MITM without any preparation step.
  #   2. The operator-supplied env map. Operator entries come last so a
  #      caller can override any CA env var if they really need to.
  defp put_env(container, env, net) do
    operator = Enum.map(env, fn {k, v} -> %{"name" => k, "value" => v} end)

    entries =
      case net do
        nil -> operator
        _ -> Manifests.workspace_ca_env() ++ operator
      end

    case entries do
      [] -> container
      list -> Map.put(container, "env", list)
    end
  end

  defp maybe_put_resources(container, resources) when map_size(resources) == 0, do: container
  defp maybe_put_resources(container, resources), do: Map.put(container, "resources", resources)

  defp maybe_put_active_deadline(spec, nil), do: spec
  defp maybe_put_active_deadline(spec, seconds), do: Map.put(spec, "activeDeadlineSeconds", seconds)

  defp maybe_put_service_account(spec, nil), do: spec
  defp maybe_put_service_account(spec, name), do: Map.put(spec, "serviceAccountName", name)
end
