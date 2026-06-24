# Launch native embedding llama-server reading models/active.json.
# Windows PowerShell.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$active = Get-Content "models/active.json" | ConvertFrom-Json
$model = $active.primary_model
$hw = Get-Content "hardware.json" | ConvertFrom-Json
$threads = if ($hw.cpu.cores_physical) { $hw.cpu.cores_physical } else { 4 }

$gpu     = if ($env:LAB_N_GPU_LAYERS) { $env:LAB_N_GPU_LAYERS } else { '0' }
$ctx     = if ($env:LAB_N_CTX) { $env:LAB_N_CTX } else { '2048' }

Write-Host "==> Starting NATIVE embedding llama-server" -ForegroundColor Cyan
Write-Host "    model     : $model"
Write-Host "    threads   : $threads"
Write-Host "    gpu_layers: $gpu"
Write-Host "    ctx       : $ctx"
Write-Host "    listening : http://0.0.0.0:8081"
Write-Host ""

.\BONUS-llama-cpp-optimization\llama.cpp\build\bin\llama-server.exe `
    -m "$model" `
    --host "0.0.0.0" --port 8081 `
    -t $threads `
    -ngl $gpu `
    -c $ctx `
    --embedding `
    --parallel 2 `
    --metrics
