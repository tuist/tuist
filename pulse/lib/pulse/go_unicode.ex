defmodule Pulse.GoUnicode do
  @moduledoc false

  # Go 1.27's Unicode 17 IsPrint. Add its new printable scalars to PCRE2's
  # Unicode 16 categories; neither private use nor other spaces print.
  # Compared exhaustively against Go 1.27.3 strconv.IsPrint; provenance is in
  # test/fixtures/logs/loki-upstream/README.md#numeric-diagnostic-continuation.
  @printable Regex.compile!(
               "\\A[\\p{L}\\p{M}\\p{N}\\p{P}\\p{S} " <>
                 "\\x{88F}\\x{C5C}\\x{CDC}\\x{1ACF}-\\x{1ADD}\\x{1AE0}-\\x{1AEB}\\x{20C1}\\x{2B96}" <>
                 "\\x{A7CE}-\\x{A7CF}\\x{A7D2}\\x{A7D4}\\x{A7F1}\\x{FBC3}-\\x{FBD2}" <>
                 "\\x{FD90}-\\x{FD91}\\x{FDC8}-\\x{FDCE}\\x{10940}-\\x{10959}\\x{10EC5}-\\x{10EC7}" <>
                 "\\x{10ED0}-\\x{10ED8}\\x{10EFA}-\\x{10EFB}\\x{11B60}-\\x{11B67}\\x{11DB0}-\\x{11DDB}" <>
                 "\\x{11DE0}-\\x{11DE9}\\x{16EA0}-\\x{16EB8}\\x{16EBB}-\\x{16ED3}\\x{16FF2}-\\x{16FF6}" <>
                 "\\x{187F8}-\\x{187FF}\\x{18D09}-\\x{18D1E}\\x{18D80}-\\x{18DF2}\\x{1CCFA}-\\x{1CCFC}" <>
                 "\\x{1CEBA}-\\x{1CED0}\\x{1CEE0}-\\x{1CEF0}\\x{1E6C0}-\\x{1E6DE}\\x{1E6E0}-\\x{1E6F5}" <>
                 "\\x{1E6FE}-\\x{1E6FF}\\x{1F6D8}\\x{1F777}-\\x{1F77A}\\x{1F8D0}-\\x{1F8D8}" <>
                 "\\x{1FA54}-\\x{1FA57}\\x{1FA8A}\\x{1FA8E}\\x{1FAC8}\\x{1FACD}\\x{1FAEA}\\x{1FAEF}" <>
                 "\\x{1FBFA}\\x{2B73A}-\\x{2B73F}\\x{2CEA2}-\\x{2CEAD}\\x{323B0}-\\x{33479}]\\z",
               "u"
             )

  def printable?(scalar), do: Regex.match?(@printable, scalar)

  def quote(text), do: IO.iodata_to_binary([?", quote_bytes(text), ?"])

  defp quote_bytes(<<>>), do: []
  defp quote_bytes(<<char, rest::binary>>) when char in [?", ?\\], do: [?\\, char | quote_bytes(rest)]
  defp quote_bytes(<<char, rest::binary>>) when char in 0x20..0x7E, do: [char | quote_bytes(rest)]

  defp quote_bytes(<<char, rest::binary>>) when char in [7, 8, 9, 10, 11, 12, 13] do
    escape = %{7 => ?a, 8 => ?b, 9 => ?t, 10 => ?n, 11 => ?v, 12 => ?f, 13 => ?r}
    [?\\, Map.fetch!(escape, char) | quote_bytes(rest)]
  end

  defp quote_bytes(<<char::utf8, rest::binary>>) do
    escaped =
      cond do
        char < 0x20 or char == 0x7F -> hex_escape(char, "x", 2)
        printable?(<<char::utf8>>) -> <<char::utf8>>
        char < 0x10000 -> hex_escape(char, "u", 4)
        true -> hex_escape(char, "U", 8)
      end

    [escaped | quote_bytes(rest)]
  end

  defp quote_bytes(<<byte, rest::binary>>), do: [hex_escape(byte, "x", 2) | quote_bytes(rest)]

  defp hex_escape(char, prefix, width) do
    digits = char |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
    ["\\", prefix, digits]
  end
end
