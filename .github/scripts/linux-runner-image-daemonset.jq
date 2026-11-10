# Preparation runs outside the waited Helm release and survives deployment.
{
  apiVersion: "apps/v1", kind: "DaemonSet",
  metadata: {name: $name, namespace: $target.namespace,
    labels: {"tuist.dev/linux-image-staging-owner": $owner}},
  spec: {
    selector: {matchLabels: {"tuist.dev/linux-image-prepull": $name}},
    template: {
      metadata: {labels: {"tuist.dev/linux-image-prepull": $name}},
      spec: ({
        automountServiceAccountToken: false,
        terminationGracePeriodSeconds: 0,
        nodeSelector: {
          "kubernetes.io/os": "linux", "kubernetes.io/arch": "amd64",
          "node.cluster.x-k8s.io/pool": $target.fleet
        },
        tolerations: [
          {key: "tuist.dev/runner-tier", operator: "Equal", value: "bare-metal", effect: "NoSchedule"},
          {key: "tuist.dev/reserved-for", operator: "Exists", effect: "NoSchedule"}
        ],
        securityContext: {runAsNonRoot: true, runAsUser: 1000, seccompProfile: {type: "RuntimeDefault"}},
        containers: [{
          name: "pull", image: $target.image, imagePullPolicy: "IfNotPresent",
          command: ["/bin/sleep", "infinity"],
          resources: {requests: {cpu: "1m", memory: "16Mi"}, limits: {memory: "64Mi"}},
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
        }]
      } + if $target.runtime == "" then {} else {runtimeClassName: $target.runtime} end)
    }
  }
}
