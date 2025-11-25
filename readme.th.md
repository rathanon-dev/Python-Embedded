# คู่มือการใช้งาน AI-Driver (README ภาษาไทย)

## ข้อกำหนดระบบ
- Windows 10/11 (64-bit)
- PowerShell 5.1+ หรือ PowerShell 7+
- การ์ดจอ NVIDIA เท่านั้น
- NVIDIA Driver เวอร์ชันล่าสุดที่รองรับ CUDA 13.x+
- ต้องมีสิทธิ์แก้ไข User PATH

---

## การติดตั้งครั้งแรก (First-time Installation)

ใช้สำหรับติดตั้ง Python + pip + PortableGit + FFmpeg + CUDA + cuDNN

```powershell
$Data = [Main]::new()

# ขั้นตอนติดตั้งครั้งแรก (รันครั้งเดียว)
$Data.InstallFlow("3.12.10")

# ตั้งค่า PATH (session + User)
# $Data.SetupPath($true)
```

ตรวจสอบว่าเครื่องมือพร้อมใช้งาน:

```powershell
python --version
pip --version
git --version
ffmpeg -version
```

---

## การใช้งานครั้งถัดไป (เมื่อเปิด PowerShell ใหม่)

เมื่อติดตั้งเสร็จแล้ว **ไม่ต้องรัน InstallFlow ซ้ำอีก**  
ให้ตั้งค่า session ใหม่ด้วยคำสั่งเดียว:

```powershell
$Data = [Main]::new()

# อย่ารันซ้ำ
# $Data.InstallFlow("3.12.10")

# ให้รันแค่คำสั่งนี้
$Data.SetupPath($true)
```

ตรวจสอบเหมือนเดิม:

```powershell
python --version
pip --version
git --version
ffmpeg -version
```

---

## ทำไมต้องรัน SetupPath ทุกครั้งเมื่อเปิด PowerShell ใหม่?

- ค่า PATH ที่สร้างใน session จะอยู่แค่ในหน้าต่าง PowerShell ที่เปิดอยู่
- ฟังก์ชัน / alias ที่ระบบสร้างขึ้นจะมีเฉพาะใน session นี้เท่านั้น
- `SetupPath($true)` รันซ้ำได้ ปลอดภัย และช่วยเซ็ตสภาพแวดล้อมให้พร้อมใช้งานทุกครั้ง

**สรุป:**
- ติดตั้งครั้งแรก → `InstallFlow` + `SetupPath`
- เปิด PowerShell ใหม่ → `SetupPath` อย่างเดียว


## โหมดติดตั้งแบบ Manual (ขั้นตอนแยกทีละสเต็ป)

เหมาะสำหรับผู้ใช้ที่ต้องการควบคุมทุกขั้นตอนเอง หรือใช้เพื่อดีบักปัญหาเฉพาะจุด

```powershell
$Data = [Main]::new()

# 1) สร้างโฟลเดอร์พื้นฐานทั้งหมด
$Data.CreateFolders()

# 2) เลือกเวอร์ชัน Python จากเมนู
$version = $Data.ShowPythonVersionsMenu()

# 3) ดาวน์โหลด + แตกไฟล์ Python embeddable
$Data.DownloadAndCopyPython($version)

# 4) ติดตั้ง pip
$Data.GetPip()

# 5) ติดตั้ง FFmpeg (portable)
$Data.InstallFFmpeg($false)

# 6) ติดตั้ง PortableGit
$Data.InstallPGit($false)

# 7) ดาวน์โหลดตัวติดตั้ง CUDA และ cuDNN
$Data.GetNvTool("cuda")
$Data.GetNvTool("cudnn")

# 8) ติดตั้ง CUDA และ cuDNN จากไฟล์ที่ดาวน์โหลด
$Data.InstallNvidia("cuda")
$Data.InstallNvidia("cudnn")

# 9) ล้างไฟล์ดาวน์โหลดชั่วคราว
$Data.RemoveFolder("DLDir")

# 10) ตั้งค่า PATH สำหรับ session ปัจจุบัน
$Data.SetupPath($true)