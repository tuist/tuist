# Production-shaped runtime handover fixture

`staging.mjs` owns only uniquely labelled resources it creates in the reserved
staging qualification namespace. Keep the explicit context/namespace checks,
UID checks before mutation, and pod-before-volume cleanup order. The pod-local
Kubernetes hostname override points exclusively at `fixture-api.mjs`; it does
not write a real serving ConfigMap. These are real runtimes with simulated
authority inputs, not controller or physical-host-failure qualification.

Both runtimes run on one explicitly selected staging host with separate PVCs.
A proxy caps aggregate retained-body transfer at 500 Mbit/s during measurement.
Do not use cross-region RTT, increased deadlines, unequal ring capacities or
extra destination storage to manufacture a passing production qualification.
A smoke pass only verifies harness plumbing. Keep full-size corpus checks and
strict expected-failure classification; a generic timeout is not the observed
repair-churn failure. Never import actual record identifiers or artifact bodies.

Run `node --test profile.test.mjs` for recipe, streaming and failure-classification
checks. Runtime runs must retain logs, exact images, corpus shape, authority
transitions, resource samples, outcome and cleanup evidence. A production
qualification requires fresh and fragmented-volume runs, repetition on identical
budgets, followed by the separate real-controller test in the parent directory.
No changes to production accounts or account-wide flags belong in this harness.
