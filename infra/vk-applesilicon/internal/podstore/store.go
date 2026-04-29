// Package podstore is a placeholder for future persistent state. The
// MVP keeps the Pod → Mac mini mapping in memory inside vkprovider;
// when the VK Pod restarts, it rebuilds the mapping by listing all
// running Tart VMs across hosts (vkprovider does this on Hosts()
// refresh + GetPods).
//
// We split this into its own package so persistent storage (Secret
// or ConfigMap-backed) can land later without touching vkprovider.
package podstore
