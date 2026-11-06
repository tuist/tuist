defmodule TuistWeb.API.BazelPublishingController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Plugs.ReportPublishingPlug

  plug(ReportPublishingPlug, {:preflight, :bazel})
  plug(TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug)
  plug(ReportPublishingPlug, :bazel)

  tags ["Bazel"]

  operation(:create,
    summary: "Authorize a network-trusted Bazel build-event stream, without cache access.",
    operation_id: "createBazelPublishingSession",
    parameters: [
      account_handle: [in: :path, type: :string, required: true],
      project_handle: [in: :path, type: :string, required: true]
    ],
    request_body: {"Publishing request", "application/json", %Schema{type: :object}},
    responses: %{
      ok:
        {"Publishing policy", "application/json",
         %Schema{type: :object, properties: %{network_trusted: %Schema{type: :boolean}}, required: [:network_trusted]}},
      unauthorized: {"Invalid credentials", "application/json", Error},
      forbidden: {"Publishing disabled", "application/json", Error},
      too_many_requests: {"Publishing quota exceeded", "application/json", Error},
      service_unavailable: {"Publishing quota unavailable", "application/json", Error}
    }
  )

  def create(conn, _params) do
    json(conn, %{network_trusted: ReportPublishingPlug.network_publisher?(conn)})
  end
end
