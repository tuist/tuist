defmodule Slack.Mailer do
  @moduledoc false
  use Swoosh.Mailer, otp_app: :slack

  # A scheduled provider change (`:ses_cutover`, set in runtime.exs) takes effect
  # at its instant on every replica, so customers' subprocessor notice period
  # decides the switch rather than a deploy.
  def deliver(email, config \\ []), do: super(email, Keyword.merge(cutover(), config))

  defp cutover do
    config = Application.get_env(:slack, __MODULE__, [])

    with {starts_at, overrides} <- config[:ses_cutover],
         true <- DateTime.compare(DateTime.utc_now(), starts_at) != :lt do
      overrides
    else
      _ -> []
    end
  end
end
