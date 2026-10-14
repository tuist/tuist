{{/*
Copyright 2019 HAProxy Technologies LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

{{/*
Render the contents of spec.template.spec for the controller pod across
the three deployment shapes (Deployment, DaemonSet, Proxy).

Call with:
  {{- include "kubernetes-ingress.podSpec" (dict "Root" . "Mode" "Deployment") | nindent 6 }}

Mode values: "Deployment" | "DaemonSet" | "Proxy".

Mode-driven behaviour:
  - Host-port wiring sourced from controller.{deployment,daemonset}.* per kind;
    Proxy uses no host-port config (ClusterIP only).
  - DaemonSet omits topologySpreadConstraints (one pod per node by design).
  - Proxy emits hard-coded proxy-mode args (--proxy-server-mode, --k8s-api-sync-type=k8s,
    --proxy-svc-label-selector); Deployment emits sync.mode-conditional args; DaemonSet
    emits neither.
*/}}
{{- define "kubernetes-ingress.podSpec" -}}
{{- $root := .Root -}}
{{- $ctlr := $root.Values.controller -}}
{{- $isDaemonSet := eq .Mode "DaemonSet" -}}
{{- $isProxy := eq .Mode "Proxy" -}}
{{- $supportsHostPorts := not $isProxy -}}
{{- $useHostNetwork := false -}}
{{- $useHostPort := false -}}
{{- $hostPorts := dict -}}
{{- $hostIP := "" -}}
{{- if $supportsHostPorts -}}
{{-   $podCfg := ternary $ctlr.daemonset $ctlr.deployment $isDaemonSet -}}
{{-   $useHostNetwork = $podCfg.useHostNetwork -}}
{{-   $useHostPort = $podCfg.useHostPort -}}
{{-   $hostPorts = $podCfg.hostPorts -}}
{{-   $hostIP = $podCfg.hostIP -}}
{{- end -}}
enableServiceLinks: {{ $ctlr.enableServiceLinks }}
serviceAccountName: {{ include "kubernetes-ingress.serviceAccountName" $root }}
{{- if hasKey $root.Values.serviceAccount "automountServiceAccountToken" }}
automountServiceAccountToken: {{ $root.Values.serviceAccount.automountServiceAccountToken }}
{{- end }}
terminationGracePeriodSeconds: {{ $ctlr.terminationGracePeriodSeconds }}
{{- if $useHostNetwork }}
hostNetwork: true
{{- end }}
{{- if not $isDaemonSet }}
{{- with $ctlr.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
{{- if $ctlr.dnsConfig }}
dnsConfig:
{{ toYaml $ctlr.dnsConfig | indent 2 }}
{{- end }}
dnsPolicy: {{ $ctlr.dnsPolicy }}
{{- if $ctlr.imageCredentials.registry }}
imagePullSecrets:
- name: {{ include "kubernetes-ingress.fullname" $root }}
{{- else if $ctlr.existingImagePullSecret }}
imagePullSecrets:
- name: {{ $ctlr.existingImagePullSecret }}
{{- end }}
{{- if $ctlr.priorityClassName }}
priorityClassName: {{ $ctlr.priorityClassName }}
{{- end }}
{{- if $ctlr.runtimeClassName }}
runtimeClassName: {{ $ctlr.runtimeClassName }}
{{- end }}
{{- if or $ctlr.unprivileged (gt (len ($ctlr.sysctls | default dict)) 0) }}
securityContext:
{{- if $ctlr.unprivileged }}
  runAsNonRoot: true
  runAsUser:  1000
  runAsGroup: 1000
{{- end }}
{{ include "kubernetes-ingress.controller.sysctls" $root | nindent 2 }}
{{- end }}
containers:
  - name: {{ include "kubernetes-ingress.name" $root }}-{{ $ctlr.name }}
    image: "{{ $ctlr.image.repository }}:{{ $ctlr.image.tag | default $root.Chart.AppVersion }}"
    imagePullPolicy: {{ $ctlr.image.pullPolicy }}
    args:
{{- if $ctlr.defaultTLSSecret.enabled -}}
{{- if and $ctlr.defaultTLSSecret.secret $ctlr.defaultTLSSecret.secretNamespace }}
    - --default-ssl-certificate={{ tpl $ctlr.defaultTLSSecret.secretNamespace $root }}/{{ $ctlr.defaultTLSSecret.secret }}
{{- else }}
    - --default-ssl-certificate={{ include "kubernetes-ingress.namespace" $root }}/{{ include "kubernetes-ingress.defaultTLSSecret.fullname" $root }}
{{- end }}
{{- end }}
    - --configmap={{ include "kubernetes-ingress.namespace" $root }}/{{ include "kubernetes-ingress.fullname" $root }}
    - --http-bind-port={{ $ctlr.containerPort.http }}
    - --https-bind-port={{ $ctlr.containerPort.https }}
{{- if and (semverCompare ">=1.24.0-0" $root.Capabilities.KubeVersion.Version) $ctlr.service.enablePorts.quic }}
{{- $announcePort := $ctlr.quic.announcePort -}}
{{- if not $announcePort -}}
{{-   if $useHostNetwork -}}
{{-     $announcePort = $ctlr.containerPort.https -}}
{{-   else if $useHostPort -}}
{{-     $announcePort = $hostPorts.https -}}
{{-   else -}}
{{-     $announcePort = $ctlr.service.ports.https -}}
{{-   end -}}
{{- end }}
    - --quic-bind-port={{ $ctlr.containerPort.https }}
    - --quic-announce-port={{ $announcePort }}
{{- end }}
{{- if $ctlr.ingressClass }}
    - --ingress.class={{ $ctlr.ingressClass }}
{{- end }}
{{- if and $ctlr.kubernetesGateway.enabled $ctlr.kubernetesGateway.gatewayControllerName }}
    - --gateway-controller-name={{ $ctlr.kubernetesGateway.gatewayControllerName }}
{{- end }}
{{- if $ctlr.publishService.enabled }}
    - --publish-service={{ include "kubernetes-ingress.publishServicePath" $root }}
{{- end }}
{{- if $ctlr.logging.level }}
    - --log={{ $ctlr.logging.level }}
{{- end }}
{{- if $ctlr.prometheus.enabled }}
    - --prometheus
{{- end }}
{{- if $ctlr.pprof.enabled }}
    - --pprof
{{- end }}
{{- if $isProxy }}
    - --proxy-server-mode
    - --k8s-api-sync-type=k8s
    - --proxy-svc-label-selector={{ $ctlr.sync.proxyParams.proxySvcLabelSelector }}
{{- if $ctlr.sync.fetchParams.period }}
    - --proxy-k8s-fetch-period={{ $ctlr.sync.fetchParams.period }}
{{- end }}
{{- else if not $isDaemonSet }}
{{- if eq $ctlr.sync.mode "fetch" }}
  {{- if $ctlr.sync.fetchParams.period }}
    - --proxy-k8s-fetch-period={{ $ctlr.sync.fetchParams.period }}
  {{- end }}
  {{- if eq $ctlr.sync.fetchParams.source "k8s" }}
    - --k8s-api-sync-type=k8s
  {{- else if eq $ctlr.sync.fetchParams.source "proxy" }}
    - --k8s-api-sync-type=proxy
    - --proxy-svc-label-selector={{ $ctlr.sync.proxyParams.proxySvcLabelSelector }}
  {{- end }}
{{- end }}
{{- end }}
{{- range $ctlr.extraArgs }}
    - {{ . }}
{{- end }}
    {{- if $ctlr.unprivileged }}
    securityContext:
      allowPrivilegeEscalation: {{ $ctlr.allowPrivilegeEscalation }}
      capabilities:
        drop:
          - ALL
        add:
          - NET_BIND_SERVICE
      {{- if $ctlr.enableRuntimeDefaultSeccompProfile }}
      seccompProfile:
        type: RuntimeDefault
      {{- end }}
    {{- end }}
    ports:
    {{- range $key, $value := $ctlr.containerPort }}
      - name: {{ $key }}
        containerPort: {{ $value }}
        protocol: TCP
        {{- if and $useHostPort (index $hostPorts $key) }}
        hostPort: {{ index $hostPorts $key }}
        {{- end }}
        {{- if $hostIP }}
        hostIP: {{ $hostIP }}
        {{- end }}
    {{- end }}
    {{- if and (semverCompare ">=1.24.0-0" $root.Capabilities.KubeVersion.Version) $ctlr.service.enablePorts.quic }}
      - name: quic
        containerPort: {{ $ctlr.containerPort.https }}
        protocol: UDP
        {{- if $useHostPort }}
        hostPort: {{ $hostPorts.https }}
        {{- end }}
        {{- if $hostIP }}
        hostIP: {{ $hostIP }}
        {{- end }}
    {{- end }}
    {{- range $ctlr.service.tcpPorts }}
      - name: {{ .name | trunc 15 | trimSuffix "-" }}
        containerPort: {{ .targetPort }}
        protocol: TCP
        {{- if $useHostPort }}
        hostPort: {{ .port }}
        {{- end }}
        {{- if $hostIP }}
        hostIP: {{ $hostIP }}
        {{- end }}
    {{- end }}
    {{- with $ctlr.livenessProbe }}
    livenessProbe:
      {{- toYaml . | trim | nindent 6 }}
    {{- end }}
    {{- with $ctlr.readinessProbe }}
    readinessProbe:
      {{- toYaml . | trim | nindent 6 }}
    {{- end }}
    {{- with $ctlr.startupProbe }}
    startupProbe:
      {{- toYaml . | trim | nindent 6 }}
    {{- end }}
    env:
    {{- if $root.Values.aws.licenseConfigSecretName }}
    - name: AWS_WEB_IDENTITY_REFRESH_TOKEN_FILE
      value: "/var/run/secrets/product-license/license_token"
    - name: AWS_ROLE_ARN
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.aws.licenseConfigSecretName }}
          key: iam_role
    {{- end }}
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    {{- if $ctlr.extraEnvs -}}
    {{- toYaml $ctlr.extraEnvs | nindent 4 }}
    {{- end }}
    {{- with $ctlr.extraEnvFrom }}
    envFrom:
      {{- toYaml . | trim | nindent 6 }}
    {{- end }}
    resources:
      {{- toYaml $ctlr.resources | nindent 6 }}
    {{- if $ctlr.lifecycle }}
    lifecycle:
      {{- if eq "string" (printf "%T" $ctlr.lifecycle) }}
{{ tpl $ctlr.lifecycle $root | indent 6 }}
      {{- else }}
{{ toYaml $ctlr.lifecycle | indent 6 }}
      {{- end }}
    {{- end }}
    volumeMounts:
      - name: tmp
        mountPath: /tmp
        subPath: tmp
      - name: tmp
        mountPath: /run
        subPath: run
      {{- if $root.Values.aws.licenseConfigSecretName }}
      - name: aws-product-license
        readOnly: true
        mountPath: /var/run/secrets/product-license
      {{- end }}
      {{- if eq "string" (printf "%T" $ctlr.extraVolumeMounts) }}
{{ tpl $ctlr.extraVolumeMounts $root | indent 6 }}
      {{- else if gt (len $ctlr.extraVolumeMounts) 0 }}
{{ toYaml $ctlr.extraVolumeMounts | indent 6 }}
      {{- end }}
      {{- if $ctlr.auxiliaryConfig }}
      - name: haproxy-aux-cfg
        mountPath: /etc/haproxy/haproxy-aux.cfg
        subPath: haproxy-aux.cfg
        readOnly: true
      {{- end }}
  {{- if $ctlr.extraContainers }}
    {{- if eq "string" (printf "%T" $ctlr.extraContainers) }}
{{ tpl $ctlr.extraContainers $root | indent 2 }}
    {{- else }}
{{ toYaml $ctlr.extraContainers | indent 2 }}
    {{- end }}
  {{- end }}
volumes:
  - name: tmp
    emptyDir:
      medium: Memory
      sizeLimit: 64Mi
  {{- if $root.Values.aws.licenseConfigSecretName }}
  - name: aws-product-license
    secret:
      secretName: {{ $root.Values.aws.licenseConfigSecretName }}
      optional: true
  {{- end }}
  {{- if eq "string" (printf "%T" $ctlr.extraVolumes) }}
{{ tpl $ctlr.extraVolumes $root | indent 2 }}
  {{- else if gt (len $ctlr.extraVolumes) 0 }}
{{ toYaml $ctlr.extraVolumes | indent 2 }}
  {{- end }}
  {{- if $ctlr.auxiliaryConfig }}
  - name: haproxy-aux-cfg
    configMap:
      name: {{ include "kubernetes-ingress.auxiliaryConfigName" $root }}
  {{- end }}
{{- if $ctlr.initContainers }}
initContainers:
  {{- if eq "string" (printf "%T" $ctlr.initContainers) }}
{{ tpl $ctlr.initContainers $root | indent 2 }}
  {{- else }}
{{ toYaml $ctlr.initContainers | indent 2 }}
  {{- end }}
{{- end }}
{{- with $ctlr.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $ctlr.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
