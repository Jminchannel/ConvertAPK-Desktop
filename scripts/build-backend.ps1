Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$backendDir = Join-Path $PSScriptRoot "..\web\backend"
$distDir = Join-Path $PSScriptRoot "..\dist\backend"

Write-Host "=== Building Backend EXE ===" -ForegroundColor Cyan

# Install dependencies
Write-Host "[1/3] Installing Python dependencies..."
python -m pip install -r (Join-Path $backendDir "requirements.txt")
python -m pip install pyinstaller

# Build with PyInstaller
Write-Host "[2/3] Building EXE with PyInstaller..."
$specPath = Join-Path $PSScriptRoot "convertapk-backend.spec"
pyinstaller --noconfirm --clean `
  --distpath $distDir `
  --workpath (Join-Path $PSScriptRoot "..\build\backend") `
  $specPath
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller failed with exit code $LASTEXITCODE"
}

# Copy to desktop resources
Write-Host "[3/3] Copying to desktop resources..."
$targetDir = Join-Path $PSScriptRoot "..\desktop\dist\win-unpacked\resources\backend"
if (Test-Path $targetDir) {
    $exePath = Join-Path $distDir "convertapk-backend.exe"
    if (Test-Path $exePath) {
        Copy-Item $exePath $targetDir -Force
        Write-Host "Copied to: $targetDir" -ForegroundColor Green
    }
}

Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "EXE location: $distDir\convertapk-backend.exe"



