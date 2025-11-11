# Python Embedded Manager

A simple PowerShell tool to manage embedded Python versions via NuGet packages. Easily download, install, and alias Python inside a dedicated folder, without interfering with your global Python installation.

---

## Features

- List all stable Python versions available via NuGet.
- Install embedded Python in a dedicated folder (`python_embeded`).
- Reinstall or upgrade existing embedded Python.
- Alias Python and pip commands globally.
- Clean and interactive PowerShell menu UI.

---

## Requirements

- Windows 10/11
- PowerShell 7+
- Internet connection (for downloading NuGet packages)

---

## Installation

1. Clone or download this repository.
2. Run the batch file `RunAs.bat` to launch the tool with elevated privileges:

```bat
RunAs.bat
```

This will start PowerShell with administrator rights and launch `PythonNuget.ps1`.

---

## Usage

1. Navigate the menu using **↑ / ↓** keys.
2. Press **Enter** to select an action.
3. Press **Esc** to exit the program.
4. After installing Python, the tool will provide the command to check your embedded Python and pip versions:

```powershell
python -c "import sys, pip; print('Python version:', sys.version); print('pip version:', pip.__version__); print('Python executable:', sys.executable); print('pip module:', pip.__file__);"
```

---

## 🎞️ Demo Video

![image](https://github.com/user-attachments/assets/1bc6cb14-ae4f-4a40-9c33-e35eb87c68f3)

---

## File Structure

```
PythonNuget/
│
├─ PythonNuget.ps1       # Main PowerShell script
├─ RunAs.bat               # Batch file to launch PS script elevated
├─ README.md             # This documentation TH
├─ README.EN.md          # This documentation EN
├─ download/             # Folder for NuGet packages and temporary files
└─ python_embeded/       # Folder for installed embedded Python versions
```

---

## Notes

- Embedded Python will be installed locally in `python_embeded`, leaving global Python untouched.
- Pip alias is set globally to the embedded Python. If a global Python exists, the alias will warn you before overriding.
- This is intended for personal or educational use.
- **Flexibility:** You can move this entire project folder anywhere and rename it to whatever you like (e.g., `MyTools`, `PortablePy`). The script will work based on its current location.

---

## License

This project uses the **PSF License 2.0** (Python Software Foundation License) for compatibility with Python packages. All code in this repository is open source and free to use.

