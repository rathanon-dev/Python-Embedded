class Main {
    <# Define the class. Try constructors, properties, or methods. #>
    [hashtable] $Config
    [hashtable] $Cache
    [string]    $RootDir
    [string]    $Report
  
    # Constructor: custom root (no auto-create)
    Main([string] $rootDir) {
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
    Main() {
        $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $root = [System.IO.Path]::GetFullPath($root)
        Write-Host "Path Default : $root" -ForegroundColor Green
        $this.SetPath($root)
    }

    # SetPath: validate and assign config (does NOT create folders)
    [void] SetPath([string] $rootDir) {
        try {
            if (-not $rootDir -or [string]::IsNullOrWhiteSpace($rootDir)) { throw [System.ArgumentException]::new("rootDir is null, empty or whitespace.") }
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
                FFmpeg   = Join-Path $absRoot "driver\ffmpeg"
            }

            # assign properties only after computed successfully
            $this.RootDir = $absRoot
            $this.Config = $newConfig
            if (-not $this.Cache) { $this.Cache = @{} }
            Write-Host "PythonManager initialized (root: $($this.RootDir))" -ForegroundColor DarkGray

            if (-not (Test-Path -Path $absRoot)) { Write-Warning "RootDir set to '$absRoot' but the directory does not exist. Call CreateFolders('Skip'| 'Backup' | 'Recreate') to create as needed." }
            else { Write-Host "Config set for RootDir: $absRoot" -ForegroundColor DarkGray }
        }
        catch { Write-Warning "SetPath() failed: $($_.Exception.GetType().Name) - $($_.Exception.Message)" }
    }
    # Helper: return first non-empty property/value from provided names
    # - ถ้าไม่ส่ง $Target จะใช้ $this ตามเดิม
    # - รองรับทั้ง PSObject และ hashtable
    [string] GetFirstNonNull([string[]] $names, [object] $Target = $null) {
        try {
            if (-not $Target) { $Target = $this }
            if (-not $Target) { return $null }

            foreach ($n in $names) {
                if (-not $n) { continue }

                $val = $null

                # กรณีเป็น hashtable
                if ($Target -is [hashtable]) {
                    if ($Target.ContainsKey($n)) {
                        $val = $Target[$n]
                    }
                }
                else {
                    # กรณีเป็น object ปกติ (PSCustomObject / class)
                    if ($Target.PSObject.Properties.Match($n).Count -gt 0) {
                        $val = $Target.$n
                    }
                }

                if ($null -ne $val) {
                    # ถ้าเป็น string ว่างหรือ whitespace ให้ถือว่า "ไม่มีค่า"
                    if ($val -is [string]) {
                        if (-not [string]::IsNullOrWhiteSpace($val)) {
                            return [string]$val
                        }
                    }
                    else {
                        return [string]$val
                    }
                }
            }

            return $null
        }
        catch {
            return $null
        }
    }

    # Helper: determine download/cache base dir
    # Priority:
    #   1) this.Config.DLDir (ทั้งแบบ hashtable และ object)
    #   2) RootDir\Download  หรือ AbsRoot\Download
    #   3) (Get-Location)\Download
    #
    # และถ้า DLDir ยังไม่ถูกตั้งใน Config จะตั้งให้ด้วย
    [string] GetCacheBase() {
        try {
            $dlDir = $null

            # มี this.Config ไหม
            if ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config) {

                # กรณี Config เป็น hashtable
                if ($this.Config -is [hashtable]) {
                    if ($this.Config.ContainsKey('DLDir') -and $this.Config['DLDir']) {
                        $dlDir = [string]$this.Config['DLDir']
                    }
                }
                else {
                    # กรณี Config เป็น object/pscustomobject
                    if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0 -and $this.Config.DLDir) {
                        $dlDir = [string]$this.Config.DLDir
                    }
                }
            }

            # ถ้ายังไม่มี DLDir -> สร้างจาก RootDir/AbsRoot
            if (-not $dlDir) {
                $root = $null

                if ($this -and $this.PSObject.Properties.Match('RootDir').Count -gt 0 -and $this.RootDir) {
                    $root = $this.RootDir
                }
                elseif ($this -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0 -and $this.AbsRoot) {
                    $root = $this.AbsRoot
                }
                else {
                    $root = (Get-Location).Path
                }

                $dlDir = Join-Path $root 'Download'

                # ตั้งกลับเข้า Config ด้วย (ถ้าเขียนได้)
                if ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config) {
                    if ($this.Config -is [hashtable]) {
                        $this.Config['DLDir'] = $dlDir
                    }
                    else {
                        if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0) {
                            $this.Config.DLDir = $dlDir
                        }
                    }
                }
            }

            return [string]$dlDir
        }
        catch {
            # fallback สุดท้าย: โฟลเดอร์ Download ใต้ cwd
            return (Join-Path (Get-Location).Path 'Download')
        }
    }
 

    [void] CreateFolders() {
        $this.CreateFolders('Skip', $false)
    }

    # 1-arg: Mode only -> perform (WhatIf = $false)
    [void] CreateFolders([string] $Mode) { $this.CreateFolders($Mode, $false) }

    # 2-arg: Mode + WhatIf -> actual implementation
    [void] CreateFolders([string] $Mode, [bool] $WhatIf) {
        if (-not $this.Config) { Write-Warning "Config is null — call SetPath() first."; return }
        # validate Mode inside method
        $allowed = @('Skip', 'Recreate', 'Backup')
        if (-not ($allowed -contains $Mode)) { Write-Warning "Invalid Mode '$Mode'. Allowed values: $($allowed -join ', '). Defaulting to 'Skip'."; $Mode = 'Skip' }
        foreach ($key in $this.Config.Keys) {
            $path = $this.Config[$key]
            if (-not $path) { Write-Warning "Empty path for '$key' — skipping."; continue }
            $exists = Test-Path -Path $path
            if ($exists) {
                switch ($Mode) {
                    'Skip' {
                        if ($WhatIf) { Write-Host "[WhatIf] Would skip existing: $key => $path" -ForegroundColor Cyan }
                        else { Write-Host "Exists : $key => $path (skipped)" -ForegroundColor Yellow }
                        continue
                    }
                    'Backup' {
                        $ts = (Get-Date).ToString('yyyyMMddHHmmss')
                        $backupPath = "$path.bak_$ts"

                        if ($WhatIf) { Write-Host "[WhatIf] Would move (backup): $path -> $backupPath" -ForegroundColor Cyan }
                        else {
                            try { Move-Item -Path $path -Destination $backupPath -Force -ErrorAction Stop ; Write-Host "Backed-up: $key => $backupPath" -ForegroundColor Yellow }
                            catch { Write-Warning "Backup failed for $key => $path : $($_.Exception.Message)"; continue }
                        }
                        # after backup, fall through to creation
                    }
                    'Recreate' {
                        if ($WhatIf) { Write-Host "[WhatIf] Would remove: $path" -ForegroundColor Cyan }
                        else {
                            try { Remove-Item -Path $path -Recurse -Force -ErrorAction Stop ; Write-Host "Removed: $key => $path" -ForegroundColor Magenta }
                            catch { Write-Warning "Remove failed for $key => $path : $($_.Exception.Message)" ; continue }
                        }
                        # after remove, fall through to creation
                    }
                } # end switch
            }

            # Now path does not exist (or was removed/backed up) -> create or WhatIf
            if ($WhatIf) { Write-Host "[WhatIf] Would create: $key => $path" -ForegroundColor Cyan }
            else {
                try { New-Item -Path $path -ItemType Directory -Force -ErrorAction Stop | Out-Null; Write-Host "Created: $key => $path" -ForegroundColor Green }
                catch {
                    try { [System.IO.Directory]::CreateDirectory($path) | Out-Null; Write-Host "Created (dotnet): $key => $path" -ForegroundColor Green }
                    catch { Write-Warning "Failed to create: $key => $path : $($_.Exception.Message)" }
                }
            }
        } # end foreach
    }

    # Overloads for RemoveFolder
    [void] RemoveFolder([string] $key) { $this.RemoveFolder($key, $false) }
    [void] RemoveFolder([string] $key, [bool] $WhatIf) {
        if (-not $this.Config) { Write-Warning "Config is null — call SetPath() first."; return }
        if (-not $this.Config.ContainsKey($key)) { Write-Warning "Unknown key: $key"; return }  $path = $this.Config[$key]; if (-not (Test-Path -Path $path)) { Write-Host "Not exists: $key => $path" -ForegroundColor Yellow ; return }
        if ($WhatIf) { Write-Host "[WhatIf] Would remove: $key => $path" -ForegroundColor Cyan ; return }
        try { Remove-Item -Path $path -Recurse -Force -ErrorAction Stop ; Write-Host "Removed: $key => $path" -ForegroundColor Magenta ; }
        catch { Write-Warning "Failed to remove $key => $path : $($_.Exception.Message)" ; }
    }

    [bool] IsFolder() { if (-not $this.Config) { Write-Warning "Config is null or empty. Call SetPath() first." ; return $false; }  $allOk = $true ; foreach ($key in $this.Config.Keys) { $path = $this.Config[$key]; if (-not (Test-Path -Path $path)) { Write-Warning "Missing: $key => $path " ; $allOk = $false } else { Write-Host "OK: $key => $path" -ForegroundColor Green } } return $allOk }


    # --- NormalizeVersion: return numeric portion only, or $null if not numeric-stable ---
    [string] NormalizeVersion([string] $v) {
        if (-not $v) { return $null }
        $s = $v.Trim();        # strip common prefix
        $s = $s -replace '^[Pp]ython[-_]*', '' ;
        $s = $s -replace '[\s_]', '.';
        # We only accept pure-numeric stable forms like "3.5.3" or "3.14.0" (no letters, no '-' suffix)
        if ($s -notmatch '^[0-9]+(\.[0-9]+){1,3}$') { return $null }
        # normalize to up to 3 components (major.minor.build)
        $parts = $s.Split('.') | Where-Object { $_ -ne '' }
        if ($parts.Count -eq 1) { $s = "$($parts[0]).0.0" }
        elseif ($parts.Count -eq 2) { $s = "$($parts[0]).$($parts[1]).0" }
        else { $s = "$($parts[0]).$($parts[1]).$($parts[2])" }
        try { return ([version]$s).ToString() } catch { return $null }
    }

    # -------------------------
    # GetPythonVersions
    # Params:
    #   [bool] $ForceRefresh = $false    - ignore cache and fetch fresh
    #   [bool] $AsJson = $false          - return JSON string when true
    # Returns: PSCustomObject[] unless $AsJson - each object contains:
    #   Version (string), VersionObj ([version]), Raw (string), MajorMinor (string), IsStable (bool)
    # -------------------------
    [Object]GetPythonVersions() { return $this.GetPythonVersions($false, $false) }
    [Object] GetPythonVersions([bool] $ForceRefresh = $false, [bool] $AsJson = $false) {
        # fallback if fetch fails
        $fallback = @('3.12.0', '3.11.11', '3.10.13', '3.9.18', '3.8.18')

        $IndexUrl = "https://api.nuget.org/v3-flatcontainer/python/index.json"
        if (-not $this.Cache) {
            $this.Cache = @{} 
        }

        if (-not $ForceRefresh -and $this.Cache.ContainsKey('versions')) {
            $cached = $this.Cache['versions']
            return ($AsJson) ? ($cached | ConvertTo-Json -Depth 3) : $cached
        }

        try {
            $index = Invoke-RestMethod -Uri $IndexUrl -TimeoutSec 20 -ErrorAction Stop
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
     
    # your existing menu implementation but return selected version
    # if $AutoInstall -and $selected - then you may call $this.CheckPython + $this.DownloadAndCopyPython here
    # BUT better approach: return selected version and let caller (InstallFlow) handle the rest.
    [string] ShowPythonVersionsMenu([bool] $Interactive = $true, [bool] $AutoInstall = $false) { $list = $this.GetPythonVersions(); return  $list[1 - 1].Version }
    [string] ShowPythonVersionsMenu() {
        $list = $this.GetPythonVersions()
        if (-not $list -or $list.Count -eq 0) { Write-Warning "No versions to show"; return $null }
        for ($i = 0; $i -lt $list.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i + 1), $list[$i].Version) }
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

        $shouldReplace = $null
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
    [bool] DownloadAndCopyPython([string] $v) { return $this.DownloadAndCopyPython($v, $false, $false, $true) }
    [bool] DownloadAndCopyPython([string] $v, [bool] $W) { return $this.DownloadAndCopyPython($v, $W, $false, $true) }
    [bool] DownloadAndCopyPython([string] $v, [bool]$W, [bool]$Force, [bool]$Backup) {

        if (-not $this.Config) { Write-Warning "Config not initialized"; return $false }

        $dl = $this.Config.DLDir
        $target = $this.Config.PyDir

        if (-not (Test-Path $dl)) {
            if ($W) { Write-Host "[WhatIf] mkdir $dl" -Foreground Cyan }
            else { New-Item $dl -ItemType Directory -Force | Out-Null }
        }

        $vNorm = $this.NormalizeVersion($v)
        if (-not $vNorm) { Write-Warning "Cannot normalize version: $v"; return $false }

        $nupkg = "python.$v.nupkg"
        $url = "https://api.nuget.org/v3-flatcontainer/python/$v/$nupkg"
        $localFile = Join-Path $dl $nupkg
        $tmp = Join-Path $env:TEMP ("py_extract_{0}" -f ([guid]::NewGuid()))

        # --- Download ---
        try {
            if ($W) { Write-Host "[WhatIf] download $url -> $localFile" -Foreground Cyan }
            else { Invoke-WebRequest $url -OutFile $localFile -TimeoutSec 300 -ErrorAction Stop }
        }
        catch { Write-Warning "Download failed: $($_.Exception.Message)"; return $false }

        if (-not $W -and -not (Test-Path $localFile)) { Write-Warning "Missing file: $localFile"; return $false }

        # --- Extract ---
        if ($W) { Write-Host "[WhatIf] extract $localFile -> $tmp" -Foreground Cyan }
        else {
            try { New-Item $tmp -ItemType Directory -Force | Out-Null; Expand-Archive $localFile $tmp -Force }
            catch { Write-Warning "Extract failed: $($_.Exception.Message)"; Remove-Item $tmp -Recurse -Force; return $false }
        }

        # --- Locate tools folder ---
        $paths = @(
            "$tmp/tools",
            "$tmp/content/tools",
            "$tmp/package/tools",
            "$tmp/package/content/tools",
            "$tmp/content",
            $tmp
        )

        $src = $paths | Where-Object { Test-Path $_ } | Where-Object {
            Test-Path (Join-Path $_ 'python.exe')
        } | Select-Object -First 1

        if (-not $src) {
            $src = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }

        if (-not $src) {
            Write-Warning "Cannot locate tools folder"; Remove-Item $tmp -Recurse -Force; return $false
        }

        # --- Prepare target ---
        if (Test-Path $target) {
            if ($W) {
                if ($Backup) { Write-Host "[WhatIf] backup $target" -Foreground Cyan }
                elseif ($Force) { Write-Host "[WhatIf] remove $target" -Foreground Cyan }
                else { Write-Host "[WhatIf] prompt overwrite" -Foreground Cyan }
            }
            else {
                if ($Backup) {
                    $bak = "$target.bak_$(Get-Date -f yyyyMMddHHmmss)"
                    try { Move-Item $target $bak -Force }
                    catch { Write-Warning "Backup failed: $($_.Exception.Message)"; Remove-Item $tmp -Recurse -Force; return $false }
                }
                elseif ($Force) {
                    try { Remove-Item $target -Recurse -Force }
                    catch { Write-Warning "Remove failed: $($_.Exception.Message)"; Remove-Item $tmp -Recurse -Force; return $false }
                }
                else {
                    $ans = Read-Host "Target exists. Overwrite? (Y/N)"
                    if ($ans -notmatch '^[Yy]') { Remove-Item $tmp -Recurse -Force; return $false }
                    try { Remove-Item $target -Recurse -Force }
                    catch { Write-Warning "Remove failed: $($_.Exception.Message)"; Remove-Item $tmp -Recurse -Force; return $false }
                }
            }
        }
        else {
            if ($W) { Write-Host "[WhatIf] mkdir $target" -Foreground Cyan }
            else { New-Item $target -ItemType Directory -Force | Out-Null }
        }

        # --- Copy ---
        if ($W) { Write-Host "[WhatIf] copy $src/* -> $target" -Foreground Cyan; return $true }

        try {
            Get-ChildItem $src -Force | ForEach-Object {
                $dest = Join-Path $target $_.Name
                if ($_.PSIsContainer) {
                    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
                    Copy-Item $_.FullName $dest -Recurse -Force
                }
                else {
                    Copy-Item $_.FullName $target -Force
                }
            }
        }
        catch { Write-Warning "Copy failed: $($_.Exception.Message)"; Remove-Item $tmp -Recurse -Force; return $false }

        Remove-Item $tmp -Recurse -Force
        return $true
    }
    [bool] GetPip() { return $this.GetPip($false) }
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
    [psobject] TestPythonGlobal() { return $this.TestPythonGlobal($true) }
    [psobject] TestPythonGlobal([bool] $ProbePip = $true) {
        $notes = @()

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

        # ----- Embedded python -----
        $embeddedPath = $null
        $embeddedVersion = $null
        $embeddedPipInstalled = $false
        $embeddedPipVersion = $null

        try {
            if ($this.Config.PyDir) {
                $p = [System.IO.Path]::GetFullPath((Join-Path $this.Config.PyDir 'python.exe'))
                if (Test-Path $p) { $embeddedPath = $p }
            }
        }
        catch { $notes += "Error resolving Config.PyDir: $($_.Exception.Message)" }

        if ($embeddedPath) {
            try {
                $out = & $embeddedPath --version 2>&1 | Out-String
                $out = $out.Trim()
                $embeddedVersion = ParsePythonVersion $out
                if (-not $embeddedVersion) { $notes += "Embedded python --version output: $out" }
            }
            catch {
                $notes += "Failed to exec embedded python: $($_.Exception.Message)"
            }

            if ($ProbePip) {
                try {
                    $pout = & $embeddedPath -m pip --version 2>&1 | Out-String
                    $pout = $pout.Trim()
                    $embeddedPipVersion = ParsePipVersion $pout
                    if ($embeddedPipVersion) { $embeddedPipInstalled = $true }
                    else {
                        $notes += "Embedded pip check unexpected / not installed: $pout"
                    }
                }
                catch {
                    $embeddedPipInstalled = $false
                    $notes += "Embedded pip probe failed: $($_.Exception.Message)"
                }
            }
        }
        else {
            $notes += "Embedded python not found at Config.PyDir (or PyDir not set)."
        }

        # ----- Global python -----
        $globalPath = $null
        $globalVersion = $null
        $globalPipInstalled = $false
        $globalPipVersion = $null

        try {
            $cmds = Get-Command python -All -ErrorAction SilentlyContinue
            if ($cmds) {
                foreach ($c in $cmds) {
                    $src = $null; try { $src = $c.Source } catch {}
                    if ($src -and $src -match '\\WindowsApps\\') { continue }
                    if ($c.CommandType -in @('Application', 'ExternalScript', 'Script')) {
                        $globalPath = $src; break
                    }
                }
            }
        }
        catch { $notes += "Get-Command python error: $($_.Exception.Message)" }

        if (-not $globalPath) {
            try {
                $pyCmd = Get-Command py -ErrorAction SilentlyContinue
                if ($pyCmd) {
                    $pyList = & py -0p 2>$null
                    foreach ($line in $pyList) {
                        if ($line -match '\.exe') {
                            $possible = ($line.Trim() -split '\s+')[-1]
                            if (Test-Path $possible) { $globalPath = $possible; break }
                        }
                    }
                }
            }
            catch { }
        }

        if (-not $globalPath) {
            try {
                foreach ($d in ($env:PATH -split ';')) {
                    $d = $d.Trim()
                    if (-not $d) { continue }

                    $candidate = Join-Path $d 'python.exe'
                    if (Test-Path $candidate) {
                        if ($candidate -notmatch '\\WindowsApps\\') {
                            $globalPath = $candidate
                            break
                        }
                    }
                }
            }
            catch {
                $notes += "Error searching PATH for python.exe: $($_.Exception.Message)"
            }
        }



        if ($globalPath) {
            $globalPath = [System.IO.Path]::GetFullPath($globalPath)
            try {
                $gout = & $globalPath --version 2>&1 | Out-String
                $gout = $gout.Trim()
                $globalVersion = ParsePythonVersion $gout
                if (-not $globalVersion) { $notes += "Global python --version output: $gout" }
            }
            catch {
                $notes += "Failed to exec global python: $($_.Exception.Message)"
            }


            if ($ProbePip) {
                try {
                    $gpout = & $globalPath -m pip --version 2>&1 | Out-String
                    $gpout = $gpout.Trim()
                    $globalPipVersion = ParsePipVersion $gpout
                    if ($globalPipVersion) { $globalPipInstalled = $true }
                    else {
                        $notes += "Global pip check unexpected / not installed: $gpout"
                    }
                }
                catch {
                    $globalPipInstalled = $false
                    $notes += "Global pip probe failed: $($_.Exception.Message)"
                }

            }
        }
        else {
            $notes += "No usable global python found (PATH and py launcher searched)."
        }

        # ----- Build summary -----
        $version = if ($embeddedVersion) { $embeddedVersion } else { $globalVersion }
        $path = if ($embeddedPath) { $embeddedPath }    else { $globalPath }
        $pipInstalled = [bool]($embeddedPipInstalled -or $globalPipInstalled)
        $pipVersion = if ($embeddedPipVersion) { $embeddedPipVersion } else { $globalPipVersion }

        $summary = [pscustomobject]@{
            Name         = 'Python'
            Exists       = [bool]($path)
            IsTest       = [bool]$version
            Version      = $version
            Path         = $path
            PipInstalled = $pipInstalled
            PipVersion   = $pipVersion
            Notes        = ($notes -join '; ')
            CheckedAt    = Get-Date
        }

        $this.Report = $summary.Notes
        return $summary
    }

    [bool] Extract7z([string] $Source, [string] $OutPath) {
        try {
            # --- ensure OutPath exists (ที่ติดตั้งจริง เช่น driver\xxx) ---
            if (-not (Test-Path -LiteralPath $OutPath)) {
                New-Item -Path $OutPath -ItemType Directory -Force | Out-Null
            }

            # --- หา DLDir = โฟลเดอร์ Download หลักของโปรเจกต์ ---
            $dlDir = $null

            # ถ้ามี Config.DLDir ให้ใช้ก่อน
            if ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config) {
                if ($this.Config -is [hashtable]) {
                    if ($this.Config.ContainsKey('DLDir')) { $dlDir = $this.Config['DLDir'] }
                }
                else {
                    if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0) {
                        $dlDir = $this.Config.DLDir
                    }
                }
            }

            # ถ้ายังไม่มี DLDir → default = ROOT\Download
            if (-not $dlDir) {
                $root = $null
                if ($this -and $this.PSObject.Properties.Match('RootDir').Count -gt 0 -and $this.RootDir) {
                    $root = $this.RootDir
                }
                elseif ($this -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0 -and $this.AbsRoot) {
                    $root = $this.AbsRoot
                }
                else {
                    $root = (Get-Location).Path
                }
                $dlDir = Join-Path $root 'Download'
            }

            if (-not (Test-Path -LiteralPath $dlDir)) {
                New-Item -Path $dlDir -ItemType Directory -Force | Out-Null
            }

            # --- ถ้า Source เป็น URL -> ดาวน์โหลดเก็บใน Download ---
            if ($Source -match '^https?://') {
                $fileName = Split-Path $Source -Leaf
                if (-not $fileName) { $fileName = 'download.bin' }
                $localPath = Join-Path $dlDir $fileName

                if (-not (Test-Path -LiteralPath $localPath)) {
                    Write-Host "Downloading: $Source -> $localPath"
                    Invoke-WebRequest -Uri $Source -OutFile $localPath -UseBasicParsing -ErrorAction Stop
                }
                else {
                    Write-Host "Using cached download: $localPath"
                }

                $Source = $localPath
            }

            # --- ตรวจว่า source file มีอยู่จริง ---
            if (-not (Test-Path -LiteralPath $Source)) {
                Write-Warning "Extract7z: source file not found: $Source"
                return $false
            }

            # --- หา 7z หรือโหลด 7zr.exe ลง Download เป็น cache ---
            $seven = $null
            $candidates = @(
                'C:\Program Files\7-Zip\7z.exe',
                'C:\Program Files (x86)\7-Zip\7z.exe'
            )

            foreach ($p in $candidates) {
                if (Test-Path -LiteralPath $p) { $seven = $p; break }
            }

            if (-not $seven) {
                $cmd = Get-Command 7z -ErrorAction SilentlyContinue
                if ($cmd) { $seven = $cmd.Path }
            }

            if (-not $seven) {
                # โหลด portable 7zr.exe เก็บไว้ใน Download
                $cached7zr = Join-Path $dlDir '7zr.exe'
                if (-not (Test-Path -LiteralPath $cached7zr)) {
                    Write-Host "Downloading portable 7zr.exe -> $cached7zr"
                    Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7zr.exe' `
                        -OutFile $cached7zr `
                        -UseBasicParsing -ErrorAction Stop
                }
                $seven = $cached7zr
            }

            # --- run extraction ---
            $args = @('x', $Source, "-o$OutPath", '-y')
            $proc = Start-Process -FilePath $seven -ArgumentList $args -NoNewWindow -Wait -PassThru

            if ($proc.ExitCode -ne 0) {
                Write-Warning "Extract7z: 7z exit code $($proc.ExitCode)"
                return $false
            }

            return $true
        }
        catch {
            Write-Warning "Extract7z failed: $($_.Exception.Message)"
            return $false
        }
    }




    [string] GetLatestReleaseAssetUrl(
        [string] $repo,
        [string] $namePattern,
        [string] $userAgent = 'PS-AssetProbe'
    ) {
        try {
            $api = "https://api.github.com/repos/$repo/releases/latest"
            $headers = @{ 'User-Agent' = $userAgent }
            $rel = Invoke-RestMethod -Uri $api -Headers $headers -ErrorAction Stop

            if (-not $rel.assets) { return $null }

            $asset = $rel.assets |
            Where-Object { $_.name -match $namePattern } |
            Select-Object -First 1

            if ($asset) { return [string]$asset.browser_download_url }
            return $null
        }
        catch {
            Write-Warning "GetLatestReleaseAssetUrl($repo) error: $($_.Exception.Message)"
            return $null
        }
    }

    [bool] InstallArchiveTool(
        [string] $name,             # "FFmpeg" / "PortableGit"
        [string] $src,              # URL หรือ path
        [string] $defaultSubDir,    # "driver\ffmpeg" / "driver\PortableGit"
        [ref]    $configPathRef,    # [ref]$this.Config.FFmpeg / [ref]$this.Config.PGit
        [bool]   $WhatIf = $false
    ) {
        if (-not $src) {
            Write-Warning "Install $name : no source URL/path provided."
            return $false
        }

        # DLDir
        $dlDir = $this.Config.DLDir
        if (-not $dlDir) {
            $dlDir = Join-Path $this.RootDir 'Download'
            $this.Config.DLDir = $dlDir   # ตั้งให้ config ด้วยเลย
        }

        if (-not (Test-Path $dlDir)) {
            if ($WhatIf) {
                Write-Host "[WhatIf] Would create download dir: $dlDir"
            }
            else {
                New-Item -Path $dlDir -ItemType Directory -Force | Out-Null
            }
        }

        # resolve downloaded file path
        $isUrl = $src -match '^https?://'
        $dl = $src

        if ($isUrl) {
            $fileName = [System.IO.Path]::GetFileName($src)
            if (-not $fileName) { $fileName = "$name-latest.7z" }
            $dl = Join-Path $dlDir $fileName

            if ($WhatIf) {
                Write-Host "[WhatIf] Would download $name : $src -> $dl"
            }
            else {
                Write-Host "Downloading $name from: $src"
                try {
                    Invoke-WebRequest -Uri $src -OutFile $dl -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
                }
                catch {
                    Write-Warning "Install $name : download failed: $($_.Exception.Message)"
                    return $false
                }
            }
        }

        # target dir
        $cfgPath = $configPathRef.Value
        if (-not $cfgPath) {
            $cfgPath = Join-Path $this.RootDir $defaultSubDir
            $configPathRef.Value = $cfgPath
        }

        if (Test-Path $cfgPath) {
            if ($WhatIf) {
                Write-Host "[WhatIf] Would remove existing $name dir: $cfgPath"
            }
            else {
                try { Remove-Item -Path $cfgPath -Recurse -Force -ErrorAction Stop }
                catch {
                    Write-Warning "Install $name : failed to remove existing dir: $($_.Exception.Message)"
                    return $false
                }
            }
        }

        if ($WhatIf) {
            Write-Host "[WhatIf] Would extract $dl -> $cfgPath"
            return $true
        }

        $ok = $this.Extract7z($dl, $cfgPath)
        if (-not $ok) {
            Write-Warning "Install $name : Extract7z returned failure."
            return $false
        }

        Write-Host "$name installed to: $cfgPath"
        return $true
    }

    [string] GetFFmpeg() {
        try {
            return $this.GetLatestReleaseAssetUrl(
                'GyanD/codexffmpeg',
                '^ffmpeg-.*-full_build\.zip$',
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'
            )
        }
        catch {
            Write-Warning "GetFFmpeg error: $($_.Exception.Message)"
            return $null
        }
    }

    [string] GetPGit() {
        try {
            return $this.GetLatestReleaseAssetUrl(
                'git-for-windows/git',
                'PortableGit.*-64-bit\.7z\.exe$',
                'PS-GetPGit'
            )
        }
        catch {
            Write-Warning "GetPGit error: $($_.Exception.Message)"
            return $null
        }
    }
    
    [bool] InstallFFmpeg([bool] $WhatIf = $false) {
        # 1) ขอ URL ล่าสุดจาก GitHub
        $src = $this.GetFFmpeg()
        if (-not $src) {
            Write-Warning "InstallFFmpeg: GetFFmpeg() did not return any source."
            return $false
        }

        # 2) ให้ InstallArchiveTool โหลด + แตกลง driver\ffmpeg
        $ok = $this.InstallArchiveTool(
            'FFmpeg',
            $src,
            'driver\ffmpeg',          # ติดตั้งไว้ใต้ ROOT\driver\ffmpeg\XXX...
            [ref]$this.Config.FFmpeg, # ชี้ config ไปที่ ROOT\driver\ffmpeg
            $WhatIf
        )

        if (-not $ok -or $WhatIf) {
            return $ok
        }

        try {
            # 3) หา root ของ ffmpeg จาก Config
            $ffRoot = $null
            if ($this.Config -is [hashtable]) {
                if ($this.Config.ContainsKey('FFmpeg')) { $ffRoot = $this.Config['FFmpeg'] }
            }
            else {
                if ($this.Config.PSObject.Properties.Match('FFmpeg').Count -gt 0) {
                    $ffRoot = $this.Config.FFmpeg
                }
            }

            if (-not $ffRoot) {
                Write-Warning "InstallFFmpeg: Config.FFmpeg not set after InstallArchiveTool."
                return $false
            }

            if (-not (Test-Path -LiteralPath $ffRoot)) {
                Write-Warning "InstallFFmpeg: FFmpeg root dir does not exist: $ffRoot"
                return $false
            }

            # 4) หาโฟลเดอร์ XXX ที่ข้างในมี bin\ffmpeg.exe เช่น ffmpeg-8.0.1-full_build
            $subDirs = Get-ChildItem -Path $ffRoot -Directory -ErrorAction SilentlyContinue
            $ffBuildDir = $null

            foreach ($d in $subDirs) {
                $bin = Join-Path $d.FullName 'bin'
                $ffexe = Join-Path $bin 'ffmpeg.exe'
                if (Test-Path -LiteralPath $ffexe) {
                    $ffBuildDir = $d.FullName
                    break
                }
            }

            # fallback: ถ้ามี subdir เดียวก็เดาว่าเป็นมัน
            if (-not $ffBuildDir -and $subDirs.Count -eq 1) {
                $ffBuildDir = $subDirs[0].FullName
            }

            if (-not $ffBuildDir) {
                Write-Warning "InstallFFmpeg: Could not locate build dir (no XXX\bin\ffmpeg.exe under $ffRoot)."
                return $false
            }

            $binDir = Join-Path $ffBuildDir 'bin'
            $targets = @('ffmpeg.exe', 'ffplay.exe', 'ffprobe.exe')
            $moved = 0

            # 5) ย้าย exe จาก XXX\bin ขึ้นมาไว้ที่ root driver\ffmpeg
            foreach ($name in $targets) {
                $srcExe = Join-Path $binDir $name
                $destExe = Join-Path $ffRoot $name

                if (Test-Path -LiteralPath $srcExe) {
                    try {
                        # ใช้ Move-Item = ย้ายออกจาก XXX/bin
                        Move-Item -LiteralPath $srcExe -Destination $destExe -Force -ErrorAction Stop
                        Write-Host "InstallFFmpeg: Moved $name -> $destExe"
                        $moved++
                    }
                    catch {
                        Write-Warning "InstallFFmpeg: Failed to move $name : $($_.Exception.Message)"
                    }
                }
                else {
                    Write-Host "InstallFFmpeg: $name not found under $binDir" -ForegroundColor Yellow
                }
            }

            if ($moved -eq 0) {
                Write-Warning "InstallFFmpeg: No executables were moved from $binDir."
                return $false
            }

            # 6) ลบโฟลเดอร์ XXX ออกให้เหลือแค่ exe ที่ root
            try {
                Remove-Item -LiteralPath $ffBuildDir -Recurse -Force -ErrorAction Stop
                Write-Host "InstallFFmpeg: Removed build directory: $ffBuildDir"
            }
            catch {
                Write-Warning "InstallFFmpeg: Failed to remove build dir $ffBuildDir : $($_.Exception.Message)"
                # ถือว่ายัง success แต่แจ้งเตือนว่าทำความสะอาดไม่หมด
            }

            Write-Host "FFmpeg runtime ready at: $ffRoot (only ffmpeg.exe / ffplay.exe / ffprobe.exe at root)."
            return $true
        }
        catch {
            Write-Warning "InstallFFmpeg: post-process failed: $($_.Exception.Message)"
            return $false
        }
    }



    [bool] InstallPGit([bool] $WhatIf = $false) {
        $src = $this.GetPGit()
        return $this.InstallArchiveTool(
            'PortableGit',
            $src,
            'driver\PortableGit',
            [ref]$this.Config.PGit,
            $WhatIf
        )
    }

    # ใช้เมธอดนี้เป็นตัวหลักภายใน class
    [pscustomobject] GetNvToolInfo([string] $Tool) {
        try {
            if (-not $Tool) { throw "Tool name required (e.g. 'cuda' or 'cudnn')." }
            $t = $Tool.ToLower().Trim()

            $archiveUrl = $null
            $downloadPattern = $null

            switch ($t) {
                'cuda' {
                    $archiveUrl = "https://developer.nvidia.com/cuda-toolkit-archive"
                    $downloadPattern = "https://developer.download.nvidia.com/compute/cuda/{0}/local_installers/cuda_{0}_windows.exe"
                }
                'cudnn' {
                    $archiveUrl = "https://developer.nvidia.com/cudnn-archive"
                    $downloadPattern = "https://developer.download.nvidia.com/compute/cudnn/{0}/local_installers/cudnn_{0}_windows.exe"
                    # หมายเหตุ: cuDNN เปลี่ยน format บ่อย อันนี้ต้อง sync ตามหน้าเว็บจริง
                }
                default {
                    throw "Unsupported tool: $Tool. Supported: cuda, cudnn."
                }
            }

            Write-Host "Fetching NVIDIA archive page for '$t': $archiveUrl"
            $resp = Invoke-WebRequest -Uri $archiveUrl -UseBasicParsing -ErrorAction Stop
            $html = $resp.Content

            # ดึง version candidates
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

            # backup: scan link text / HTML ทั่ว ๆ
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

            # normalize version และเลือกตัวที่ใหญ่สุด
            $norm = foreach ($v in $candidates) {
                $parts = $v -split '\.'
                if ($parts.Count -eq 2) { $parts += '0' }
                while ($parts.Count -lt 3) { $parts += '0' }
                $major = [int]$parts[0]
                $minor = [int]$parts[1]
                $patch = [int]$parts[2]
                $score = $major * 1000000 + $minor * 1000 + $patch

                [pscustomobject]@{
                    Ver   = "$major.$minor.$patch"
                    Score = $score
                }
            }

            $best = $norm | Sort-Object -Property Score -Descending | Select-Object -First 1
            $version = $best.Ver

            Write-Host "Selected latest version for $t : $version"

            $installerUrl = [string]::Format($downloadPattern, $version)
            Write-Host "Mapped installer URL: $installerUrl"

            return [pscustomobject]@{
                Tool    = $t
                Version = $version
                Url     = $installerUrl
            }
        }
        catch {
            Write-Error "GetNvToolInfo($Tool) failed: $($_.Exception.Message)"
            return $null
        }
    }

    # wrapper เดิม เพื่อให้โค้ดเก่าที่เรียก GetNvTool() ยังใช้ได้
    [string] GetNvTool([string] $tool) {
        $info = $this.GetNvToolInfo($tool)
        if ($info) { return [string]$info.Url }
        return $null
    }

    [pscustomobject] InstallNvidia([string] $Component) {
        $summary = [pscustomobject]@{
            Success = $false
            Details = @()
            Error   = $null
        }

        try {
            if (-not $Component) {
                $summary.Error = "Component required: 'cuda','cudnn' or 'all'"
                Write-Host $summary.Error
                return $summary
            }

            $compNorm = $Component.ToLower().Trim()
            if ($compNorm -notin @('cuda', 'cudnn', 'all')) {
                $summary.Error = "Unsupported component: $Component (use 'cuda','cudnn','all')"
                Write-Host $summary.Error
                return $summary
            }

            $requested = switch ($compNorm) {
                'cuda' { @('cuda') }
                'cudnn' { @('cudnn') }
                'all' { @('cuda', 'cudnn') }
            }

            # require Config
            if (-not ($this -and $this.PSObject.Properties.Match('Config').Count -gt 0 -and $this.Config)) {
                $summary.Error = 'Config missing'
                Write-Error "Config not set on instance. Set this.Config before calling InstallNvidia()."
                return $summary
            }

            # DLDir
            $dlDir = $null
            if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('DLDir')) { $dlDir = $this.Config['DLDir'] } }
            else { if ($this.Config.PSObject.Properties.Match('DLDir').Count -gt 0) { $dlDir = $this.Config.DLDir } }

            if (-not $dlDir) {
                # default = ROOT\Download แล้วเซตกลับเข้า config
                $root = $null
                if ($this.Config -is [hashtable]) { if ($this.Config.ContainsKey('RootDir')) { $root = $this.Config['RootDir'] } }
                else { if ($this.Config.PSObject.Properties.Match('RootDir').Count -gt 0) { $root = $this.Config.RootDir } }

                if (-not $root -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0) { $root = $this.AbsRoot }
                if (-not $root) { $summary.Error = 'DLDir/RootDir missing' ; Write-Error "InstallNvidia: RootDir not set." ; return $summary }
                $dlDir = Join-Path $root 'Download'

                if ($this.Config -is [hashtable]) { $this.Config['DLDir'] = $dlDir }
                else { $this.Config.DLDir = $dlDir }
            }

            if (-not (Test-Path $dlDir)) { New-Item -Path $dlDir -ItemType Directory -Force | Out-Null }

            # CudaBin / CuDNNBin
            $cudaBin = $null
            $cudnnBin = $null
            if ($this.Config -is [hashtable]) {
                if ($this.Config.ContainsKey('CudaBin')) { $cudaBin = $this.Config['CudaBin'] }
                if ($this.Config.ContainsKey('CuDNNBin')) { $cudnnBin = $this.Config['CuDNNBin'] }
            }
            else {
                if ($this.Config.PSObject.Properties.Match('CudaBin').Count -gt 0) { $cudaBin = $this.Config.CudaBin }
                if ($this.Config.PSObject.Properties.Match('CuDNNBin').Count -gt 0) { $cudnnBin = $this.Config.CuDNNBin }
            }

            if (-not $cudaBin -and $requested -contains 'cuda') {
                $summary.Error = 'CudaBin missing'
                Write-Error "Config.CudaBin not set. Set this.Config.CudaBin (driver\CUDA)."
                return $summary
            }
            if (-not $cudnnBin -and $requested -contains 'cudnn') {
                $summary.Error = 'CuDNNBin missing'
                Write-Error "Config.CuDNNBin not set. Set this.Config.CuDNNBin (driver\CUDNN)."
                return $summary
            }

            if ($cudaBin -and -not (Test-Path $cudaBin)) { New-Item -Path $cudaBin  -ItemType Directory -Force | Out-Null }
            if ($cudnnBin -and -not (Test-Path $cudnnBin)) { New-Item -Path $cudnnBin -ItemType Directory -Force | Out-Null }

            foreach ($comp in $requested) {
                $detail = [pscustomobject]@{
                    Component  = $comp
                    Success    = $false
                    Archive    = $null
                    ExtractDir = $null
                    Copied     = 0
                    Missing    = @()
                    Error      = $null
                }

                try {
                    $info = $this.GetNvToolInfo($comp)
                    if (-not $info) {
                        $detail.Error = "GetNvToolInfo returned null"
                        $summary.Details += $detail
                        continue
                    }

                    $source = $info.Url
                    if (-not $source) {
                        $detail.Error = "Installer URL empty"
                        $summary.Details += $detail
                        continue
                    }

                    # URL -> archive in DLDir
                    if ($source -match '^https?://') {
                        $leaf = Split-Path $source -Leaf
                        $archive = Join-Path $dlDir $leaf
                        if (-not (Test-Path $archive)) {
                            try {
                                Write-Host "Downloading $comp from: $source"
                                Invoke-WebRequest -Uri $source -OutFile $archive -UseBasicParsing -ErrorAction Stop
                            }
                            catch {
                                $detail.Error = "Download failed: $($_.Exception.Message)"
                                $summary.Details += $detail
                                continue
                            }
                        }
                    }
                    else {
                        if (Test-Path $source) { $archive = $source }
                        else {
                            $detail.Error = "Local source not found: $source"
                            $summary.Details += $detail
                            continue
                        }
                    }

                    $detail.Archive = $archive

                    # extract to DLDir\<archiveBaseName>
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($archive)
                    $outdir = Join-Path $dlDir $base

                    if (-not (Test-Path $outdir)) { New-Item -Path $outdir -ItemType Directory -Force | Out-Null }
                    $detail.ExtractDir = $outdir

                    if (-not ($this.PSObject.Methods.Match('Extract7z').Count -gt 0)) {
                        $detail.Error = 'Extract7z missing on instance'
                        $summary.Details += $detail
                        continue
                    }

                    $ok = $this.Extract7z($archive, $outdir)
                    if (-not $ok) {
                        $detail.Error = "Extract failed"
                        $summary.Details += $detail
                        continue
                    }

                    # copy target DLLs
                    $this.CopyNvidia($comp)

                    if ($comp -eq 'cuda') {
                        try { $detail.Copied = ($this.CopiedCudaFiles.Count) }  catch {}
                        try { $detail.Missing = $this.MissingCudaFiles }        catch {}
                    }
                    else {
                        try { $detail.Copied = ($this.CopiedCudnnFiles.Count) } catch {}
                        try { $detail.Missing = $this.MissingCudnnFiles }       catch {}
                    }

                    $detail.Success = $true
                    $summary.Details += $detail
                }
                catch {
                    $detail.Error = $_.Exception.Message
                    $summary.Details += $detail
                }
            }

            $summary.Success = ($summary.Details | Where-Object { -not $_.Success }).Count -eq 0
            return $summary
        }
        catch {
            $summary.Error = $_.Exception.Message
            Write-Error "InstallNvidia failed: $($_.Exception.Message)"
            return $summary
        }
    }

    [void] CopyNvidia([string] $Component) {
        try {
            if (-not $Component) { Write-Error "Component required"; return }
            $c = $Component.ToLower().Trim()

            if ($c -eq 'cuda') {
                $targets = @(
                    "cublas64_13.dll", "cublasLt64_13.dll", "cudart64_13.dll", "cufft64_12.dll", "cufftw64_12.dll",
                    "curand64_10.dll", "cusolver64_12.dll", "cusolverMg64_12.dll", "cusparse64_12.dll",
                    "nppc64_13.dll", "nppial64_13.dll", "nppicc64_13.dll", "nppidei64_13.dll", "nppif64_13.dll",
                    "nppig64_13.dll", "nppim64_13.dll", "nppist64_13.dll", "nppisu64_13.dll", "nppitc64_13.dll",
                    "npps64_13.dll", "nvblas64_13.dll", "nvfatbin_130_0.dll", "nvJitLink_130_0.dll", "nvjpeg64_13.dll",
                    "nvrtc-builtins64_130.dll", "nvrtc64_130_0.alt.dll", "nvrtc64_130_0.dll", "nvvm64_40_0.dll"
                )
                if ($this.Config -is [hashtable]) { $dest = $this.Config['CudaBin'] }
                else { $dest = $this.Config.CudaBin }
                if (-not $dest) { Write-Error "Config.CudaBin not set"; return }
            }
            elseif ($c -eq 'cudnn') {
                $targets = @(
                    "cudnn_adv64_9.dll", "cudnn_cnn64_9.dll", "cudnn_engines_precompiled64_9.dll",
                    "cudnn_engines_runtime_compiled64_9.dll", "cudnn_graph64_9.dll", "cudnn_heuristic64_9.dll",
                    "cudnn_ops64_9.dll", "cudnn64_9.dll"
                )
                if ($this.Config -is [hashtable]) { $dest = $this.Config['CuDNNBin'] }
                else { $dest = $this.Config.CuDNNBin }
                if (-not $dest) { Write-Error "Config.CuDNNBin not set"; return }
            }
            else {
                Write-Error "Unsupported component: $Component"; return
            }

            if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory -Force | Out-Null }

            # DLDir + subfolders (extract dirs)
            if ($this.Config -is [hashtable]) { $dlRoot = $this.Config['DLDir'] }
            else { $dlRoot = $this.Config.DLDir }
            if (-not $dlRoot) { Write-Error "Config.DLDir not set"; return }

            $candidates = @()
            $candidates += $dlRoot
            try {
                $candidates += Get-ChildItem -Path $dlRoot -Directory -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
            }
            catch {}

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

                        $g = Get-ChildItem -Path $srcRoot -Filter $t -Recurse -ErrorAction SilentlyContinue |
                        Select-Object -First 1
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
                else {
                    $missing.Add($t) | Out-Null
                }
            }

            $uc = $c.Substring(0, 1).ToUpper() + $c.Substring(1)
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

        # Normalize PATH ปัจจุบันก่อน
        $sessionItems = @()
        foreach ($p in ($env:Path -split ';')) {
            $p = $p.Trim()
            if (-not $p) { continue }
            try {
                if (Test-Path -LiteralPath $p) {
                    $full = (Get-Item -LiteralPath $p -ErrorAction Stop).FullName.TrimEnd('\')
                }
                else {
                    $full = $p.TrimEnd('\')
                }
            }
            catch {
                $full = $p.TrimEnd('\')
            }
            if ($sessionItems -notcontains $full) {
                $sessionItems += $full
            }
        }

        $toPrepend = New-Object System.Collections.Generic.List[string]

        foreach ($item in $Items) {
            if (-not $item) { continue }
            $resolved = $null
            try {
                if (Test-Path -LiteralPath $item) {
                    $resolved = (Get-Item -LiteralPath $item).FullName.TrimEnd('\')
                }
                else {
                    $resolved = $item.Trim()
                }
            }
            catch {
                $resolved = $item.Trim()
            }

            if ($resolved -and (Test-Path -LiteralPath $resolved)) {
                $exists = $false
                foreach ($si in $sessionItems) {
                    if ($si -ieq $resolved) { $exists = $true; break }
                }
                if (-not $exists) {
                    $null = $toPrepend.Add($resolved)
                    $sessionItems += $resolved
                }
            }
        }

        if ($toPrepend.Count -gt 0) {
            $env:Path = ($toPrepend + $sessionItems) -join ';'
            Write-Host "Prepended $($toPrepend.Count) PATH entries to session PATH."
        }
        else {
            Write-Host "No new PATH entries were added (all present or not found)." -ForegroundColor Yellow
        }
    }
    # Detect executables. Accept existing dirs list (optional) to prefer local ones.
    [hashtable] DetectExecutables([string[]]$existingDirs) {
        $result = @{
            python                  = $null
            pip                     = $null
            git                     = $null
            ffmpeg                  = $null
            pip_using_python_module = $false
        }

        $existing = @()
        if ($existingDirs) {
            foreach ($d in $existingDirs) {
                if ($d -and (Test-Path -LiteralPath $d)) {
                    $existing += (Get-Item -LiteralPath $d).FullName.TrimEnd('\')
                }
            }
        }

        # Helper เล็ก ๆ
        function Get-ConfigValueLocal([object]$cfgRef, [string]$key) {
            if (-not $cfgRef) { return $null }
            if ($cfgRef -is [hashtable]) {
                if ($cfgRef.ContainsKey($key)) { return $cfgRef[$key] }
            }
            else {
                if ($cfgRef.PSObject.Properties.Match($key).Count -gt 0) { return $cfgRef.$key }
            }
            return $null
        }

        # --- python: Get-Command ก่อน ---
        foreach ($name in @('python', 'python3')) {
            try {
                $cmd = Get-Command $name -ErrorAction Stop
                if ($cmd -and $cmd.Path) { $result.python = $cmd.Path; break }
            }
            catch {}
        }

        # fallback: หา python.exe ใน existingDirs หรือ Config.PyDir
        if (-not $result.python) {
            $candPaths = @()
            if ($existing.Count -gt 0) {
                foreach ($e in $existing) { $candPaths += (Join-Path $e 'python.exe') }
            }
            try {
                $py = Get-ConfigValueLocal $this.Config 'PyDir'
                if ($py) { $candPaths += (Join-Path $py 'python.exe') }
            }
            catch {}
            foreach ($cand in $candPaths) {
                if (Test-Path -LiteralPath $cand) {
                    $result.python = (Get-Item -LiteralPath $cand).FullName
                    break
                }
            }
        }

        # --- pip ---
        try {
            $cmdpip = Get-Command pip -ErrorAction Stop
            if ($cmdpip -and $cmdpip.Path) { $result.pip = $cmdpip.Path }
        }
        catch {}

        if (-not $result.pip) {
            $pCandidates = @()
            if ($existing.Count -gt 0) {
                foreach ($e in $existing) {
                    $pCandidates += (Join-Path $e 'Scripts\pip.exe')
                    $pCandidates += (Join-Path $e 'Scripts\pip3.exe')
                }
            }
            try {
                $py = Get-ConfigValueLocal $this.Config 'PyDir'
                if ($py) {
                    $pCandidates += (Join-Path $py 'Scripts\pip.exe')
                    $pCandidates += (Join-Path $py 'Scripts\pip3.exe')
                }
            }
            catch {}
            foreach ($pc in $pCandidates) {
                if (Test-Path -LiteralPath $pc) {
                    $result.pip = (Get-Item -LiteralPath $pc).FullName
                    break
                }
            }
            if (-not $result.pip -and $result.python) {
                $result.pip_using_python_module = $true
            }
        }

        # --- git ---
        try {
            $cmdgit = Get-Command git -ErrorAction Stop
            if ($cmdgit -and $cmdgit.Path) { $result.git = $cmdgit.Path }
        }
        catch {
            try {
                $pg = Get-ConfigValueLocal $this.Config 'PGit'
                if ($pg) {
                    $cands = @(
                        Join-Path $pg 'cmd\git.exe',
                        Join-Path $pg 'bin\git.exe',
                        Join-Path $pg 'mingw64\bin\git.exe'
                    )
                    foreach ($g in $cands) {
                        if (Test-Path -LiteralPath $g) {
                            $result.git = (Get-Item -LiteralPath $g).FullName
                            break
                        }
                    }
                }
            }
            catch {}

            # last resort: search under python_embeded tree
            try {
                $root = Get-ConfigValueLocal $this.Config 'RootDir'
                if (-not $root -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0) { $root = $this.AbsRoot }
                if ($root) {
                    $pe = Join-Path $root 'python_embeded'
                    if (Test-Path -LiteralPath $pe) {
                        $foundGit = Get-ChildItem -Path $pe -Recurse -Filter 'git.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($foundGit) { $result.git = $foundGit.FullName }
                    }
                }
            }
            catch {}
        }

        # --- ffmpeg ---
        try {
            $cmdff = Get-Command ffmpeg -ErrorAction Stop
            if ($cmdff -and $cmdff.Path) { $result.ffmpeg = $cmdff.Path }
        }
        catch {}

        if (-not $result.ffmpeg) {
            $ffRoot = Get-ConfigValueLocal $this.Config 'FFmpeg'
            $ffCandidates = @()
            if ($ffRoot) {
                $ffCandidates += (Join-Path $ffRoot 'bin\ffmpeg.exe')
                $ffCandidates += (Join-Path $ffRoot 'ffmpeg.exe')
            }
            if ($existing.Count -gt 0) {
                foreach ($e in $existing) {
                    $ffCandidates += (Join-Path $e 'ffmpeg.exe')
                }
            }
            foreach ($fc in $ffCandidates) {
                if (Test-Path -LiteralPath $fc) {
                    $result.ffmpeg = (Get-Item -LiteralPath $fc).FullName
                    break
                }
            }
        }

        return $result
    }

 
    # Create session-only function aliases pointing to resolved executables
    [void] CreateSessionAliases([hashtable]$detected) {

        function _MakeFunction($name, $exePath, [bool]$usePythonModule = $false) {
            if (-not $exePath) { return }

            if ($usePythonModule) {
                # ใช้ python -m pip
                $sb = @"
param(
    [Parameter(ValueFromRemainingArguments=`$true)]
    [object[]] `$Args
)
& "$exePath" -m pip @Args
"@
            }
            else {
                # เรียก exe ตรง ๆ
                $sb = @"
param(
    [Parameter(ValueFromRemainingArguments=`$true)]
    [object[]] `$Args
)
& "$exePath" @Args
"@
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
        if ($detected.pip) {
            _MakeFunction 'pip' $detected.pip
        }
        elseif ($detected.pip_using_python_module -and $detected.python) {
            _MakeFunction 'pip' $detected.python $true
        }
        else {
            Write-Host "pip not available." -ForegroundColor Yellow
        }

        # git
        if ($detected.git) { _MakeFunction 'git' $detected.git }
        else { Write-Host "git not found." -ForegroundColor Yellow }

        # ffmpeg
        if ($detected.ffmpeg) { _MakeFunction 'ffmpeg' $detected.ffmpeg }
        else { Write-Host "ffmpeg not found." -ForegroundColor Yellow }
    }

   

    <#
        .SYNOPSIS
            ตั้งค่า PATH ให้พร้อมใช้งาน Python/pip/Git/FFmpeg/CUDA/cuDNN จาก config ปัจจุบัน

        .DESCRIPTION
            ทำหน้าที่:
              1) อ่านค่าโฟลเดอร์จาก $this.Config (RootDir, PyDir, PGit, FFmpeg, CudaBin, CuDNNBin)
              2) สร้างลิสต์โฟลเดอร์ที่ต้องการเพิ่มลง PATH (เช่น python_embeded, driver\PortableGit\cmd, driver\ffmpeg\bin ฯลฯ)
              3) ตรวจว่ามีอยู่จริงแล้วค่อยเพิ่ม (ลดโอกาส PATH เน่า)
              4) เพิ่มลง PATH ของ session ปัจจุบัน (เฉพาะถ้ายังไม่มี)
              5) ถ้า $Persist เป็น $true จะ prepend ลง User PATH ด้วย (เซสชันใหม่ก็เห็น)
              6) ตรวจหา executables จริงจาก PATH (python, pip, git, ffmpeg, nvcc ฯลฯ)
              7) สร้างฟังก์ชัน/alias ใน session ให้เรียกใช้เครื่องมือเหล่านี้ได้สะดวก

        .PARAMETER Persist
            - $false : แก้เฉพาะ PATH ของ session ปัจจุบัน (ปิด PowerShell แล้วค่า PATH เดิมกลับมา)
            - $true  : แก้ทั้ง session ปัจจุบัน + บันทึกลง User PATH (เซสชันใหม่ก็เห็นเหมือนกัน)

        .NOTES
            - ควรเรียกหลังจาก InstallFlow() ติดตั้งทุกอย่างเรียบร้อยแล้ว
            - ถ้าเปิด PowerShell ใหม่ (session ใหม่) และติดตั้งทุกอย่างเสร็จแล้ว
              ให้เรียกเฉพาะ SetupPath($true) ก็เพียงพอ ไม่ต้อง InstallFlow() ซ้ำ
    #>

    # Setup PATH and aliases for current session. If $Persist = $true, persist to User PATH.
    [void] SetupPath([bool]$Persist = $false) {
        $cfg = $this.Config
        $root = $null

        # Helper: อ่านค่า config ทั้งแบบ hashtable และ object
        function Get-ConfigValue([object]$cfgRef, [string]$key) {
            if (-not $cfgRef) { return $null }
            if ($cfgRef -is [hashtable]) {
                if ($cfgRef.ContainsKey($key)) { return $cfgRef[$key] }
            }
            else {
                if ($cfgRef.PSObject.Properties.Match($key).Count -gt 0) { return $cfgRef.$key }
            }
            return $null
        }

        if ($cfg) {
            $root = Get-ConfigValue $cfg 'RootDir'
        }
        if (-not $root -and $this.PSObject.Properties.Match('AbsRoot').Count -gt 0 -and $this.AbsRoot) {
            $root = $this.AbsRoot
        }
        if (-not $root) {
            Write-Host "SetupPath: RootDir/AbsRoot not set; abort." -ForegroundColor Red
            return
        }

        # Helper: resolve config path (absolute under $root if relative)
        function ResolveCfgPath([string] $p) {
            if (-not $p) { return $null }
            try {
                if (Test-Path -LiteralPath $p) {
                    return (Get-Item -LiteralPath $p).FullName.TrimEnd('\')
                }
                $maybe = Join-Path $root $p
                if (Test-Path -LiteralPath $maybe) {
                    return (Get-Item -LiteralPath $maybe).FullName.TrimEnd('\')
                }
            }
            catch {}
            return $p
        }

        # --- Build candidate directories ---

        $candidates = @()

        # Python + Scripts
        $py = ResolveCfgPath( (Get-ConfigValue $cfg 'PyDir') )
        if ($py) {
            $candidates += $py
            $candidates += (Join-Path $py 'Scripts')
        }

        # CUDA / cuDNN bin
        $cudaBin = ResolveCfgPath( (Get-ConfigValue $cfg 'CudaBin') )
        $cuDNNBin = ResolveCfgPath( (Get-ConfigValue $cfg 'CuDNNBin') )
        if ($cudaBin) { $candidates += $cudaBin }
        if ($cuDNNBin) { $candidates += $cuDNNBin }

        # PortableGit
        $pgit = ResolveCfgPath( (Get-ConfigValue $cfg 'PGit') )
        if ($pgit) {
            $candidates += (Join-Path $pgit 'cmd')
            $candidates += (Join-Path $pgit 'bin')
            $candidates += (Join-Path $pgit 'mingw64\bin')
        }

        # FFmpeg: เดาว่า Config.FFmpeg ชี้ไป root ของ FFmpeg (เช่น โฟลเดอร์ที่มี bin\ffmpeg.exe)
        $ffmpegRoot = ResolveCfgPath( (Get-ConfigValue $cfg 'FFmpeg') )
        if ($ffmpegRoot) {
            $ffBin1 = Join-Path $ffmpegRoot 'bin'
            if (Test-Path (Join-Path $ffBin1 'ffmpeg.exe')) {
                $candidates += $ffBin1
            }
            elseif (Test-Path (Join-Path $ffmpegRoot 'ffmpeg.exe')) {
                $candidates += $ffmpegRoot
            }
            else {
                # ไม่รู้ structure แน่ชัด ใส่ root ไปก่อน
                $candidates += $ffmpegRoot
            }
        }

        # เก็บเฉพาะที่มีอยู่จริง
        $existing = New-Object System.Collections.Generic.List[string]
        foreach ($p in $candidates) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                try { $full = (Get-Item -LiteralPath $p).FullName.TrimEnd('\') } catch { $full = $p }
                if (-not ($existing -contains $full)) { $null = $existing.Add($full) }
            }
        }

        if ($existing.Count -eq 0) {
            Write-Host "SetupPath: No candidate directories exist under $root. Nothing changed." -ForegroundColor Yellow
        }
        else {
            # Prepend to session PATH (unique)
            $this.PrependUniquePathItems($existing.ToArray())
            Write-Host "SetupPath: Prepend $($existing.Count) directories to session PATH:" -ForegroundColor Cyan
            foreach ($e in $existing) { Write-Host "  + $e" }
        }

        # ตรวจ executables จาก PATH ที่เราเพิ่งเติม
        $detected = $this.DetectExecutables($existing.ToArray())

        # Create session-only functions/aliases สำหรับ python/pip/git/ffmpeg
        try { $this.CreateSessionAliases($detected) } catch {}

        # Persist to User PATH ถ้าขอ
        if ($Persist -and $existing.Count -gt 0) {
            try {
                $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User') -or ''
                $userItems = ($currentUserPath -split ';' | Where-Object { $_ -ne '' })
                $toPrependUser = New-Object System.Collections.Generic.List[string]
                foreach ($e in $existing) {
                    $found = $false
                    foreach ($ui in $userItems) {
                        if ($ui -ieq $e) { $found = $true; break }
                    }
                    if (-not $found) { $null = $toPrependUser.Add($e) }
                }
                if ($toPrependUser.Count -gt 0) {
                    $newUserPath = ($toPrependUser + $userItems) -join ';'
                    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
                    Write-Host "SetupPath: Persisted $($toPrependUser.Count) entries to User PATH." -ForegroundColor Green
                }
                else {
                    Write-Host "SetupPath: No new entries to persist to User PATH." -ForegroundColor Green
                }
            }
            catch {
                Write-Host "SetupPath: Failed to persist PATH to User: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Quick checks (session)
        Write-Host "`nQuick checks (session):" -ForegroundColor Green
        try { & python --version }            catch { Write-Host "  python: (not available or redirected)" }
        try { & python -m pip --version }     catch { Write-Host "  pip: (not available)" }
        try { & git --version }               catch { Write-Host "  git: (not available)" }
        try { & ffmpeg -version | Select-String -Pattern '^ffmpeg' -SimpleMatch } catch { Write-Host "  ffmpeg: (not available)" }
    }


    <#
        .SYNOPSIS
            One-shot installer สำหรับ Python embed + pip + PortableGit + FFmpeg + NVIDIA CUDA/cuDNN

        .DESCRIPTION
            รันทีเดียวแล้วจัดการทุกอย่างตามลำดับ:
              1) ตรวจสอบโครงสร้างโฟลเดอร์ (RootDir, DLDir, PyDir, driver\*)
              2) ดาวน์โหลด + แตกไฟล์ Python embeddable ตามเวอร์ชันที่ระบุ
              3) ติดตั้ง pip ลง Python embeddable
              4) ติดตั้ง PortableGit แบบ portable ไปยัง driver\PortableGit
              5) ติดตั้ง FFmpeg ไปยัง driver\ffmpeg
              6) ติดตั้ง NVIDIA runtime (CUDA + cuDNN) ผ่าน InstallNvidia("all")
              7) เรียก SetupPath($true) เพื่ออัปเดต PATH (session + User)
              8) เคลียร์โฟลเดอร์ดาวน์โหลด (DLDir) เพื่อล้าง cache

        .PARAMETER version
            เวอร์ชัน Python (เช่น "3.12.10") ต้องตรงกับรูปแบบที่ GetPythonVersions() คืนค่า

        .NOTES
            - ต้องมี NVIDIA GPU และไดรเวอร์เวอร์ชันที่รองรับ CUDA 13.x ขึ้นไป
            -  เมธอดต่อไปนี้มีอยู่ใน class:
                * IsFolder()
                * CreateFolders()
                * DownloadAndCopyPython()
                * GetPip()
                * InstallPGit()
                * InstallFFmpeg()
                * InstallNvidia()
                * SetupPath()
                * RemoveFolder()
    #>
    
    [void] InstallFlow() {
        $version = $this.ShowPythonVersionsMenu()
        Write-Host "Select Python Version $version"
        $this.InstallFlow($version)
         
    }
    [void] InstallFlow([string] $version) {
        if (-not $version -or [string]::IsNullOrWhiteSpace($version)) {
            throw [System.ArgumentException]::new("InstallFlow: version is null or empty.")
        }

        if (-not $this.Config) {
            throw "InstallFlow: Config is not initialized. Make sure constructor / SetPath() has been called."
        }

        Write-Host ""
        Write-Host "=== InstallFlow :: Python $version ===" -ForegroundColor Cyan

        # 1) Ensure folder structure exists
        try {
            if (-not $this.IsFolder()) {
                Write-Host "InstallFlow: Folder structure missing. Creating folders (skip existing)..." -ForegroundColor Yellow
                $this.CreateFolders()
            }
            else {
                Write-Host "InstallFlow: Folder structure OK." -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Warning "InstallFlow: Failed while checking/creating folders. $_"
            return
        }

        # 2) Download & install Python embeddable
        Write-Host "InstallFlow: Downloading + installing Python $version (embeddable)..." -ForegroundColor Cyan
        $downloadOk = $false
        try {
            $downloadOk = $this.DownloadAndCopyPython($version, $false, $true, $false)
        }
        catch {
            Write-Warning "InstallFlow: DownloadAndCopyPython($version) threw an exception: $_"
            $downloadOk = $false
        }

        if (-not $downloadOk) {
            Write-Warning "InstallFlow: DownloadAndCopyPython($version) failed. Aborting flow."
            return
        }
        Write-Host "InstallFlow: Python $version installed successfully." -ForegroundColor Green

        # 3) Install pip
        Write-Host "InstallFlow: Installing pip into embedded Python..." -ForegroundColor Cyan
        $pipOk = $false
        try {
            $pipOk = $this.GetPip()
        }
        catch {
            Write-Warning "InstallFlow: GetPip() threw an exception: $_"
            $pipOk = $false
        }

        if (-not $pipOk) {
            Write-Warning "InstallFlow: GetPip() failed. You may need to install pip manually."
        }
        else {
            Write-Host "InstallFlow: pip installed successfully." -ForegroundColor Green
        }

        # 4) Install PortableGit
        Write-Host "InstallFlow: Installing PortableGit..." -ForegroundColor Cyan
        $gitOk = $false
        try {
            $gitOk = $this.InstallPGit($false)
        }
        catch {
            Write-Warning "InstallFlow: InstallPGit() threw an exception: $_"
            $gitOk = $false
        }

        if (-not $gitOk) {
            Write-Warning "InstallFlow: InstallPGit() failed. Git may not be available on PATH."
        }
        else {
            Write-Host "InstallFlow: PortableGit installed successfully." -ForegroundColor Green
        }

        # 5) Install FFmpeg
        Write-Host "InstallFlow: Installing FFmpeg..." -ForegroundColor Cyan
        $ffmpegOk = $false
        try {
            $ffmpegOk = $this.InstallFFmpeg($false)
        }
        catch {
            Write-Warning "InstallFlow: InstallFFmpeg() threw an exception: $_"
            $ffmpegOk = $false
        }

        if (-not $ffmpegOk) {
            Write-Warning "InstallFlow: InstallFFmpeg() failed. FFmpeg may not be available on PATH."
        }
        else {
            Write-Host "InstallFlow: FFmpeg installed successfully." -ForegroundColor Green
        }

        # 6) Install NVIDIA runtime (CUDA + cuDNN)
        Write-Host "InstallFlow: Installing NVIDIA components (CUDA + cuDNN)..." -ForegroundColor Cyan
        $nvSummary = $null
        try {
            $nvSummary = $this.InstallNvidia("all")
        }
        catch {
            Write-Warning "InstallFlow: InstallNvidia('all') threw an exception: $_"
            $nvSummary = $null
        }

        if ($nvSummary -and $nvSummary.PSObject.Properties.Match('Success').Count -gt 0) {
            if ($nvSummary.Success) {
                Write-Host "InstallFlow: NVIDIA components installed successfully." -ForegroundColor Green
            }
            else {
                Write-Warning "InstallFlow: InstallNvidia reported failure."
                if ($nvSummary.PSObject.Properties.Match('Error').Count -gt 0 -and $nvSummary.Error) {
                    Write-Warning "InstallFlow: InstallNvidia error: $($nvSummary.Error)"
                }
            }
        }
        else {
            Write-Host "InstallFlow: InstallNvidia('all') executed (no summary object returned)." -ForegroundColor Yellow
        }

        # 7) Setup PATH (session + persist user) ตาม config (PyDir, PGit, FFmpeg, CudaBin, CuDNNBin)
        Write-Host "InstallFlow: Updating PATH (session + user)..." -ForegroundColor Cyan
        try {
            $this.SetupPath($true)
        }
        catch {
            Write-Warning "InstallFlow: SetupPath($true) threw an exception: $_"
        }

        # 8) Cleanup download/cache folder (DLDir)
        Write-Host "InstallFlow: Cleaning up download/cache folder (DLDir)..." -ForegroundColor Cyan
        try {
            $this.RemoveFolder("DLDir")
        }
        catch {
            Write-Warning "InstallFlow: RemoveFolder('DLDir') threw an exception: $_"
        }

        Write-Host "=== InstallFlow :: Completed (Python $version) ===" -ForegroundColor Green
    }

    
}

 
$Data = [Main]::new()
$Data.InstallFlow()
# $Data.InstallFlow("3.12.10")
# $Data.SetupPath($true)


