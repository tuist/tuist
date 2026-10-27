{{/*
Whether the tailscale.com CRDs are already registered on the cluster, which
gates every Connector, ProxyClass and ProxyGroup this chart renders.

The CRDs ship in the subchart's templates/, not crds/, so on a new cluster Helm
cannot map those kinds when it builds the release and the install fails with
"no matches for kind". There, the first install lays down the operator and its
CRDs, and the CRs come with the next one: the deploy workflow runs a second
pass when the CRDs were missing, and a manual install has to be run twice.

These CRs used to be post-install/post-upgrade hooks instead. A hook is
deleted and recreated on every upgrade, and when a ProxyGroup or Connector is
deleted the operator deletes its devices from the tailnet, and its state
Secrets go with it through their owner references, so every Service behind one
lost all of its proxies at once on each deploy and came back on new devices.
As ordinary release resources they are patched in place. The hooks did not
make the first install reliable either: with Helm 4, deleting the hook before
creating it hits the same mapping error.
*/}}
{{- define "tuist-tailscale-operator.crdsInstalled" -}}
{{- if .Capabilities.APIVersions.Has "tailscale.com/v1alpha1/ProxyGroup" }}true{{ end }}
{{- end }}
