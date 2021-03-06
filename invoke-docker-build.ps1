[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0)]
    [string]$ImageType = "alpine",
    [Parameter(Mandatory=$false,Position=1)]
    [string]$Version
)

if (-not $PSBoundParameters.ContainsKey("ErrorAction")) { $ErrorActionPreference = "Stop" }
if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }

Import-Module -Name "$PSScriptRoot\docker\docker-include.psm1" -Scope Local -Force

$ImageType = $ImageType.ToLower()
$SafeguardDockerFile = (Get-SafeguardDockerFile $ImageType)

Write-Host $SafeguardDockerFile

if (-not (Get-Command "docker" -EA SilentlyContinue))
{
    throw "Unable to find docker command. Is docker installed on this machine?"
}

if (-not (Get-Command "dotnet" -EA SilentlyContinue))
{
    throw "This script requires dotnet cli for building the service"
}

if ($Version)
{
    $Version = "$Version-"
}
$ImageName = "oneidentity/safeguard-devops:$Version$ImageType"

try
{
    Push-Location $PSScriptRoot
    Write-Host "Cleaning up all build directories ..."
    (Get-ChildItem -Recurse -Filter obj -EA SilentlyContinue) | ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
    (Get-ChildItem -Recurse -Filter bin -EA SilentlyContinue) | ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
    Write-Host "Building for full-size Linux distros ..."
    dotnet publish -v d -r linux-x64 -c Release --self-contained --force /p:PublishSingleFile=true SafeguardDevOpsService/SafeguardDevOpsService.csproj
    Write-Host "Building for tiny Linux distros ..."
    dotnet publish -v d -r linux-musl-x64 -c Release --self-contained --force /p:PublishSingleFile=true SafeguardDevOpsService/SafeguardDevOpsService.csproj

    if (Invoke-Expression "docker images -q $ImageName")
    {
        Write-Host "Cleaning up the old image: $ImageName ..."
        & docker rmi --force "$ImageName"
    }

    Write-Host "Building a new image: $ImageName ..."
    & docker build --no-cache -t "$ImageName" -f "$SafeguardDockerFile" "$PSScriptRoot"
}
finally
{
    Pop-Location
}