# Roda a suite de testes automatizados headless e mostra o resumo.
# Uso:  tools\run_tests.ps1
param(
    [string]$Godot = "C:\Users\roger\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe",
    [string]$Project = (Join-Path $PSScriptRoot "..")
)

if (-not (Test-Path $Godot)) {
    Write-Error "Godot nao encontrado em: $Godot"
    exit 2
}

Write-Host "Rodando testes automatizados do Elementio..." -ForegroundColor Cyan
& $Godot --headless --path $Project res://tests/test_runner.tscn 2>&1 |
    Select-String -Pattern "PASS|FAIL|RESULTADO|SCRIPT ERROR|Parse Error" |
    ForEach-Object { $_.Line }

$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Host "TODOS OS TESTES PASSARAM" -ForegroundColor Green
} else {
    Write-Host "HOUVE FALHAS (exit $code)" -ForegroundColor Red
}
exit $code
