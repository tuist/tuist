Mimic.copy(Slack.Captcha)
Mimic.copy(Slack.Invitations)
Mimic.copy(Slack.Notifier)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Slack.Repo, :manual)
