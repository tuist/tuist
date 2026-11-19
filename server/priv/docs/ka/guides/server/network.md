---
{
  "title": "ქსელი",
  "titleTemplate": ":title | სერვერი | სახელმძღვანელოები | Tuist",
  "description": "Tuist-ის ქსელის კონფიგურაცია, მათ შორის გამავალი IP მისამართები."
}
---
# ქსელი {#network}

ეს გვერდი აღწერს ქსელთან დაკავშირებულ კონფიგურაციას, რომელიც შეიძლება დაგჭირდეთ Tuist-ის თქვენს ინფრასტრუქტურაში ინტეგრირებისას.

## გამომავალი IP მისამართები {#outbound-ip-addresses}

თუ თქვენი ინფრასტრუქტურა ზღუდავს შემომავალ ტრაფიკს IP მისამართის მიხედვით, შეიძლება დაგჭირდეთ Tuist-ის მიერ გამოყენებული IP დიაპაზონების თეთრ სიაში შეყვანა. ეს ხშირად გვხვდება, როდესაც Tuist-ს სჭირდება კომუნიკაცია ფაიერვოლის ან VPN-ის უკან მყოფ სერვისებთან, მაგალითად, საკუთარ სერვერზე განთავსებულ Git პროვაიდერებთან ან არტიფაქტების საცავებთან, ან როდესაც თქვენი GitHub ორგანიზაცია იყენებს [IP ნებართვების სიებს](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization).

თეთრ სიაში შეიყვანეთ სერვერის მისამართები Tuist-ის ინტეგრაციებისთვის და რანერების მისამართები ყოველი პლატფორმისთვის, რომელსაც თქვენი სამუშაო პროცესები იყენებენ.

### სერვერის IP მისამართები {#server-ip-addresses}

თეთრ სიაში შეიყვანეთ ორივე მისამართი Tuist-ის სერვისებიდან და ინტეგრაციებიდან მომავალი კავშირებისთვის:

| IP მისამართი | CIDR ჩანაწერი |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist უკავშირდება თქვენს ინფრასტრუქტურას მხოლოდ HTTPS-ით, ამიტომ საკმარისია ამ მისამართებიდან მხოლოდ HTTPS ტრაფიკის (TCP პორტი 443, ან პორტი, რომელზეც თქვენი HTTPS ბოლო წერტილი ელოდება) ნებართვა. Tuist-ს SSH წვდომა არ სჭირდება.

### Tuist Runners {#tuist-runners}

ამოცანები, რომლებიც <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>-ზე გაეშვება, იყენებენ ქვემოთ მოცემულ გამომავალ მისამართებს. თუ ამოცანას სჭირდება ისეთ ინფრასტრუქტურასთან წვდომა, რომელიც ზღუდავს ტრაფიკს IP მისამართის მიხედვით, მაგალითად, რეპოზიტორიის გადმოწერა GitHub ორგანიზაციიდან IP ნებართვების სიით, თეთრ სიაში შეიყვანეთ მისამართები ან დიაპაზონები ყოველი პლატფორმისთვის, რომელზეც თქვენი სამუშაო პროცესები გაეშვება.

#### macOS {#tuist-runners-macos}

თეთრ სიაში შეიყვანეთ შემდეგი დიაპაზონები macOS რანერის ამოცანებისთვის:

| IP ვერსია | CIDR ჩანაწერი |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

თეთრ სიაში შეიყვანეთ მთელი დიაპაზონი Linux რანერის ამოცანებისთვის:

| IP ვერსია | CIDR ჩანაწერი |
|---|---|
| IPv4 | `5.135.7.160/27` |

<!--
MAINTAINERS: the server table is the customer-facing contract for the reserved
egress set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.

The macOS IPv4 range is configured in infra/rack-switch-fleet/sites/ber1.json.
The public allowlist excludes Scaleway hosts; reassess it before using them
for runner jobs again.

The Linux range must match `capi.ovhRunnerEgress.cidr` in
infra/helm/tuist/values-managed-production.yaml. Publish this range-only guide
with the production cutover after verifying every runner on the new block.
Rollback to primary IPs requires restoring the old allowlist entries; see the
internal OVH runner egress runbook.
-->
