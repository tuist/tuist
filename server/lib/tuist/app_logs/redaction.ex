defmodule Tuist.AppLogs.Redaction do
  @moduledoc """
  Removes credentials and personal data from log lines uploaded by the Tuist app.

  The app applies the same rules before it stores or uploads a line. The server
  applies them again so a line from an older or modified client cannot reach Loki
  unredacted.
  """

  @redacted "[redacted]"

  def redact(value) when is_binary(value) do
    Enum.reduce(rules(), value, fn {pattern, replacement}, output ->
      Regex.replace(pattern, output, replacement)
    end)
  end

  defp rules do
    [
      {~r/(?i)(bearer\s+)[A-Za-z0-9._~+\-\/]+=*/, "\\1#{@redacted}"},
      {~r/(?i)\b(access_token|refresh_token|id_token|authorization|password|api[_-]?key)=([^\s&,]+)/, "\\1=#{@redacted}"},
      {~r/(?i)(["']?[A-Za-z0-9_.-]*(?:authorization|cookie|token|secret|password|api[_-]?key)[A-Za-z0-9_.-]*["']?\s*:\s*["']?)([^"',\]\s&]+)/,
       "\\1#{@redacted}"},
      {~r/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/, @redacted},
      {~r/\btuist_[A-Za-z0-9-]+_[A-Za-z0-9]{16,}/, @redacted},
      {~r/(?i)\b(https?:\/\/[^\s?#"'<>]+)\?[^\s"'<>]*/, "\\1?#{@redacted}"},
      {~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, @redacted},
      {~r/(\/Users|\/home)\/[^\/\s"']+/, "\\1/#{@redacted}"}
    ]
  end
end
