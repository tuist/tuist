Mimic.copy(TuistCloud.Storage)
Mimic.copy(TuistCloud.Time)
Mimic.copy(TuistCloud.Environment)
Mimic.copy(TuistCloud.Billing)
Mimic.copy(Stripe.BillingPortal.Session)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TuistCloud.Repo, :manual)
