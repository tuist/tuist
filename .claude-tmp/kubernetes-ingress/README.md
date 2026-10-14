# ![HAProxy](https://github.com/haproxytech/kubernetes-ingress/raw/master/assets/images/haproxy-weblogo-210x49.png "HAProxy")

## HAProxy Kubernetes Ingress Controller

An ingress controller is a Kubernetes resource that routes traffic from outside your cluster to services within the cluster. HAProxy Kubernetes Ingress Controller uses ConfigMap to store the haproxy configuration.

Detailed documentation can be found within the [Official Documentation](https://www.haproxy.com/documentation/kubernetes/latest/).

Additional configuration details can be found in [annotation reference](https://github.com/haproxytech/kubernetes-ingress/tree/master/documentation) and in image [arguments reference](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/controller.md).

## Introduction

This chart bootstraps an HAProxy kubernetes-ingress deployment/daemonset on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

### Prerequisites

- Kubernetes 1.23+ (recommended 1.24+)
- Helm 3.6+ (recommended 3.7+)

## Before you begin

### Setting up a Kubernetes Cluster

The quickest way to setup a Kubernetes cluster is with [Azure Kubernetes Service](https://azure.microsoft.com/en-us/services/kubernetes-service/), [AWS Elastic Kubernetes Service](https://aws.amazon.com/eks/) or [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/) using their respective quick-start guides.

For setting up Kubernetes on other cloud platforms or bare-metal servers refer to the Kubernetes [getting started guide](http://kubernetes.io/docs/getting-started-guides/).

### Install Helm

Get the latest [Helm release](https://github.com/helm/helm#install).

### Adding Helm chart repo

Once you have Helm installed, add the haproxytech Chart Repository as follows:

```console
helm repo add haproxytech https://haproxytech.github.io/helm-charts

helm repo update
```

Alternatively if you want to proceed with just OCI-based repository, skip this step and follow the installation with OCI.

## Installing the chart

To install the chart with Helm v3 as _my-release_ deployment from Chat Repository:

```console
helm install my-release haproxytech/kubernetes-ingress
```

**_NOTE_**: To install the chart with Helm v2 (legacy Helm) the syntax requires adding deployment name to `--name` parameter:

```console
helm install haproxytech/kubernetes-ingress \
  --name my-release
```

Alternatively also have OCI-based repository available for simplified access:

```console
helm install oci://ghcr.io/haproxytech/helm-charts/kubernetes-ingress
```

### Installing with unique name

To auto-generate controller and its resources names when installing, use the following:

```console
helm install haproxytech/kubernetes-ingress \
  --generate-name
```

### Installing from a private registry

To install the chart using a private registry for controller into a separate namespace _prod_.

**_NOTE_**: Helm v3 requires namespace to be precreated (eg. with `kubectl create namespace prod`)

```console
helm install my-ingress haproxytech/kubernetes-ingress  \
  --namespace prod \
  --set controller.image.tag=SOMETAG \
  --set controller.imageCredentials.registry=myregistry.domain.com \
  --set controller.imageCredentials.username=MYUSERNAME \
  --set controller.imageCredentials.password=MYPASSWORD
```

Alternatively, use a pre-configured (existing) imagePullSecret in the same namespace:

```console
helm install my-ingress haproxytech/kubernetes-ingress  \
  --namespace prod \
  --set controller.image.tag=SOMETAG \
  --set controller.existingImagePullSecret name-of-existing-image-pull-secret
```

### Using values from YAML file

As opposed to using many `--set` invocations, much simpler approach is to define value overrides in a separate YAML file and specify them when invoking Helm:

_mylb.yaml_:

```yaml
controller:
  kind: DaemonSet
  ingressClass: haproxy
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
      service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0
```

And invoking Helm becomes (compare to the previous example):

```console
helm install my-ingress -f mylb.yml haproxytech/kubernetes-ingress
```

A typical YAML file for TCP services looks like (provided that configmap "[default/tcp](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/controller.md)" was created) :

```yaml
controller:
  service:
    tcpPorts:
      - name: mysql
        port: 3306
        targetPort: 3306
  extraArgs:
    - --configmap-tcp-services=default/tcp
```

### Installing as DaemonSet

Default controller mode is [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), but it is possible to use [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) as well:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet
```

### Installing in multi-ingress environment

It is also possible to set controller ingress class to be used in [multi-ingress environments](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/#using-multiple-ingress-controllers):

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet \
  --set controller.ingressClass=haproxy
```

**_NOTE_**: make sure your Ingress routes have corresponding `ingress.class: haproxy` annotation.

### Installing Gateway API support

[Gateway API support](https://gateway-api.sigs.k8s.io/) can be installed and used wth controller. Supported features can seen in [Ingress Controller documentation](https://github.com/haproxytech/kubernetes-ingress/blob/master/documentation/gateway-api.md)

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kubernetesGateway.enabled=true \
  --set controller.kubernetesGateway.gatewayControllerName=haproxy.org/gateway-controller
```

**_NOTE_**: Gateway API is not part of the default k8s API so it needs to be installed.

### Installing with service annotations

On some environments like EKS and GKE there might be a need to pass service annotations. Syntax can become a little tedious however:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.kind=DaemonSet \
  --set controller.ingressClass=haproxy \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="0.0.0.0/0" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-cross-zone-load-balancing-enabled"="true"
```

**_NOTE_**: With helm `--set` it is needed to put quotes and escape dots in the annotation key and commas in the value string.

### Installing with Horizontal Pod Autoscaler (HPA)

[HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) automatically scales number of replicas in Deployment or Replication Controller and adjusts replica count for the controller:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.autoscaling.enabled=true
```

### Installing the ServiceMonitor

If you're using the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), you can automatically install the `ServiceMonitor` definition in order to automate the scraping options according to your needs.

```console
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.serviceMonitor.enabled=true
```

### Installing the PodMonitor

As an alternative to a `ServiceMonitor` you can use a `PodMonitor`, which targets the pods directly instead of using a service.
If you're using the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), you can automatically install the `PodMonitor` definition in order to automate the scraping options according to your needs.

```console
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.podMonitor.enabled=true
```

### Installing with Kubernetes Event-driven Autoscaling (KEDA)

[KEDA](https://keda.sh/docs/2.3/concepts/scaling-deployments/) is an improved scaling solution built on top of HPA which allows autoscaling criteria based on information from any event source including Prometheus metrics collected from HAProxy native Prometheus Exporter.

To enable KEDA, you will also need to install Prometheus Operator and ServiceMonitor enabled (serverAddress has to match `prometheus-kube-prometheus-prometheus` service IP):

_mykeda.yaml_:

```yaml
controller:
  kind: Deployment
  serviceMonitor:
    enabled: true
  keda:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    triggers:
      - type: prometheus
        metadata:
          serverAddress: http://10.96.206.247:9090
          metricName: haproxy_frontend_current_sessions
          threshold: "100"
          query: sum(rate(haproxy_frontend_current_sessions{proxy="http"}[2m]))
```

Note: Other options to trigger scaling can be found in Prometheus [native exporter documentation](https://github.com/haproxy/haproxy/blob/master/addons/promex/README), but some ideas are:

- `haproxy_process_idle_time_percent`
- `haproxy_frontend_current_sessions`
- `haproxy_backend_current_queue`

And to install:

```console
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts

helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

kubectl create namespace keda
helm install keda kedacore/keda --namespace keda

helm install mytest haproxytech/kubernetes-ingress -f mykeda.yaml
```

### Installing on Amazon Elastic Kubernetes Service (EKS)

By default AWS LB does not support mixed protocols (TCP and UDP) on the same port yet, resulting in the following error on deploy:

```
Error syncing load balancer: failed to ensure load balancer: mixed protocol is not supported for LoadBalancer
```

This issue can be easily fixed by disabling QUIC support (requires `udp/443` listener) with the following:

```console
helm install my-ingress haproxytech/kubernetes-ingress \
  --set controller.service.type=LoadBalancer \
  --set controller.service.enablePorts.quic=false
```

### Installing on Azure Managed Kubernetes Service (AKS)

By default Azure LB sends probe to `/` and expects HTTP status codes of 200-399 to consider Pod healthy, which means probes end up on default HTTP backend returning HTTP 404 status code. Since v1.20 AKS service annotation `service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path` can be used to override health probe behaviour and we recommend using the following annotation on AKS to target `/healthz` endpoint for health probes:

```console
helm install ...
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
```

## Configuration

The full set of supported values is defined in [`values.yaml`](values.yaml), which is also the canonical source of inline documentation (every value carries a `##` comment block explaining its purpose and linking the relevant Kubernetes docs). At any time you can dump the effective defaults for the version of the chart you have installed with:

```console
helm show values haproxytech/kubernetes-ingress
helm show readme  haproxytech/kubernetes-ingress
```

To override defaults, either pass a values file with `-f my-values.yaml` (recommended for anything non-trivial) or use `--set key=value` for one-offs. The tables below summarise every top-level key. Defaults reflect chart version `1.50.0` (controller `appVersion 3.2.8`); refer to `values.yaml` for the exact current default if you are on a different version.

### Global / cluster-wide

| Key | Description | Default |
|---|---|---|
| `rbac.create` | Create the ClusterRole + ClusterRoleBinding required by the controller. | `true` |
| `namespace.create` | Create the release namespace from the chart (do **not** combine with `helm install --create-namespace`). | `false` |
| `namespaceOverride` | Override `.Release.Namespace` for all rendered resources (useful in umbrella/combined charts). | _unset_ |
| `serviceAccount.create` | Create a dedicated ServiceAccount for the controller. | `true` |
| `serviceAccount.name` | Name of the ServiceAccount (auto-generated when empty). | _unset_ |
| `serviceAccount.automountServiceAccountToken` | Override the SA-token automount behaviour. Unset = use the Kubernetes default (`true`). | _unset_ |
| `podSecurityPolicy.enabled` | Create a PodSecurityPolicy (Kubernetes &lt; 1.25 only — PSP was removed in 1.25). | `false` |
| `podSecurityPolicy.annotations` | Annotations applied to the PSP (e.g. AppArmor / seccomp profile selectors). | `{}` |
| `aws.licenseConfigSecretName` | Name of the Secret holding AWS Marketplace HAPEE license files (EKS / EKS-Anywhere only). | `""` |

### Controller image and rollout

| Key | Description | Default |
|---|---|---|
| `controller.name` | Component name; influences resource naming. | `controller` |
| `controller.image.repository` | Controller image repository. Switch this to use CE/EE images. | `docker.io/haproxytech/kubernetes-ingress` |
| `controller.image.tag` | Image tag override (defaults to `.Chart.appVersion`). | `""` |
| `controller.image.pullPolicy` | Image pull policy. | `IfNotPresent` |
| `controller.imageCredentials.registry` / `.username` / `.password` | Inline credentials for a private registry (chart will create an `imagePullSecret`). | `null` |
| `controller.existingImagePullSecret` | Name of an existing `kubernetes.io/dockerconfigjson` Secret to use instead. | `null` |
| `controller.kind` | `Deployment` or `DaemonSet`. | `Deployment` |
| `controller.replicaCount` | Replica count (Deployment only; ignored for DaemonSet). | `2` |
| `controller.minReadySeconds` | Min seconds a new pod must be ready before counting as available. | `0` |
| `controller.strategy.type` | Rollout strategy (`RollingUpdate` or `Recreate` for Deployment; `RollingUpdate` / `OnDelete` for DaemonSet). | `RollingUpdate` |
| `controller.terminationGracePeriodSeconds` | Pod termination grace period. | `60` |
| `controller.priorityClassName` | `PriorityClass` for the controller pod. | `""` |
| `controller.runtimeClassName` | `RuntimeClass` for the controller pod. | `""` |

### Pod security and runtime

| Key | Description | Default |
|---|---|---|
| `controller.unprivileged` | Run the container as non-root (UID 1000). | `true` |
| `controller.allowPrivilegedPorts` | Allow non-root to bind ports &lt; 1024 (auto-enables `net.ipv4.ip_unprivileged_port_start=0`). | `false` |
| `controller.enableRuntimeDefaultSeccompProfile` | Apply seccomp `RuntimeDefault` profile. | `true` |
| `controller.allowPrivilegeEscalation` | Container `allowPrivilegeEscalation`. | `false` |
| `controller.initContainers` | List of init containers. | `[]` |
| `controller.sysctls` | Pod-level sysctls (map). | `{}` |
| `controller.lifecycle` | Container lifecycle handlers (`preStop`, `postStart`). | `{}` |
| `controller.enableServiceLinks` | Whether to inject service-discovery env vars (set `false` in large clusters to reduce env-var bloat). | `true` |

### Container ports, probes, debug endpoints

| Key | Description | Default |
|---|---|---|
| `controller.containerPort.http` / `.https` / `.stat` / `.admin` | Container listener ports. | `8080`, `8443`, `1024`, `6060` |
| `controller.prometheus.enabled` | Enable the controller's `/metrics` endpoint (served on the `stat` port). Required for `ServiceMonitor` / `PodMonitor` scraping. **No longer gated on `service.enablePorts.admin`** (decoupled in 1.50.0). | `true` |
| `controller.pprof.enabled` | Enable `/debug/pprof` on the `admin` port. Consider disabling in production. | `true` |
| `controller.quic.announcePort` | Port advertised to clients in `Alt-Svc` headers for HTTP/3. When empty, auto-derived from topology (`useHostNetwork` → `containerPort.https`; `useHostPort` → `hostPorts.https`; otherwise `service.ports.https`). Set explicitly when a port-translating LB sits in front. | `""` |
| `controller.livenessProbe` / `readinessProbe` / `startupProbe` | Probe definitions. Default port is `1042` — the controller's built-in `/healthz` listener bound unconditionally by the binary (independent of `containerPort`). | see `values.yaml` |

### Ingress class and Gateway API

| Key | Description | Default |
|---|---|---|
| `controller.ingressClassResource.name` | Name of the `IngressClass` resource (Kubernetes &ge; 1.18). | `haproxy` |
| `controller.ingressClassResource.default` | Mark this `IngressClass` as the cluster default. | `false` |
| `controller.ingressClassResource.parameters` | `parametersRef` block for the `IngressClass`. | `{}` |
| `controller.ingressClass` | The class name the controller listens on (`null` = serve all). | `haproxy` |
| `controller.kubernetesGateway.enabled` | Enable Gateway API support (Gateway API CRDs must be installed separately). | `false` |
| `controller.kubernetesGateway.gatewayControllerName` | Name advertised in `GatewayClass.spec.controllerName`. | `haproxy.org/gateway-controller` |
| `controller.defaultTLSSecret.enabled` | Enable default TLS Secret (auto-generated if `secret` is `null`, otherwise reused). | `true` |
| `controller.defaultTLSSecret.secretNamespace` | Namespace of the default TLS Secret. | release namespace |
| `controller.defaultTLSSecret.secret` | Name of an existing Secret to reuse (must contain `tls.crt` **and** `tls.key`). | `null` |
| `controller.publishService.enabled` | Mirror the Service endpoints into `Ingress.status.loadBalancer`. | `true` |
| `controller.publishService.pathOverride` | Override path (`<namespace>/<service>`). | `""` |

### Metadata and labels

| Key | Description | Default |
|---|---|---|
| `controller.extraLabels` | Additional labels on the Deployment/DaemonSet metadata. | `{}` |
| `controller.annotations` | Additional annotations on the Deployment/DaemonSet metadata. | `{}` |
| `controller.podLabels` | Additional labels on the pod template. | `{}` |
| `controller.podAnnotations` | Additional annotations on the pod template. | `{}` |

### Resources, autoscaling and disruption

| Key | Description | Default |
|---|---|---|
| `controller.resources.requests` / `.limits` | CPU/memory requests and (optional) limits for the controller container. | `cpu: 250m`, `memory: 400Mi` (no limits) |
| `controller.autoscaling.enabled` | Enable HPA (Deployment only). | `false` |
| `controller.autoscaling.minReplicas` / `.maxReplicas` | HPA bounds. | `2` / `20` |
| `controller.autoscaling.targetCPUUtilizationPercentage` | CPU utilisation target. | `80` |
| `controller.autoscaling.targetMemoryUtilizationPercentage` | Memory utilisation target. | _unset_ |
| `controller.autoscaling.behavior` | HPA scaling behaviour block. | _unset_ |
| `controller.autoscaling.custom` | Custom HPA metrics (Pods/Object/External). | _unset_ |
| `controller.autoscaling.annotations` | HPA annotations. | `{}` |
| `controller.keda.enabled` | Enable KEDA `ScaledObject` (mutually exclusive with HPA; requires `serviceMonitor` enabled). | `false` |
| `controller.keda.minReplicas` / `.maxReplicas` | KEDA bounds. | `2` / `20` |
| `controller.keda.pollingInterval` / `.cooldownPeriod` | KEDA timing. | `30` / `300` |
| `controller.keda.restoreToOriginalReplicaCount` | Restore replica count on KEDA removal. | `false` |
| `controller.keda.fallback` | Fallback behaviour on trigger failure. | _unset_ |
| `controller.keda.scaledObject.annotations` | `ScaledObject` annotations. | `{}` |
| `controller.keda.horizontalPodAutoscalerConfig` | Underlying HPA config emitted by KEDA. | `{}` |
| `controller.keda.triggers` | List of KEDA triggers (required when `keda.enabled=true`; chart fails at render if empty). | `[]` |
| `controller.PodDisruptionBudget.enable` | Create a PDB (Deployment only). | `false` |
| `controller.PodDisruptionBudget.maxUnavailable` / `.minAvailable` | PDB constraints (set one). | _unset_ |

### Scheduling

| Key | Description | Default |
|---|---|---|
| `controller.nodeSelector` | `nodeSelector` map. | `{}` |
| `controller.tolerations` | Tolerations list. | `[]` |
| `controller.affinity` | Node/pod affinity rules. | `{}` |
| `controller.topologySpreadConstraints` | Topology spread constraints (Deployment only — ignored for DaemonSet since DS already runs one pod per node). | `[]` |
| `controller.dnsConfig` | Pod DNS config. | `{}` |
| `controller.dnsPolicy` | Pod DNS policy. Set to `ClusterFirstWithHostNet` when `useHostNetwork=true`. | `ClusterFirst` |

### Controller arguments, ConfigMap and logging

| Key | Description | Default |
|---|---|---|
| `controller.extraArgs` | Additional CLI flags passed to the controller binary (e.g. `--namespace-whitelist`, `--disable-ipv6`, `--sync-period`). | `[]` |
| `controller.config` | Map written into the controller ConfigMap (global HAProxy tuning — `timeout-connect`, `rate-limit-*`, etc.). Ignored when `config.cr-global` is set; move config into `spec.log_targets` of the Global CR. | `{}` |
| `controller.configAnnotations` | Annotations on the controller ConfigMap. | `{}` |
| `controller.logging.level` | Controller log level (`trace`, `debug`, `info`, `warning`, `error`). Applies only to the **controller's own** logs. | `info` |
| `controller.logging.traffic` | HAProxy access-log config (`address`, `format`, `facility`). Ignored when `config.cr-global` is set (use the CR's `spec.log_targets` instead). | `{}` |

### Service (the main HAProxy frontend)

| Key | Description | Default |
|---|---|---|
| `controller.service.enabled` | Render the Service. Set `false` for DaemonSet + `useHostPort` deployments where the Service is redundant. | `true` |
| `controller.service.type` | `ClusterIP`, `NodePort` or `LoadBalancer`. | `NodePort` |
| `controller.service.annotations` / `.labels` | Service metadata (cloud-provider LB hints typically go here). | `{}` |
| `controller.service.ports.http` / `.https` / `.stat` / `.admin` | Service port numbers. | `80`, `443`, `1024`, `6060` |
| `controller.service.nodePorts.http` / `.https` / `.stat` / `.admin` | Optional explicit NodePort values; omit for random allocation. | _unset_ |
| `controller.service.enablePorts.http` / `.https` / `.quic` / `.stat` / `.admin` | Toggle individual Service ports (at least one of `http`/`https`/`stat` or a `tcpPorts` entry must remain enabled). **Disabling `admin` no longer disables Prometheus/pprof** — use `controller.prometheus.enabled` / `controller.pprof.enabled` for that. | all `true` |
| `controller.service.targetPorts` | Mapping of Service ports to container ports (name or number). | named ports |
| `controller.service.tcpPorts` | Extra TCP ports (e.g. for MySQL/Redis pass-through via the TCP ConfigMap). | `[]` |
| `controller.service.healthCheckNodePort` | Health-check NodePort (only used with `externalTrafficPolicy: Local`). | `0` |
| `controller.service.externalTrafficPolicy` | `Cluster` (default) or `Local` (preserves client source IP). | _unset_ |
| `controller.service.externalIPs` | List of external IPs to advertise. | `[]` |
| `controller.service.loadBalancerIP` | Requested LB IP (provider-dependent). | `""` |
| `controller.service.loadBalancerSourceRanges` | CIDR allowlist for the LB. | `[]` |
| `controller.service.loadBalancerClass` | `LoadBalancerClass` (Kubernetes &ge; 1.24). | `null` |
| `controller.service.clusterIP` | Pin a specific ClusterIP. | _unset_ |
| `controller.service.ipFamilies` / `.ipFamilyPolicy` | IPv4 / IPv6 dual-stack config. | _unset_ |
| `controller.service.sessionAffinity` | Service `sessionAffinity` (`None` / `ClientIP`). | _unset_ |
| `controller.service.trafficDistribution` | Traffic distribution policy (`PreferSameZone`, `PreferSameNode`). | _unset_ |
| `controller.service.metrics.type` | Type of the secondary metrics Service (created when `serviceMonitor.enabled=true`). | `ClusterIP` |
| `controller.service.metrics.annotations` / `.labels` | Metadata for the metrics Service. | `{}` |

### Deployment / DaemonSet host networking

| Key | Description | Default |
|---|---|---|
| `controller.deployment.useHostNetwork` | Deployment pods use `hostNetwork` (remember to set `dnsPolicy: ClusterFirstWithHostNet`). | `false` |
| `controller.deployment.useHostPort` | Bind container ports to host ports (Deployment). | `false` |
| `controller.deployment.hostIP` | Bind to a specific host IP. | `null` |
| `controller.deployment.hostPorts.http` / `.https` / `.stat` | Host port mappings. | `80` / `443` / `1024` |
| `controller.daemonset.useHostNetwork` | DaemonSet pods use `hostNetwork`. | `false` |
| `controller.daemonset.useHostPort` | DaemonSet binds to host ports (set `service.enabled=false` when used standalone). | `false` |
| `controller.daemonset.hostIP` | Bind to a specific host IP. | `null` |
| `controller.daemonset.hostPorts.http` / `.https` / `.stat` | Host port mappings. | `80` / `443` / `1024` |

### Extra workload customisation

| Key | Description | Default |
|---|---|---|
| `controller.extraEnvs` | Extra `env:` entries on the controller container (e.g. `TZ`). | `[]` |
| `controller.extraEnvFrom` | Extra `envFrom:` entries (ConfigMap / Secret refs). | `[]` |
| `controller.extraContainers` | Additional sidecar containers. | `[]` |
| `controller.extraVolumeMounts` | Extra `volumeMounts` on the controller container (needed e.g. when running with `readOnlyRootFilesystem`). | `[]` |
| `controller.extraVolumes` | Extra `volumes` on the pod. | `[]` |

### Prometheus integrations (ServiceMonitor / PodMonitor)

Both ServiceMonitor and PodMonitor are gated behind the `monitoring.coreos.com/v1` API — they are only rendered when the Prometheus Operator CRDs are present. Enabling either toggle requires `controller.prometheus.enabled=true` (the chart fails at render otherwise, since `/metrics` would not be exposed). `serviceMonitor` and `podMonitor` are mutually exclusive — enable at most one.

| Key | Description | Default |
|---|---|---|
| `controller.serviceMonitor.enabled` | Create a `ServiceMonitor`. Also creates the secondary metrics Service. | `false` |
| `controller.serviceMonitor.extraLabels` | Labels for Prometheus Operator selector matching. | `{}` |
| `controller.serviceMonitor.endpoints` | List of scrape endpoints (defaults to one scrape on the `stat` port `/metrics`). | see `values.yaml` |
| `controller.podMonitor.enabled` | Create a `PodMonitor` (alternative to `ServiceMonitor`). | `false` |
| `controller.podMonitor.extraLabels` | Labels for Prometheus Operator selector matching. | `{}` |
| `controller.podMonitor.endpoints` | List of scrape endpoints. | see `values.yaml` |

### Sync mode (Enterprise-only fetch / proxy mode)

| Key | Description | Default |
|---|---|---|
| `controller.sync.mode` | `default` (event-driven via K8s informers) or `fetch` (periodic pull). | `default` |
| `controller.sync.fetchParams.period` | Polling period when `mode=fetch`. | `5s` |
| `controller.sync.fetchParams.source` | `k8s` or `proxy`. | `k8s` |
| `controller.sync.proxyParams.replicaCount` | Number of proxy-mode replicas (required when `source=proxy`). | `3` |
| `controller.sync.proxyParams.proxySvcLabelSelector` | Label selector for the proxy service. | `run:haproxy-ingress-proxy` |

### CRD installation job

A Helm `post-install` / `pre-upgrade` hook Job that applies the controller's CRDs (`core.haproxy.org/v1alpha2` Defaults, Globals, Backends). Available since chart `1.35.0`.

| Key | Description | Default |
|---|---|---|
| `crdjob.podAnnotations` | Annotations on the Job pod. | `{}` |
| `crdjob.ttlSecondsAfterFinished` | Seconds after which the Job is garbage-collected. | `600` |
| `crdjob.activeDeadlineSeconds` | Seconds the Job may stay active before Kubernetes terminates it and marks it `DeadlineExceeded`. Omitted when unset, so the Job runs without a deadline. | _unset_ |
| `crdjob.nodeSelector` / `.tolerations` / `.affinity` | Scheduling controls for the Job pod. | `{}` / `[]` / `{}` |
| `crdjob.resources.requests` / `.limits` | CPU/memory requests and (optional) limits for the Job container. | `cpu: 250m`, `memory: 400Mi` (no limits) |

### Extra Objects

Declare additional arbitrary manifests to deploy as part of the Helm release. Available since chart `1.53.0`.

| Key | Description | Default |
|---|---|---|
| `extraObjects` | Extra raw objects to template. | `[]` |

Each entry may be written in one of two forms, and the form decides whether it gets templated:

- **Map form** is emitted verbatim. Any foreign Go template syntax survives untouched, which is what you want for Grafana dashboards, Prometheus recording/alerting rules and Alertmanager templates that contain their own `{{ }}`.
- **String form** is an explicit opt-in to templating: the whole string is passed through `tpl`, so every `{{ }}` is evaluated against the chart context. One string may hold several `---` separated documents.

```yaml
extraObjects:
  # map form: verbatim, foreign {{ }} preserved
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: prometheus-rules
    data:
      rules.yaml: |
        - alert: Example
          annotations:
            summary: "{{ $labels.instance }} is down"
  # string form: templated, multiple documents
  - |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ .Release.Name }}-extra-a
    data:
      extra.conf: example_a
    ---
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ .Release.Name }}-extra-b
    data:
      extra.conf: example_b
```

Every entry must carry `apiVersion`, `kind` and either `metadata.name` or `metadata.generateName`; the body shape is not validated. Chart labels are merged in, and `metadata.namespace` defaults to the release namespace (honouring `namespaceOverride`) unless the object sets it. For a cluster-scoped object, set `namespace: null` to leave it without one.

Note that this manifest is not capability-gated: if the CRD backing an extra object is missing, `helm install` fails. It is also not intended for `ingress.v3.haproxy.org/v3` CRs, whose CRDs are installed by the `post-install` / `pre-upgrade` job described above.

### Migration notes (1.50.0)

- **Prometheus / pprof decoupled from `admin` port.** Previously, setting `controller.service.enablePorts.admin=false` implicitly disabled the controller's `/metrics` and `/debug/pprof` endpoints. Starting in 1.50.0, the dedicated toggles `controller.prometheus.enabled` and `controller.pprof.enabled` control these (both default `true`). If you were relying on the old coupling, set the new toggles to `false` explicitly.
- **QUIC announce port auto-derivation.** `--quic-announce-port` is no longer hard-wired to `controller.service.ports.https`. The chart now derives it from the deployment topology (`useHostNetwork` / `useHostPort` / Service). Override with `controller.quic.announcePort` if your topology terminates QUIC behind a port-translating LB.
- **Render-time validation.** The chart now fails at template render when a misconfiguration would otherwise produce a silently-broken release: `serviceMonitor`/`podMonitor` enabled with `prometheus.enabled=false`, or `keda.enabled=true` with an empty `triggers` list.
- **CRD-job name no longer revision-suffixed.** Upgrading from a previous release leaves the old revision-suffixed Job in-cluster; remove it manually if desired (the `before-hook-creation` delete policy handles future runs).

## Upgrading the chart

To upgrade the _my-release_ deployment:

```console
helm upgrade my-release haproxytech/kubernetes-ingress
```

By default Helm [does not upgrade](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) CRDs during an upgrade, so before doing an upgrade it is mandatory to upgrade CRDs to the latest version by hand **before** doing a Helm chart upgrade.

```console
kubectl apply -f https://raw.githubusercontent.com/haproxytech/helm-charts/main/kubernetes-ingress/crds/core.haproxy.org_defaults.yaml
kubectl apply -f https://raw.githubusercontent.com/haproxytech/helm-charts/main/kubernetes-ingress/crds/core.haproxy.org_globals.yaml
kubectl apply -f https://raw.githubusercontent.com/haproxytech/helm-charts/main/kubernetes-ingress/crds/core.haproxy.org_backends.yaml
```

Note: from Helm Chart 1.35.0, Helm Chart contains CRD install/upgrade job that will take care of both installing and
upgrading CRDs accordingly.

## Uninstalling the chart

To uninstall/delete the _my-release_ deployment:

```console
helm delete my-release
```

## Debugging

It is possible to generate a set of YAML files for testing/debugging:

```console
helm install my-release haproxytech/kubernetes-ingress \
  --debug \
  --dry-run
```

## Contributing

We welcome all contributions. Please refer to [guidelines](../CONTRIBUTING.md) on how to make a contribution.
