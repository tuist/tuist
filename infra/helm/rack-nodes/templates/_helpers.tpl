{{- /*
The fleet name the tuist chart's `tuist.rackLinuxFleetName` gives the same
values, with the tuist release named by `tuistRelease`.
*/ -}}
{{- define "rackNodes.fleetName" -}}
{{- $tuistFullname := .Values.fullnameOverride | default (printf "%s-%s" .Values.tuistRelease (.Values.nameOverride | default "tuist")) | trunc 63 | trimSuffix "-" -}}
{{- .Values.rackLinuxFleet.name | default (printf "%s-rack-linux" $tuistFullname) -}}
{{- end -}}

{{- define "rackNodes.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := (dig "commonLabels" dict (.Values.global | default dict)) }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "rackNodes.image" -}}
{{ .Values.macosFleet.image.repository }}:{{ .Values.macosFleet.image.tag | default "latest" }}
{{- end -}}

{{- define "rackNodes.imageCacheName" -}}
{{- $tuistFullname := .Values.fullnameOverride | default (printf "%s-%s" .Values.tuistRelease (.Values.nameOverride | default "tuist")) | trunc 63 | trimSuffix "-" -}}
{{- printf "%s-rack-image-cache" $tuistFullname -}}
{{- end -}}

{{- /*
The prewarm set's tags, as JSON: each Xcode's `imageTag` override, else
`macos-<xcode-dashes>-<runnerImageSemver>`, the tag whose digest the tuist
chart's `tuist.macosRunnerImage` names that Xcode's pools by. The cache syncs
the tag, so its retention keeps the manifest, and serves a host's pull by
that digest from it. An Xcode outside the catalog fails the render rather than
prewarming an image no pool runs. Without a semver (a render outside a
deploy, which resolves it) an Xcode without an override is skipped.
*/ -}}
{{- define "rackNodes.imageCachePrewarmTags" -}}
{{- $tags := list -}}
{{- $catalog := list -}}
{{- range (.Values.runnersFleet.xcodeVersions | default list) -}}
{{- $catalog = append $catalog (.xcodeVersion | toString) -}}
{{- end -}}
{{- $overrides := .Values.runnersFleet.xcodeOverrides | default dict -}}
{{- range $xcode := (.Values.rackFleet.imageCache.prewarm | default list) -}}
{{- $xcode = $xcode | toString -}}
{{- if not (has $xcode $catalog) -}}
{{- fail (printf "rackFleet.imageCache.prewarm names Xcode %s, which is not in runnersFleet.xcodeVersions" $xcode) -}}
{{- end -}}
{{- $tag := dig $xcode "imageTag" "" $overrides -}}
{{- if and (not $tag) $.Values.runnersFleet.runnerImageSemver -}}
{{- $tag = printf "macos-%s-%s" ($xcode | replace "." "-") $.Values.runnersFleet.runnerImageSemver -}}
{{- end -}}
{{- with $tag -}}
{{- $tags = append $tags . -}}
{{- end -}}
{{- end -}}
{{- $tags | uniq | toJson -}}
{{- end -}}
