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
The images the cache holds, in priority order, as JSON: for each
`rackFleet.imageCache.xcodeVersions` entry, the image the tuist chart's
`tuist.macosRunnerImage` gives that Xcode's pools,
`<runnerImageRepository>:macos-<xcode-dashes>-<runnerImageSemver>` or the
Xcode's `imageTag` override. An Xcode outside the catalog, or a repository
outside the cache's upstream, fails the render rather than holding an image
no pool runs. Without a semver (a render outside a deploy, which resolves it)
an Xcode without an override is skipped.
*/ -}}
{{- define "rackNodes.imageCacheImages" -}}
{{- $images := list -}}
{{- $catalog := list -}}
{{- range (.Values.runnersFleet.xcodeVersions | default list) -}}
{{- $catalog = append $catalog (.xcodeVersion | toString) -}}
{{- end -}}
{{- $repository := .Values.runnersFleet.runnerImageRepository | default "" -}}
{{- $upstream := .Values.rackFleet.imageCache.upstream | default "" -}}
{{- $overrides := .Values.runnersFleet.xcodeOverrides | default dict -}}
{{- range $xcode := (.Values.rackFleet.imageCache.xcodeVersions | default list) -}}
{{- $xcode = $xcode | toString -}}
{{- if not (has $xcode $catalog) -}}
{{- fail (printf "rackFleet.imageCache.xcodeVersions names Xcode %s, which is not in runnersFleet.xcodeVersions" $xcode) -}}
{{- end -}}
{{- if not (hasPrefix (printf "%s/" $upstream) $repository) -}}
{{- fail (printf "runnersFleet.runnerImageRepository %q is not in rackFleet.imageCache.upstream %q" $repository $upstream) -}}
{{- end -}}
{{- $tag := dig $xcode "imageTag" "" $overrides -}}
{{- if and (not $tag) $.Values.runnersFleet.runnerImageSemver -}}
{{- $tag = printf "macos-%s-%s" ($xcode | replace "." "-") $.Values.runnersFleet.runnerImageSemver -}}
{{- end -}}
{{- with $tag -}}
{{- $images = append $images (printf "%s:%s" $repository .) -}}
{{- end -}}
{{- end -}}
{{- $images | uniq | toJson -}}
{{- end -}}
