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
Expand the name of the chart.
*/}}
{{- define "kubernetes-ingress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "kubernetes-ingress.namespace" -}}
{{- if .Values.namespaceOverride -}}
{{- .Values.namespaceOverride -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kubernetes-ingress.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kubernetes-ingress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create HAProxy Ingress Chart labels
*/}}
{{- define "kubernetes-ingress.helmChartLabels" -}}
helm.sh/chart: {{ include "kubernetes-ingress.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create HAProxy Ingress Selector labels
*/}}
{{- define "kubernetes-ingress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kubernetes-ingress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create HAProxy Ingress labels
*/}}
{{- define "kubernetes-ingress.labels" -}}
{{ include "kubernetes-ingress.selectorLabels" . }}
{{ include "kubernetes-ingress.helmChartLabels" . }}
{{- end }}

{{/*
Create CRD Job selector labels
*/}}
{{- define "kubernetes-ingress.crdJobSelectorLabels" -}}
app.kubernetes.io/name: {{ include "kubernetes-ingress.serviceProxyName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create CRD Job labels
*/}}
{{- define "kubernetes-ingress.crdJobLabels" -}}
{{ include "kubernetes-ingress.crdJobSelectorLabels" . }}
{{ include "kubernetes-ingress.helmChartLabels" . }}
{{- end }}

{{/*
Create Service Proxy selector labels
*/}}
{{- define "kubernetes-ingress.serviceProxySelectorLabels" -}}
app.kubernetes.io/name: {{ include "kubernetes-ingress.serviceProxyName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create Service Proxy labels
*/}}
{{- define "kubernetes-ingress.serviceProxyLabels" -}}
{{ include "kubernetes-ingress.serviceProxySelectorLabels" . }}
{{ include "kubernetes-ingress.helmChartLabels" . }}
{{- end }}

{{/*
Encode an imagePullSecret string.
*/}}
{{- define "kubernetes-ingress.imagePullSecret" }}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.controller.imageCredentials.registry (printf "%s:%s" .Values.controller.imageCredentials.username .Values.controller.imageCredentials.password | b64enc) | b64enc }}
{{- end }}

{{/*
Generate default certificate for HAProxy.
*/}}
{{- define "kubernetes-ingress.gen-certs" -}}
{{- $ca := genCA "kubernetes-ingress-ca" 365 -}}
{{- $cn := printf "%s.%s" .Release.Name (include "kubernetes-ingress.namespace" .) -}}
{{- $cert := genSignedCert $cn nil nil 365 $ca -}}
tls.crt: {{ $cert.Cert | b64enc }}
tls.key: {{ $cert.Key | b64enc }}
{{- end -}}

{{/*
Create the name of the controller service account to use.
*/}}
{{- define "kubernetes-ingress.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "kubernetes-ingress.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified default cert secret name.
*/}}
{{- define "kubernetes-ingress.defaultTLSSecret.fullname" -}}
{{- printf "%s-%s" (include "kubernetes-ingress.fullname" .) "default-cert" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Construct the path for the publish-service.
By default this will use the <namespace>/<service-name> matching the controller's service name.
Users can provide an override for an explicit service they want to use via `.Values.controller.publishService.pathOverride`
*/}}
{{- define "kubernetes-ingress.publishServicePath" -}}
{{- $defServicePath := printf "%s/%s" (include "kubernetes-ingress.namespace" .) (include "kubernetes-ingress.fullname" .) -}}
{{- $servicePath := default $defServicePath .Values.controller.publishService.pathOverride }}
{{- print $servicePath | trimSuffix "-" -}}
{{- end -}}

{{/*
Construct the syslog-server annotation
*/}}
{{- define "kubernetes-ingress.syslogServer" -}}
{{- range $key, $val := .Values.controller.logging.traffic -}}
{{- printf "%s:%s, " $key $val }}
{{- end -}}
{{- end -}}

