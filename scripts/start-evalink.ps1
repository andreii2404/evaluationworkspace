[CmdletBinding(DefaultParameterSetName = 'Preview')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Local')]
    [switch]$LocalSupabase,

    [Parameter(Mandatory, ParameterSetName = 'Hosted')]
    [ValidatePattern('^[a-z0-9]{20}$')]
    [string]$ProjectRef,

    [Parameter(ParameterSetName = 'Hosted')]
    [ValidatePattern('^sb_publishable_[a-zA-Z0-9_-]+$')]
    [string]$PublishableKey,

    [switch]$Build,
    [ValidateRange(1024, 65535)]
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $root
try {
    $settings = $null
    if ($LocalSupabase) {
        & npx --yes supabase@3.0.0 start
        if ($LASTEXITCODE -ne 0) { throw 'Supabase could not start. Check that Docker is running.' }
        & npx --yes supabase@3.0.0 migration up
        if ($LASTEXITCODE -ne 0) { throw 'The local database migration failed.' }

        $statusJson = & npx --yes supabase@3.0.0 status --output json
        if ($LASTEXITCODE -ne 0) { throw 'Could not read the local Supabase status.' }
        $status = ($statusJson -join [Environment]::NewLine) | ConvertFrom-Json
        $localUrl = $status.API_URL
        if (-not $localUrl) { $localUrl = $status.PROJECT_URL }
        $localKey = $status.PUBLISHABLE_KEY
        if (-not $localKey) { $localKey = $status.ANON_KEY }
        if (-not $localUrl -or -not $localKey) { throw 'The local public API configuration is missing.' }
        $settings = @{ SUPABASE_URL = $localUrl; SUPABASE_PUBLISHABLE_KEY = $localKey }
    }

    if ($ProjectRef) {
        if (-not $PublishableKey) {
            $keysJson = & npx --yes supabase@3.0.0 projects api-keys "--remote=$ProjectRef" --output json
            if ($LASTEXITCODE -ne 0) { throw 'Sign in with the Supabase CLI or provide the project publishable key.' }
            $keys = ($keysJson -join [Environment]::NewLine) | ConvertFrom-Json

            foreach ($entry in $keys) {
                $candidate = $entry.api_key
                if (-not $candidate) { $candidate = $entry.key }
                if (-not $entry.disabled -and $candidate -match '^sb_publishable_[a-zA-Z0-9_-]+$') {
                    $PublishableKey = $candidate
                    break
                }
            }
            if (-not $PublishableKey) { throw 'Pass the publishable key from the project Connect panel.' }
        }
        & npx --yes supabase@3.0.0 db push "--remote=$ProjectRef" --skip-vault --yes
        if ($LASTEXITCODE -ne 0) { throw 'The hosted database migration failed.' }
        $settings = @{
            SUPABASE_URL = "https://$ProjectRef.supabase.co"
            SUPABASE_PUBLISHABLE_KEY = $PublishableKey
        }
    }

    $flutterArgs = if ($Build) { @('build', 'web') }
        else { @('run', '-d', 'web-server', '--web-hostname', 'localhost', '--web-port', "$Port") }

    if ($settings) {
        foreach ($entry in $settings.GetEnumerator()) {
            $flutterArgs += "--dart-define=$($entry.Key)=$($entry.Value)"
        }
    }
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter did not finish successfully.' }
} finally {
    Pop-Location
}

