package linux

import (
	"context"
	"fmt"

	"github.com/go-logr/logr"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
)

// KubeletIdentityMode is how the OVH and Vultr kinds' kubelets authenticate.
//
// Without Certificates (the default until every environment has moved) each
// machine's kubelet runs on a long-lived token of a tart-kubelet-<machine>
// ServiceAccount bound to system:node. The Node authorizer and NodeRestriction
// scope only system:node:<name> users, so that token reads every Secret in the
// cluster, and the operator, which mints it, can mint one for any name.
//
// With Certificates the kubelet joins as the rack Linux kind's does: a
// one-hour kubeadm bootstrap token gets it a system:node:<name> client
// certificate, which kubeadm's bindings approve and rotate, and the
// ServiceAccount identity is revoked once the kubelet holds it.
type KubeletIdentityMode struct {
	Certificates bool
}

// prepare puts what the kubelet authenticates with into opts. The returned
// cleanup deletes the bootstrap token; call it once the script that uses it
// has returned, since the script waits for the kubelet's certificate.
func (k KubeletIdentityMode) prepare(ctx context.Context, cm *credentials.Manager, kc *kubeconfig.Builder, machineName string, opts *linuxCloudInitOptions) (func(logr.Logger), error) {
	if !k.Certificates {
		identity, err := cm.EnsureNodeIdentity(ctx, machineName, linuxNodeIdentityClusterRole)
		if err != nil {
			return nil, fmt.Errorf("mint node identity: %w", err)
		}
		kubeconfigYAML, err := kc.Render(ctx, machineName, identity.Token, identity.CA)
		if err != nil {
			return nil, fmt.Errorf("render kubelet kubeconfig: %w", err)
		}
		opts.KubeconfigYAML = kubeconfigYAML
		opts.ClusterCAPEM = identity.CA
		return func(logr.Logger) {}, nil
	}
	ca, err := cm.ClusterCABundle()
	if err != nil {
		return nil, err
	}
	server := ""
	if kc != nil {
		server = kc.APIServerURL
	}
	if server == "" {
		return nil, fmt.Errorf("no API server URL for %s's bootstrap kubeconfig", machineName)
	}
	secretName, token, err := cm.MintNodeBootstrapToken(ctx, machineName)
	if err != nil {
		return nil, err
	}
	opts.NodeCertificates = true
	opts.ClusterCAPEM = ca
	opts.BootstrapKubeconfigYAML = rackBootstrapKubeconfig(server, ca, token)
	return func(logger logr.Logger) {
		if err := cm.DeleteBootstrapToken(ctx, secretName); err != nil {
			logger.Error(err, "delete the bootstrap token; it expires within the hour", "token", secretName)
		}
	}, nil
}
