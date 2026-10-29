param([Parameter(Mandatory=$true)][ValidateSet('da-DK','en-US','zh-CN','zh-TW')][string]$Locale)
$ErrorActionPreference = 'Stop'
# Explicit user-requested OS setup. No reading/runtime code downloads OCR.
Add-WindowsCapability -Online -Name ('Language.OCR~~~' + $Locale + '~0.0.1.0') | Out-Null
