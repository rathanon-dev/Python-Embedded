class PythonNuget {
    # =======================
    # Properties
    # =======================
    [hashtable]$Config
    [string]$ListVersions
    [string]$Version
    [string]$EmbeddedPath  
    [string]$EmbeddedVersion  
    [bool]$GlobalExists = $false
    [string]$IndexUrl = "https://api.nuget.org/v3-flatcontainer/python/index.json"

    # =======================
    # Constructor
    # =======================
    PythonNuget() {
        Write-Host "Initializing PythonNuget Manager..." -ForegroundColor Cyan
        $this.SetConfig()
        $this.EnsureDirectoriesExist()
    }

    # =======================
    # Configuration & Directories
    # =======================
    [void] SetConfig() {
        $script:rootDir = $PSScriptRoot
        if (-not $script:rootDir) {
            $script:rootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.PSCommandPath)
        }

        $script:Config = @{
            Dirs = @{
                rootDir = $script:rootDir
                PyDir   = Join-Path $script:rootDir "python_embeded"
                DLDir   = Join-Path $script:rootDir "download"
            }
        }
        $this.Config = $script:Config
    }

    [void] EnsureDirectoriesExist() {
        $dirs = $this.Config.Dirs.GetEnumerator() | ForEach-Object { $_.Value }
        $missing = $dirs | Where-Object { -not (Test-Path $_) }

        foreach ($dir in $missing) {
            Write-Host "Creating missing folder: $dir" -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $dir | Out-Null
        }

        if ($missing.Count -eq 0) {
            Write-Host "All required directories exist." -ForegroundColor Green
        }
    }

    # =======================
    # Version Handling
    # =======================
    hidden [Version] NormalizeVersion([string]$verStr) {
        if (-not $verStr) { return $null }
        $base = $verStr.Split('-', 2)[0].Trim() -replace '[^0-9.]', ''
        $parts = $base.Split('.', [System.StringSplitOptions]::RemoveEmptyEntries)
        while ($parts.Count -lt 3) { $parts += '0' }
        try { return [Version]("$($parts[0]).$($parts[1]).$($parts[2])") } catch { return $null }
    }

    [Object] GetPythonVersions() {
        Write-Host "Fetching Python versions from NuGet..." -ForegroundColor Yellow
        try {
            $index = Invoke-RestMethod -Uri $this.IndexUrl -TimeoutSec 20
        }
        catch { throw "Failed to fetch NuGet index: $($_.Exception.Message)" }

        $entries = @()
        foreach ($raw in $index.versions) {
            $norm = $this.NormalizeVersion($raw)
            if ($norm) {
                $entries += [PSCustomObject]@{
                    Raw         = $raw
                    NormVersion = $norm
                    MajorMinor  = "$($norm.Major).$($norm.Minor)"
                    IsStable    = ($raw -notmatch '-')
                }
            }
        }

        if ($entries.Count -eq 0) { throw "No valid versions found." }

        # Choose latest stable per major.minor
        $latestPerGroup = $entries | Where-Object { $_.IsStable } |
            Group-Object -Property MajorMinor |
            ForEach-Object { $_.Group | Sort-Object NormVersion -Descending | Select-Object -First 1 }

        $sorted = $latestPerGroup | Sort-Object @{Expression = { $_.NormVersion.Major } }, @{Expression = { $_.NormVersion.Minor } }
        $result = $sorted | ForEach-Object { "$($_.NormVersion.Major).$($_.NormVersion.Minor).$($_.NormVersion.Build)" }

        $this.ListVersions = ($result | ConvertTo-Json -Depth 3)
        $this.Version = ($result -join ",")
        return $this.ListVersions
    }

    # =======================
    # Download & Install
    # =======================
    [bool] CheckPython([string]$version) {
        $pyPath = Join-Path $this.Config.Dirs.PyDir 'python.exe'
        if (Test-Path $pyPath) {
            $installed = (& $pyPath --version 2>&1).Trim()
            Write-Host "Detected installed Python: $installed" -ForegroundColor Yellow
            $resp = Read-Host "Do you want to replace it with $version ? (Y/N)"
            if ($resp -match '^[Yy]') {
                Remove-Item $this.Config.Dirs.PyDir -Recurse -Force
                Write-Host "Old Python removed." -ForegroundColor Green
                return $true
            }
            return $false
        }
        return $true
    }

    [void] DownloadPython([string]$version) {
        if (-not $this.CheckPython($version)) { Write-Host "Installation cancelled."; return }

        $dest = $this.Config.Dirs.DLDir
        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

        $url = "https://api.nuget.org/v3-flatcontainer/python/$version/python.$version.nupkg"
        $nupkg = Join-Path $dest "python.$version.nupkg"
        $outDir = Join-Path $dest "python.$version"

        Write-Host "Downloading Python $version ..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $nupkg -TimeoutSec 300

        if (-not (Test-Path $nupkg)) { throw "Download failed." }

        if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
        Expand-Archive -Path $nupkg -DestinationPath $outDir

        $this.CopyPython($outDir)
    }

    [void] CopyPython([string]$sourceDir) {
        $sourceTools = Join-Path $sourceDir "tools"
        if (-not (Test-Path $sourceTools)) { Write-Warning "No tools folder found."; return }

        $dest = $this.Config.Dirs.PyDir
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Copy-Item -Path $sourceTools -Destination $dest -Recurse
        Write-Host "Python copied to embedded folder successfully." -ForegroundColor Green
        Read-Host "Press Enter to continue"
    }

    # =======================
    # Alias / Pip Setup
    # =======================
    [void] SetupAlias() {
        Write-Host "--------------------------------------------"
        Write-Host "Setting Python and pip aliases..." -ForegroundColor Blue
        $global:PY_EMB = Join-Path $this.Config.Dirs.PyDir 'python.exe'
        if (-not (Test-Path $global:PY_EMB)) { 
            Write-Host "python.exe not found!" -ForegroundColor Red
            Read-Host "Press Enter to continue"
            return
        }

        Set-Alias python $global:PY_EMB -Scope Global -Force
        Write-Host "Python alias set globally."
        if (Get-Alias pip -ErrorAction Ignore) { Remove-Item Alias:\pip }
        function global:pip { & $global:PY_EMB -m pip @args }
        Write-Host "pip alias set globally."
        try { & $global:PY_EMB -m ensurepip --upgrade } catch {}

        Write-Host "Python alias and pip setup complete." -ForegroundColor Green
        Read-Host "Press Enter to continue"
    }

    # =======================
    # UI: Show & Select Versions
    # =======================
    [void] ShowPythonVersionsMenu() {
        try {
            $json = $this.GetPythonVersions() | ConvertFrom-Json
            $menuItems = @()
            foreach ($v in $json) {
                $ver = $v.Trim()
                if ($ver -eq "") { continue }
                $menuItems += [PSCustomObject]@{ Name = $ver; Path = "" }
            }

            $keyInfo = $null
            $Script:exitLoop = $false
            $quitOptions = ("Q", "Escape", "Backspace")
            $selectedIndex = 0

            while ($null -eq $keyInfo -or ($keyInfo.Key -notin $quitOptions -and -not $Script:exitLoop)) {
                Clear-Host
                Write-Host "📂 Show Python Versions" -ForegroundColor Yellow
                Write-Host "──────────────────────────────────────────────" -ForegroundColor Yellow

                for ($i = 0; $i -lt $menuItems.Count; $i++) {
                    $name = $menuItems[$i].Name
                    if ($i -eq $selectedIndex) {
                        Write-Host ("{0}. {1} <<" -f ($i + 1), $name) -ForegroundColor Cyan
                    } else {
                        Write-Host ("{0}. {1}" -f ($i + 1), $name)
                    }
                }

                Write-Host "──────────────────────────────────────────────" -ForegroundColor Yellow
                Write-Host "Use ↑/↓ to navigate | Enter to select | Esc/Backspace to exit" -ForegroundColor Yellow

                $keyInfo = [System.Console]::ReadKey($true)

                switch ($keyInfo.Key) {
                    'UpArrow' { if ($selectedIndex -gt 0) { $selectedIndex-- } }
                    'DownArrow' { if ($selectedIndex -lt ($menuItems.Count - 1)) { $selectedIndex++ } }
                    'Enter' {
                        $selectedItem = $menuItems[$selectedIndex]
                        $this.Version = $selectedItem.Name
                        Write-Host "`nSelected: $($selectedItem.Name)" -ForegroundColor Green
                        try { $this.DownloadPython($this.Version) } catch { Write-Warning "Download failed: $($_.Exception.Message)" }
                        return
                    }
                }
            }

        } catch {
            Write-Error "ShowPythonVersionsMenu error: $($_.Exception.Message)"
        }
    }

    # =======================
    # Test Embedded & Global Python
    # =======================
    [void] TestPythonGlobal() {
        $pyPath = Join-Path $this.Config.Dirs.PyDir 'python.exe'
        $this.EmbeddedVersion = ""
        if (Test-Path $pyPath) {
            try { $out = & $pyPath --version 2>&1; if ($out -match 'Python\s+\d+\.\d+') { $this.EmbeddedVersion = $out.Trim() } } catch {}
        }

        $this.GlobalExists = $false
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd) {
            $src = $null
            try { $src = $cmd.Source } catch {}
            if (-not ($src -and $src -match '\\WindowsApps\\')) {
                try { $gout = & python --version 2>&1; if ($gout -match 'Python\s+\d+\.\d+' -and $LASTEXITCODE -eq 0) { $this.GlobalExists = $true } } catch {}
            }
        }

        $this.EmbeddedPath = $pyPath
    }

    # =======================
    # Main UI
    # =======================
    [void] Run() {
        $keyInfo = $null
        $selectedIndex = 0
        $script:exit = $false

        while (-not $script:exit) {
            $null = $this.TestPythonGlobal()
            $menu = @()
            
            $menu += @{
                Name = if ($this.EmbeddedVersion) { "🔄 ReInstall Embedded $($this.EmbeddedVersion)" } else { "🛠️ Install Python Embedded" }
                Action = { $this.ShowPythonVersionsMenu(); $null = $this.TestPythonGlobal() }
            }

            if ($this.EmbeddedVersion) {
                $aliasLabel = if ($this.GlobalExists) { "🔄 ReAlias Python (global exists)" } else { "🔑 Alias Python" }
                $menu += @{ Name = $aliasLabel; Action = { $this.SetupAlias(); $null = $this.TestPythonGlobal() } }
            }

            $menu += @{ Name = "❌ Exit Program"; Action = { $script:exit = $true } }

            if ($selectedIndex -ge $menu.Count) { $selectedIndex = 0 }

            Clear-Host
            Write-Host "Python Embedded Manager" -ForegroundColor Cyan
            Write-Host "------------------------------------------------"
            for ($i = 0; $i -lt $menu.Count; $i++) {
                if ($i -eq $selectedIndex) {
                    Write-Host ("{0}. {1} <<" -f ($i + 1), $menu[$i].Name) -ForegroundColor Cyan
                } else {
                    Write-Host ("{0}. {1}" -f ($i + 1), $menu[$i].Name)
                }
            }
            Write-Host "------------------------------------------------"
            Write-Host "Use ↑/↓ to navigate | Enter to select | Esc to exit" -ForegroundColor Yellow

            $keyInfo = [System.Console]::ReadKey($true)
            switch ($keyInfo.Key) {
                'UpArrow' { if ($selectedIndex -gt 0) { $selectedIndex-- } }
                'DownArrow' { if ($selectedIndex -lt ($menu.Count - 1)) { $selectedIndex++ } }
                'Enter' { $menu[$selectedIndex].Action.Invoke(); Start-Sleep -Milliseconds 150 }
                'Escape' { $script:exit = $true }
            }
        }

        # Show Python/pip check command
        Write-Host "`n------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Check your Python executable and pip using this command:" -ForegroundColor Yellow
        Write-Host "------------------------------------------------" -ForegroundColor DarkGray
        $pythonCmd = "import sys, pip;  print('Python version:', sys.version); print('pip version:', pip.__version__); print('Python executable:', sys.executable);print('pip module:', pip.__file__);"
        $fullCmd = "python -c `"$pythonCmd`""
        Write-Host $fullCmd `n
        
    }
}

# =======================
# Run Program
# =======================
[PythonNuget]::new().Run()
