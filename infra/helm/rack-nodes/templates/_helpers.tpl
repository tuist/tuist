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
The codename `tuist.macosCodename` gives a macOS major in the tuist chart.
*/ -}}
{{- define "rackNodes.macosCodename" -}}
{{- $codenames := dict "26" "tahoe" "27" "golden-gate" -}}
{{- $major := . | toString -}}
{{- if not (hasKey $codenames $major) -}}
{{- fail (printf "macOS %s has no runner image chain; known majors are %s" $major (keys $codenames | sortAlpha | join ", ")) -}}
{{- end -}}
{{- get $codenames $major -}}
{{- end -}}

{{- /*
The prewarm set's tags, as JSON: each Xcode's `imageTag` override, else
`macos-<profile-dashes>-<runnerImageSemver>`, the tag whose digest the tuist
chart's `tuist.macosRunnerImage` names the rack's pools for that Xcode by. The
profile is the Xcode, or `<codename>-<xcode>` when the rack runs it on a newer
guest (`rackFleet.runners.xcodeOverrides[].guestMacOS`), whose override is then
the rack's own. The cache syncs the tag, so its retention keeps the manifest,
and serves a host's pull by that digest from it. An Xcode outside the catalog
fails the render rather than prewarming an image no pool runs. Without a
semver (a render outside a deploy, which resolves it) an Xcode without an
override is skipped.
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
{{- $profile := $xcode -}}
{{- $override := dig $xcode (dict) $overrides -}}
{{- $guest := dig "runners" "xcodeOverrides" $xcode "guestMacOS" "26" $.Values.rackFleet | toString -}}
{{- if ne $guest "26" -}}
{{- $profile = printf "%s-%s" (include "rackNodes.macosCodename" $guest) $xcode -}}
{{- $override = dig "runners" "xcodeOverrides" $xcode (dict) $.Values.rackFleet -}}
{{- end -}}
{{- $tag := dig "imageTag" "" $override -}}
{{- if and (not $tag) $.Values.runnersFleet.runnerImageSemver -}}
{{- $tag = printf "macos-%s-%s" ($profile | replace "." "-") $.Values.runnersFleet.runnerImageSemver -}}
{{- end -}}
{{- with $tag -}}
{{- $tags = append $tags . -}}
{{- end -}}
{{- end -}}
{{- $tags | uniq | toJson -}}
{{- end -}}