{{/*
Render controller pod sysctls.

Input: .Values.controller.sysctls (map[string]string)
Also keeps the existing allowPrivilegedPorts behaviour by adding
net.ipv4.ip_unprivileged_port_start=0 unless explicitly overridden via controller.sysctls.
*/}}
{{- define "kubernetes-ingress.controller.sysctls" -}}
{{- $sysctls := .Values.controller.sysctls | default dict -}}
{{- $keys := keys $sysctls | sortAlpha -}}
{{- $needPrivPorts := and .Values.controller.unprivileged .Values.controller.allowPrivilegedPorts (not (hasKey $sysctls "net.ipv4.ip_unprivileged_port_start")) -}}
{{- if or (gt (len $keys) 0) $needPrivPorts -}}
sysctls:
{{- range $name := $keys }}
  - name: {{ $name }}
    value: {{ index $sysctls $name | quote }}
{{- end }}
{{- if $needPrivPorts }}
  - name: net.ipv4.ip_unprivileged_port_start
    value: "0"
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Create a default fully qualified ServiceMonitor name.
*/}}
{{- define "kubernetes-ingress.serviceMonitorName" -}}
{{- default (include "kubernetes-ingress.fullname" .) .Values.controller.serviceMonitor.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified PodMonitor name.
*/}}
{{- define "kubernetes-ingress.podMonitorName" -}}
{{- default (include "kubernetes-ingress.fullname" .) .Values.controller.podMonitor.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a FQDN for the Service metrics.
*/}}
{{- define "kubernetes-ingress.serviceMetricsName" -}}
{{- printf "%s-%s" (include "kubernetes-ingress.fullname" . | trunc 56 | trimSuffix "-") "metrics" }}
{{- end -}}

