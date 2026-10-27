defmodule Tuist.MCP.Components.Tools.ListBuildEntities do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, action: :index
end

defmodule Tuist.MCP.Components.Tools.GetBuildEntity do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, action: :show
end

defmodule Tuist.MCP.Components.Tools.ListBuildEntityHistory do
  @moduledoc false
  use Tuist.MCP.Components.Tools.BuildEntityTool, action: :history
end
