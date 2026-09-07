defmodule Tuist.Tests.Sanitizer do
  @moduledoc false

  @authorization_pattern ~r/(?i)(\bauthorization\b\s*(?:=|:)\s*)(?:bearer\s+)?(?:"[^"]*"|'[^']*'|\S+)/
  @named_credential_pattern ~r/(?i)(\b(?:[A-Za-z0-9_-]+[_-]token|api[_-]?key|password|secret)\b\s*(?:=|:)\s*)(?:"[^"]*"|'[^']*'|\S+)/
  @token_assignment_pattern ~r/(?i)(\btoken\b\s*=\s*)(?:"[^"]*"|'[^']*'|\S+)/
  @credential_flag_pattern ~r/(?i)(--(?:token|api[_-]?key|password|secret)(?:=|\s+))(?:"[^"]*"|'[^']*'|\S+)/
  @bearer_pattern ~r/(?i)(\bbearer\s+)[A-Za-z0-9._~+\/=:-]+/
  @url_credentials_pattern ~r/([A-Za-z][A-Za-z0-9+.-]*:\/\/)[^\s\/:@]+:[^\s@\/]+@/
  @local_path_pattern ~r{(?:~/[^\s'"]*|/(?:Users|home|private|var/folders|tmp)(?:/[^\s'"]*)?)(?=$|[\s'"])}
  @ansi_escape_pattern ~r/\e\[[0-?]*[ -\/]*[@-~]/

  def sanitize(message) when is_binary(message) do
    message
    |> then(&Regex.replace(@ansi_escape_pattern, &1, ""))
    |> then(&Regex.replace(@url_credentials_pattern, &1, "\\1<REDACTED>@"))
    |> then(&Regex.replace(@authorization_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@named_credential_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@token_assignment_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@credential_flag_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@bearer_pattern, &1, "\\1<REDACTED>"))
    |> then(&Regex.replace(@local_path_pattern, &1, "<LOCAL_PATH>"))
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  def sanitize(_), do: ""
end
