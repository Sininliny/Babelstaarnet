[CmdletBinding()]
param([string]$OutputDirectory, [ValidateSet('Debug','Release')][string]$Configuration='Release')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'Shared\BabelPolicy'
$build=Join-Path $root 'build\shared-policy'
cmake -S $source -B $build -A x64
if ($LASTEXITCODE -ne 0) { throw 'Shared policy configuration failed. Install Visual Studio C++ build tools and CMake.' }
cmake --build $build --config $Configuration
if ($LASTEXITCODE -ne 0) { throw 'Shared policy build failed.' }
if ($OutputDirectory) {
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $build "$Configuration\babel_policy.dll") -Destination $OutputDirectory -Force
}
