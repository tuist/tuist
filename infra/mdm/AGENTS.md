# Fleet MDM (NanoMDM stack)

Self-hosted Apple MDM for the Mac runner fleet (BER1 rack program).
Zero-touch ABM automated device enrollment with a deliberately tiny
payload: service account, fleet SSH key, Remote Login + autorestart via
a signed pkg, USB-accessory allowance. Everything else on a host comes
from the operator SSH bootstrap (`infra/macos-host-bootstrap`), not the
MDM.

## Layout

- `enroller/` — Go service beside NanoMDM: serves the ADE enrollment
  profile (`/enroll`) and the signed bootstrap pkg (`/static`), and
  turns NanoMDM's check-in webhook into the on-enroll command sequence
  (AccountConfiguration → InstallProfile → InstallEnterpriseApplication
  → DeviceConfigured). Part of the root `go.work`.
- `scep/` — Dockerfile building `micromdm/scep`'s scepserver at a
  pinned tag (upstream publishes no image).
- `pkg/` — the bootstrap package source: `build.sh` (run on a Mac with
  a Developer ID Installer identity) + `postinstall.tmpl`. Remote Login
  is enabled via `launchctl enable/bootstrap` of sshd, NOT
  `systemsetup -setremotelogin` (which needs Full Disk Access that an
  MDM-delivered postinstall does not reliably have).
- `README.md` — the operator runbook: enrollment flow, the manual
  ceremonies (APNs push cert, ABM token exchange, DEP profile, package
  signing), payload contents, caveats, validation checklist. Keep it
  current when changing anything here.

## Deployment

Helm chart in `infra/helm/mdm` (nanomdm, nanodep depserver+depsyncer,
scepserver, enroller, CNPG Postgres), deployed to the staging cluster
namespace `mdm` by `.github/workflows/mdm-deployment.yml`. The
NanoMDM/NanoDEP pgsql schemas are vendored under the chart's
`files/schema/` from the pinned upstream tags and applied once at CNPG
initdb; upstream pgsql schema changes are rare and would land as manual
migrations (diff `storage/pgsql/schema.sql` between tags when bumping
image versions).

## Invariants

- The device-facing hostname (`host`) is immutable per enrollment: the
  MDM protocol cannot move an enrollment's ServerURL. Changing it means
  re-provisioning every enrolled device.
- The APNs push certificate and the ABM server token both expire
  yearly. The push cert must be *renewed* on the existing portal row —
  creating a new one changes the push topic and orphans every
  enrollment.
- The enroller's `/webhook` must never be routed by the ingress.
