defmodule Pulse.Test.LokiPipelineFixture do
  @moduledoc "Public LogQL spellings of the pinned pipeline-test stage constructors, not upstream query oracles."

  def query("TestNoopPipeline", _), do: "{}"

  def query("TestPipeline", _), do: ~s'{} | foo="bar" | line_format "lbs {{.foo}}"'

  def query("TestPipelineWithStructuredMetadata", _),
    do: ~s'{} | foo="bar" | user="bob" | line_format "lbs {{.foo}} {{.user}}"'

  def query("TestDropLabelsPipeline", 0), do: "{} | logfmt --strict | json | drop __error__, __error_details__"

  def query("TestDropLabelsPipeline", 1),
    do: ~s'{} | logfmt --strict | json | drop __error__="LogfmtParserErr", status="200", app'

  # Loki's empty keep constructor is an identity stage. There is no public
  # empty-keep grammar; omit the identity rather than inventing that syntax or
  # claiming parity with a manually constructed empty Pulse AST.Keep.
  def query("TestKeepLabelsPipeline", 0), do: "{} | logfmt"
  def query("TestKeepLabelsPipeline", 1), do: "{} | logfmt | keep level"
  def query("TestKeepLabelsPipeline", 2), do: ~s'{} | logfmt | keep level="info"'
end
