{{- /*
Validates `runnerEgressGateways` and returns the enabled entries as a JSON
array sorted by name. Every template that consumes the gateways goes through
this helper, so the host-configurer, the failover controller and the gateway
resources always agree on the same set.
*/ -}}
{{- define "platform.runnerEgressGateways" -}}
{{- $gateways := list }}
{{- $server := .Values.ciliumEgressGateway.server }}
{{- $seen := dict "index" dict "port" dict "egressIP" dict "floatingIpName" dict }}
{{- $_ := set (get $seen "egressIP") (toString $server.egressIP) "ciliumEgressGateway.server" }}
{{- $_ := set (get $seen "floatingIpName") (toString $server.failoverController.floatingIpName) "ciliumEgressGateway.server" }}
{{- range $name := keys (.Values.runnerEgressGateways | default dict) | sortAlpha }}
{{- $gw := get $.Values.runnerEgressGateways $name }}
{{- if and $gw $gw.enabled }}
{{- $path := printf "runnerEgressGateways.%s" $name }}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]{0,28}[a-z0-9])?$" $name) }}
{{- fail (printf "%s: the name must be a DNS label of at most 30 characters" $path) }}
{{- end }}
{{- if not (and $server.enabled $server.hostConfigurator.enabled $server.failoverController.enabled) }}
{{- fail (printf "%s needs ciliumEgressGateway.server with hostConfigurator and failoverController enabled: they place the gateway's Floating IP on the active egress node" $path) }}
{{- end }}
{{- if not (hasKey $gw "index") }}
{{- fail (printf "%s.index is required" $path) }}
{{- end }}
{{- $index := int $gw.index }}
{{- if or (not (or (kindIs "float64" $gw.index) (kindIs "int64" $gw.index) (kindIs "int" $gw.index))) (ne (toString (float64 $gw.index)) (toString (float64 $index))) (lt $index 0) (gt $index 99) }}
{{- fail (printf "%s.index must be an integer between 0 and 99" $path) }}
{{- end }}
{{- $port := int (required (printf "%s.port is required" $path) $gw.port) }}
{{- if or (lt $port 1) (gt $port 65535) }}
{{- fail (printf "%s.port must be between 1 and 65535" $path) }}
{{- end }}
{{- $egressIP := required (printf "%s.egressIP is required" $path) $gw.egressIP }}
{{- if not (regexMatch "^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$" (toString $egressIP)) }}
{{- fail (printf "%s.egressIP must be an IPv4 address" $path) }}
{{- end }}
{{- $floatingIpName := required (printf "%s.floatingIpName is required" $path) $gw.floatingIpName }}
{{- $publicKey := required (printf "%s.publicKey (the gateway's WireGuard public key) is required" $path) $gw.publicKey }}
{{- $secret := $gw.privateKeySecret | default dict }}
{{- $item := required (printf "%s.privateKeySecret.item is required" $path) $secret.item }}
{{- range $field, $value := dict "index" (toString $index) "port" (toString $port) "egressIP" (toString $egressIP) "floatingIpName" (toString $floatingIpName) }}
{{- $owners := get $seen $field }}
{{- if hasKey $owners $value }}
{{- fail (printf "%s.%s %s is already used by %s" $path $field $value (get $owners $value)) }}
{{- end }}
{{- $_ := set $owners $value $path }}
{{- end }}
{{- $gateways = append $gateways (dict
  "name" $name
  "index" $index
  "port" $port
  "egressIP" (toString $egressIP)
  "floatingIpName" (toString $floatingIpName)
  "publicKey" (toString $publicKey)
  "privateKeyItem" (toString $item)
  "privateKeyProperty" (toString ($secret.property | default "private-key"))
) }}
{{- end }}
{{- end }}
{{- toJson $gateways }}
{{- end }}
