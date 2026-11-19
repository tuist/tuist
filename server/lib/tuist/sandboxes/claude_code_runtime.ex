defmodule Tuist.Sandboxes.ClaudeCodeRuntime do
  @moduledoc """
  The Kubernetes workload that runs one Claude Code environment's on-demand
  orchestrator (`infra/claude-code-runners`): a ServiceAccount whose projected
  token, of audience `tuist-claude-code-runners`, identifies the environment to
  `TuistWeb.ClaudeCodeRunnersController`, a Secret with the environment secret,
  and a Deployment of two orchestrator replicas. It lives in the Amp provider
  namespace.
  """
  alias Tuist.Kubernetes.Client

  @label "tuist.dev/claude-code-environment"
  @audience "tuist-claude-code-runners"

  def name(agent_environment), do: "claude-code-#{agent_environment.id}"

  def agent_environment_id("claude-code-" <> id) do
    case Integer.parse(id) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_identity}
    end
  end

  def agent_environment_id(_name), do: {:error, :invalid_identity}

  def manifests(agent_environment, config) do
    name = name(agent_environment)
    labels = %{@label => to_string(agent_environment.id), "app.kubernetes.io/component" => "claude-code-orchestrator"}
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
        "data" => %{"environment-secret" => Base.encode64(agent_environment.environment_key)}
      },
      %{
        "apiVersion" => "apps/v1",
        "kind" => "Deployment",
        "metadata" => metadata,
        "spec" => %{
          # An orchestrator polls Anthropic for spawn requests every 5 s (with
          # 20% jitter, not configurable), and Anthropic hands each request to
          # the first replica that polls: with two, a session's request
          # reaches Tuist after about 1.7 s on average instead of 2.5 s.
          "replicas" => 2,
          "strategy" => %{"type" => "Recreate"},
          "selector" => %{"matchLabels" => %{"app" => name}},
          "template" => %{
            "metadata" => %{
              "labels" => Map.put(labels, "app", name),
              # The orchestrator's /metrics: queue wait, hook durations and
              # queue counts, with no session or account labels.
              "annotations" => %{"prometheus.io/scrape" => "true", "prometheus.io/port" => "8080"}
            },
            "spec" => %{
              "serviceAccountName" => name,
              "automountServiceAccountToken" => false,
              # The orchestrator drains running hooks for 60 seconds.
              "terminationGracePeriodSeconds" => 90,
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
                  "name" => "orchestrator",
                  "image" => config.image,
                  "securityContext" => %{
                    "allowPrivilegeEscalation" => false,
                    "readOnlyRootFilesystem" => true,
                    "capabilities" => %{"drop" => ["ALL"]}
                  },
                  "env" => [
                    %{"name" => "TUIST_URL", "value" => config.url},
                    %{"name" => "TUIST_WORKLOAD_TOKEN_FILE", "value" => "/identity/token"}
                  ],
                  "ports" => [%{"name" => "metrics", "containerPort" => 8080}],
                  "resources" => %{
                    "requests" => %{"cpu" => "100m", "memory" => "256Mi"},
                    "limits" => %{"memory" => "1Gi"}
                  },
                  "readinessProbe" => %{
                    "exec" => %{"command" => ["test", "-f", "/state/orchestrator-running"]},
                    "periodSeconds" => 10
                  },
                  "volumeMounts" => [
                    %{"name" => "environment", "mountPath" => "/secrets", "readOnly" => true},
                    %{"name" => "identity", "mountPath" => "/identity", "readOnly" => true},
                    %{"name" => "state", "mountPath" => "/state"},
                    %{"name" => "tmp", "mountPath" => "/tmp"}
                  ]
                }
              ],
              "volumes" => [
                %{"name" => "environment", "secret" => %{"secretName" => name, "defaultMode" => 288}},
                %{
                  "name" => "identity",
                  "projected" => %{
                    "defaultMode" => 288,
                    "sources" => [
                      %{
                        "serviceAccountToken" => %{
                          "path" => "token",
                          "audience" => @audience,
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

  def ensure(agent_environment, config) do
    Enum.reduce_while(manifests(agent_environment, config), :ok, fn manifest, :ok ->
      case Client.apply(manifest) do
        {:ok, _} -> {:cont, :ok}
        _ -> {:halt, {:error, :provisioning_failed}}
      end
    end)
  end

  # Only names returned by the label-scoped listing are passed here. The
  # ServiceAccount is the reconciliation marker, removed last so partial
  # cleanup is retried on the next sweep.
  def remove(namespace, name) do
    with :ok <- delete_resource("/apis/apps/v1/namespaces/#{namespace}/deployments/#{name}"),
         :ok <- await_pod_cleanup(namespace, name),
         :ok <- delete_resource("/api/v1/namespaces/#{namespace}/secrets/#{name}") do
      delete_resource("/api/v1/namespaces/#{namespace}/serviceaccounts/#{name}")
    end
  end

  # A second orchestrator on the same secret would only double the spawn
  # polling, but wait for the old pods anyway, as Amp providers do.
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

  def resources(config) do
    case Client.get(
           "/api/v1/namespaces/#{config.namespace}/serviceaccounts?labelSelector=#{URI.encode_www_form(@label)}",
           timeout: 5_000
         ) do
      {:ok, %{"items" => items}} -> {:ok, items}
      _ -> {:error, :unavailable}
    end
  end
end
