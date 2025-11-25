@echo off
REM check pwsh
where pwsh >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7+ pwsh not found in PATH.
    echo Please install PowerShell 7+ and re-run this script.
    echo You can use winget: winget install --id=Microsoft.Powershell
    pause
    exit /b 1
)

REM run PythonNuget.ps1 elevated from the same folder as this batch
set "scriptPath=%~dp0\PythonDev.ps1"

powershell -Command ^
    "Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy Bypass','-NoExit','-Command & ''%scriptPath%'' ' -Verb RunAs"
