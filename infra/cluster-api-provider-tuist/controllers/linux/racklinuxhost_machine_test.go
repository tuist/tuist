package linux

import (
	"strings"
	"testing"

	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// Each host is its own Machine: the operator keeps a CAPI Machine and the
// RackLinuxMachine it owns under the host's name, with no pool to claim from.
func TestRackLinuxHostKeepsTheMachineThatMakesItANode(t *testing.T) {
	h := newInstallHarness(t, svcHost())
	h.r.Machines = &RackMachines{ClusterName: "tuist-tuist-capi", BootstrapSecret: "tuist-tuist-noop-bootstrap"}

	h.reconcile(t, svcUUID)
	h.reconcile(t, svcUUID)

	rlm := &infrav1.RackLinuxMachine{}
	if !h.exists(t, rlm, rackTestNamespace, svcUUID) {
		t.Fatal("no RackLinuxMachine")
	}
	if rlm.Spec.Host != svcUUID || rlm.Labels[RackLinuxHostLabel] != svcUUID || rlm.Labels[clusterv1.ClusterNameLabel] != "tuist-tuist-capi" {
		t.Fatalf("RackLinuxMachine %+v labels %v", rlm.Spec, rlm.Labels)
	}

	machine := &clusterv1.Machine{}
	if !h.exists(t, machine, rackTestNamespace, svcUUID) {
		t.Fatal("no Machine")
	}
	spec := machine.Spec
	if spec.ClusterName != "tuist-tuist-capi" || spec.Bootstrap.DataSecretName == nil || *spec.Bootstrap.DataSecretName != "tuist-tuist-noop-bootstrap" {
		t.Fatalf("Machine spec %+v", spec)
	}
	if ref := spec.InfrastructureRef; ref.Kind != "RackLinuxMachine" || ref.Name != svcUUID || ref.APIVersion != infrav1.GroupVersion.String() {
		t.Fatalf("infrastructureRef %+v", ref)
	}
	if machine.Labels[RackLinuxRoleLabel] != "services" || machine.Labels[clusterv1.ClusterNameLabel] != "tuist-tuist-capi" {
		t.Fatalf("labels %v", machine.Labels)
	}
	owners := machine.OwnerReferences
	if len(owners) != 1 || owners[0].Kind != "RackLinuxHost" || owners[0].Name != svcUUID || owners[0].Controller == nil || !*owners[0].Controller {
		t.Fatalf("owners %+v, want the host as controller", owners)
	}

	created := 0
	for _, e := range drainEvents(h) {
		if strings.Contains(e, "MachineCreated") {
			created++
		}
	}
	if created != 1 {
		t.Fatalf("%d MachineCreated events, want one across two reconciles", created)
	}
}
