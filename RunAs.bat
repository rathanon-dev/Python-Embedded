@echo off
REM check pwsh
where pwsh >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7+ is required.
    pause
    exit /b
)

REM run PythonNuget.ps1 elevated from the same folder as this batch
set "scriptPath=%~dp0PythonNuget.ps1"

powershell -Command ^
    "Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy Bypass','-NoExit','-Command & ''%scriptPath%'' ' -Verb RunAs"
