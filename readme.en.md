# AI-Driver Usage Guide (English README)

## System Requirements
- Windows 10/11 (64-bit)
- PowerShell 5.1+ or PowerShell 7+
- NVIDIA GPU only
- Latest NVIDIA driver supporting CUDA 13.x+
- Permission to modify User PATH

---

## First-time Installation

Used to install Python + pip + PortableGit + FFmpeg + CUDA + cuDNN.

```powershell
$Data = [Main]::new()

# Install everything (run once)
$Data.InstallFlow("3.12.10")

# Set PATH (session + User)
# $Data.SetupPath($true)
```

Verify tools:

```powershell
python --version
pip --version
git --version
ffmpeg -version
```

---

## Usage on Subsequent Sessions (Every time you open PowerShell)

After installation, **do NOT run InstallFlow again.**  
Just set up the new PowerShell session:

```powershell
$Data = [Main]::new()

# Do NOT run this again
# $Data.InstallFlow("3.12.10")

# Use this every session
$Data.SetupPath($true)
```


The command `SetupPath($true)` does not modify the real User PATH in Windows.
It only updates the PATH inside the current PowerShell session.

- Once you close the PowerShell window, all PATH additions are lost.
- Therefore, every time you open a new PowerShell session, you must run:
 

Verify:

```powershell
python --version
pip --version
git --version
ffmpeg -version
```

---

## Why must SetupPath be run on every new PowerShell session?

- Session-level PATH only exists while the current PowerShell window is open.
- Functions / aliases created by the script only exist in the current session.
- Running `SetupPath($true)` is safe and ensures a correct environment every time.

**Summary:**
- First install → `InstallFlow` + `SetupPath`
- New PowerShell session → only `SetupPath`


## Manual Installation (step-by-step mode)

This mode is for advanced users who want full control over each step,
or for debugging a specific part of the installation flow.

```powershell
$Data = [Main]::new()

# 1) Create all base folders
$Data.CreateFolders()

# 2) Show a menu of available Python versions and pick one
$version = $Data.ShowPythonVersionsMenu()

# 3) Download and extract the selected Python embeddable
$Data.DownloadAndCopyPython($version)

# 4) Install pip into the embeddable Python
$Data.GetPip()

# 5) Install FFmpeg (portable build)
$Data.InstallFFmpeg($false)

# 6) Install PortableGit
$Data.InstallPGit($false)

# 7) Download NVIDIA CUDA and cuDNN installers/tools
$Data.GetNvTool("cuda")
$Data.GetNvTool("cudnn")

# 8) Install CUDA and cuDNN from the downloaded files
$Data.InstallNvidia("cuda")
$Data.InstallNvidia("cudnn")

# 9) Clean up the temporary download folder
$Data.RemoveFolder("DLDir")

# 10) Set up PATH for the current PowerShell session
$Data.SetupPath($true)