{{/*
Create a default fully qualified CRD job name.
*/}}
{{- define "kubernetes-ingress.crdjob.fullname" -}}
{{- printf "%s-%s" (include "kubernetes-ingress.fullname" .) "crdjob" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the CRD job's dedicated ServiceAccount / ClusterRole / ClusterRoleBinding.
*/}}
{{- define "kubernetes-ingress.crdjob.saName" -}}
{{- printf "%s-%s" (include "kubernetes-ingress.fullname" .) "crdjob" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Resolve the ServiceAccount the CRD job should run under.
When rbac.create is true, prefer the dedicated crdjob SA (created as a pre-upgrade hook so it
exists before the Job runs, even when --reset-values changes the controller's SA name).
Otherwise fall back to the controller SA so users managing RBAC externally aren't forced
into a new naming convention.
*/}}
{{- define "kubernetes-ingress.crdjob.serviceAccountName" -}}
{{- if .Values.rbac.create -}}
{{ include "kubernetes-ingress.crdjob.saName" . }}
{{- else -}}
{{ include "kubernetes-ingress.serviceAccountName" . }}
{{- end -}}
{{- end -}}

{{/*
Create a FQDN for the proxy pods.
*/}}
{{- define "kubernetes-ingress.serviceProxyName" -}}
{{- printf "%s-%s" (include "kubernetes-ingress.fullname" . | trunc 58 | trimSuffix "-") "proxy" }}
{{- end -}}

{{/*
Create a name for the auxiliary configmap.
*/}}
{{- define "kubernetes-ingress.auxiliaryConfigName" -}}
{{- printf "%s-%s" (include "kubernetes-ingress.fullname" . | trunc 54 | trimSuffix "-") "auxiliary" }}
{{- end -}}

{{/*
Create extra raw objects labels.
*/}}
{{- define "kubernetes-ingress.extraRawLabels" -}}
metadata:
  labels:
    {{- include "kubernetes-ingress.labels" . | nindent 4 }}
{{- end }}

{{/*
Ensure an extra object looks like a Kubernetes manifest.
It must be a map carrying apiVersion, kind and either metadata.name or
metadata.generateName.

The body shape is deliberately not checked. Requiring 'spec' or 'data' would
reject plenty of valid kinds that carry neither: ServiceAccount, ClusterRole
and Role ('rules'), RoleBinding ('roleRef'/'subjects'), Secret ('stringData'),
PriorityClass ('value'), StorageClass ('provisioner'), Endpoints ('subsets'),
ConfigMap with only 'binaryData'. The API server is the authority on the body.
*/}}
{{- define "kubernetes-ingress.validateExtraObject" -}}
{{- $obj := . -}}
{{- $tplName := "kubernetes-ingress.validateExtraObject" -}}
{{- if not (kindIs "map" $obj) -}}
{{- fail (printf "%s: expected a map, got %s" $tplName (kindOf $obj)) -}}
{{- end -}}
{{- if not (hasKey $obj "apiVersion") -}}
{{- fail (printf "%s: object is missing required key 'apiVersion'" $tplName) -}}
{{- end -}}
{{- if not (kindIs "string" $obj.apiVersion) -}}
{{- fail (printf "%s: 'apiVersion' must be a string, got %s" $tplName (kindOf $obj.apiVersion)) -}}
{{- end -}}
{{- $_ := required (printf "%s: 'apiVersion' must not be empty" $tplName) $obj.apiVersion -}}
{{- if not (hasKey $obj "kind") -}}
{{- fail (printf "%s: object is missing required key 'kind'" $tplName) -}}
{{- end -}}
{{- if not (kindIs "string" $obj.kind) -}}
{{- fail (printf "%s: 'kind' must be a string, got %s" $tplName (kindOf $obj.kind)) -}}
{{- end -}}
{{- $_ := required (printf "%s: 'kind' must not be empty" $tplName) $obj.kind -}}
{{- if not (hasKey $obj "metadata") -}}
{{- fail (printf "%s: object is missing required key 'metadata'" $tplName) -}}
{{- end -}}
{{- if not (kindIs "map" $obj.metadata) -}}
{{- fail (printf "%s: 'metadata' must be a map, got %s" $tplName (kindOf $obj.metadata)) -}}
{{- end -}}
{{- if not (or (hasKey $obj.metadata "name") (hasKey $obj.metadata "generateName")) -}}
{{- fail (printf "%s: object is missing required key 'metadata.name' (or 'metadata.generateName')" $tplName) -}}
{{- end -}}
{{- range $key := list "name" "generateName" -}}
{{- if hasKey $obj.metadata $key -}}
{{- $value := get $obj.metadata $key -}}
{{- if not (kindIs "string" $value) -}}
{{- fail (printf "%s: 'metadata.%s' must be a string, got %s" $tplName $key (kindOf $value)) -}}
{{- end -}}
{{- $_ := required (printf "%s: 'metadata.%s' must not be empty" $tplName $key) $value -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Render one extraObjects entry, which may expand to several documents.

Map form is emitted verbatim so that foreign {{ }} (Grafana dashboards,
Prometheus rules, Alertmanager templates) survives untouched. String form is an
explicit opt-in to templating and may hold multiple '---' separated documents.

Emitted documents are '---' joined, so the caller supplies only the leading
separator.
*/}}
{{- define "kubernetes-ingress.renderExtraObject" -}}
{{- $context := .context -}}
{{- $docs := list -}}
{{- if typeIs "string" .value -}}
{{- /* string form is an explicit opt-in to templating */ -}}
{{- range $raw := regexSplit "(?m)^---[[:blank:]]*$" (tpl .value $context) -1 -}}
{{- if trim $raw -}}
{{- $parsed := fromYaml $raw -}}
{{- /* fromYaml never errors out: on a parse failure it returns
       {"Error": "<reason>"}, which would otherwise reach validateExtraObject
       and be reported as a misleading missing 'apiVersion'. */ -}}
{{- if and (hasKey $parsed "Error") (not (hasKey $parsed "apiVersion")) -}}
{{- fail (printf "kubernetes-ingress.extraObjects: could not parse manifest as YAML: %v" (get $parsed "Error")) -}}
{{- end -}}
{{- $docs = append $docs $parsed -}}
{{- end -}}
{{- end -}}
{{- if not $docs -}}
{{- fail "kubernetes-ingress.extraObjects: entry rendered to an empty manifest" -}}
{{- end -}}
{{- else -}}
{{- /* map form is emitted verbatim; foreign {{ }} left untouched */ -}}
{{- $docs = append $docs (deepCopy .value) -}}
{{- end -}}
{{- $labels := fromYaml (include "kubernetes-ingress.extraRawLabels" $context) -}}
{{- $rendered := list -}}
{{- range $doc := $docs -}}
{{- include "kubernetes-ingress.validateExtraObject" $doc -}}
{{- /* keep extra objects in the same namespace as the rest of the release,
       honouring namespaceOverride; an explicit metadata.namespace always wins,
       and 'namespace: null' opts a cluster-scoped object out entirely */ -}}
{{- if not (hasKey $doc.metadata "namespace") -}}
{{- $_ := set $doc.metadata "namespace" (include "kubernetes-ingress.namespace" $context) -}}
{{- end -}}
{{- $rendered = append $rendered (toYaml (merge $doc $labels)) -}}
{{- end -}}
{{- join "\n---\n" $rendered -}}
{{- end -}}

{{/* vim: set filetype=mustache: */}}
