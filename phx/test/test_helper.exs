Mimic.copy(Stripe.BillingPortal.Session)
Mimic.copy(TuistCloud.Billing)
Mimic.copy(TuistCloud.Environment)
Mimic.copy(TuistCloud.Storage)
Mimic.copy(TuistCloud.Time)
Mimic.copy(:tls_certificate_check)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TuistCloud.Repo, :manual)
