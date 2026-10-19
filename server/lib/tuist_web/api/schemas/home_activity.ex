defmodule TuistWeb.API.Schemas.HomeActivityItem do
  @moduledoc false
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "HomeActivityItem",
    type: :object,
    properties: %{
      id: %Schema{type: :string},
      title: %Schema{type: :string},
      subtitle: %Schema{type: :string},
      occurred_at: %Schema{
        type: :integer,
        format: :int64,
        description: "Run timestamp (report time for legacy sources) or flaky-state transition, in Unix seconds."
      },
      url: %Schema{
        type: :string,
        description: "Deployment-relative project dashboard path; append to the complete server base URL."
      }
    },
    required: [:id, :title, :subtitle, :occurred_at, :url]
  })
end

defmodule TuistWeb.API.Schemas.HomeActivity do
  @moduledoc false
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.HomeActivityItem

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "HomeActivity",
    type: :object,
    properties: %{
      items: %Schema{type: :array, maxItems: 3, items: HomeActivityItem}
    },
    required: [:items]
  })
end
