defmodule Tuist.Sandboxes.AmpRuntime do
  @moduledoc false
  alias Tuist.Kubernetes.Client

  @label "tuist.dev/amp-integration"

  def name(integration), do: "amp-" <> String.replace(integration.id, "-", "") <> "-#{integration.revision}"

  def manifests(integration, config) do
    name = name(integration)
    labels = %{@label => integration.id, "app.kubernetes.io/component" => "amp-orb-provider"}
    metadata = %{"name" => name, "namespace" => config.namespace, "labels" => labels}

    [
      %{
        "apiVersion" => "v1",
        "kind" => "ServiceAccount",
        "metadata" => metadata,
        "automountServiceAccountToken" => false
      },
      %{
        "apiVersion" => "v1",
        "kind" => "Secret",
        "metadata" => metadata,
        "type" => "Opaque",
        "data" => %{"amp-token" => Base.encode64(integration.provider_token)}
      },
      %{
        "apiVersion" => "apps/v1",
        "kind" => "Deployment",
        "metadata" => metadata,
        "spec" => %{
          "replicas" => 1,
          "strategy" => %{"type" => "Recreate"},
          "selector" => %{"matchLabels" => %{"app" => name}},
          "template" => %{
            "metadata" => %{"labels" => Map.put(labels, "app", name)},
            "spec" => %{
              "serviceAccountName" => name,
              "automountServiceAccountToken" => false,
              "terminationGracePeriodSeconds" => 300,
              "nodeSelector" => Map.put(config.node_selector, "kubernetes.io/arch", "amd64"),
              "securityContext" => %{
                "runAsNonRoot" => true,
                "runAsUser" => 10_001,
                "runAsGroup" => 10_001,
                "fsGroup" => 10_001,
                "seccompProfile" => %{"type" => "RuntimeDefault"}
              },
              "containers" => [
                %{
                  "name" => "provider",
                  "image" => config.image,
                  "securityContext" => %{
                    "allowPrivilegeEscalation" => false,
                    "readOnlyRootFilesystem" => true,
                    "capabilities" => %{"drop" => ["ALL"]}
                  },
                  "env" =>
                    Enum.map(
                      %{
                        "TUIST_URL" => config.url,
                        "ORB_IMAGE" => "default",
                        "TUIST_WORKLOAD_TOKEN_FILE" => "/identity/token"
                      },
                      fn {key, value} -> %{"name" => key, "value" => value} end
                    ),
                  "resources" => %{
                    "requests" => %{"cpu" => "100m", "memory" => "256Mi"},
                    "limits" => %{"memory" => "1Gi"}
                  },
                  "readinessProbe" => %{
                    "exec" => %{"command" => ["test", "-f", "/state/provider-running"]},
                    "periodSeconds" => 10
                  },
                  "volumeMounts" => [
                    %{"name" => "amp", "mountPath" => "/secrets", "readOnly" => true},
                    %{"name" => "identity", "mountPath" => "/identity", "readOnly" => true},
                    %{"name" => "state", "mountPath" => "/state"},
                    %{"name" => "tmp", "mountPath" => "/tmp"}
                  ]
                }
              ],
              "volumes" => [
                %{"name" => "amp", "secret" => %{"secretName" => name, "defaultMode" => 288}},
                %{
                  "name" => "identity",
                  "projected" => %{
                    "defaultMode" => 288,
                    "sources" => [
                      %{
                        "serviceAccountToken" => %{
                          "path" => "token",
                          "audience" => "tuist-amp-orbs",
                          "expirationSeconds" => 3600
                        }
                      }
                    ]
                  }
                },
                %{"name" => "state", "emptyDir" => %{}},
                %{"name" => "tmp", "emptyDir" => %{"medium" => "Memory", "sizeLimit" => "64Mi"}}
              ]
            }
          }
        }
      }
    ]
  end

  def ensure(integration, config) do
    Enum.reduce_while(manifests(integration, config), :ok, fn manifest, :ok ->
      case Client.apply(manifest) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, :provisioning_failed}}
      end
    end)
  end

  def status(integration, config) do
    case Client.get(deployment_path(config.namespace, name(integration)), timeout: 5_000) do
      {:ok,
       %{
         "metadata" => %{"generation" => generation},
         "status" => %{"observedGeneration" => observed, "readyReplicas" => 1}
       }}
      when observed >= generation ->
        :running

      _ ->
        :pending
    end
  end

  # Only resource names returned by the label-scoped API listing are passed here.
  # The ServiceAccount is the reconciliation marker, removed last so partial cleanup is retried.
  def remove(namespace, name) do
    with :ok <- delete_resource(deployment_path(namespace, name)),
         :ok <- await_pod_cleanup(namespace, name),
         :ok <- delete_resource("/api/v1/namespaces/#{namespace}/secrets/#{name}") do
      delete_resource("/api/v1/namespaces/#{namespace}/serviceaccounts/#{name}")
    end
  end

  # Deleting a Deployment is asynchronous. Retain the marker and retry next sweep
  # until its pods disappear, so rotation cannot start a second consumer early.
  defp await_pod_cleanup(namespace, name) do
    path = "/api/v1/namespaces/#{namespace}/pods?labelSelector=#{URI.encode_www_form("app=" <> name)}"

    case Client.get(path, timeout: 5_000) do
      {:ok, %{"items" => []}} -> :ok
      _ -> {:error, :cleanup_pending}
    end
  end

  defp delete_resource(path) do
    case Client.delete(path) do
      result when result in [:ok, {:error, :not_found}] -> :ok
      _ -> {:error, :cleanup_failed}
    end
  end

  def resources(config, integration_id \\ nil) do
    selector = if integration_id, do: "#{@label}=#{integration_id}", else: @label

    case Client.get(
           "/api/v1/namespaces/#{config.namespace}/serviceaccounts?labelSelector=#{URI.encode_www_form(selector)}",
           timeout: 5_000
         ) do
      {:ok, %{"items" => items}} -> {:ok, items}
      _ -> {:error, :unavailable}
    end
  end

  defp deployment_path(namespace, name), do: "/apis/apps/v1/namespaces/#{namespace}/deployments/#{name}"
end
