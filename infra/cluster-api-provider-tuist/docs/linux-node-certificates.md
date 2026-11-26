# Linux node certificates

The OVH and Vultr kubelets join on a long-lived token of a
`tart-kubelet-<machine>` ServiceAccount bound to the `system:node`
ClusterRole. The Node authorizer and NodeRestriction scope only users named
`system:node:<name>` in `system:nodes`, so such a token falls through to RBAC,
where `system:node` gets, lists and watches every Secret in the cluster. A
compromised Kura or Linux runner host therefore reads every Secret, and so
does the operator: it holds `bind` on `system:node`, and its admission policy
admits any `tart-kubelet-*` binding of it.

`macosFleet.linuxNodeCertificates` (`--linux-node-certificates`) makes these
kubelets join like the rack Linux nodes do. A one-hour kubeadm bootstrap token
gets the kubelet a `system:node:<machine>` client certificate, which kubeadm's
bindings approve and the kubelet rotates (`rotateCertificates: true`). The
flag also removes `system:node` from the operator's `bind` and from its
admission policy.

`controllers/shared/operator_rbac_envtest_test.go`
(`TestOperatorCannotMintANodeIdentityThatReadsEverySecret`) runs the rendered
chart, with the flag on, on an API server authorizing as production does
(`Node,RBAC` and NodeRestriction). The operator is refused the binding, and
can still delete an existing one, which revoking a moved node needs. The same
test rendered with the flag off failed: the operator bound `system:node` to a
new ServiceAccount, minted its token, and the token read the 1Password service
account token and listed every Secret.

## What the flag does to a joined node

The kubelet-config drift loop folds the identity into its hash, so every
joined node gets a re-push (`kubeletMigrationGuard`,
`kubeletIdentityMigration`):

1. A bootstrap token is minted for the node.
2. On a node still on a ServiceAccount, `config.yaml` and the unit are copied
   aside and the kubeconfig is moved aside (`*.serviceaccount`), and a trap
   is armed.
3. `config.yaml` gains `rotateCertificates: true`, the unit gains
   `--bootstrap-kubeconfig` after `--kubeconfig`, and the bootstrap
   kubeconfig is written.
4. The kubelet restarts. Running Pods survive, as on any kubelet restart.
5. The script waits up to two minutes for
   `pki/kubelet-client-current.pem`. If any step fails, or no certificate
   comes, the trap restores all three files, removes the bootstrap
   kubeconfig and any client certificate, and restarts the kubelet. The node
   stays Ready on its old identity and nothing is revoked. Restoring the
   kubeconfig alone would not do: with rotation or the bootstrap flag still
   set, the kubelet treats a token kubeconfig as invalid and bootstraps over
   it.
6. With the certificate, the backups go, the operator deletes the bootstrap
   token, revokes the node's ServiceAccount, its token Secret and its
   ClusterRoleBinding, and only then stamps the node, with
   `tuist.dev/kubelet-identity: certificate`. The Kata runtime repair renders
   the unit for the identity that annotation records.

A fresh join with the flag on drops a certificate the box holds for another
node name (a box re-adopted without a wipe), since NodeRestriction would
refuse the new Node.

A failed move restores the ServiceAccount kubelet. When the failure is no
certificate within two minutes (exit 75, usually CSR approval), the Node is
stamped `tuist.dev/kubelet-identity-failed-at` and the drift loop holds it
for an hour; any other failure retries at the next resync. The script
ignores SIGPIPE and SIGHUP, so a dropped SSH session neither stops it nor
skips the restore; it holds `/run/lock/tuist-kubelet-identity.lock`, so a
second run started meanwhile waits for it; and a run killed anyway leaves
backups the next run restores from.

The re-push waits on a Kata runner host until it has no Pod with exclusive
CPUs (the existing guard), so `runners-linux` hosts move only once cordoned
and drained.

## Rollout

1. Ship the code with the flag off. Nothing changes: renders and scripts are
   byte-identical with it off.
2. Staging: turn the flag on. Watch each Linux node's CSR
   (`kubectl get csr`, requestor `system:bootstrap:<id>` then
   `system:node:<machine>`), that its Node stays Ready, and that
   `kubectl get clusterrolebindings` lists no `system:node` binding to a
   ServiceAccount. Cordon the runners-linux host so it moves.
3. Canary, the same.
4. Production. The flag is global, so the kura fleets move on their next
   drift reconcile, one node per reconcile. Cordon the 10 `runners-linux`
   hosts one at a time. Done when no ClusterRoleBinding binds `system:node`
   to a ServiceAccount.
5. Make the flag the default and delete the ServiceAccount path
   (`EnsureNodeIdentity` for the Linux kinds and the `kubeconfig` it renders).

No rollback restores the old state on its own. Turning the flag off, or
reverting the image, makes the drift loop mint a new `system:node`
ServiceAccount for each moved node and re-push `config.yaml` without
certificate rotation, so its certificate lapses at the signing duration (a
year by default) while the unit still bootstraps from a token nobody mints.
Before rolling back, replace each moved node: deleting its Machine
reinstalls the box back to the pool, and the fleet adopts and joins a host
on whatever identity the operator then uses.
Prefer fixing forward.
