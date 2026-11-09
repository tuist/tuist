param([Parameter(Mandatory=$true)][string]$Path,
      [Parameter(Mandatory=$true)][string]$Thumbprint)
$ErrorActionPreference = 'Stop'
$signature = Get-AuthenticodeSignature -LiteralPath $Path
if ($signature.Status -ne 'Valid' -or
    $signature.SignerCertificate.Thumbprint -ne $Thumbprint -or
    $null -eq $signature.TimeStamperCertificate) {
    throw 'Final installer must have valid timestamped Authenticode from the approved certificate'
}
