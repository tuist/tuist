# Authentication verification

Run `MIX_ENV=test mix run --no-start --no-compile verification/bcrypt_load.exs` after compiling tests. It starts only owned cache/verification processes, uses rounds 12, and checks one expensive verification for a warm/concurrent credential burst. Never point it at production. Unit regressions cover mixed credentials, revocation, TTL, failures and eviction separately.
