## Credential-free reporting on a private network {#network-trusted-publishing}

A self-hosted deployment can allow developers to publish completed reports without signing in. An operator must configure `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` on the instance and restart it as described in the <.localized_link href="/guides/server/self-host/server#network-trusted-access">self-hosting guide</.localized_link>. This applies to every supported project; there is no dashboard setting. Configure the self-hosted URL and project in the environment used by your scheme post-action or terminal. The CLI automatically discovers the instance policy when credentials are absent:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

With genuinely absent credentials, activity logs and XCResult bundles are parsed locally and sent as structured reports. No raw archive, attachment, coverage/history upload, remote processor, shard reference, or selective-execution evidence is submitted. Reports remain visible but cannot update authenticated testcase state or drive quarantine/failure automations. Dashboards and other privileged commands still require sign-in. Keep cache integration disabled unless the instance separately enables network-trusted cache access or credentials are provisioned.

Present credentials remain authenticated. Invalid, corrupt, blank, or rejected-refresh credentials fail closed and remain on disk, so later commands do not silently become unsigned. Sign in again or explicitly sign out as a deliberate recovery action. Upgrade every server replica to a discovery-capable version before upgrading credential-free clients, and configure the final server URL without redirects. Older servers without discovery, disabled instances, and discovery failures still require authentication. No client-side opt-in is needed. Set `TUIST_ACTOR_ID=""` independently to omit the configured actor claim; verified credential identity is unaffected.
