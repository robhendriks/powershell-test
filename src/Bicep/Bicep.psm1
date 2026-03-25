$BicepModuleMainFile = 'main.bicep'
$BicepModuleReadmeFile = 'README.md'
$BicepModuleChangelogFile = 'CHANGELOG.md'
$BicepModuleManifestFile = 'module.json'

function New-BicepModule {
    [CmdletBinding()]
    param(
        [ValidateScript({ Test-Path $_ -Type Container })]
        [string]$Path = $PWD,
        [string]$Name = '',
        [string]$Description = '',
        [string]$Author = '',
        [string]$Version = '0.0.1',
        [string[]]$Tags = @(),
        [switch]$DoNotPublish,
        [switch]$Force
    )

    # 1. Check if directory is empty
    $dirEmpty = (Get-ChildItem $Path).Length -eq 0
    if (!$Force -and !$dirEmpty) {
        throw 'Directory not empty, use -Force to overwrite'
    }

    # 2. Use fallback name when name is not provided
    $dir = Get-Item $Path
    if (!$Name) {
        $Name = $dir.BaseName
    }

    # 3. Construct manifest object
    $manifest = [ordered]@{
        name        = $Name
        description = $Description
        author      = $Author
        version     = $Version
        main        = $BicepModuleMainFile
        tags        = $Tags
    }

    if ($DoNotPublish) {
        $manifest.publish = $false
    }

    # 4. Save manifest as JSON
    $manifestJson = $manifest | ConvertTo-Json
    $manifestPath = Join-Path $Path $BicepModuleManifestFile

    $null = $manifestJson | Set-Content $manifestPath -Encoding utf8

    # 5. Create readme
    $readmePath = Join-Path $Path $BicepModuleReadmeFile
    $readmeContent = Markdown {
        Heading 1 $Name
    }
    $null = $readmeContent | Set-Content $readmePath -Encoding utf8 -NoNewline

    # 6. Create changelog
    $changelogPath = Join-Path $Path $BicepModuleChangelogFile
    $changelogContent = Markdown {
        Heading 1 'Changelog'
        Heading 2 $Version
        Heading 3 'Changes'
        Paragraph {
            List {
                'Initial module creation'
            }
        }
        Heading 3 'Breaking Changes'
        Paragraph {
            'No'
        }
    }
    $null = $changelogContent | Set-Content $changelogPath -Encoding utf8 -NoNewline

    # 8. Create main file
    $mainPath = Join-Path $Path $BicepModuleMainFile
    $mainContents = @'
metadata name = '{0}'
metadata description = '{1}'
metadata owner = '{2}'
'@ -f $Name, $Description, $Author
    $null = $mainContents | Set-Content $mainPath -Encoding utf8

    # 7. Import module (validate) and return instance
    return Import-BicepModule $manifestPath
}

function Import-BicepModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path
    )
    
    $manifest = Get-Content $Path -Raw -Encoding utf8 | ConvertFrom-Json
    $id = ($manifest.tags + $manifest.name) -join '/'
    
    $pathInfo = Get-Item $Path 
    $mainPath = Join-Path $pathInfo.Directory $manifest.Main
    $mainPathInfo = Get-Item $mainPath

    $publish = $manifest.publish -ne $false

    $obj = [PSCustomObject]@{
        PSTypeName  = 'Bicep.Module'
        Id          = $id
        Name        = $manifest.name
        Description = $manifest.description
        Author      = $manifest.author
        Main        = $mainPathInfo
        Version     = [semver]::Parse($manifest.version)
        Tags        = $manifest.tags
        Directory   = $pathInfo.Directory
        Path        = $pathInfo
        Publish     = $publish
    }

    $obj | Add-Member -Name 'ErrorDetails' -MemberType ScriptMethod -Value {
        @{ 
            title = $this.Id
            file  = $this.Path.FullName 
        }
    }

    return $obj
}

