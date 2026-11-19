defmodule Atlas.Engineering.Errors.FingerprintTest do
  use ExUnit.Case, async: true

  alias Atlas.Engineering.Errors.Fingerprint
  alias Atlas.Engineering.Errors.SentryEvent

  # Pulse groups errors with a port of this module (its `sentry_errors`
  # pipeline), checked against the same cases by
  # infra/helm/pulse/test-sentry-errors.mjs. When grouping changes here,
  # change the pipeline and these expected fingerprints together.
  @cases Path.expand("../../../../../infra/helm/pulse/sentry-errors-cases.json", __DIR__)
  @external_resource @cases

  for %{"name" => name, "fingerprint" => fingerprint, "level" => level, "event" => event} <-
        @cases |> File.read!() |> Jason.decode!() do
    test "groups #{name} like Pulse" do
      event = SentryEvent.parse(unquote(Macro.escape(event)))

      assert Fingerprint.compute(event) == unquote(fingerprint)
      assert event.level == unquote(level)
    end
  end
end
