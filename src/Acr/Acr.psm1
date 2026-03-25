function Get-AcrVersion {
    [CmdletBinding()]
    [OutputType([semver])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Registry,

        [Parameter(Mandatory, Position = 1)]
        [string]$Repository
    )

    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true

    $azArgs = @(
        'acr'
        'repository'
        'show-tags'
        '--name'
        $Registry
        '--repository'
        $Repository
        '--orderby'
        'time_desc'
        '--top'
        '1'
        '--output'
        'json'
    )

    try {
        $azResult = az @azArgs
        $latestVersion = $azResult | ConvertFrom-Json

        if ($latestVersion.StartsWith('v')) {
            $latestVersion = $latestVersion.Substring(1)
        }

        return [semver]::Parse($latestVersion)
    }
    catch {
        throw "Failed to get ACR tags for repository ""$($Repository)"" in registry ""$($Registry)"": $_"
    }
}

function Get-AcrVersionBatch {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Registry,

        [Parameter(Mandatory, Position = 1, ValueFromRemainingArguments)]
        [string[]]$Repositories,

        [int]$ThrottleLimit = 4
    )

    $batchFunc = "${function:Get-AcrVersion}"

    $Repositories | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        ${function:Get-AcrVersion} = $using:batchFunc
        try {
            return [pscustomobject]@{
                Repository = $_
                Version    = Get-AcrVersion $using:Registry $_
            }
        }
        catch {
            # Ignore batch errors
        }
    }
}

function Get-AcrManifest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Registry,

        [Parameter(Mandatory, Position = 1)]
        [string]$Repository
    )

    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true

    $azArgs = @(
        'acr'
        'repository'
        'show'
        '--name'
        $Registry
        '--repository'
        $Repository
    )

    try {
        $azResult = az @azArgs
        return $azResult | ConvertFrom-Json -NoEnumerate
    }
    catch {
        throw "Failed to get ACR manifest for repository ""$($Repository)"" in registry ""$($Registry)"": $_"
    }
}

function Get-AcrManifestBatch {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Registry,

        [Parameter(Mandatory, Position = 1, ValueFromRemainingArguments)]
        [string[]]$Repositories,

        [int]$ThrottleLimit = 4
    )

    $batchFunc = "${function:Get-AcrManifest}"

    $Repositories | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        ${function:Get-AcrManifest} = $using:batchFunc
        try {
            Get-AcrManifest $using:Registry $_
        }
        catch {
            # Ignore batch errors
        }
    }
}