function Get-BicepModule {
    [CmdletBinding()]
    [OutputType('Bicep.Module')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path,

        [string]$Filter = '*'
    )

    Get-ChildItem -Path $Path -Recurse -File -Filter $BicepModuleManifestFile | ForEach-Object {
        $modulePath = $_
        try {
            Import-BicepModule $modulePath
        }
        catch {
            Write-GitHubActionCommand `
                -Name 'error' `
                -Message "Failed to load module: $_" `
                -Properties @{ file = $modulePath }
        }
    } | Where-Object { $_.Name -like $Filter } | Sort-Object -Property Id
}

function Get-BicepModuleIndexInMarkdown {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModules,

        [string]$Heading = 'Modules',

        [string]$AcrRegistry = 'iodigital',

        [string]$AcrRepositoryFormat = 'bicep/modules/{0}',

        [switch]$UseSha,

        [int]$ThrottleLimit = 8
    )

    $acrRepositories = $BicepModules | ForEach-Object { $AcrRepositoryFormat -f $_.Id }
    $versions = Get-AcrVersionBatch $AcrRegistry $acrRepositories -ThrottleLimit $ThrottleLimit
    $manifests = Get-AcrManifestBatch $AcrRegistry $acrRepositories -ThrottleLimit $ThrottleLimit

    Write-Host $versions
    Write-Host $manifests

    $table = $BicepModules | ForEach-Object {        
        $repository = $AcrRepositoryFormat -f $_.Id 

        $version = $versions | Where-Object { $_.Repository -eq $repository }
        $manifest = $manifests | Where-Object { $_.imageName -eq $repository }

        $links = @(
            Link 'Docs' (Get-BicepModuleGitHubUri $_ 'blob' $BicepModuleReadmeFile -UseSha:$UseSha)
            Link 'Changelog' (Get-BicepModuleGitHubUri $_ 'blob' $BicepModuleChangelogFile -UseSha:$UseSha)
        )

        $idText = Text $_.Id -Code
        $stateText = if ($version) { 'Published' } else { 'Draft' }
        $versionText = if ($version) { "v$($version.Version)" }  else { Text 'n/a' -Italic }
        
        $lastModifiedText = if ($manifest) { 
            $date = [datetime]::Parse($manifest.lastUpdateTime)
            $date.ToString()
        } 
        else { 
            Text 'n/a' -Italic
        }

        $linksText = $links -join ' '

        [PSCustomObject]@{
            'Id'            = $idText
            'State'         = $stateText
            'Version'       = $versionText
            'Last Modified' = $lastModifiedText
            'Links'         = $linksText
        }
    }

    return Markdown {
        Heading 1 $Heading
        Table $table
    }
}

function Publish-BicepModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule,

        [Parameter(Mandatory)]
        [string]$Registry,

        [switch]$Force
    )

    begin {
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $true

        Write-GitHubActionGroupStart -Name '🚀 Publish Modules'
    }

    process {
        if ($BicepModule.Publish -eq $false) {
            Write-GitHubActionCommand `
                -Name 'notice' `
                -Message "Skipping module '$($BicepModule.Id)' (publish=false)" `
                -Properties $BicepModule.ErrorDetails()

            return
        }

        $latestVersion = Get-BicepModuleLatestVersion $BicepModule $Registry
        $newVersion = $BicepModule.Version

        if (!$Force -and $newVersion -le $latestVersion) {
            throw "New version (v$($newVersion)) must be greater than current version (v$($latestVersion))"
        }

        Write-Host "$($PSStyle.Foreground.Cyan)publish " -NoNewline
        Write-Host "$($PSStyle.Foreground.White)$($BicepModule.Id) " -NoNewline
        Write-Host "$($PSStyle.Dim)v$($latestVersion)$($PSStyle.Reset) ➞ " -NoNewline
        Write-Host "$($PSStyle.Dim)v$($newVersion)$($PSStyle.Reset)"

        $azConfigArgs = @(
            'config'
            'set'
            'bicep.use_binary_from_path=false'
        )

        try {
            $null = az @azConfigArgs
        }
        catch {
            Write-GitHubActionCommand `
                -Name 'error' `
                -Message "$_" `
                -Properties $BicepModule.ErrorDetails()

            return
        }

        $file = $BicepModule.Main.FullName
        $target = 'br:{0}.azurecr.io/bicep/modules/{1}:v{2}' -f $Registry, $BicepModule.Id, $BicepModule.Version
        $docsUri = Get-BicepModuleGitHubUri $BicepModule 'blob' $BicepModuleReadmeFile -UseSha

        $azArgs = @(
            'bicep'
            'publish'
            '--file', $file
            '--target', $target
            '--documentation-uri', $docsUri
        )

        if ($Force) {
            $azArgs += '--force'
        }

        try {
            $null = az @azArgs
        }
        catch {
            Write-GitHubActionCommand `
                -Name 'error' `
                -Message "$_" `
                -Properties $BicepModule.ErrorDetails()

            return
        }

        $BicepModule
    }

    end {
        Write-GitHubActionGroupEnd
    }
}

function Select-BicepModuleId {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule
    )

    process {
        $BicepModule.Id
    }
}

function Select-BicepModuleModified {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule,

        [Parameter(Mandatory)]
        [string]$BaseRef,

        [Parameter(Mandatory)]
        [string]$HeadRef
    )

    begin {
        $changeSet = Compare-GitHubRef -BaseRef $BaseRef -HeadRef $HeadRef -AsFileArray |
            ConvertTo-GitHubActionAbsolutePath
    }

    process {
        $moduleFiles = $changeSet | Where-Object {
            $_.StartsWith($BicepModule.Directory.FullName)
        }

        if ($moduleFiles -match '\.(bicep|json)$') {
            return $BicepModule
        }
    }
}

