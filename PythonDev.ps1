# PythonDev class: corrected to avoid default params in class methods
Class PythonDev {
    [hashtable] $Config
    [hashtable] $Cache 
    [string]    $RootDir
    [string]    $IndexUrl = "https://api.nuget.org/v3-flatcontainer/python/index.json"

    [string] $EmbeddedPath = $null
    [string] $EmbeddedVersion = $null
    [bool]   $EmbeddedPipInstalled = $false
    [string] $EmbeddedPipVersion = $null

    [bool]   $GlobalExists = $false
    [string] $GlobalPath = $null
    [string] $GlobalVersion = $null
    [bool]   $GlobalPipInstalled = $false
    [string] $GlobalPipVersion = $null
    [datetime] $TestLastChecked  
    [string] $Report

    # Constructor: custom root (no auto-create)
    PythonDev([string] $rootDir) {
        # resolve relative -> absolute
        if (-not [System.IO.Path]::IsPathRooted($rootDir)) {
            $resolved = Join-Path (Get-Location).Path $rootDir
        }
        else {
            $resolved = $rootDir
        }

        $resolved = [System.IO.Path]::GetFullPath($resolved)

        if (-not (Test-Path -Path $resolved)) {
            Write-Warning "Specified root path '$rootDir' resolved to '$resolved' but it does not exist. Config will be set to this path, but folders will not be created automatically. Call `CreateFolders()` to create them when ready."
        }
        else {
            Write-Host "Path Custom : $resolved" -ForegroundColor Green
        }

        $this.SetPath($resolved)
    }

    # Default constructor: resolve PSScriptRoot or current location
    PythonDev() {
        $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $root = [System.IO.Path]::GetFullPath($root)
        Write-Host "Path Default : $root" -ForegroundColor Green
        $this.SetPath($root)
    }

    # SetPath: validate and assign config (does NOT create folders)
    [void] SetPath([string] $rootDir) {
        try {
            if (-not $rootDir -or [string]::IsNullOrWhiteSpace($rootDir)) {
                throw [System.ArgumentException]::new("rootDir is null, empty or whitespace.")
            }

            # normalize to full absolute path
            $absRoot = [System.IO.Path]::GetFullPath($rootDir)

            # build newConfig based on absolute root
            $newConfig = @{
                RootDir  = $absRoot
                DLDir    = Join-Path $absRoot "download"
                PyDir    = Join-Path $absRoot "python_embeded"
                CudaBin  = Join-Path $absRoot "driver\CUDA"
                CuDNNBin = Join-Path $absRoot "driver\CUDNN"
                PGit     = Join-Path $absRoot "driver\PortableGit"
            }

            # assign properties only after computed successfully
            $this.RootDir = $absRoot
            $this.Config = $newConfig
            if (-not $this.Cache) {
                $this.Cache = @{} 
            }
            Write-Host "PythonManager initialized (root: $($this.RootDir))" -ForegroundColor DarkGray

            if (-not (Test-Path -Path $absRoot)) {
                Write-Warning "RootDir set to '$absRoot' but the directory does not exist. Call CreateFolders('Skip'| 'Backup' | 'Recreate') to create as needed."
            }
            else {
                Write-Host "Config set for RootDir: $absRoot" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Warning "SetPath() failed: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
        }
    }

    # Overloads for CreateFolders
    # 0-arg: default to Skip + perform (create real)
    

    # Helper: return first non-empty property from provided names
    [string] GetFirstNonNull([string[]] $names) {
        try {
            foreach ($n in $names) {
                if ($this -and $this.PSObject.Properties.Match($n).Count -gt 0) {
                    $val = $this.$n
                    if ($val) { return [string]$val }
                }
            }
            return $null
        }
        catch {
            return $null
        }
    }

    # Helper: determine cache/download base dir (uses Config.DLDir -> DLDir -> AbsRoot\cache)
    [string] GetCacheBase() {
        try {
            if ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config -and $this.Config.PSObject.Properties.Match('DLDir').Count -gt 0 -and $this.Config.DLDir) {
                return [string]$this.Config.DLDir
            }
            $v = $this.GetFirstNonNull(@('DLDir', 'CacheDir', 'Cache'))
            if ($v) { return $v }
            if ($this -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0 -and $this.AbsRoot) {
                return (Join-Path $this.AbsRoot 'cache')
            }
            return (Join-Path (Get-Location).Path 'cache')
        }
        catch {
            return (Join-Path (Get-Location).Path 'cache')
        }
    }

    [void] CreateFolders() {
        $this.CreateFolders('Skip', $false)
    }

    # 1-arg: Mode only -> perform (WhatIf = $false)
    [void] CreateFolders([string] $Mode) {
        $this.CreateFolders($Mode, $false)
    }

    # 2-arg: Mode + WhatIf -> actual implementation
    [void] CreateFolders([string] $Mode, [bool] $WhatIf) {
        if (-not $this.Config) {
            Write-Warning "Config is null — call SetPath() first."
            return
        }

        # validate Mode inside method
        $allowed = @('Skip', 'Recreate', 'Backup')
        if (-not ($allowed -contains $Mode)) {
            Write-Warning "Invalid Mode '$Mode'. Allowed values: $($allowed -join ', '). Defaulting to 'Skip'."
            $Mode = 'Skip'
        }

        foreach ($key in $this.Config.Keys) {
            $path = $this.Config[$key]
            if (-not $path) {
                Write-Warning "Empty path for '$key' — skipping."
                continue
            }

            $exists = Test-Path -Path $path

            if ($exists) {
                switch ($Mode) {
                    'Skip' {
                        if ($WhatIf) {
                            Write-Host "[WhatIf] Would skip existing: $key => $path" -ForegroundColor Cyan
                        }
                        else {
                            Write-Host "Exists : $key => $path (skipped)" -ForegroundColor Yellow
                        }
                        continue
                    }
                    'Backup' {
                        $ts = (Get-Date).ToString('yyyyMMddHHmmss')
                        $backupPath = "$path.bak_$ts"

                        if ($WhatIf) {
                            Write-Host "[WhatIf] Would move (backup): $path -> $backupPath" -ForegroundColor Cyan
                        }
                        else {
                            try {
                                Move-Item -Path $path -Destination $backupPath -Force -ErrorAction Stop
                                Write-Host "Backed-up: $key => $backupPath" -ForegroundColor Yellow
                            }
                            catch {
                                Write-Warning "Backup failed for $key => $path : $($_.Exception.Message)"
                                continue
                            }
                        }
                        # after backup, fall through to creation
                    }
                    'Recreate' {
                        if ($WhatIf) {
                            Write-Host "[WhatIf] Would remove: $path" -ForegroundColor Cyan
                        }
                        else {
                            try {
                                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                                Write-Host "Removed: $key => $path" -ForegroundColor Magenta
                            }
                            catch {
                                Write-Warning "Remove failed for $key => $path : $($_.Exception.Message)"
                                continue
                            }
                        }
                        # after remove, fall through to creation
                    }
                } # end switch
            }

            # Now path does not exist (or was removed/backed up) -> create or WhatIf
            if ($WhatIf) {
                Write-Host "[WhatIf] Would create: $key => $path" -ForegroundColor Cyan
            }
            else {
                try {
                    New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Write-Host "Created: $key => $path" -ForegroundColor Green
                }
                catch {
                    try {
                        [System.IO.Directory]::CreateDirectory($path) | Out-Null
                        Write-Host "Created (dotnet): $key => $path" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Failed to create: $key => $path : $($_.Exception.Message)"
                    }
                }
            }
        } # end foreach
    }

    # Overloads for RemoveFolder
    [void] RemoveFolder([string] $key) {
        $this.RemoveFolder($key, $false)
    }

    [void] RemoveFolder([string] $key, [bool] $WhatIf) {
        if (-not $this.Config) { Write-Warning "Config is null — call SetPath() first."; return }
        if (-not $this.Config.ContainsKey($key)) { Write-Warning "Unknown key: $key"; return }

        $path = $this.Config[$key]
        if (-not (Test-Path -Path $path)) {
            Write-Host "Not exists: $key => $path" -ForegroundColor Yellow
            return
        }

        if ($WhatIf) {
            Write-Host "[WhatIf] Would remove: $key => $path" -ForegroundColor Cyan
            return
        }

        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Host "Removed: $key => $path" -ForegroundColor Magenta
        }
        catch {
            Write-Warning "Failed to remove $key => $path : $($_.Exception.Message)"
        }
    }

    [bool] IsFolder() {
        if (-not $this.Config) {
            Write-Warning "Config is null or empty. Call SetPath() first."
            return $false
        }

        $allOk = $true

        foreach ($key in $this.Config.Keys) {
            $path = $this.Config[$key]
            if (-not (Test-Path -Path $path)) {
                Write-Warning "Missing: $key => $path"
                $allOk = $false
            }
            else {
                Write-Host "OK: $key => $path" -ForegroundColor Green
            }
        }

        return $allOk
    }

 
    # --- NormalizeVersion: return numeric portion only, or $null if not numeric-stable ---
    [string] NormalizeVersion([string] $v) {
        if (-not $v) { return $null }
        $s = $v.Trim()

        # strip common prefix
        $s = $s -replace '^[Pp]ython[-_]*', ''
        $s = $s -replace '[\s_]', '.'

        # We only accept pure-numeric stable forms like "3.5.3" or "3.14.0" (no letters, no '-' suffix)
        if ($s -notmatch '^[0-9]+(\.[0-9]+){1,3}$') {
            return $null
        }

        # normalize to up to 3 components (major.minor.build)
        $parts = $s.Split('.') | Where-Object { $_ -ne '' }
        if ($parts.Count -eq 1) { $s = "$($parts[0]).0.0" }
        elseif ($parts.Count -eq 2) { $s = "$($parts[0]).$($parts[1]).0" }
        else { $s = "$($parts[0]).$($parts[1]).$($parts[2])" }

        try { return ([version]$s).ToString() } catch { return $null }
    }
    [Object]GetPythonVersions() {
        return $this.GetPythonVersions($false, $false)
    }
    # -------------------------
    # GetPythonVersions
    # Params:
    #   [bool] $ForceRefresh = $false    - ignore cache and fetch fresh
    #   [bool] $AsJson = $false          - return JSON string when true
    # Returns: PSCustomObject[] unless $AsJson - each object contains:
    #   Version (string), VersionObj ([version]), Raw (string), MajorMinor (string), IsStable (bool)
    # -------------------------
    [Object] GetPythonVersions([bool] $ForceRefresh = $false, [bool] $AsJson = $false) {
        # fallback if fetch fails
        $fallback = @('3.12.0', '3.11.11', '3.10.13', '3.9.18', '3.8.18')

        if (-not $this.Cache) {
            $this.Cache = @{} 
        }

        if (-not $ForceRefresh -and $this.Cache.ContainsKey('versions')) {
            $cached = $this.Cache['versions']
            return ($AsJson) ? ($cached | ConvertTo-Json -Depth 3) : $cached
        }

        try {
            $index = Invoke-RestMethod -Uri $this.IndexUrl -TimeoutSec 20 -ErrorAction Stop
        }
        catch {
            Write-Warning "Fetch failed: $($_.Exception.Message)"
            if ($this.Cache.ContainsKey('versions')) {
                $cached = $this.Cache['versions']
                return ($AsJson) ? ($cached | ConvertTo-Json -Depth 3) : $cached
            }
            else {
                # return fallback converted to objects
                $res = $fallback | ForEach-Object {
                    $nv = $this.NormalizeVersion($_)
                    [PSCustomObject]@{ Version = $nv; VersionObj = ([version]$nv); Raw = $_; MajorMinor = "$($nv.Split('.')[0]).$($nv.Split('.')[1])"; IsStable = $true }
                }
                $this.Cache['versions'] = $res
                return ($AsJson) ? ($res | ConvertTo-Json -Depth 3) : $res
            }
        }

        if (-not $index -or -not $index.versions) { throw "Index JSON did not contain 'versions'." }

        $entries = New-Object System.Collections.Generic.List[object]

        foreach ($raw in $index.versions) {
            $rawStr = [string]$raw

            # Only accept stable numeric releases: no letters, no '-' pre-release suffix
            if ($rawStr -notmatch '^[0-9]+(\.[0-9]+){1,3}$') { continue }

            $norm = $this.NormalizeVersion($rawStr)
            if (-not $norm) { continue }

            try {
                $vObj = [version]$norm
            }
            catch {
                continue
            }

            $po = [PSCustomObject]@{
                Version    = $vObj.ToString()
                VersionObj = $vObj
                Raw        = $rawStr
                MajorMinor = "$($vObj.Major).$($vObj.Minor)"
                IsStable   = $true
            }
            $entries.Add($po)
        }

        if ($entries.Count -eq 0) { throw "No stable numeric versions found in index." }

        # group by MajorMinor and pick the highest version per group (latest stable)
        $groups = $entries | Group-Object -Property MajorMinor
        $latest = @()
        foreach ($g in $groups) {
            $pick = $g.Group | Sort-Object -Property VersionObj -Descending | Select-Object -First 1
            $latest += $pick
        }

        # final sort desc
        $sorted = $latest | Sort-Object -Property VersionObj -Descending

        $this.Cache['versions'] = $sorted
        return ($AsJson) ? ($sorted | ConvertTo-Json -Depth 3) : $sorted
    }
    # ตัวเลือก: เมทอด menu ที่สามารถเลือก auto-install mode (ไม่ควรเป็น default)
    [string] ShowPythonVersionsMenu([bool] $Interactive = $true, [bool] $AutoInstall = $false) {
        # your existing menu implementation but return selected version
        # if $AutoInstall -and $selected - then you may call $this.CheckPython + $this.DownloadAndCopyPython here
        # BUT better approach: return selected version and let caller (InstallFlow) handle the rest.
        $list = $this.GetPythonVersions()
        return  $list[1 - 1].Version
    }
    # Small helper: Show as simple numeric menu (returns selected Version string or $null)
    [string] ShowPythonVersionsMenu() {
        $list = $this.GetPythonVersions()
        if (-not $list -or $list.Count -eq 0) { Write-Warning "No versions to show"; return $null }
        for ($i = 0; $i -lt $list.Count; $i++) {
            Write-Host ("[{0}] {1}" -f ($i + 1), $list[$i].Version)
        }
        $sel = Read-Host "Select number (q to cancel)"
        if ($sel -match '^[Qq]') { return $null }
        if (-not ($sel -as [int])) { Write-Warning "Invalid selection"; return $null }
        $n = [int]$sel
        if ($n -lt 1 -or $n -gt $list.Count) { Write-Warning "Out of range"; return $null }
        return $list[$n - 1].Version
    }

    # -------------------------
    # CheckPython
    # - Checks whether python exists in Config.PyDir and whether same version exists
    # - If python exists, returns $true if ready to install (i.e., it was removed/backup by choice)
    # - If python does not exist returns $true (ready to install)
    # - This method is interactive by default; you can pass $autoReplace,$backup,$whatIf via overload later
    # -------------------------
    [bool] CheckPython([string] $version) { return $this.CheckPython($version, $false, $true, $false) }

    
    [bool] CheckPython([string] $version, [bool] $autoRemove, [bool] $backupBeforeRemove, [bool] $whatIf) {
        if (-not $this.Config) { Write-Warning "Config not initialized"; return $false }
        $pyDir = $this.Config.PyDir
        $pyExe = Join-Path $pyDir 'python.exe'

        if (-not (Test-Path -Path $pyExe)) {
            Write-Host "No python installed at $pyExe — ready to install." -ForegroundColor Green
            return $true
        }

        try { $installed = (& $pyExe --version 2>&1).Trim() } catch { Write-Warning "Cannot run existing python --version"; return $false }
        Write-Host "Detected installed Python: $installed" -ForegroundColor Yellow

        $instVer = ($installed -match '\d+(\.\d+){1,2}') ? $matches[0] : $null
        $targetNorm = $this.NormalizeVersion($version)

        $shouldReplace = $false
        if ($instVer -and $targetNorm -and ([version]$instVer -eq [version]$targetNorm)) {
            if (-not $autoRemove) {
                $r = Read-Host "Installed matches $targetNorm. Replace? (Y/N)"
                if ($r -notmatch '^[Yy]') { Write-Host "Keeping existing." -ForegroundColor Yellow; return $false }
            }
            $shouldReplace = $true
        }
        else {
            if (-not $autoRemove) {
                $r = Read-Host "Replace installed ($installed) with $version ? (Y/N)"
                if ($r -notmatch '^[Yy]') { Write-Host "Keeping existing." -ForegroundColor Yellow; return $false }
            }
            $shouldReplace = $true
        }

        if ($whatIf) {
            if ($backupBeforeRemove) {
                $ts = (Get-Date).ToString('yyyyMMddHHmmss')
                Write-Host "[WhatIf] Would move: $pyDir -> $pyDir.bak_$ts" -ForegroundColor Cyan
            }
            else {
                Write-Host "[WhatIf] Would remove: $pyDir" -ForegroundColor Cyan
            }
            return $true
        }

        if ($backupBeforeRemove) {
            $ts = (Get-Date).ToString('yyyyMMddHHmmss')
            $backup = "$pyDir.bak_$ts"
            try { Move-Item -Path $pyDir -Destination $backup -Force -ErrorAction Stop; Write-Host "Backed up to $backup" -ForegroundColor Yellow; return $true } catch { Write-Warning "Backup failed: $($_.Exception.Message)"; return $false }
        }
        else {
            try { Remove-Item -Path $pyDir -Recurse -Force -ErrorAction Stop; Write-Host "Removed $pyDir" -ForegroundColor Magenta; return $true } catch { Write-Warning "Remove failed: $($_.Exception.Message)"; return $false }
        }
    }

    # --- DownloadAndCopyPython overloads ---
    [bool] DownloadAndCopyPython([string] $version) { return $this.DownloadAndCopyPython($version, $false, $false, $true) }
    [bool] DownloadAndCopyPython([string] $version, [bool] $WhatIf) { return $this.DownloadAndCopyPython($version, $WhatIf, $false, $true) }
    # Replace existing DownloadAndCopyPython implementation with this
    [bool] DownloadAndCopyPython([string] $version, [bool] $WhatIf, [bool] $ForceOverwrite, [bool] $BackupExisting) {
        if (-not $this.Config) { Write-Warning "Config not initialized"; return $false }

        $dl = $this.Config.DLDir
        $target = $this.Config.PyDir

        # Ensure download dir exists (or show whatif)
        if (-not (Test-Path -Path $dl)) {
            if ($WhatIf) { Write-Host "[WhatIf] Would create download directory: $dl" -ForegroundColor Cyan }
            else { New-Item -Path $dl -ItemType Directory -Force | Out-Null; Write-Host "Created DLDir: $dl" -ForegroundColor Green }
        }

        $vNorm = $this.NormalizeVersion($version)
        if (-not $vNorm) { Write-Warning "Cannot normalize version: $version"; return $false }

        $nupkgName = "python.$version.nupkg"
        $url = "https://api.nuget.org/v3-flatcontainer/python/$version/$nupkgName"
        $nupkgLocal = Join-Path $dl $nupkgName
        $extractTmp = Join-Path $env:TEMP ("py_extract_{0}" -f ([Guid]::NewGuid().ToString()))

        # Download
        try {
            if ($WhatIf) {
                Write-Host "[WhatIf] Would download: $url -> $nupkgLocal" -ForegroundColor Cyan
            }
            else {
                Write-Host "Downloading $url ..." -ForegroundColor Cyan
                Invoke-WebRequest -Uri $url -OutFile $nupkgLocal -TimeoutSec 300 -ErrorAction Stop
                Write-Host "Downloaded: $nupkgLocal" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "Download failed: $($_.Exception.Message)"; return $false
        }

        if (-not $WhatIf -and -not (Test-Path -Path $nupkgLocal)) {
            Write-Warning "Downloaded package not found: $nupkgLocal"; return $false
        }

        # Extract nupkg
        if ($WhatIf) {
            Write-Host "[WhatIf] Would extract $nupkgLocal -> $extractTmp" -ForegroundColor Cyan
        }
        else {
            try {
                New-Item -Path $extractTmp -ItemType Directory -Force | Out-Null
                Expand-Archive -Path $nupkgLocal -DestinationPath $extractTmp -Force
                Write-Host "Extracted to $extractTmp" -ForegroundColor DarkGray
            }
            catch {
                Write-Warning "Extract failed: $($_.Exception.Message)"
                if (Test-Path $extractTmp) { Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue }
                return $false
            }
        }

        # locate 'tools' folder inside extracted nupkg (common paths)
        $candidatePaths = @(
            (Join-Path $extractTmp 'tools'),
            (Join-Path $extractTmp 'content\tools'),
            (Join-Path $extractTmp 'package\tools'),
            (Join-Path $extractTmp 'package\content\tools'),
            (Join-Path $extractTmp 'content'),
            $extractTmp
        )

        $sourceTools = $null
        foreach ($p in $candidatePaths) {
            if (Test-Path -Path $p) {
                # prefer a path that actually contains python.exe or DLLs
                $hasPython = Test-Path -Path (Join-Path $p 'python.exe')
                if ($hasPython) { $sourceTools = $p; break }
                # otherwise first existing candidate is acceptable
                if (-not $sourceTools) { $sourceTools = $p }
            }
        }

        if (-not $sourceTools) {
            Write-Warning "Cannot find tools/content folder inside package. Extracted structure may differ."
            if (-not $WhatIf) { Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue }
            return $false
        }

        Write-Host "Using source folder: $sourceTools" -ForegroundColor DarkGray

        # Prepare target: if exists handle according to flags
        if (Test-Path -Path $target) {
            if ($WhatIf) {
                if ($BackupExisting) {
                    Write-Host "[WhatIf] Would backup existing $target -> $target.bak_TIMESTAMP" -ForegroundColor Cyan
                }
                elseif ($ForceOverwrite) {
                    Write-Host "[WhatIf] Would remove existing $target" -ForegroundColor Cyan
                }
                else {
                    Write-Host "[WhatIf] Target exists: $target (would prompt or abort)" -ForegroundColor Cyan
                }
            }
            else {
                if ($BackupExisting) {
                    $ts = (Get-Date).ToString('yyyyMMddHHmmss')
                    $backup = "$target.bak_$ts"
                    try {
                        Move-Item -Path $target -Destination $backup -Force -ErrorAction Stop
                        Write-Host "Backed up $target -> $backup" -ForegroundColor Yellow
                    }
                    catch {
                        Write-Warning "Backup failed: $($_.Exception.Message)"
                        Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue
                        return $false
                    }
                }
                elseif ($ForceOverwrite) {
                    try {
                        Remove-Item -Path $target -Recurse -Force -ErrorAction Stop
                        Write-Host "Removed existing target $target" -ForegroundColor Magenta
                    }
                    catch {
                        Write-Warning "Remove failed: $($_.Exception.Message)"
                        Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue
                        return $false
                    }
                }
                else {
                    $resp = Read-Host "Target $target exists. Overwrite? (Y/N)"
                    if ($resp -notmatch '^[Yy]') {
                        Write-Host "Aborted by user." -ForegroundColor Yellow
                        if (Test-Path $extractTmp) { Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue }
                        return $false
                    }
                    try { Remove-Item -Path $target -Recurse -Force -ErrorAction Stop } catch { Write-Warning "Remove failed: $($_.Exception.Message)"; Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue; return $false }
                }
            }
        }
        else {
            # create target if missing (unless WhatIf)
            if ($WhatIf) { Write-Host "[WhatIf] Would create target directory: $target" -ForegroundColor Cyan }
            else { New-Item -Path $target -ItemType Directory -Force | Out-Null; Write-Host "Created target: $target" -ForegroundColor Green }
        }

        # Copy only children of tools -> target root
        if ($WhatIf) {
            Write-Host "[WhatIf] Would copy contents of: $sourceTools\* -> $target\" -ForegroundColor Cyan
            # cleanup not required for WhatIf
            return $true
        }

        try {
            # enumerate children (files and directories)
            $children = Get-ChildItem -LiteralPath $sourceTools -Force
            foreach ($child in $children) {
                $sourcePath = $child.FullName
                $destPath = Join-Path $target $child.Name

                if ($child.PSIsContainer) {
                    # it's a directory: copy whole directory as a subfolder (preserve folder name)
                    if (Test-Path -Path $destPath) {
                        try { Remove-Item -Path $destPath -Recurse -Force -ErrorAction Stop } 
                        catch { Write-Warning "Failed to remove existing folder $destPath : $($_.Exception.Message)"; continue }
                    }
                    Copy-Item -LiteralPath $sourcePath -Destination $destPath -Recurse -Force
                }
                else {
                    # it's a file: copy into target (root)
                    Copy-Item -LiteralPath $sourcePath -Destination $target -Force
                }
            }
            Write-Host "Copied tools/* -> $target (folders preserved)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Copy failed: $($_.Exception.Message)"
            if (Test-Path $extractTmp) { Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue }
            return $false
        }

        # cleanup extracted temp
        if (Test-Path $extractTmp) {
            try { Remove-Item -Path $extractTmp -Recurse -Force -ErrorAction SilentlyContinue } catch { /* ignore */ }
        }

        return $true
    }
  

    [bool] GetPip([bool] $whatIf = $false) {
        if (-not $this.Config) { Write-Warning "Config null"; return $false }
        $pyExe = Join-Path $this.Config['PyDir'] 'python.exe'
        if (-not (Test-Path -Path $pyExe)) { Write-Warning "python.exe not found at $pyExe"; return $false }
        if ($whatIf) { Write-Host "[WhatIf] Would run: $pyExe -m ensurepip --upgrade" -ForegroundColor Cyan; return $true }

        try {
            & $pyExe -m ensurepip --upgrade 2>&1 | ForEach-Object { Write-Host $_ }
            & $pyExe -m pip install --upgrade pip 2>&1 | ForEach-Object { Write-Host $_ }
            Write-Host "pip should be available" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "ensurepip failed: $($_.Exception.Message). Trying get-pip.py"
            $dl = $this.Config['DLDir']; if (-not (Test-Path -Path $dl)) { New-Item -Path $dl -ItemType Directory -Force | Out-Null }
            $gp = Join-Path $dl 'get-pip.py'
            try {
                Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile $gp -UseBasicParsing -ErrorAction Stop
                & $pyExe $gp 2>&1 | ForEach-Object { Write-Host $_ }
                Write-Host "pip should be installed" -ForegroundColor Green
                return $true
            }
            catch {
                Write-Warning "get-pip failed: $($_.Exception.Message)"; return $false
            }
        }
    }

    # === Method: TestPythonGlobal ===
    # Usage:
    #   $res = $this.TestPythonGlobal()                 # probe python and pip (embedded preferred)
    #   $res = $this.TestPythonGlobal($false)           # probe python only (no pip)
    # Returns: PSCustomObject with fields: Name, Exists, IsTest, Version, Path, PipInstalled, PipVersion, Notes, CheckedAt
    [psobject] TestPythonGlobal([bool] $ProbePip = $true) {
        # reset object properties
        $this.EmbeddedPath = $null
        $this.EmbeddedVersion = $null
        $this.EmbeddedPipInstalled = $false
        $this.EmbeddedPipVersion = $null

        $this.GlobalExists = $false
        $this.GlobalPath = $null
        $this.GlobalVersion = $null
        $this.GlobalPipInstalled = $false
        $this.GlobalPipVersion = $null

        $this.TestLastChecked = Get-Date
        $notes = @()

        # Helper: parse python version string "Python X.Y.Z" -> X.Y.Z
        function ParsePythonVersion($text) {
            if (-not $text) { return $null }
            if ($text -match 'Python\s+(\d+\.\d+(\.\d+)?)') { return $matches[1] }
            return $null
        }
        function ParsePipVersion($text) {
            if (-not $text) { return $null }
            if ($text -match 'pip\s+(\d+\.\d+(\.\d+)?)') { return $matches[1] }
            return $null
        }

        # 1) Resolve embedded python path if available in config
        $embeddedCandidate = $null
        try {
            if ($this.Config.PyDir) {
                $embeddedCandidate = Join-Path $this.Config.PyDir 'python.exe'
                $embeddedCandidate = [System.IO.Path]::GetFullPath($embeddedCandidate)
                if (-not (Test-Path -Path $embeddedCandidate)) { $embeddedCandidate = $null }
            }
        }
        catch {
            $notes += "Error resolving Config.PyDir: $($_.Exception.Message)"
            $embeddedCandidate = $null
        }

        # 2) Probe embedded interpreter
        if ($embeddedCandidate) {
            $this.EmbeddedPath = $embeddedCandidate
            try {
                $out = & $embeddedCandidate --version 2>&1
                $out = ($out -join "`n").Trim()
                $pv = ParsePythonVersion $out
                if ($pv) {
                    $this.EmbeddedVersion = $pv
                }
                else {
                    # still store raw output as note if cannot parse
                    $notes += "Embedded python --version returned unexpected output: $out"
                }
            }
            catch {
                $notes += "Failed to execute embedded python: $($_.Exception.Message)"
            }

            if ($ProbePip) {
                try {
                    $pout = & $embeddedCandidate -m pip --version 2>&1
                    $pout = ($pout -join "`n").Trim()
                    $pp = ParsePipVersion $pout
                    if ($pp) {
                        $this.EmbeddedPipInstalled = $true
                        $this.EmbeddedPipVersion = $pp
                    }
                    else {
                        # pip command may fail or not be present
                        $this.EmbeddedPipInstalled = $false
                        $notes += "Embedded python pip check returned unexpected output or not installed: $pout"
                    }
                }
                catch {
                    # pip not installed or error running
                    $this.EmbeddedPipInstalled = $false
                    $notes += "Embedded pip probe failed: $($_.Exception.Message)"
                }
            }
        }
        else {
            $notes += "Embedded python not found at Config.PyDir (or PyDir not set)."
        }

        # 3) Resolve global python (avoid WindowsApps stub)
        $globalCandidate = $null
        try {
            $cmds = Get-Command python -ErrorAction SilentlyContinue -All
            if ($cmds) {
                foreach ($c in $cmds) {
                    $src = $null
                    try { $src = $c.Source } catch {}
                    # skip WindowsApps store stub
                    if ($src -and ($src -match '\\WindowsApps\\')) { continue }
                    if ($c.CommandType -in @('Application', 'ExternalScript', 'Script')) {
                        $globalCandidate = $src
                        break
                    }
                }
            }
        }
        catch {
            $notes += "Get-Command python error: $($_.Exception.Message)"
        }

        # fallback to 'py' launcher (try to extract a real interpreter path)
        if (-not $globalCandidate) {
            try {
                $pyCmd = Get-Command py -ErrorAction SilentlyContinue
                if ($pyCmd) {
                    # 'py -0p' typically lists installed interpreters with paths; parse the first path found
                    $pyList = & py -0p 2>$null
                    if ($pyList) {
                        foreach ($line in $pyList) {
                            if ($line -match '\.exe') {
                                $tokens = $line.Trim() -split '\s+'
                                $possible = $tokens[-1]
                                if (Test-Path $possible) { $globalCandidate = $possible; break }
                            }
                        }
                    }
                }
            }
            catch {
                # ignore; py may not be installed
            }
        }

        # final fallback: search PATH for python.exe (avoid WindowsApps)
        if (-not $globalCandidate) {
            try {
                $pathDirs = ($env:PATH -split ';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                foreach ($d in $pathDirs) {
                    try {
                        $candidate = Join-Path $d 'python.exe'
                        if ((Test-Path -Path $candidate) -and ($candidate -notmatch '\\WindowsApps\\')) {
                            $globalCandidate = $candidate
                            break
                        }
                    }
                    catch {}
                }
            }
            catch {
                $notes += "Error searching PATH: $($_.Exception.Message)"
            }
        }

        # 4) Probe global interpreter if found
        if ($globalCandidate) {
            $this.GlobalPath = [System.IO.Path]::GetFullPath($globalCandidate)
            try {
                $gout = & $this.GlobalPath --version 2>&1
                $gout = ($gout -join "`n").Trim()
                $gv = ParsePythonVersion $gout
                if ($gv) {
                    $this.GlobalVersion = $gv
                    $this.GlobalExists = $true
                }
                else {
                    $notes += "Global python --version returned unexpected output: $gout"
                }
            }
            catch {
                $notes += "Failed to execute global python: $($_.Exception.Message)"
            }

            if ($ProbePip) {
                try {
                    $gpout = & $this.GlobalPath -m pip --version 2>&1
                    $gpout = ($gpout -join "`n").Trim()
                    $gpp = ParsePipVersion $gpout
                    if ($gpp) {
                        $this.GlobalPipInstalled = $true
                        $this.GlobalPipVersion = $gpp
                    }
                    else {
                        $this.GlobalPipInstalled = $false
                        $notes += "Global pip check returned unexpected output or not installed: $gpout"
                    }
                }
                catch {
                    $this.GlobalPipInstalled = $false
                    $notes += "Global pip probe failed: $($_.Exception.Message)"
                }
            }
        }
        else {
            $notes += "No usable global python found (PATH and py launcher searched)."
        }
        $hasEmbedded = -not [string]::IsNullOrWhiteSpace($this.EmbeddedPath)
        $hasGlobal = -not [string]::IsNullOrWhiteSpace($this.GlobalPath)

        # 5) Build result summary object for caller
        $summary = [PSCustomObject]@{
            Name         = 'Python'
            Exists       = ($hasEmbedded -or $hasGlobal)
            IsTest       = $false    # will set below
            Version      = $this.GetFirstNonNull(@('EmbeddedVersion', 'GlobalVersion'))
            Path         = $this.GetFirstNonNull(@('EmbeddedPath', 'GlobalPath'))
            PipInstalled = $this.GetFirstNonNull(@('EmbeddedPipInstalled', 'GlobalPipInstalled'))
            PipVersion   = $this.GetFirstNonNull(@('EmbeddedPipVersion', 'GlobalPipVersion'))
            Notes        = ($notes -join '; ')
            CheckedAt    = $this.TestLastChecked
        }

        # Determine IsTest policy:
        # - if interpreter version found -> IsTest = $true
        # - else false
        if ($summary.Version) { $summary.IsTest = $true } else { $summary.IsTest = $false }

        # Save notes property to instance (concatenate)
        $this.Report = $summary.Notes

        return $summary
    }
    [bool] Extract7z([string] $Source, [string] $OutPath) {
        try {
            # Ensure destination
            if (-not (Test-Path $OutPath)) { New-Item -Path $OutPath -ItemType Directory -Force | Out-Null }

            # If Source is URL, download to cache
            if ($Source -match '^https?://') {
                # หา cache directory อย่างปลอดภัย (รองรับ PS5.1)
                if ($this -and $this.PSObject.Properties.Match('CacheDir').Count -gt 0 -and $this.CacheDir) {
                    $cacheBase = $this.CacheDir
                }
                elseif ($this -and $this.PSObject.Properties.Match('Cache').Count -gt 0 -and $this.Cache) {
                    # ถ้าคลาสใช้ชื่อ property เป็น 'Cache' แทน 'CacheDir'
                    $cacheBase = $this.Cache
                }
                else {
                    $cacheBase = Join-Path $this.AbsRoot 'cache'
                }

                $cdl = Join-Path $cacheBase (Split-Path $Source -Leaf)
               
                if (-not (Test-Path $cdl)) {
                    Invoke-WebRequest -Uri $Source -OutFile $cdl -UseBasicParsing -ErrorAction Stop
                }
                $Source = $cdl
            }

            # find 7z/7zr
            $seven = $null
            $candidates = @(
                'C:\Program Files\7-Zip\7z.exe',
                'C:\Program Files (x86)\7-Zip\7z.exe'
            )
            foreach ($p in $candidates) { if (Test-Path $p) { $seven = $p; break } }
            if (-not $seven) {
                $cmd = Get-Command 7z -ErrorAction SilentlyContinue
                if ($cmd) { $seven = $cmd.Path }
            }
            if (-not $seven) {
                $cached7zr = Join-Path $this.GetCacheBase() '7zr.exe'
                if (-not (Test-Path $cached7zr)) {
                    # download portable 7zr
                    Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile $cached7zr -UseBasicParsing -ErrorAction Stop
                }
                $seven = $cached7zr
            }

            # run extraction
            $args = @('x', $Source, "-o$OutPath", '-y')
            $proc = Start-Process -FilePath $seven -ArgumentList $args -NoNewWindow -Wait -PassThru
            return ($proc.ExitCode -eq 0)
        }
        catch {
            Write-Warning "Extract7z failed: $($_.Exception.Message)"
            return $false
        }
    }

    [string] GetPGit() {
        try {
            # 1) Existing local (prefer configured PGit)
            try { $local = $this.GetGitPath() } catch { $local = $null }
            if ($local) { return [string]$local }

            # 2) Fallback: query GitHub releases for PortableGit -64-bit.7z.exe
            $api = 'https://api.github.com/repos/git-for-windows/git/releases/latest'
            $headers = @{ 'User-Agent' = 'PS-GetPGit' }
            $rel = Invoke-RestMethod -Uri $api -Headers $headers -ErrorAction Stop
            $pattern = '(?i)^.*PortableGit.*-64-bit\.7z\.exe$'
            $asset = ($rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1)
            if ($asset) { return [string]$asset.browser_download_url }
            return $null
        }
        catch {
            Write-Warning "GetPGit error: $($_.Exception.Message)"
            return $null
        }
    }

    # InstallPGit method with pre-checks: detects local git version, compares to remote, avoids redownload if file exists,
    # extracts archive to Config.PGit, and obeys flags configured in this.Config.InstallOptions (Hashtable or PSCustomObject).
    # This method is intended to be pasted into a PowerShell class (as a method). It uses zero-argument InstallPGit() and reads flags
    # from this.Config.InstallOptions to avoid default parameter issues in PowerShell class methods.
    [pscustomobject] InstallPGit() {
        $result = [pscustomobject]@{
            Success       = $false
            Action        = $null
            Path          = $null
            LocalVersion  = $null
            RemoteVersion = $null
            Error         = $null
        }

        try {
            # ---------- Read flags from Config.InstallOptions (support Hashtable or PSCustomObject) ----------
            $opts = $null
            if ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config) {
                if ($this.Config -is [hashtable]) {
                    if ($this.Config.ContainsKey('InstallOptions') -and $this.Config['InstallOptions']) { $opts = $this.Config['InstallOptions'] }
                }
                else {
                    if ($this.Config.PSObject.Properties.Match('InstallOptions').Count -gt 0 -and $this.Config.InstallOptions) { $opts = $this.Config.InstallOptions }
                }
            }

            # read individual flags from opts (supports hashtable or object)
            $Force = $false; $AutoUpdate = $false; $WhatIf = $false
            if ($opts) {
                if ($opts -is [hashtable]) {
                    if ($opts.ContainsKey('Force')) { $Force = [bool]$opts['Force'] }
                    if ($opts.ContainsKey('AutoUpdate')) { $AutoUpdate = [bool]$opts['AutoUpdate'] }
                    if ($opts.ContainsKey('WhatIf')) { $WhatIf = [bool]$opts['WhatIf'] }
                }
                else {
                    if ($opts.PSObject.Properties.Match('Force').Count -gt 0) { $Force = [bool]$opts.Force }
                    if ($opts.PSObject.Properties.Match('AutoUpdate').Count -gt 0) { $AutoUpdate = [bool]$opts.AutoUpdate }
                    if ($opts.PSObject.Properties.Match('WhatIf').Count -gt 0) { $WhatIf = [bool]$opts.WhatIf }
                }
            }

            # ---------- Require Config.DLDir and Config.PGit (fail-fast) ----------
            if (-not ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config)) {
                Write-Error "Config is not set on this instance. Set this.Config before calling InstallPGit()."
                $result.Error = "Config missing"
                return $result
            }

            # DLDir
            $dlDir = $null
            if ($this.Config -is [hashtable]) {
                if ($this.Config.ContainsKey('DLDir') -and $this.Config['DLDir']) { $dlDir = $this.Config['DLDir'] }
            }
            else {
                if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0 -and $this.Config.DLDir) { $dlDir = $this.Config.DLDir }
            }
            if (-not $dlDir) {
                Write-Error "Config.DLDir is not set. Please set this.Config.DLDir before calling InstallPGit()."
                $result.Error = "Config.DLDir missing"
                return $result
            }
            if (-not (Test-Path $dlDir)) { New-Item -Path $dlDir -ItemType Directory -Force | Out-Null }

            # PGit
            $cfgPgit = $null
            if ($this.Config -is [hashtable]) {
                if ($this.Config.ContainsKey('PGit') -and $this.Config['PGit']) { $cfgPgit = $this.Config['PGit'] }
            }
            else {
                if ($this.Config.PSObject.Properties.Match('PGit').Count -gt 0 -and $this.Config.PGit) { $cfgPgit = $this.Config.PGit }
            }
            if (-not $cfgPgit) {
                Write-Error "Config.PGit is not set. Please set this.Config.PGit before calling InstallPGit()."
                $result.Error = "Config.PGit missing"
                return $result
            }

            # ---------- Detect existing git (local) ----------
            $localGitPath = $null; $localVersion = $null
            # prefer Config.PGit location if it exists
            if ($cfgPgit -and (Test-Path $cfgPgit)) {
                $foundLocal = Get-ChildItem -Path $cfgPgit -Filter 'git.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($foundLocal) { $localGitPath = $foundLocal.FullName }
            }
            # fallback to PATH
            if (-not $localGitPath) {
                $cmd = Get-Command git -ErrorAction SilentlyContinue
                if ($cmd -and $cmd.Path -and (Test-Path $cmd.Path)) { $localGitPath = $cmd.Path }
            }
            if ($localGitPath) {
                try {
                    $verOut = & $localGitPath --version 2>$null
                    # parse "git version X.Y.Z"
                    if ($verOut -match '([0-9]+(?:\.[0-9]+)+)') { $localVersion = $Matches[1] }
                    $result.LocalVersion = $localVersion
                }
                catch { $localVersion = $null }
            }

            # ---------- Determine remote/latest source via GetPGit() ----------
            $source = $this.GetPGit()
            if (-not $source) {
                Write-Error "GetPGit() returned null. Cannot determine remote PortableGit source."
                $result.Error = "GetPGit returned null"
                return $result
            }

            # If source is a local git.exe path, behave as adopt/local case
            if ($source -match 'git\.exe$' -and (Test-Path $source)) {
                $cmdDir = Split-Path $source; $gitRoot = Split-Path $cmdDir
                if ($this.Config -is [hashtable]) { $this.Config['PGit'] = $gitRoot } else { $this.Config.PGit = $gitRoot }
                $result.Success = $true; $result.Action = 'used-local'; $result.Path = $gitRoot
                return $result
            }

            # If source is a URL, try to infer remote version from filename (PortableGit-<ver>-64-bit.7z.exe)
            $remoteVersion = $null; $assetName = $null
            if ($source -match '^https?://') {
                $assetName = Split-Path $source -Leaf
                if ($assetName -match 'PortableGit-([0-9]+(?:\.[0-9]+)+)') { $remoteVersion = $Matches[1] }
                $result.RemoteVersion = $remoteVersion
            }
            else {
                # local archive
                $assetName = Split-Path $source -Leaf
                if ($assetName -match 'PortableGit-([0-9]+(?:\.[0-9]+)+)') { $remoteVersion = $Matches[1] }
                $result.RemoteVersion = $remoteVersion
            }

            # ---------- Compare versions if localVersion available ----------
            if ($localVersion -and $remoteVersion) {
                # basic semver compare by splitting numeric parts
                function Compare-SemVer($a, $b) {
                    $pa = $a -split '\.' | ForEach-Object { [int]$_ }
                    $pb = $b -split '\.' | ForEach-Object { [int]$_ }
                    for ($i = 0; $i -lt [Math]::Max($pa.Length, $pb.Length); $i++) {
                        $va = 0; $vb = 0
                        if ($i -lt $pa.Length) { $va = $pa[$i] }
                        if ($i -lt $pb.Length) { $vb = $pb[$i] }
                        if ($va -lt $vb) { return -1 }
                        if ($va -gt $vb) { return 1 }
                    }
                    return 0
                }

                $cmp = Compare-SemVer $localVersion $remoteVersion
                if ($cmp -ge 0 -and -not $Force) {
                    Write-Host "Local git version $localVersion is up-to-date (remote $remoteVersion). Nothing to do." -ForegroundColor Green
                    $result.Success = $true; $result.Action = 'uptodate'; $result.Path = Split-Path $localGitPath -Parent
                    return $result
                }
                # if local older
                if ($cmp -lt 0) {
                    if (-not $AutoUpdate) {
                        # interactive prompt to confirm update (unless WhatIf or Force)
                        if ($WhatIf) {
                            Write-Host "[WhatIf] Would update git from $localVersion to $remoteVersion"
                        }
                        else {
                            $confirm = Read-Host "Local git ($localVersion) is older than remote ($remoteVersion). Update? (Y/n)"
                            if ($confirm -ne '' -and $confirm -notmatch '^[Yy]') {
                                $result.Success = $false; $result.Action = 'cancelled'; $result.Path = Split-Path $localGitPath -Parent
                                return $result
                            }
                        }
                    }
                    # if AutoUpdate or user confirmed, proceed to download/install unless Force prevents? Force forces download anyway
                }
            }

            # ---------- Determine local archive path in dlDir (avoid re-download) ----------
            $dl = $null
            if ($assetName) {
                $candidate = Join-Path $dlDir $assetName
                if (Test-Path $candidate) { $dl = $candidate }
            }

            # If no local archive present or Force requested, download from remote source
            if (-not $dl) {
                if ($source -match '^https?://') {
                    $dl = Join-Path $dlDir (Split-Path $source -Leaf)
                    if ($Force -or -not (Test-Path $dl)) {
                        if ($WhatIf) { Write-Host "[WhatIf] Would download $source -> $dl" }
                        else {
                            try {
                                Invoke-WebRequest -Uri $source -OutFile $dl -UseBasicParsing -ErrorAction Stop
                            }
                            catch {
                                Write-Error "Download failed: $($_.Exception.Message)"
                                $result.Error = "Download failed"
                                return $result
                            }
                        }
                    }
                    else {
                        Write-Host "Using existing archive: $dl" -ForegroundColor DarkGray
                    }
                }
                else {
                    # source is a local archive path (not URL)
                    if (Test-Path $source) { $dl = $source } else {
                        Write-Error "Source archive not found: $source"
                        $result.Error = "Source missing"
                        return $result
                    }
                }
            }

            # ---------- Extract using Extract7z ----------
            if (-not ($this.PSObject.Methods.Match('Extract7z').Count -gt 0)) {
                Write-Error "Extract7z method not found in class."
                $result.Error = "Extract7z missing"
                return $result
            }

            if ($WhatIf) {
                Write-Host "[WhatIf] Would extract $dl -> $cfgPgit"
            }
            else {
                $ok = $this.Extract7z($dl, $cfgPgit)
                if (-not $ok) {
                    Write-Error "Extraction failed for $dl -> $cfgPgit"
                    $result.Error = "Extraction failed"
                    return $result
                }
            }

            # ---------- verify installation ----------
            $foundFinal = Get-ChildItem -Path $cfgPgit -Filter 'git.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $foundFinal) {
                Write-Error "Installation completed but git.exe not found under $cfgPgit"
                $result.Error = "git.exe missing"
                return $result
            }

            $gitRoot = Split-Path (Split-Path $foundFinal.FullName)
            if ($this.Config -is [hashtable]) { $this.Config['PGit'] = $gitRoot } else { $this.Config.PGit = $gitRoot }

            $result.Success = $true
            $result.Action = 'installed'
            $result.Path = $gitRoot
            $result.LocalVersion = $remoteVersion  # after install assume remote version installed
            return $result
        }
        catch {
            Write-Error "InstallPGit failed: $($_.Exception.Message)"
            $result.Error = $_.Exception.Message
            return $result
        }
    }
    [string] GetNvTool([string]$tool) {
        return $this.GetNvTool($tool, $true)
    }
    [string] GetNvTool([string]$tool, [bool]$CheckExists = $false) {
        <#
    Generic fetcher for NVIDIA toolkit installers (cuda, cudnn).
    Returns installer URL (string) or $null on failure.
    Side-effects: NONE (will NOT set $this.NVTool, $this.NVToolLatestVersion, $this.NVToolInstallerUrl, $this.NVToolInstallerExists).
    #>
        $archiveUrl = $null 
        $downloadTemplate = $null 
        try {
            if (-not $tool) { throw "Tool name required (e.g. 'cuda' or 'cudnn')." }
            $t = $tool.ToLower().Trim()

            switch ($t) {
                'cuda' {
                    $archiveUrl = "https://developer.nvidia.com/cuda-toolkit-archive"
                    $downloadTemplate = "https://developer.download.nvidia.com/compute/cuda/{0}/local_installers/cuda_{0}_windows.exe"
                }
                'cudnn' {
                    $archiveUrl = "https://developer.nvidia.com/cudnn-archive"
                    $downloadTemplate = "https://developer.download.nvidia.com/compute/cudnn/{0}/local_installers/cudnn_{0}_windows_x86_64.exe"
                }
                default {
                    throw "Unsupported tool: $tool. Supported: cuda, cudnn."
                }
            }

            Write-Host "Fetching archive page for '$t': $archiveUrl"
            $resp = Invoke-WebRequest -Uri $archiveUrl -UseBasicParsing -ErrorAction Stop
            $html = $resp.Content

            $candidates = New-Object System.Collections.Generic.HashSet[string]

            if ($t -eq 'cuda') {
                $pat = '(?is)Latest[^\S\r\n]*(?:<[^>]+>)*[^\S\r\n]*.*?CUDA(?:\s|<[^>]+>)*Toolkit(?:\s|<[^>]+>)*([0-9]+(?:\.[0-9]+){1,2})'
                $m = [regex]::Match($html, $pat)
                if ($m.Success) { $candidates.Add($m.Groups[1].Value.Trim()) | Out-Null }
            }
            else {
                $pat2 = '(?is)Latest[^\S\r\n]*(?:<[^>]+>)*[^\S\r\n]*.*?cuDNN(?:\s|<[^>]+>)*([0-9]+(?:\.[0-9]+){1,2})'
                $m2 = [regex]::Match($html, $pat2)
                if ($m2.Success) { $candidates.Add($m2.Groups[1].Value.Trim()) | Out-Null }
            }

            if ($resp.Links) {
                foreach ($lnk in $resp.Links) {
                    $text = ($lnk.innerText -as [string]) -replace "`r|`n", " "
                    foreach ($mm in [regex]::Matches($text, '([0-9]+(?:\.[0-9]+){1,2})')) {
                        $candidates.Add($mm.Groups[1].Value) | Out-Null
                    }
                }
            }
            else {
                foreach ($mm in [regex]::Matches($html, '([0-9]+(?:\.[0-9]+){1,2})')) {
                    $candidates.Add($mm.Groups[1].Value) | Out-Null
                }
            }

            if ($candidates.Count -eq 0) {
                Write-Warning "No version candidates found on archive page for '$t'."
                return $null
            }

            $norm = @()
            foreach ($v in $candidates) {
                $parts = ($v -split '\.')
                if ($parts.Count -eq 2) { $parts += '0' }
                while ($parts.Count -lt 3) { $parts += '0' }
                $major = [int]$parts[0]; $minor = [int]$parts[1]; $patch = [int]$parts[2]
                $score = $major * 1000000 + $minor * 1000 + $patch
                $norm += [pscustomobject]@{ Ver = "$major.$minor.$patch"; Score = $score }
            }

            $best = ($norm | Sort-Object -Property Score -Descending | Select-Object -First 1)
            $version = $best.Ver
            Write-Host "Selected latest version for $t : $version"

            $installerUrl = [string]::Format($downloadTemplate, $version)
            Write-Host "Mapped installer URL: $installerUrl"

            $exists = $null
            if ($CheckExists) {
                try {
                    $h = Invoke-WebRequest -Uri $installerUrl -Method Head -UseBasicParsing -Headers @{ 'User-Agent' = 'PS-GetNvTool' } -TimeoutSec 15 -ErrorAction Stop
                    $exists = ($h.StatusCode -eq 200)
                    Write-Host "HEAD status: $($h.StatusCode)"
                }
                catch {
                    try {
                        $g = Invoke-WebRequest -Uri $installerUrl -Method Get -UseBasicParsing -Headers @{ 'User-Agent' = 'PS-GetNvTool' } -TimeoutSec 15 -MaximumRedirection 0 -ErrorAction Stop
                        $exists = ($g.StatusCode -eq 200)
                        Write-Host "GET status: $($g.StatusCode)"
                    }
                    catch {
                        Write-Warning "Existence check failed or returned non-200. This is common for cuDNN (may require login/redirect)."
                        $exists = $false
                    }
                }
            }

            # NOTE: intentionally do NOT set any $this.* NVTool fields here to avoid side-effects
            return $installerUrl
        }
        catch {
            Write-Error "GetNvTool($tool) failed: $($_.Exception.Message)"
            return $null
        }
    }
    # Updated InstallNvidia() and CopyNvidia() methods
    # Behavior:
    # - Downloaded installer (e.g. cuda_13.0.2_windows.exe) is stored in this.Config.DLDir
    # - Extract7z extracts the archive into this.Config.DLDir\<archive-base-name> (e.g. cuda_13.0.2_windows)
    # - CopyNvidia('cuda') copies only the exact target DLL filenames (listed below) from the extracted folder(s)
    #   into this.Config.CudaBin (driver\CUDA). CopyNvidia('cudnn') copies cudnn targets into this.Config.CuDNNBin.
    # - No nvcc.exe verification; presence of target files is used to determine success.
    # - Both methods are "fail-fast": require Config.DLDir and Config.CudaBin / Config.CuDNNBin to be set.
    #
    # Paste these methods into your class (PowerShell). They assume Extract7z() and GetNvTool() exist in the class.
    # They return PSCustomObject summary (InstallNvidia) and void for CopyNvidia (but set instance summary props).

    [pscustomobject] InstallNvidia([string] $Component) {
        $summary = [pscustomobject]@{
            Success = $false
            Details = @()
            Error   = $null
        }

        try {

           
            # Validate component (strict, fail-fast)
            if (-not $Component) {
                Write-Host "Component required: 'cuda','cudnn' or 'all'"
                $summary.Error = 'Component missing'
                return $summary
            }

            $compNorm = $Component.ToLower().Trim()
            if ($compNorm -notin @('cuda', 'cudnn', 'all')) {
                Write-Host "Component required: 'cuda','cudnn' or 'all'"
                $summary.Error = "Unsupported component: $Component"
                return $summary
            }
            $requested = @()
            switch ($compNorm) {
                'cuda' { $requested = @('cuda') }
                'cudnn' { $requested = @('cudnn') }
                'all' { $requested = @('cuda', 'cudnn') }
            }

            # require Config.DLDir
            if (-not ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config)) {
                Write-Error "Config not set on instance. Set this.Config before calling InstallNvidia()."; $summary.Error = 'Config missing'; return $summary
            }

            # resolve DLDir
            $dlDir = $null
            if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('DLDir')) { $dlDir = $this.Config['DLDir'] } }
            else { if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0) { $dlDir = $this.Config.DLDir } }
            if (-not $dlDir) { Write-Error "Config.DLDir not set. Set this.Config.DLDir before calling."; $summary.Error = 'DLDir missing'; return $summary }
            if (-not (Test-Path $dlDir)) { New-Item -Path $dlDir -ItemType Directory -Force | Out-Null }

            # require target bins
            $cudaBin = $null; $cudnnBin = $null
            if ($this.Config -is [hashtable]) {
                if ($this.Config.ContainsKey('CudaBin')) { $cudaBin = $this.Config['CudaBin'] }
                if ($this.Config.ContainsKey('CuDNNBin')) { $cudnnBin = $this.Config['CuDNNBin'] }
            }
            else {
                if ($this.Config.PSObject.Properties.Match('CudaBin').Count -gt 0) { $cudaBin = $this.Config.CudaBin }
                if ($this.Config.PSObject.Properties.Match('CuDNNBin').Count -gt 0) { $cudnnBin = $this.Config.CuDNNBin }
            }
            if (-not $cudaBin -and $requested -contains 'cuda') { Write-Error "Config.CudaBin not set. Set this.Config.CudaBin (driver\\CUDA)"; $summary.Error = 'CudaBin missing'; return $summary }
            if (-not $cudnnBin -and $requested -contains 'cudnn') { Write-Error "Config.CuDNNBin not set. Set this.Config.CuDNNBin (driver\\CUDNN)"; $summary.Error = 'CuDNNBin missing'; return $summary }
            if ($cudaBin -and -not (Test-Path $cudaBin)) { New-Item -Path $cudaBin -ItemType Directory -Force | Out-Null }
            if ($cudnnBin -and -not (Test-Path $cudnnBin)) { New-Item -Path $cudnnBin -ItemType Directory -Force | Out-Null }

            foreach ($comp in $requested) {
                $detail = [pscustomobject]@{ Component = $comp; Success = $false; Archive = $null; ExtractDir = $null; Copied = 0; Missing = @(); Error = $null }

                try {
                    $source = $this.GetNvTool($comp, $true)
                    if (-not $source) { $detail.Error = "GetNvTool returned null"; $summary.Details += $detail; continue }

                    # if URL -> check existing archive in dlDir; else if local path, use directly
                    if ($source -match '^https?://') {
                        $leaf = Split-Path $source -Leaf
                        $candidate = Join-Path $dlDir $leaf
                        if (Test-Path $candidate) { $archive = $candidate }
                        else {
                            try { Invoke-WebRequest -Uri $source -OutFile $candidate -UseBasicParsing -ErrorAction Stop; $archive = $candidate }
                            catch { $detail.Error = "Download failed: $($_.Exception.Message)"; $summary.Details += $detail; continue }
                        }
                    }
                    else {
                        if (Test-Path $source) { $archive = $source } else { $detail.Error = "Local source not found: $source"; $summary.Details += $detail; continue }
                    }
                    $detail.Archive = $archive

                    # extract into dlDir\<archive-base-name>
                    $base = Split-Path $archive -LeafBase
                    $outdir = Join-Path $dlDir $base
                    if (-not (Test-Path $outdir)) { New-Item -Path $outdir -ItemType Directory -Force | Out-Null }
                    $detail.ExtractDir = $outdir

                    if (-not ($this.PSObject.Methods.Match('Extract7z').Count -gt 0)) { $detail.Error = 'Extract7z missing'; $summary.Details += $detail; continue }
                    $ok = $this.Extract7z($archive, $outdir)
                    if (-not $ok) { $detail.Error = "Extract failed"; $summary.Details += $detail; continue }

                    # After extraction, copy targets
                    if ($comp -eq 'cuda') {
                        $copied_summary = $this.CopyNvidia('cuda')  # CopyNvidia will set instance properties and return nothing; it will locate files under dlDir candidates
                    }
                    else {
                        $copied_summary = $this.CopyNvidia('cudnn')
                    }

                    # summarize by checking instance Missing/Copied lists if available
                    if ($comp -eq 'cuda') {
                        try { $detail.Copied = ($this.CopiedCudaFiles.Count) } catch {}
                        try { $detail.Missing = $this.MissingCudaFiles } catch {}
                    }
                    else {
                        try { $detail.Copied = ($this.CopiedCudnnFiles.Count) } catch {}
                        try { $detail.Missing = $this.MissingCudnnFiles } catch {}
                    }

                    $detail.Success = $true
                    $summary.Details += $detail
                }
                catch {
                    $detail.Error = $_.Exception.Message
                    $summary.Details += $detail
                }
            }

            $summary.Success = ($summary.Details | Where-Object { $_.Success -eq $false }).Count -eq 0
            return $summary
        }
        catch {
            Write-Error "InstallNvidia failed:  $($_.Exception.Message)"
            $summary.Error = $_.Exception.Message
            return $summary
        }
    }


    [void] CopyNvidia([string]$Component) {
        try {
            if (-not $Component) { Write-Error "Component required"; return }
            $c = $Component.ToLower().Trim()
            # hardcoded target lists (exact filenames)
            if ($c -eq 'cuda') {
                $targets = @(
                    "cublas64_13.dll", "cublasLt64_13.dll", "cudart64_13.dll", "cufft64_12.dll", "cufftw64_12.dll",
                    "curand64_10.dll", "cusolver64_12.dll", "cusolverMg64_12.dll", "cusparse64_12.dll",
                    "nppc64_13.dll", "nppial64_13.dll", "nppicc64_13.dll", "nppidei64_13.dll", "nppif64_13.dll",
                    "nppig64_13.dll", "nppim64_13.dll", "nppist64_13.dll", "nppisu64_13.dll", "nppitc64_13.dll",
                    "npps64_13.dll", "nvblas64_13.dll", "nvfatbin_130_0.dll", "nvJitLink_130_0.dll", "nvjpeg64_13.dll",
                    "nvrtc-builtins64_130.dll", "nvrtc64_130_0.alt.dll", "nvrtc64_130_0.dll", "nvvm64_40_0.dll"
                )
                $dest = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('CudaBin')) { $dest = $this.Config['CudaBin'] } }
                else { if ($this.Config.PSObject.Properties.Match('CudaBin').Count -gt 0) { $dest = $this.Config.CudaBin } }
                if (-not $dest) { Write-Error "Config.CudaBin not set"; return }
            }
            elseif ($c -eq 'cudnn') {
                $targets = @(
                    "cudnn_adv64_9.dll", "cudnn_cnn64_9.dll", "cudnn_engines_precompiled64_9.dll",
                    "cudnn_engines_runtime_compiled64_9.dll", "cudnn_graph64_9.dll", "cudnn_heuristic64_9.dll",
                    "cudnn_ops64_9.dll", "cudnn64_9.dll"
                )
                $dest = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('CuDNNBin')) { $dest = $this.Config['CuDNNBin'] } }
                else { if ($this.Config.PSObject.Properties.Match('CuDNNBin').Count -gt 0) { $dest = $this.Config.CuDNNBin } }
                if (-not $dest) { Write-Error "Config.CuDNNBin not set"; return }
            }
            else {
                Write-Error "Unsupported component: $Component"; return
            }

            # Ensure dest exists
            if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory -Force | Out-Null }

            # Candidate source directories: DLDir\<component>, DLDir, extracted subfolders
            $dlRoot = $null
            if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('DLDir')) { $dlRoot = $this.Config['DLDir'] } }
            else { if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0) { $dlRoot = $this.Config.DLDir } }
            if (-not $dlRoot) { Write-Error "Config.DLDir not set"; return }

            $candidates = @()
            $candidates += (Join-Path $dlRoot $c)
            $candidates += $dlRoot

            # include any extracted subfolders inside dlRoot (first level)
            try {
                $firstLevel = Get-ChildItem -Path $dlRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
                foreach ($d in $firstLevel) { $candidates += $d }
            }
            catch {}

            # also include configured runtime bins
            if ($this -and $this.PSObject.Properties.Match('CudaBin').Count -gt 0 -and $this.CudaBin) { $candidates += $this.CudaBin }
            if ($this -and $this.PSObject.Properties.Match('CuDNNBin').Count -gt 0 -and $this.CuDNNBin) { $candidates += $this.CuDNNBin }

            # normalize and filter existing
            $candidates = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

            $copied = New-Object System.Collections.Generic.List[string]
            $missing = New-Object System.Collections.Generic.List[string]
            $errors = New-Object System.Collections.Generic.List[psobject]

            foreach ($t in $targets) {
                $found = $null
                foreach ($srcRoot in $candidates) {
                    try {
                        $srcFile = Join-Path -Path $srcRoot -ChildPath $t
                        if (Test-Path $srcFile) { $found = $srcFile; break }
                        # case-insensitive search
                        $g = Get-ChildItem -Path $srcRoot -Filter $t -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($g) { $found = $g.FullName; break }
                    }
                    catch {}
                }
                if ($found) {
                    try {
                        $destFile = Join-Path -Path $dest -ChildPath $t
                        Copy-Item -Path $found -Destination $destFile -Force -ErrorAction Stop
                        $copied.Add($t) | Out-Null
                    }
                    catch {
                        $errors.Add([pscustomobject]@{ File = $t; Error = $_.Exception.Message }) | Out-Null
                    }
                }
                else { $missing.Add($t) | Out-Null }
            }

            # write summaries back to instance
            $uc = ($c.Substring(0, 1).ToUpper() + $c.Substring(1))
            try { $this."Copied${uc}Files" = $copied } catch {}
            try { $this."Missing${uc}Files" = $missing } catch {}
            try { $this."Copy${uc}Errors" = $errors } catch {}

            Write-Host "CopyNvidia($Component) done. Copied: $($copied.Count). Missing: $($missing.Count). Errors: $($errors.Count)" -ForegroundColor Green
        }
        catch {
            Write-Error "CopyNvidia failed: $($_.Exception.Message)"
        }
    }
    # Helper: prepend only unique, existing paths to session PATH
    [void] PrependUniquePathItems([string[]] $Items) {
        if (-not $env:Path) { $env:Path = '' }
        $sessionItems = ($env:Path -split ';' | Where-Object { $_ -ne '' })

        $toPrepend = New-Object System.Collections.Generic.List[string]

        foreach ($item in $Items) {
            if (-not $item) { continue }
            # normalize path: resolve relative -> absolute if possible
            $resolved = $null
            try {
                if (Test-Path $item) { $resolved = (Get-Item $item).FullName.TrimEnd('\') }
                else { $resolved = $item } # keep as-is (may be fixed later)
            }
            catch {
                $resolved = $item
            }

            if ($resolved -and (Test-Path $resolved)) {
                $exists = $false
                foreach ($si in $sessionItems) {
                    if ($si -ieq $resolved) { $exists = $true; break }
                }
                if (-not $exists) { $null = $toPrepend.Add($resolved) }
            }
        }

        if ($toPrepend.Count -gt 0) {
            $newSession = ($toPrepend + $sessionItems) -join ';'
            $env:Path = $newSession
            Write-Host "Prepended $($toPrepend.Count) PATH entries to session PATH."
        }
        else {
            Write-Host "No new PATH entries were added (all present or not found)." -ForegroundColor Yellow
        }
    }

    # Setup PATH and aliases for current session. If $Persist = $true, persist to User PATH.
    [void] SetupPath([bool]$Persist = $false) {
        # prefer config.RootDir or AbsRoot if present
        $cfg = $this.Config
        $root = $null
        if ($cfg) {
            if ($cfg -is [hashtable]) {
                if ($cfg.ContainsKey('RootDir') -and $cfg['RootDir']) { $root = $cfg['RootDir'] }
            }
            else {
                if ($cfg.PSObject.Properties.Match('RootDir').Count -gt 0 -and $cfg.RootDir) { $root = $cfg.RootDir }
            }
        }
        if (-not $root -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0 -and $this.AbsRoot) { $root = $this.AbsRoot }
        if (-not $root) { Write-Host "SetupPath: RootDir/AbsRoot not set; abort." -ForegroundColor Red; return }

        # Helper to resolve config path (if relative, make absolute under $root)
        function ResolveCfgPath([string] $p) {
            if (-not $p) { return $null }
            try {
                if (Test-Path $p) { return (Get-Item $p).FullName.TrimEnd('\') }
                # attempt relative to root
                $maybe = Join-Path $root $p
                if (Test-Path $maybe) { return (Get-Item $maybe).FullName.TrimEnd('\') }
            }
            catch {}
            return $p
        }

        # Build candidate directories (strings guaranteed by SetConfig ideally)
        $candidates = @()
        $py = ResolveCfgPath(($cfg -is [hashtable] ? $cfg['PyDir'] : $cfg.PyDir))
        if ($py) {
            $candidates += $py
            $candidates += (Join-Path $py 'Scripts')
        }
        $cudaBin = ResolveCfgPath(($cfg -is [hashtable] ? $cfg['CudaBin'] : $cfg.CudaBin))
        $cuDNNBin = ResolveCfgPath(($cfg -is [hashtable] ? $cfg['CuDNNBin'] : $cfg.CuDNNBin))
        if ($cudaBin) { $candidates += $cudaBin }
        if ($cuDNNBin) { $candidates += $cuDNNBin }

        $pgit = ResolveCfgPath(($cfg -is [hashtable] ? $cfg['PGit'] : $cfg.PGit))
        if ($pgit) {
            $candidates += (Join-Path $pgit 'cmd')
            $candidates += (Join-Path $pgit 'bin')
            $candidates += (Join-Path $pgit 'mingw64\bin')
        }

        # Collect existing directories (normalized)
        $existing = New-Object System.Collections.Generic.List[string]
        foreach ($p in $candidates) {
            if ($p -and (Test-Path $p)) {
                try { $full = (Get-Item $p).FullName.TrimEnd('\') } catch { $full = $p }
                if (-not ($existing -contains $full)) { $null = $existing.Add($full) }
            }
        }

        if ($existing.Count -eq 0) {
            Write-Host "SetupPath: No candidate directories exist under $root. Nothing changed." -ForegroundColor Yellow
        }
        else {
            # Prepend to session PATH (unique)
            $this.PrependUniquePathItems($existing)
            Write-Host "SetupPath: Prepend $($existing.Count) directories to session PATH:" -ForegroundColor Cyan
            foreach ($e in $existing) { Write-Host "  + $e" }
        }

        # Detect executables now that env:Path is updated
        $detected = $this.DetectExecutables($existing)

        # Create session-only functions/aliases for python/pip/git
        try { $this.CreateSessionAliases($detected) } catch {}

        # Optionally persist to User PATH
        if ($Persist -and $existing.Count -gt 0) {
            try {
                $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User') -or ''
                $userItems = ($currentUserPath -split ';' | Where-Object { $_ -ne '' })
                $toPrepend = New-Object System.Collections.Generic.List[string]
                foreach ($e in $existing) {
                    $found = $false
                    foreach ($ui in $userItems) { if ($ui -ieq $e) { $found = $true; break } }
                    if (-not $found) { $null = $toPrepend.Add($e) }
                }
                if ($toPrepend.Count -gt 0) {
                    $newUserPath = ($toPrepend + $userItems) -join ';'
                    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
                    Write-Host "SetupPath: Persisted $($toPrepend.Count) entries to User PATH." -ForegroundColor Green
                }
                else {
                    Write-Host "SetupPath: No new entries to persist to User PATH." -ForegroundColor Green
                }
            }
            catch {
                Write-Host "SetupPath: Failed to persist PATH to User: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Print quick checks (session)
        Write-Host "`nQuick checks (session):" -ForegroundColor Green
        try { & python --version } catch { Write-Host "  python: (not available or redirected to Store)"; }
        try { & python -m pip --version } catch { Write-Host "  pip: (not available)"; }
        try { & git --version } catch { Write-Host "  git: (not available)"; }
    }

    # Detect executables. Accept existing dirs list (optional) to prefer local ones.
    [hashtable] DetectExecutables([string[]]$existingDirs) {
        $result = @{
            python                  = $null
            pip                     = $null
            git                     = $null
            pip_using_python_module = $false
        }

        # Helper: prefer existingDirs (normalized) when searching
        $existing = @()
        if ($existingDirs) {
            foreach ($d in $existingDirs) { if ($d -and (Test-Path $d)) { $existing += (Get-Item $d).FullName.TrimEnd('\') } }
        }

        # 1) Prefer Get-Command (system aware)
        foreach ($name in @('python', 'python3')) {
            try {
                $cmd = Get-Command $name -ErrorAction Stop
                if ($cmd -and $cmd.Path) { $result.python = $cmd.Path; break }
            }
            catch {}
        }

        # 2) fallback to local pyDir python.exe if present (prefer existingDirs)
        if (-not $result.python) {
            $candPaths = @()
            if ($existing.Count -gt 0) { foreach ($e in $existing) { $candPaths += (Join-Path $e 'python.exe') } }
            # also check configured PyDir
            try {
                $py = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('PyDir')) { $py = $this.Config['PyDir'] } }
                else { if ($this.Config.PSObject.Properties.Match('PyDir').Count -gt 0) { $py = $this.Config.PyDir } }
                if ($py) { $candPaths += (Join-Path $py 'python.exe') }
            }
            catch {}
            foreach ($cand in $candPaths) {
                if (Test-Path $cand) { $result.python = (Get-Item $cand).FullName; break }
            }
        }

        # 3) pip: prefer pip executable in Scripts or system pip, else python -m pip
        try {
            $cmdpip = Get-Command pip -ErrorAction Stop
            if ($cmdpip -and $cmdpip.Path) { $result.pip = $cmdpip.Path }
        }
        catch {}
        if (-not $result.pip) {
            $pCandidates = @()
            if ($existing.Count -gt 0) { foreach ($e in $existing) { $pCandidates += (Join-Path $e 'Scripts\pip.exe'); $pCandidates += (Join-Path $e 'Scripts\pip3.exe') } }
            try {
                $py = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('PyDir')) { $py = $this.Config['PyDir'] } }
                else { if ($this.Config.PSObject.Properties.Match('PyDir').Count -gt 0) { $py = $this.Config.PyDir } }
                if ($py) { $pCandidates += (Join-Path $py 'Scripts\pip.exe'); $pCandidates += (Join-Path $py 'Scripts\pip3.exe') }
            }
            catch {}
            foreach ($pc in $pCandidates) {
                if (Test-Path $pc) { $result.pip = (Get-Item $pc).FullName; break }
            }
            if (-not $result.pip -and $result.python) { $result.pip_using_python_module = $true }
        }

        # 4) git: Get-Command, then PGit candidates, then recursive search fallback
        try {
            $cmdgit = Get-Command git -ErrorAction Stop
            if ($cmdgit -and $cmdgit.Path) { $result.git = $cmdgit.Path }
        }
        catch {
            # try portable git configured path
            try {
                $pg = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('PGit')) { $pg = $this.Config['PGit'] } }
                else { if ($this.Config.PSObject.Properties.Match('PGit').Count -gt 0) { $pg = $this.Config.PGit } }
                if ($pg) {
                    $cands = @(
                        Join-Path $pg 'cmd\git.exe',
                        Join-Path $pg 'bin\git.exe',
                        Join-Path $pg 'mingw64\bin\git.exe'
                    )
                    foreach ($g in $cands) { if (Test-Path $g) { $result.git = (Get-Item $g).FullName; break } }
                }
            }
            catch {}

            # last-resort: search under python_embeded tree if nothing found
            try {
                $root = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('RootDir')) { $root = $this.Config['RootDir'] } }
                else { if ($this.Config.PSObject.Properties.Match('RootDir').Count -gt 0) { $root = $this.Config.RootDir } }
                if (-not $root -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0) { $root = $this.AbsRoot }
                if ($root) {
                    $pe = Join-Path $root 'python_embeded'
                    if (Test-Path $pe) {
                        $found = Get-ChildItem -Path $pe -Recurse -Filter 'git.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found) { $result.git = $found.FullName }
                    }
                }
            }
            catch {}
        }

        return $result
    }
    # Create session-only function aliases pointing to resolved executables
    [void] CreateSessionAliases([hashtable]$detected) {
        function _MakeFunction($name, $exePath, [bool]$usePythonModule = $false) {
            if (-not $exePath) { return }
            if ($usePythonModule) {
                $sb = "param([Parameter(ValueFromRemainingArguments=`$true)] `$Args) & `"$exePath`" -m pip @Args"
            }
            else {
                $sb = "param([Parameter(ValueFromRemainingArguments=`$true)] `$Args) & `"$exePath`" @Args"
            }
            try {
                Set-Item -Path ("Function:\" + $name) -Value ([ScriptBlock]::Create($sb)) -Force
                Write-Host "Alias/function '$name' -> $exePath (session only)"
            }
            catch {
                Write-Host "Failed to create function $name : $_" -ForegroundColor Yellow
            }
        }

        # python
        if ($detected.python) { _MakeFunction 'python' $detected.python }
        else { Write-Host "python not found via detection." -ForegroundColor Yellow }

        # pip
        if ($detected.pip) { _MakeFunction 'pip' $detected.pip }
        elseif ($detected.pip_using_python_module -and $detected.python) { _MakeFunction 'pip' $detected.python $true }
        else { Write-Host "pip not available." -ForegroundColor Yellow }

        # git
        if ($detected.git) { _MakeFunction 'git' $detected.git }
        else { Write-Host "git not found." -ForegroundColor Yellow }
    }
    
    # เมทอดสำหรับติดตั้งตาม flow ที่ต้องการ
    [void] InstallFlow([bool] $WhatIf = $false, [bool] $AutoRemove = $false, [bool] $BackupExisting = $true) {
        # 1) show menu (interactive) -> returns version string or $null
        $version = $this.ShowPythonVersionsMenu()
        if (-not $version) { Write-Host "No version selected. Aborting." -ForegroundColor Yellow; return }

        Write-Host "Selected version: $version" -ForegroundColor DarkGray

        # 2) check existing python (interactive prompt inside CheckPython will ask unless $AutoRemove = $true)
        $ok = $this.CheckPython($version, $AutoRemove, $BackupExisting, $WhatIf)
        if (-not $ok) { Write-Host "CheckPython declined or failed. Aborting." -ForegroundColor Yellow; return }

        # 3) download + copy
        # $downloadOk = $this.DownloadAndCopyPython($version, $false, $false, $false)
        $downloadOk = $this.DownloadAndCopyPython($version, $WhatIf, $false, $BackupExisting)
        if (-not $downloadOk) { Write-Warning "DownloadAndCopyPython failed. Aborting."; return }

        # 4) get pip
        $pipOk = $this.GetPip($false)
        if (-not $pipOk) { Write-Warning "GetPip failed. Please run manually."; return }

        Write-Host "Installation complete: $version" -ForegroundColor Green

        $GitOk = $this.InstallPGit()
        if (-not $GitOk) { Write-Warning "Get Git failed. Please run manually."; return }

         
        $NvidiaOk = $this.InstallNvidia('All')

        if (-not $NvidiaOk) { Write-Warning "Instal lNvidia Cuda and Cudnn failed. Please run manually."; return }

        $this.SetupPath($true)
    }

   

    
    [void] Run() {
        Write-Host "RUN DEMO" 
        if (-not $this.IsFolder()) {
            Write-Host "One or more folders are missing. Creating folders (Skip mode)..." -ForegroundColor Yellow
            # CreateFolders() default overload will create (Skip existing)
            $this.CreateFolders()
        }
        else { Write-Host "All folders exist. Nothing to do." -ForegroundColor Green }
         
        $res = $this.TestPythonGlobal($true)
        $fmt = $res | Format-List * | Out-String
        Write-Host $fmt
        $this.InstallPGit($true)
        Write-Host $this.GetNvTool('cuda')
        Write-Host $this.GetNvTool('cunvv')
        $this.InstallNvidia('All')
        $this.SetupPath($true)
    }
    
}

# ------------- USAGE -------------
#[PythonDev]::new().Run()
#[PythonDev]::new().InstallFlow($false, $false, $false) 
# $mgr = [PythonDev]::new()
# $res = $mgr.TestPythonGlobal($false)
# $res | Format-List *
# $pd = [PythonDev]::new('C:\AI-Driver\Custamer-dev\TEST')   # ตัวอย่าง ถ้าคลาสชื่อ PythonDev
# # หรือเรียก SetPath ถ้าคลาสมีเมธอดนั้น
# $pd.SetPath('C:\AI-Driver\Custamer-dev\TEST')

# # ตรวจสอบ GetCacheBase และ GetPGit
# $pd.GetCacheBase()
# $urlOrLocal = $pd.GetPGit()
# Write-Host "GetPGit => $urlOrLocal"
# $pd.Config.GetType().FullName
# # เรียก InstallPGit (จะดาวน์โหลด/แตก ถาจำเป็น)
# $r = $pd.InstallPGit()
# $r | Format-List *
# All install python + pip + cuda 13.0 + cudnn 
# [PythonDev]::new().InstallFlow($false, $false, $false) 
#ls version Python

# $data = [PythonDev]::new()
# $version = "3.12.10"
# $data.DownloadAndCopyPython($version, $false, $false, $false)
# $data.GetPip($false)
# $data.InstallPGit()
# $data.InstallNvidia('cuda')
# $data.InstallNvidia('cudnn')
# $data.SetupPath($true)
[PythonDev]::new().SetupPath($true) 
 
