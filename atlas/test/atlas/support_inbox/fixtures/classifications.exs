# Hand-labeled fixture of real inbound emails to contact@tuist.dev,
# used as ground truth for `Atlas.SupportInbox.Agents.ClassifierAgent` tests.
#
# Each entry captures only the signal the classifier sees at inbound time:
# sender, subject, has_attachments. Bodies are intentionally out of scope
# for the fixture — the agent test runs against subject-only inputs, which
# is the harder path; running against subject + body should only raise
# recall.
#
# Categories:
#   :support         customer question or bug report; humans must reply
#   :invoice         vendor invoice/receipt to file and pay
#   :vendor_notice   transactional vendor mail (reboots, order confirms,
#                    traffic warnings, plan-cancellations)
#   :shipping        delivery/tracking updates
#   :publish         package/plugin publish confirmations
#   :registration    account-creation, verification codes, activations
#   :ar              accounts-receivable notifications (invoices we sent,
#                    payouts we received)
#   :spam            cold pitches, guest-post spam, dubious opportunities
#   :other           anything the above misses
#
# The classifier must reach at least 95% recall on `action_needed: true`
# entries — silencing a real support request is the primary failure mode
# we guard against.

[
  # ==== Real support & sales inquiries — action_needed: true ====
  %{
    from: "vedran@indexedlabs.com",
    subject: "Re: Remote module-cache artifacts crashed all consumers with ABI-skew while the producing warm's local copies passed — request server-side integrity check for 2026-08-12",
    category: :support,
    action_needed: true,
    urgency: :high
  },
  %{
    from: "kai.lee@kakaobank.com",
    subject: "Inquiry about evaluating Tuist Enterprise before adoption",
    category: :support,
    action_needed: true,
    urgency: :normal
  },
  %{
    from: "kaan.eksen@akbank.com",
    subject: "Demo and Self-Hosted Pricing Request for Tuist at Akbank Mobil",
    category: :support,
    action_needed: true,
    urgency: :normal
  },
  %{
    from: "margulan.daribayev@indriver.com",
    subject: "Enterprise pricing for inDrive and technical questions on Tuist cache",
    category: :support,
    action_needed: true,
    urgency: :normal
  },
  %{
    from: "ssandler@whatnot.com",
    subject: "Getting logged out of iOS app",
    category: :support,
    action_needed: true,
    urgency: :high
  },
  %{
    from: "omar.zairi@enicar.ucar.tn",
    subject: "Final-year internship from February 2027: build infrastructure, caching and CI",
    category: :support,
    action_needed: true,
    urgency: :low
  },

  # ==== Vendor invoices — action_needed: false, auto-attach candidate ====
  %{
    from: "noreply.billing@hetzner.com",
    subject: "Hetzner Online GmbH - Invoice 083001178539 (K0701467324)",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@notify.cloudflare.com",
    subject: "Your invoice is available",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "no-reply@deepl.com",
    subject: "Your DeepL Pro invoice",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@reichelt.de",
    subject: "Ihre Bestellung vom 24.9.2026 (Bearbeitungsnummer I-691078 )",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@jacob.de",
    subject: "JACOB - Rechnung (SRE) SRE10870283 [B2B]",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "office@racknex.com",
    subject: "[racknex SHOP]: Invoice 2026091605 for order #29287",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@mindfactory.de",
    subject: "Versandmitteilung (inkl. Rechnung): Ihre Bestellung vom 21.09.2026 ist unterwegs!",
    category: :invoice,
    action_needed: false,
    urgency: :none
  },

  # ==== Vendor notices — mostly silent, some action_needed ====
  %{
    from: "noreply@hetzner.com",
    subject: "Soft reboot for your server AX102-4 #3080350 (46.4.64.107) tuist-bm-production-1",
    category: :vendor_notice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@hetzner.com",
    subject: "Soft reboot for your server AX102-4 #3080353 (46.4.107.16) tuist-bm-production-2",
    category: :vendor_notice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "support@hetzner.com",
    subject: "Your ordered AX102-4 server",
    category: :vendor_notice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "support@hetzner.com",
    subject: "Order Confirmation B20260922-3511071 - AX102-4",
    category: :vendor_notice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "server-order@hetzner.com",
    subject: "Order confirmation (Hetzner Online GmbH)",
    category: :vendor_notice,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@notify.cloudflare.com",
    subject: "[Confirmation] Purchase confirmed",
    category: :vendor_notice,
    action_needed: false,
    urgency: :none
  },
  # Action-needed vendor notices — the ones the classifier MUST catch
  %{
    from: "support-cloud@hetzner.com",
    subject: "server cache-eu-central is close to exceeding its included traffic",
    category: :vendor_notice,
    action_needed: true,
    urgency: :high
  },
  %{
    from: "support-cloud@hetzner.com",
    subject: "Billing alert for project tuist-workloads",
    category: :vendor_notice,
    action_needed: true,
    urgency: :normal
  },
  %{
    from: "support@pinaccounting.zendesk.com",
    subject: "Action required: Verify bank account change for your Pinterest vendor record",
    category: :vendor_notice,
    action_needed: true,
    urgency: :high
  },
  %{
    from: "kontakt@jacob.de",
    subject: "Wir haben eine Frage zu Ihrer Bestellung BEK17627477",
    category: :vendor_notice,
    action_needed: true,
    urgency: :normal
  },
  %{
    from: "chris@mail.loops.so",
    subject: "Your plan has been canceled",
    category: :vendor_notice,
    action_needed: true,
    urgency: :normal
  },

  # ==== Shipping — silent, digest ====
  %{
    from: "info@jacob.de",
    subject: "JACOB - JE20360641 - Neuigkeiten zur Sendung 1Z617V136890289184",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@jacob.de",
    subject: "JACOB - JE20357431 - Neuigkeiten zur Sendung 1Z860Y6W6874381016",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@jacob.de",
    subject: "JACOB - JE20360641 - Neuigkeiten zur Sendung 158358705686",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "b2b@jacob.de",
    subject: "JACOB - JE20360641 - Neuigkeiten zur Sendung 751035239642",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "trackingupdates@fedex.com",
    subject: "Ihre Sendung wurde geliefert. 877144598946",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "trackingupdates@fedex.com",
    subject: "Your shipment was delivered 877144598946",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "trackingupdates@fedex.com",
    subject: "Your shipment is out for delivery today 877144598946",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "trackingupdates@fedex.com",
    subject: "Part of your shipment is scheduled for delivery tomorrow 877144598946",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "trackingupdates@fedex.com",
    subject: "We have your shipment 877144598946.",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@dhl.de",
    subject: "Ihre Galaxus Deutschland GmbH Sendung liegt nebenan",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@dhl.de",
    subject: "Ihre Galaxus Deutschland GmbH Sendung wird gleich zugestellt",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@dhl.de",
    subject: "Ihre Galaxus Deutschland GmbH Sendung ist unterwegs",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@notifications.galaxus.de",
    subject: "Your parcel is on its way",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "versandinfo@reichelt.de",
    subject: "Ihre Bestellung vom 24.9.2026 ",
    category: :shipping,
    action_needed: false,
    urgency: :none
  },

  # ==== Publish notifications — silent, digest ====
  %{
    from: "noreply@hex.pm",
    subject: "Hex.pm - Package tuist_ex v0.2.0 published",
    category: :publish,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@hex.pm",
    subject: "Hex.pm - Package tuist_ex v0.1.0 published",
    category: :publish,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "no-reply@mailer.rubygems.org",
    subject: "Gem buildonce (0.61.0) pushed to RubyGems.org",
    category: :publish,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "no-reply@mailer.rubygems.org",
    subject: "Gem buildonce (0.60.0) pushed to RubyGems.org",
    category: :publish,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "no-reply@gradle.com",
    subject: "[Gradle] Plugin dev.tuist published",
    category: :publish,
    action_needed: false,
    urgency: :none
  },

  # ==== Registration / verification codes ====
  %{
    from: "support@certpanel.com",
    subject: "Your verification code: 241715",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "support@sectigostore.com",
    subject: "SectigoStore.com Order Confirmation",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@notebook.de",
    subject: "Deine Registrierung bei Notebook.de",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@easynotebooks.de",
    subject: "Ihre Registrierung bei Easynotebooks.de - Auswahl, Lieferzeit, Service - Alles Easy",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@jacob.de",
    subject: "Deine Registrierung bei B2B Storefront",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "info@jacob.de",
    subject: "Bitte bestätigen Sie Ihre Anmeldung bei B2B Storefront",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "keineantwortadresse@jacob.de",
    subject: "JACOB - Neue Zugangsdaten",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "noreply@galaxus.de",
    subject: "Galaxus – Confirm your e-mail address",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "office@racknex.com",
    subject: "Your racknex account has been created!",
    category: :registration,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "office@racknex.com",
    subject: "Activate your account on racknex",
    category: :registration,
    action_needed: false,
    urgency: :none
  },

  # ==== AR — invoices we sent, payments we received ====
  %{
    from: "notifications@ziphq.com",
    subject: "Payment initiated: Whatnot paid you USD 24,000.00",
    category: :ar,
    action_needed: false,
    urgency: :none
  },
  %{
    from: "streamingap@ap.netflix.com",
    subject: "New invoice from Tuist GmbH #TUIST-12382",
    category: :ar,
    action_needed: false,
    urgency: :none
  },

  # ==== Spam ====
  %{
    from: "violet@allmktscale.org",
    subject: "Collaboration Opportunity – Guest Post for tuist.dev",
    category: :spam,
    action_needed: false,
    urgency: :none
  }
]
