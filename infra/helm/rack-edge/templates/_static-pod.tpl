{{- /*
The edge's workload as a kubelet static pod, which the installer DaemonSet
writes into the node's static pod path. The kubelet runs a static pod from its
manifest alone, so the path, keepalived and DHCP come back after a cold boot
with no API server in reach, and the WAN that the API server is reached
through comes back with them. Everything it reads is on the node: the
configuration under /etc/rack-edge/<hash> and the VRRP password in
/etc/rack-edge-vrrp, which the installer copies there first. The hash
names that copy, so a change to the configuration or the image is a new
manifest, which the kubelet answers by replacing the pod.

Called with a dict: root (the chart's top-level context) and hash.
*/}}
{{- define "rack-edge.staticPod" -}}
{{- $root := .root }}
{{- $site := include "rack-edge.site" $root }}
{{- $image := printf "%s:%s" $root.Values.image.repository $root.Values.image.tag }}
{{- $config := printf "/etc/rack-edge/%s" .hash }}
apiVersion: v1
kind: Pod
metadata:
  name: rack-edge-{{ $site }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    app.kubernetes.io/name: rack-edge-static
    app.kubernetes.io/instance: {{ $root.Release.Name }}
    tuist.dev/rack-edge-static: {{ $site }}
  annotations:
    tuist.dev/rack-edge-hash: {{ .hash | quote }}
spec:
  # The switches' port, the uplinks and tailscale0 are the node's own. No
  # cluster DNS: nothing here resolves a name, and a cold boot has none.
  hostNetwork: true
  dnsPolicy: Default
  priorityClassName: system-node-critical
  automountServiceAccountToken: false
  enableServiceLinks: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  terminationGracePeriodSeconds: 10
  # The path first, so keepalived starts with the VRRP bond it talks over
  # already up. What the path installs stays in the node's kernel when the
  # pod goes. The floating addresses go with keepalived, to the other edge,
  # and come back when this one is master again. Once the path is applied it
  # records the hash it ran, which is how the installer knows this
  # configuration took.
  initContainers:
    - name: path
      image: {{ $image | quote }}
      imagePullPolicy: {{ $root.Values.image.pullPolicy }}
      command: [sh, -ec, 'sh /etc/rack-edge/mgmt-path.sh; echo "$RACK_EDGE_HASH" > /run/rack-edge/started']
      env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: RACK_EDGE_HASH
          value: {{ .hash | quote }}
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
          add: [NET_ADMIN]
      volumeMounts:
        - name: config
          mountPath: /etc/rack-edge
          readOnly: true
        - name: state
          mountPath: /run/rack-edge
  containers:
    - name: path-reapply
      image: {{ $image | quote }}
      imagePullPolicy: {{ $root.Values.image.pullPolicy }}
      command: [sh, -ec, 'while sleep {{ $root.Values.reapplySeconds }}; do sh /etc/rack-edge/mgmt-path.sh; done']
      env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
          add: [NET_ADMIN]
      resources:
        {{- toYaml $root.Values.resources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /etc/rack-edge
          readOnly: true
    # The site's floating addresses, on whichever edge is master. dnsmasq on
    # every edge has the same configuration and answers only for the ranges
    # whose address this node holds.
    - name: vrrp
      image: {{ $image | quote }}
      imagePullPolicy: {{ $root.Values.image.pullPolicy }}
      command: [sh, -ec, 'exec keepalived --dont-fork --log-console --log-detail --no-syslog --vrrp --use-file "/etc/rack-edge/keepalived-$NODE_NAME.conf"']
      env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
          # Addresses and routes, and the raw sockets VRRP and gratuitous ARP
          # go out on.
          add: [NET_ADMIN, NET_RAW]
      resources:
        {{- toYaml $root.Values.resources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /etc/rack-edge
          readOnly: true
        - name: vrrp
          mountPath: /etc/rack-edge-vrrp
          readOnly: true
    - name: dhcp
      image: {{ $image | quote }}
      imagePullPolicy: {{ $root.Values.image.pullPolicy }}
      # --no-daemon rather than --keep-in-foreground: it also keeps dnsmasq
      # from changing to a user and group of its own, which it has no
      # capability for.
      command: [dnsmasq, --no-daemon, --conf-file=/etc/rack-edge/dnsmasq.conf]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
          # Port 67, the ARP entry a unicast reply needs, and the ping that
          # checks an address is free before offering it.
          add: [NET_BIND_SERVICE, NET_ADMIN, NET_RAW]
      resources:
        {{- toYaml $root.Values.resources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /etc/rack-edge
          readOnly: true
        - name: leases
          mountPath: /var/lib/misc
    # The machines segment's DHCP, a dnsmasq of its own because it must not
    # be authoritative: both edges answer there.
    - name: dhcp-machines
      image: {{ $image | quote }}
      imagePullPolicy: {{ $root.Values.image.pullPolicy }}
      command: [dnsmasq, --no-daemon, --conf-file=/etc/rack-edge/dnsmasq-machines.conf]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
          add: [NET_BIND_SERVICE, NET_ADMIN, NET_RAW]
      resources:
        {{- toYaml $root.Values.resources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /etc/rack-edge
          readOnly: true
    # The machines' addresses, advertised to the tailnet by both edges
    # through the node's own tailscaled, so the tailnet fails over between
    # them. tailscaled trusts its socket's caller by uid, and this runs as
    # root, so it needs no capability.
    - name: routes
      image: {{ $image | quote }}
      imagePullPolicy: {{ $root.Values.image.pullPolicy }}
      command: [sh, -ec, 'while :; do sh /etc/rack-edge/tailnet-routes.sh; sleep {{ $root.Values.routesReapplySeconds }}; done']
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
      resources:
        {{- toYaml $root.Values.resources | nindent 8 }}
      volumeMounts:
        - name: config
          mountPath: /etc/rack-edge
          readOnly: true
        - name: tailscale
          mountPath: /run/tailscale
          readOnly: true
  volumes:
    - name: config
      hostPath:
        path: {{ $config }}
        type: Directory
    - name: vrrp
      hostPath:
        path: /etc/rack-edge-vrrp
        type: Directory
    # On the node, so a restarted pod hands a switch the lease it had.
    - name: leases
      hostPath:
        path: /var/lib/misc
        type: DirectoryOrCreate
    - name: state
      hostPath:
        path: /run/rack-edge
        type: DirectoryOrCreate
    - name: tailscale
      hostPath:
        path: /run/tailscale
        type: Directory
{{- end }}