function Write-BicepModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule,

        [string]$Action = 'load',

        [string]$ActionColor = $PSStyle.Foreground.Green,

        [string]$GroupName = '📦 Modules'
    )

    begin {
        Write-GitHubActionGroupStart -Name $GroupName
    }

    process {
        $segments = @(
            "$($ActionColor)$($Action)"
            "$($PSStyle.Foreground.White)$($BicepModule.Id)"
            "$($PSStyle.Dim)v$($BicepModule.Version)"
        )

        if ($BicepModule.Publish -eq $false) {
            $segments += "$($PSStyle.Foreground.Yellow)[publish disabled]"
        }

        $segments = $segments | ForEach-Object {
            "$($PSStyle.Reset)$_$($PSStyle.Reset)"
        }

        Write-Host $($segments -join ' ')
    }

    end {
        Write-GitHubActionGroupEnd
    }
}

function Get-BicepModuleGitHubUri {
    [CmdletBinding()]
    [OutputType([System.Uri])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('blob', 'tree', IgnoreCase = $false)]
        [string]$Type,

        [Parameter(Position = 2)]
        [string]$Path = '',

        [switch]$UseSha
    )

    begin {
        $workingDirectory = $Env:GITHUB_WORKSPACE ?? $(throw 'GITHUB_WORKSPACE is not set')
    }

    process {
        $modulePath = [System.IO.Path]::GetRelativePath($workingDirectory, $BicepModule.Directory.FullName)
        
        $uriSegments = $modulePath -split [IO.Path]::DirectorySeparatorChar
        if ($Path) {
            $uriSegments += $Path
        }
        $uriPath = $uriSegments -join '/'

        Get-GitHubUri -Path $uriPath -Type $Type -UseSha:$UseSha
    }
}

function Get-BicepModuleLatestVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule,

        [Parameter(Mandatory, Position = 1)]
        [string]$Registry
    )

    process {
        $repository = 'bicep/modules/{0}' -f $BicepModule.Id
        $latestVersion = [semver]::new(0, 0, 0)

        try {
            $latestVersion = Get-AcrVersion $Registry $repository
        }
        catch {
            Write-GitHubActionCommand `
                -Name 'warning' `
                -Message "$_" `
                -Properties $BicepModule.ErrorDetails()
        }

        $latestVersion
    }
}

function New-BicepModuleRule {
    [CmdletBinding()]
    [Alias('BicepModuleRule')]
    [OutputType('Bicep.ModuleRule')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('error', 'warning', 'notice')]
        [string]$Severity,

        [Parameter(Mandatory, Position = 2)]
        [scriptblock]$Script
    )

    return [PSCustomObject]@{
        PSTypeName = 'Bicep.ModuleRule'
        Name       = $Name
        Severity   = $Severity
        Script     = $Script
    }
}

$BicepModuleRuleRequiredFiles = BicepModuleRule 'required_files' 'warning' {
    $files = @(
        $BicepModuleReadmeFile
        $BicepModuleChangelogFile
    )
        
    foreach ($file in $files) {
        $path = Join-Path $_.Directory $file
        if (!(Test-Path $path)) {
            return "Missing file $file"
        }
    }
}

$BicepModuleRuleChangelogContent = BicepModuleRule 'changelog_content' 'warning' {
    $changelogPath = Join-Path $_.Directory $BicepModuleChangelogFile
    $changelog = Get-Content -Raw $changelogPath -Encoding utf8

    if ($changelog -notmatch "## $($_.Version)") {
        return "Changelog out of date, please add a level 2 heading for version $($_.Version)"
    }
}

$BicepModuleDefaultRules = @(
    $BicepModuleRuleRequiredFiles
    $BicepModuleRuleChangelogContent
)

function Get-BicepModuleReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('Bicep.Module')]
        [PSCustomObject]$BicepModule,

        [PSCustomObject[]]$Rules = $BicepModuleDefaultRules
    )

    begin {
        $reportItems = @()
    }

    process {
        foreach ($rule in $Rules) {
            try {
                $results = @(
                    $rule.Script.InvokeWithContext(
                        @{},
                        [psvariable]::new('_', $BicepModule),
                        @()
                    )
                )

                foreach ($result in $results) {
                    if ($result -is [string]) {
                        $reportItems += [PSCustomObject]@{
                            Severity = $rule.Severity
                            Message  = $result
                            Details  = $BicepModule.ErrorDetails()
                        }
                    }
                }       
            }
            catch {
                $reportItems += [PSCustomObject]@{
                    Severity = 'error'
                    Message  = "Failed to execute rule $($rule.Name): $_"
                    Details  = $BicepModule.ErrorDetails()
                }
            }
        }
    }

    end {
        $reportItems
    }
}