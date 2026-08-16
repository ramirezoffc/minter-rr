[CmdletBinding()]
param(
    [string]$BinaryPath,
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root "crates\minter-desktop\src-tauri\tauri.conf.json"
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$binaryName = "$($config.mainBinaryName).exe"

if (-not $BinaryPath) {
    $candidates = @(
        (Join-Path $root "target\x86_64-pc-windows-msvc\release\$binaryName"),
        (Join-Path $root "target\release\$binaryName"),
        (Join-Path $root "crates\minter-desktop\src-tauri\target\x86_64-pc-windows-msvc\release\$binaryName"),
        (Join-Path $root "crates\minter-desktop\src-tauri\target\release\$binaryName")
    )
    $BinaryPath = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

if (-not $BinaryPath -or -not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
    throw "$binaryName was not found. Run 'npm run build:windows' first or pass -BinaryPath."
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root "dist\windows"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$archiveName = "$($config.productName)_$($config.version)_x64-portable.zip"
$archivePath = Join-Path $OutputDirectory $archiveName
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -Force -LiteralPath $archivePath
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::Open(
    $archivePath,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    $entry = $archive.CreateEntry(
        $binaryName,
        [System.IO.Compression.CompressionLevel]::Optimal
    )
    $entry.LastWriteTime = [DateTimeOffset]::Parse("1980-01-01T00:00:00Z")

    $source = [System.IO.File]::OpenRead($BinaryPath)
    $destination = $entry.Open()
    try {
        $source.CopyTo($destination)
    } finally {
        $destination.Dispose()
        $source.Dispose()
    }
} finally {
    $archive.Dispose()
}

$readArchive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $members = @($readArchive.Entries | ForEach-Object { $_.FullName })
    if ($members.Count -ne 1 -or $members[0] -ne $binaryName) {
        throw "Portable archive must contain only $binaryName; found: $($members -join ', ')"
    }
} finally {
    $readArchive.Dispose()
}

Write-Host "Verified portable archive: $archivePath"
Write-Host "Archive member: $binaryName"
