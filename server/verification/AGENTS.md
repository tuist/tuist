# Cluster formation verification

`cluster_formation.exs` runs in an isolated named VM with two owned Erlang nodes, no server/database startup and no production access. It verifies configured DNS discovery, the fixed peer listener, the shared cookie and departure. It is not an authorization, loaded rolling-restart, real network-policy or partition recovery test. Run a real two-replica canary before promotion.