# Manual installation (advanced / step-by-step)
# ใช้กรณีต้องการควบคุมทุกขั้นตอนเอง แทนการใช้ InstallFlow()

############################################
# 1) สร้างโฟลเดอร์พื้นฐานทั้งหมดตาม Config
#    - RootDir
#    - DLDir (โฟลเดอร์ดาวน์โหลดชั่วคราว)
#    - PyDir (โฟลเดอร์ Python embeddable)
#    - driver\* (เช่น ffmpeg, PortableGit, CUDA, cuDNN)
# $Data.CreateFolders()

# 2) แสดงเมนูให้เลือกเวอร์ชัน Python จากรายการที่ดึงมาจาก NuGet
#    คืนค่าเป็นสตริงเวอร์ชัน เช่น "3.12.10"
# $version = $Data.ShowPythonVersionsMenu()

# 3) ดาวน์โหลด + แตกไฟล์ Python embeddable ตามเวอร์ชันที่เลือกไปยัง PyDir
# $Data.DownloadAndCopyPython($version)

# 4) ติดตั้ง pip ลงใน Python embeddable
# $Data.GetPip()

# 5) ดาวน์โหลดและติดตั้ง FFmpeg (portable) ไปยังโฟลเดอร์ driver\ffmpeg
# $Data.InstallFFmpeg($false)

