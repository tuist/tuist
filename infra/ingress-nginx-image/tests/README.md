# nginx tests

The nginx-tests harness `../nginx-tests.sh` builds and runs: the pinned
upstream [nginx-tests](https://github.com/nginx/nginx-tests) suite against
nginx built with AddressSanitizer from the fork's version, configure flags and
patch stack, ours included. Adapted from the Chainguard fork's
`images/nginx/tests` (Apache-2.0), since the Rancher fork has none; see
../README.md, "nginx tests".

Add our regression tests here as Test::Nginx scripts (`*.t`). `run.sh` runs
them after the upstream suite, and `nginx-tests.sh WORK_DIR t/<name>.t` runs one.
