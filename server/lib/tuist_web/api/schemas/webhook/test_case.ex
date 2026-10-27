defmodule TuistWeb.API.Schemas.Webhook.TestCase do
  @moduledoc """
  The `object` payload shared by every `test_case.*` webhook event.

  Mirrors `Tuist.Webhooks.Dispatcher.test_case_snapshot/1` — keep both in
  sync when adding fields.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookTestCase",
    description:
      "Snapshot of the test case that triggered the webhook event. Identified by `id`; the surrounding event envelope tells you which transition produced the snapshot.",
    type: :object,
    required: [:id, :name, :module_name, :suite_name, :project_id, :is_flaky, :state],
    properties: %{
      id: %Schema{type: :string, description: "Stable identifier of the test case."},
      name: %Schema{type: :string, description: "Test case name (the method name)."},
      module_name: %Schema{type: :string, description: "Name of the module the test case belongs to."},
      suite_name: %Schema{type: :string, description: "Name of the test suite the test case belongs to."},
      project_id: %Schema{type: :integer, description: "Identifier of the project the test case belongs to."},
      is_flaky: %Schema{
        type: :boolean,
        description: "True when Tuist (or an operator) has flagged the test case as flaky."
      },
      state: %Schema{
        type: :string,
        enum: ["enabled", "muted", "skipped"],
        description: "Current lifecycle state of the test case."
      },
      last_status: %Schema{
        type: :string,
        nullable: true,
        enum: ["success", "failure", "skipped"],
        description: "Result of the most recent run, when one exists."
      },
      last_ran_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "ISO-8601 timestamp of the most recent run, when one exists."
      }
    }
  })
end
