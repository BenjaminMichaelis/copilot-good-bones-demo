param(
    [string[]]$Targets,
    [switch]$DiscoverFromCurrentDirectory,
    [switch]$RestoreTargets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Targets -or $Targets.Count -eq 0) {
    if (-not $DiscoverFromCurrentDirectory) {
        throw 'Specify -Targets or pass -DiscoverFromCurrentDirectory.'
    }

    $solutionFile = Get-ChildItem -Path . -File | Where-Object { $_.Extension -eq '.sln' -or $_.Extension -eq '.slnx' } | Select-Object -First 1
    if ($solutionFile) {
        $Targets = @($solutionFile.FullName)
    } else {
        $Targets = @(Get-ChildItem -Path . -Recurse -Filter *.csproj | Select-Object -ExpandProperty FullName)
    }
}

if (-not $Targets -or $Targets.Count -eq 0) {
    throw 'No solution or project files found for format validation.'
}

foreach ($target in $Targets) {
    if ($RestoreTargets) {
        dotnet restore $target
    }

    dotnet format whitespace $target --verify-no-changes --no-restore
    dotnet format style $target --verify-no-changes --no-restore --severity info
    dotnet format analyzers $target --verify-no-changes --no-restore --severity info
}