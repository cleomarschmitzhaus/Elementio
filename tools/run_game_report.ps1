# Roda o jogo por N segundos, captura toda a saida do engine e resume os erros.
# Tambem le o relatorio do autodebug (docs/diagnostico/runtime_report.txt).
# Uso:  tools\run_game_report.ps1 -Seconds 10
param(
    [int]$Seconds = 10,
    [string]$Godot = "C:\Users\roger\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe",
    [string]$Project = (Join-Path $PSScriptRoot "..")
)

if (-not (Test-Path $Godot)) {
    Write-Error "Godot nao encontrado em: $Godot"
    exit 2
}

$diag = Join-Path $Project "docs/diagnostico"
New-Item -ItemType Directory -Force -Path $diag | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outLog = Join-Path $diag "execucao_$stamp.out.log"
$errLog = Join-Path $diag "execucao_$stamp.err.log"

Write-Host "Rodando o jogo por $Seconds s..." -ForegroundColor Cyan
$p = Start-Process -FilePath $Godot -ArgumentList @("--path", "`"$Project`"") `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
Start-Sleep -Seconds $Seconds
if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2 }
if (-not $p.HasExited) { $p.Kill() }
Start-Sleep -Seconds 1

$all = @()
if (Test-Path $outLog) { $all += Get-Content $outLog }
if (Test-Path $errLog) { $all += Get-Content $errLog }

$errors   = $all | Select-String -CaseSensitive -Pattern "ERROR|SCRIPT ERROR|Parse Error"
$warnings = $all | Select-String -CaseSensitive -Pattern "^WARNING|WARNING:"

Write-Host ""
Write-Host "=== RELATORIO DE EXECUCAO ($stamp) ===" -ForegroundColor Cyan
Write-Host ("Linhas de saida: {0}" -f $all.Count)
Write-Host ("Erros: {0} | Avisos: {1}" -f $errors.Count, $warnings.Count) `
    -ForegroundColor ($(if ($errors.Count -gt 0) { "Red" } else { "Green" }))
if ($errors.Count -gt 0) {
    Write-Host "--- erros ---" -ForegroundColor Red
    $errors | ForEach-Object { $_.Line }
}
$errLogPath = Join-Path $diag "runtime_report.txt"
if (Test-Path $errLogPath) {
    Write-Host "--- autodebug (runtime_report.txt) ---" -ForegroundColor DarkGray
    Get-Content $errLogPath | Select-Object -First 8 | ForEach-Object { $_ }
}
Write-Host "Logs completos: $outLog / $errLog"
exit $(if ($errors.Count -gt 0) { 1 } else { 0 })
