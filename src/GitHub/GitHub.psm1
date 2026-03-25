function ConvertTo-EscapedPropertyString {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]$String = ''
    )

    $String `
        -replace '%', '%25' `
        -replace '\r', '%0D' `
        -replace '\n', '%0A' `
        -replace ':', '%3A' `
        -replace ',', '%2C'
}

function ConvertTo-EscapedString {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]$String = ''
    )

    $String `
        -replace '%', '%25' `
        -replace '\r', '%0D' `
        -replace '\n', '%0A'
}

function ConvertTo-KeyValueString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [hashtable]$Value
    )

    $values = $Value.GetEnumerator() | ForEach-Object {
        '{0}={1}' -f $_.Key, (ConvertTo-EscapedPropertyString -String $_.Value)
    }

    $values -join ','
}

function New-GitHubContext {
    $props = [ordered] @{
        BaseRef    = 'GITHUB_BASE_REF'
        HeadRef    = 'GITHUB_HEAD_REF'
        RefName    = 'GITHUB_REF_NAME'
        Repository = 'GITHUB_REPOSITORY'
        ServerUrl  = 'GITHUB_SERVER_URL'
        Sha        = 'GITHUB_SHA'
        Workspace  = 'GITHUB_WORKSPACE'
    }

    $obj = [pscustomobject]@{ PSTypeName = 'GitHub.Context' }

    $props.GetEnumerator() | ForEach-Object {
        $getterSrc = '$Env:{0} ?? $(throw ''{1} is not set'')' -f $_.Value, $_.Value
        $getter = [scriptblock]::Create($getterSrc)
        $obj | Add-Member -MemberType ScriptMethod -Name $_.Key -Value $getter
    }
    
    return $obj
}

function Get-GitHubContext {
    [CmdletBinding()]
    [OutputType('GitHub.Context')]
    param(
        [switch]$NoCache
    )

    if (!$NoCache -and $Script:Context) {
        return $Script:Context
    }

    $Script:Context = New-GitHubContext
    return $Script:Context
}

function Compare-GitHubRef {
    [CmdletBinding()]
    param (
        [string]$Owner = '{owner}',

        [string]$Repo = '{repo}',

        [Parameter(Mandatory)]
        [string]$BaseRef,

        [Parameter(Mandatory)]
        [string]$HeadRef,

        [switch]$AsFileArray
    )

    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true

    $ghUrl = 'repos/{0}/{1}/compare/{2}...{3}' -f $Owner, $Repo, $BaseRef, $HeadRef
    $ghArgs = @('api', $ghUrl)

    if ($AsFileArray) {
        $ghArgs += '--jq', '.files | map(.filename)'
    }

    try {
        $apiResponse = gh @ghArgs
        $apiResponse | ConvertFrom-Json
    }
    catch {
        throw "Failed to compare git refs: $_"
    }
}

function ConvertTo-GitHubActionAbsolutePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    begin {
        $workspace = $Env:GITHUB_WORKSPACE ?? $(throw 'GITHUB_WORKSPACE is not set')
    }

    process {
        Join-Path $workspace $Path
    }
}

function Get-GitHubRepoUri {
    [CmdletBinding()]
    [OutputType([System.Uri])]
    param (
        [switch]$IncludeTrailingSlash
    )

    $server = $Env:GITHUB_SERVER_URL ?? $(throw 'GITHUB_SERVER_URL is not set')
    $repository = $Env:GITHUB_REPOSITORY ?? $(throw 'GITHUB_REPOSITORY is not set')

    $suffix = if ($IncludeTrailingSlash) { '/' } else { '' }
    $baseUri = [System.Uri]::new($server)

    [System.Uri]::new($baseUri, "$($repository)$($suffix)")
}

function Get-GitHubUri {
    [CmdletBinding()]
    [OutputType([System.Uri])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('blob', 'tree', IgnoreCase = $false)]
        [string]$Type,

        [switch]$UseSha
    )

    $repoUri = Get-GitHubRepoUri -IncludeTrailingSlash

    $ref = if ($UseSha) {
        $Env:GITHUB_SHA ?? $(throw 'GITHUB_SHA is not set')
    }
    else {
        $Env:GITHUB_REF_NAME ?? $(throw 'GITHUB_REF_NAME is not set')
    }

    [System.Uri]::new($repoUri, ('{0}/{1}/{2}' -f $Type, $ref, $Path))
}

function Write-GitHubActionCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Message = '',

        [Parameter(Position = 2)]
        [hashtable]$Properties = @{}
    )

    $propertyString = ''

    if ($Properties.Count -gt 0) {
        $propertyString = ' ' + (ConvertTo-KeyValueString -Value $Properties)
    }

    Write-Host ('::{0}{1}::{2}' -f $Name, $propertyString, (ConvertTo-EscapedString -String $Message))
}

function Write-GitHubActionGroupEnd {
    Write-GitHubActionCommand -Name 'endgroup'
}

function Write-GitHubActionGroupStart {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    Write-GitHubActionCommand -Name 'group' -Message $Name
}

function Write-GitHubActionOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Key,

        [Parameter(Mandatory, Position = 1)]
        [string]$Value
    )

    ('{0}={1}' -f $Key, $Value) >> $Env:GITHUB_OUTPUT
}

function Write-GitHubActionSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Value
    )

    $Value >> $Env:GITHUB_STEP_SUMMARY
}