# 6) ดาวน์โหลดและติดตั้ง PortableGit ไปยังโฟลเดอร์ driver\PortableGit
# $Data.InstallPGit($false)

# 7) ดาวน์โหลดตัวติดตั้ง NVIDIA CUDA runtime
# $Data.GetNvTool("cuda")

# 8) ดาวน์โหลดไฟล์ที่ต้องใช้สำหรับติดตั้ง cuDNN
# $Data.GetNvTool("cudnn")

# 9) ติดตั้ง CUDA จากไฟล์ที่ดาวน์โหลดไว้
# $Data.InstallNvidia("cuda")

# 10) ติดตั้ง cuDNN จากไฟล์ที่ดาวน์โหลดไว้
# $Data.InstallNvidia("cudnn")

# 11) ลบโฟลเดอร์ DLDir (ไฟล์ดาวน์โหลดชั่วคราว) ทิ้งเพื่อล้าง cache
# $Data.RemoveFolder("DLDir")

# 12) ตั้งค่า PATH ใน session ปัจจุบัน (และบันทึกลง User ถ้าระบบรองรับ)
#     - ทำให้ python / pip / git / ffmpeg / CUDA / cuDNN ใช้งานได้ใน PowerShell นี้
# $Data.SetupPath($true)
############################################



 