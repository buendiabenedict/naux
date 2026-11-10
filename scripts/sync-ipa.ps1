param(
  [string]$Repo = "buendiabenedict/naux",
  [string]$Workflow = "iOS",
  [string]$Artifact = "naux-unsigned-ipa",
  [string]$Dest = "C:\Users\buendia\Downloads\naux-unsigned.ipa",
  [int]$IntervalSeconds = 60
)

$ErrorActionPreference = "Continue"
$stateFile = Join-Path $PSScriptRoot ".last-ipa-run"
$lastId = ""
if (Test-Path $stateFile) { $lastId = (Get-Content $stateFile -Raw).Trim() }

function Sync-Latest {
  try {
    $json = gh run list --repo $Repo --workflow $Workflow --status success --limit 1 --json databaseId 2>$null
    if (-not $json) { return }
    $runs = $json | ConvertFrom-Json
    if (-not $runs -or $runs.Count -eq 0) { return }
    $id = [string]$runs[0].databaseId
    if (-not $id -or $id -eq $script:lastId) { return }

    $tmp = Join-Path $env:TEMP ("naux-ipa-" + $id)
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null

    $dl = gh run download $id --repo $Repo -n $Artifact -D $tmp 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Output "$(Get-Date -Format o) download-failed run=$id $dl"
      Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
      return
    }

    $ipa = Get-ChildItem -Path $tmp -Recurse -Filter "*.ipa" | Select-Object -First 1
    if (-not $ipa) {
      Write-Output "$(Get-Date -Format o) no-ipa run=$id"
      Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
      return
    }

    Copy-Item -LiteralPath $ipa.FullName -Destination $Dest -Force
    $script:lastId = $id
    Set-Content -Path $stateFile -Value $id -NoNewline
    $info = Get-Item -LiteralPath $Dest
    Write-Output "$(Get-Date -Format o) synced run=$id -> $Dest ($($info.Length) bytes)"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  } catch {
    Write-Output "$(Get-Date -Format o) error $($_.Exception.Message)"
  }
}

Write-Output "$(Get-Date -Format o) watcher-start repo=$Repo workflow=$Workflow dest=$Dest interval=${IntervalSeconds}s"
while ($true) {
  Sync-Latest
  Start-Sleep -Seconds $IntervalSeconds
}
