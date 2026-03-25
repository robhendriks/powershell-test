function Get-MarkdownText {
    [CmdletBinding()]
    [Alias('Text')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,

        [switch]$Bold,
        [switch]$Italic,
        [switch]$Strikethrough,
        [switch]$Code
    )

    $modifiers = @()

    if ($Bold) {
        $modifiers += '**'
    }

    if ($Italic) {
        $modifiers += '_'
    }

    if ($Strikethrough) {
        $modifiers += '~~'
    }

    if ($Code) {
        $modifiers += '`'
    }

    $prefix = $modifiers -join ''
    [array]::Reverse($modifiers)
    $suffix = $modifiers -join ''

    return "$prefix$Text$suffix"
}

function Get-MarkdownLink {
    [CmdletBinding()]
    [Alias('Link')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text,

        [Parameter(Mandatory, Position = 1)]
        [string]$Url,

        [Parameter(Position = 2)]
        [string]$Title
    )

    if ($Title) {
        return '[{0}]({1} "{2}")' -f $Text, $Url, $Title
    }

    return '[{0}]({1})' -f $Text, $Url
}

function Get-MarkdownTable {
    [CmdletBinding()]
    [Alias('Table')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [pscustomobject]$InputObject,

        [Parameter(Position = 1)]
        [scriptblock]$RenderIfEmpty
    )

    if ($InputObject -isnot [array]) {
        $InputObject = @($InputObject)
    }

    if ($InputObject.Count -eq 0) {
        if ($RenderIfEmpty) {
            return $RenderIfEmpty.Invoke()
        }
        return
    }

    $headers = $InputObject[0].PSObject.Properties.Name

    # Return headers to pipeline
    "| $($headers -join ' | ') |"

    # Return separators to pipeline
    "| $(@($headers | ForEach-Object { '---' }) -join ' | ') |"

    foreach ($row in $InputObject) {
        $values = $headers | ForEach-Object { $row.$_ }
        "| $($values -join ' | ') |"
    }
}

function New-MarkdownDocument {
    [CmdletBinding()]
    [Alias('Markdown')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$Render
    )

    $lines = $render.Invoke()

    return $lines -join "`n"
}

function New-MarkdownHeading {
    [CmdletBinding()]
    [Alias('Heading')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Level,

        [Parameter(Mandatory, Position = 1)]
        [string]$Text
    )

    # Return heading to pipeline
    "$('#' * $Level) $Text"

    # Return new-line to pipeline
    ''
}

function New-MarkdownParagraph {
    [CmdletBinding()]
    [Alias('Paragraph')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$Render
    )

    $Render.Invoke() | Out-String
}

function New-MarkdownQuoteBlock {
    [CmdletBinding()]
    [Alias('QuoteBlock')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$Render
    )

    # Capture quote block contents
    $captured = @($Render.Invoke())

    foreach ($capture in $captured) {
        # Render captured content to pipeline with quote prefix
        '> ' + ($capture | Out-String -NoNewline)
    }
}

function New-MarkdownCodeBlock {
    [CmdletBinding()]
    [Alias('CodeBlock')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Syntax,
        
        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$Render
    )

    # Capture code block contents
    $source = $Render.Invoke() | Out-String -NoNewline

    # Render code block
    @'
```{0}
{1}
```
'@ -f $Syntax, $source
}

function New-MarkdownList {
    [CmdletBinding()]
    [Alias('List')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$Content
    )

    $script:ListDepth = if ($null -eq $script:ListDepth) { 0 } else { $script:ListDepth }
    
    $currentDepth = $script:ListDepth
    $indent = '  ' * $currentDepth
    
    $script:ListDepth++

    $lines = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($item in (& $Content)) {
            if ($item -is [System.Collections.Generic.List[string]]) {
                $lines.AddRange($item)
            }
            else {
                $lines.Add("${indent}- $item")
            }
        }
    }
    finally {
        $script:ListDepth--
        if ($script:ListDepth -eq 0) { $script:ListDepth = $null }
    }

    if ($currentDepth -eq 0) {
        $lines
    }
    else {
        , $lines
    }
}