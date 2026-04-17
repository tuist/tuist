Mimic.copy(Slack.Captcha)
Mimic.copy(Slack.Invitations)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Slack.Repo, :manual)
