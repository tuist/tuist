# Our nginx patches

nginx patches applied after the fork's stack, in name order. Name them
`NNNN-description.patch`; see ../README.md, "Our nginx patches".

- `0001-script-run-reserved-length.patch`: fixes the fork's CVE-2026-42533
  backport, which drops the reserved bytes from the length
  `ngx_http_script_run()` and `ngx_stream_script_run()` return (an
  `access_log` path with variables loses its last character). Drop it when the
  fork's backport returns `e.pos + len - value->data` as upstream 1.30.4 does.
