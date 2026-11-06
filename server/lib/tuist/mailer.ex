defmodule Tuist.Mailer do
  @moduledoc false
  use Bamboo.Mailer, otp_app: :tuist

  defoverridable deliver_now: 1, deliver_now: 2, deliver_now!: 1, deliver_now!: 2

  # A scheduled provider change (`:ses_cutover`, set in runtime.exs) takes effect
  # at its instant on every replica, so customers' subprocessor notice period
  # decides the switch rather than a deploy.
  def deliver_now(email, opts \\ []), do: super(email, cutover(opts))
  def deliver_now!(email, opts \\ []), do: super(email, cutover(opts))

  defp cutover(opts) do
    config = Application.get_env(:tuist, __MODULE__, [])

    with {starts_at, overrides} <- config[:ses_cutover],
         true <- DateTime.compare(DateTime.utc_now(), starts_at) != :lt do
      Keyword.update(opts, :config, overrides, &Map.merge(overrides, &1))
    else
      _ -> opts
    end
  end
end
