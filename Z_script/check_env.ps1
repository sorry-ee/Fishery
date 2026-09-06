# check_env.ps1 - 智慧渔业系统环境就绪检查（只读预检）
# ------------------------------------------------------------
# 用法（在项目根下执行；脚本用 $PSScriptRoot 自动定位项目根）：
#   powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1
#   powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1 -CheckOnnx -Deep
#
# 可选参数：
#   -Root <path>     指定项目根目录（默认 = 本脚本所在目录）
#   -SkipGpu         跳过 GPU/CUDA 探测（无显卡环境）
#   -Deep            额外真实加载模型推理一次（较慢，约 10s）
#   -CheckOnnx       只读探测 onnxruntime-gpu 版本并提示 CUDA 匹配（pip show，不触发 AutoUpdate）
#   -NoColor         纯文本输出（便于重定向到文件/CI）
#
# 退出码：0 = 无必查失败（可尝试启动）；1 = 存在必查失败
#
# 说明：验证跑起本项目所需依赖（venv / Python 包 / GPU / 模型 / 密钥 / 端口）是否齐全。
#       只检测、不修改、不联网、不触发 ultralytics AutoUpdate。
#
# 注意：本文件必须以 UTF-8 with BOM 保存，否则 Windows PowerShell 5.1 会中文乱码。
# ------------------------------------------------------------

param(
    [string]$Root = "",
    [switch]$SkipGpu,
    [switch]$Deep,
    [switch]$CheckOnnx,
    [switch]$NoColor
)

$ErrorActionPreference = "SilentlyContinue"

# ---------- 定位项目根 ----------
# 脚本位于 Z_script\ 下，项目根 = 脚本所在目录的上一级
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }
if (-not $Root -or -not (Test-Path $Root)) { $Root = (Get-Location).Path }
Set-Location $Root
$py = Join-Path $Root ".venv\Scripts\python.exe"
$models = Join-Path $Root "models"

# ---------- 结果收集 ----------
$script:fatal = 0
$script:warn  = 0
$script:pass  = 0
$script:info  = 0

function Emit {
    param([string]$Level, [string]$Name, [string]$Detail = "")
    switch ($Level) {
        "PASS" { $script:pass++ }
        "FAIL" { $script:fatal++ }
        "WARN" { $script:warn++ }
        default { $script:info++ }
    }
    $tag = switch ($Level) { "PASS" { "[ OK ]" }; "FAIL" { "[FAIL]" }; "WARN" { "[WARN]" }; default { "[INFO]" } }
    $color = switch ($Level) { "PASS" { "Green" }; "FAIL" { "Red" }; "WARN" { "Yellow" }; default { "Cyan" } }
    $line = "{0} {1}" -f $tag, $Name
    if ($Detail) { $line += "  --  $Detail" }
    if ($NoColor) { Write-Host $line } else { Write-Host $line -ForegroundColor $color }
}

function Section {
    param([string]$Title)
    Write-Host ""
    if ($NoColor) { Write-Host $Title } else { Write-Host ("===== " + $Title + " =====") -ForegroundColor Magenta }
}

# ---------- 探测用的内联 Python（一次进程完成多包 + CUDA 探测） ----------
$probeCode = @'
import importlib
out = []
def chk(m):
    try:
        importlib.import_module(m); return "OK"
    except Exception: return "MISSING"
for m in ["cv2", "flask", "flask_sock", "openai", "numpy", "sklearn"]:
    out.append("%s=%s" % (m, chk(m)))
try:
    import torch
    out.append("torch=%s" % torch.__version__)
    out.append("build_cuda=%s" % (torch.version.cuda or "NONE"))
    out.append("cuda_ok=%s" % torch.cuda.is_available())
    if torch.cuda.is_available():
        out.append("gpu_name=%s" % torch.cuda.get_device_name(0))
        try:
            out.append("gpu_mem=%.1f" % (torch.cuda.get_device_properties(0).total_memory / 1024**3))
        except Exception:
            pass
except Exception:
    out.append("torch=MISSING")
try:
    import ultralytics
    out.append("ultralytics=%s" % ultralytics.__version__)
except Exception:
    out.append("ultralytics=MISSING")
print("\n".join(out))
'@

# 把探测代码写入临时文件执行（避免 PS5.1 多行字符串传给 python -c 的兼容问题）
$probeFile = Join-Path $env:TEMP ("fishery_env_probe_" + $PID + ".py")
[IO.File]::WriteAllText($probeFile, $probeCode, (New-Object System.Text.UTF8Encoding $false))
$probeHash = @{}
if (Test-Path $py) {
    $probeOut = & $py $probeFile 2>&1
    foreach ($ln in $probeOut) {
        if ($ln -match '^(.*?)=(.*)$') { $probeHash[$matches[1]] = $matches[2] }
    }
}
Remove-Item $probeFile -ErrorAction SilentlyContinue

# =====================================================================
# A. 系统与外部程序
# =====================================================================
Section "A. 系统与外部程序"

$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($osInfo) {
    Emit "INFO" "操作系统" $osInfo.Caption
} else {
    Emit "PASS" "操作系统" "Windows"
}

# ffmpeg：优先用项目内自带 (tools\ffmpeg\bin)，找不到回退系统 PATH
$ffmpeg = ""
if (Test-Path "$Root\tools\ffmpeg\bin\ffmpeg.exe") { $ffmpeg = "$Root\tools\ffmpeg\bin\ffmpeg.exe" }
if (-not $ffmpeg) {
    $g = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($g) { $ffmpeg = $g.Source }
}
if ($ffmpeg) {
    Emit "PASS" "ffmpeg 可用" $ffmpeg
    $nvenc = & $ffmpeg -hide_banner -encoders 2>$null | Select-String "nvenc"
    if ($nvenc) { Emit "INFO" "ffmpeg 支持 h264_nvenc" "H.264 GPU 硬编可用" }
    else { Emit "WARN" "ffmpeg 无 h264_nvenc" "将回退 CPU 软编 (libx264)，可在 config.py 改 H264_ENCODER" }
} else {
    Emit "FAIL" "ffmpeg 可用" "未找到 ffmpeg（项目内 tools\ffmpeg\bin 或系统 PATH 均无），推流/H.264 必需"
}

if (Test-Path (Join-Path $Root "tools\mediamtx\mediamtx.exe")) {
    Emit "PASS" "mediamtx.exe 存在"
} else {
    Emit "FAIL" "mediamtx.exe 存在" "缺少 tools\mediamtx\mediamtx.exe（本地 RTSP 服务器）"
}

$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $driver = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1)
    if ($driver) { Emit "INFO" "NVIDIA 驱动版本" $driver }
    else { Emit "INFO" "NVIDIA 驱动" "nvidia-smi 无输出" }
} else {
    if ($SkipGpu) { Emit "INFO" "nvidia-smi" "已用 -SkipGpu，跳过（无 NVIDIA 工具）" }
    else { Emit "WARN" "nvidia-smi 不可用" "无法读取驱动版本（GPU 推理可能需要）" }
}

# A6. 可用摄像头（可选：真实摄像头推流用，仅提示，不影响退出码）
if ($ffmpeg) {
    # ffmpeg 设备清单写 stderr；SilentlyContinue 会吞掉它，故临时降为 Continue 捕获（同 troubleshooting 第 9 条）
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $devOut = (& $ffmpeg -hide_banner -f dshow -list_devices true -i dummy 2>&1 | Out-String)
    } finally {
        $ErrorActionPreference = $prev
    }
    $cams = @()
    foreach ($m in [regex]::Matches($devOut, '"(.*?)"\s*\(video')) {
        if ($m.Groups[1].Value) { $cams += $m.Groups[1].Value }
    }
    if ($cams.Count -gt 0) {
        Emit "INFO" "可用摄像头" (($cams -join " | ") + " —— 真实推流见 Z_script\run\start_pc_camera.ps1 / start_usb_camera.ps1")
    } else {
        Emit "WARN" "可用摄像头" "未检测到（真实摄像头不可用；可用本地视频/RTSP 代替）"
    }
}

# =====================================================================
# B. Python 虚拟环境
# =====================================================================
Section "B. Python 虚拟环境"

if (Test-Path $py) {
    Emit "PASS" ".venv 存在" $py
    $ver = & $py --version 2>&1
    $verStr = "$ver"
    if ($verStr -match '(\d+)\.(\d+)') {
        $major = [int]$matches[1]; $minor = [int]$matches[2]
        if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 9)) {
            Emit "PASS" "Python 版本" $verStr
        } else {
            Emit "FAIL" "Python 版本" "$verStr（项目要求 3.9+，推荐 3.11）"
        }
    }
} else {
    Emit "FAIL" ".venv 存在" "找不到 $py"
    Write-Host ""
    Write-Host "检测中止：缺少虚拟环境，后续 Python 相关检查跳过。" -ForegroundColor Yellow
    Write-Host "汇总：就绪 $script:pass / 警告 $script:warn / 失败 $script:fatal" -ForegroundColor Yellow
    if ($script:fatal -gt 0) { exit 1 } else { exit 0 }
}

# =====================================================================
# C. Python 第三方包
# =====================================================================
Section "C. Python 第三方包"

function Chk-Pkg {
    param([string]$Key, [string]$Display, [string]$Level)
    if ($probeHash[$Key] -eq "OK") {
        Emit "PASS" "$Display 可用"
    } else {
        $hint = "请安装: pip install $Display"
        if ($Level -eq "FAIL") { Emit "FAIL" "$Display 可用" $hint }
        else { Emit "WARN" "$Display 可用" "$hint（缺失会降级：RAG 退化为关键词匹配）" }
    }
}

if (-not $probeHash.ContainsKey("torch")) {
    Emit "FAIL" "torch 可用" "未安装。GPU 版安装参考: pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121"
} else {
    Emit "PASS" "torch 版本" $probeHash["torch"]
    if ($probeHash["build_cuda"] -eq "NONE") {
        Emit "WARN" "torch 为 CPU 版" "版本号不含 +cu，GPU 推理不可用；请重装 GPU 版 torch (cu121)"
    }
}
if (-not $probeHash.ContainsKey("ultralytics")) {
    Emit "FAIL" "ultralytics 可用" "未安装。请: pip install ultralytics"
} else {
    Emit "PASS" "ultralytics 版本" $probeHash["ultralytics"]
}
Chk-Pkg "cv2"       "opencv-python (cv2)"   "FAIL"
Chk-Pkg "flask"     "flask"                 "FAIL"
Chk-Pkg "flask_sock" "flask-sock"           "FAIL"
Chk-Pkg "openai"    "openai"                "FAIL"
Chk-Pkg "numpy"     "numpy"                 "FAIL"
Chk-Pkg "sklearn"   "scikit-learn"          "WARN"

# =====================================================================
# D. GPU 与 CUDA
# =====================================================================
Section "D. GPU 与 CUDA"

if ($SkipGpu) {
    Emit "INFO" "GPU 探测" "已用 -SkipGpu 跳过"
} else {
    if (-not $probeHash.ContainsKey("torch")) {
        Emit "FAIL" "CUDA 对 torch 可用" "torch 未安装，无法判定"
    } else {
        if ($probeHash["cuda_ok"] -eq "True") {
            Emit "PASS" "CUDA 对 torch 可用" "推理将使用 GPU"
            Emit "PASS" "torch CUDA 构建" "CUDA $($probeHash['build_cuda'])"
            $g = if ($probeHash["gpu_name"]) { $probeHash["gpu_name"] } else { "未知" }
            $mem = if ($probeHash["gpu_mem"]) { "  ($($probeHash['gpu_mem'])) GB" } else { "" }
            Emit "INFO" "显卡" "$g$mem"
        } else {
            Emit "FAIL" "CUDA 对 torch 可用" "torch.cuda.is_available()=False：无驱动 / 无显卡 / torch 为 CPU 版"
        }
    }

    if ($Deep) {
        Write-Host ""
        Write-Host "--- 深度检查：真实加载模型推理一次（约 10s）---" -ForegroundColor Yellow
        $deepCode = @'
import sys; sys.path.insert(0, ".")
import numpy as np, torch
from core.custom_yolo import register; register()
from ultralytics import YOLO
dev = "cuda" if torch.cuda.is_available() else "cpu"
try:
    m = YOLO("models/fish_detect_m.pt", task="detect")
    frame = (np.random.rand(480, 640, 3) * 255).astype("uint8")
    r = m.predict(frame, conf=0.25, imgsz=640, device=dev, verbose=False)
    print("DEEP_OK device=%s det=%d" % (dev, len(r[0].boxes)))
except Exception as e:
    print("DEEP_FAIL %s" % e)
'@
        $deepFile = Join-Path $env:TEMP ("fishery_env_deep_" + $PID + ".py")
        [IO.File]::WriteAllText($deepFile, $deepCode, (New-Object System.Text.UTF8Encoding $false))
        $deepOut = & $py $deepFile 2>&1 | Select-Object -Last 1
        Remove-Item $deepFile -ErrorAction SilentlyContinue
        if ("$deepOut" -match "DEEP_OK") { Emit "PASS" "真实模型推理" "$deepOut" }
        else { Emit "WARN" "真实模型推理" "加载/推理异常: $deepOut（可忽略，但建议排查模型兼容性）" }
    }
}

# =====================================================================
# E. 模型与配置文件
# =====================================================================
Section "E. 模型与配置文件"

$mustFiles = @(
    @("models\fish_detect_m.pt",   "默认 YOLO 检测模型 (EMA)"),
    @("models\sam2.1_t.pt",        "SAM2 权重"),
    @("models\sam2_hiera_t.yaml",  "SAM2 配置文件")
)
foreach ($f in $mustFiles) {
    if (Test-Path (Join-Path $Root $f[0])) { Emit "PASS" $f[1] "($($f[0]))" }
    else { Emit "FAIL" $f[1] "缺少 $($f[0])" }
}

$optModels = @(
    "fish_detect_seam.pt", "fish_detect_s_ECA_EMA_BIFPN.pt", "fish_detect.onnx",
    "fish_disease.pt", "fish_seg_yolo26.pt", "fish_seg_yolo26_nano.pt",
    "fish_seg_yolo11n.pt", "fish_seg_yolo11n.onnx", "fish_seg_yolo26_nano.onnx"
)
$missingOpt = @()
foreach ($n in $optModels) {
    if (-not (Test-Path (Join-Path $models $n))) { $missingOpt += $n }
}
if ($missingOpt.Count -eq 0) {
    Emit "INFO" "可选模型" "全部齐全 ($($optModels.Count) 个)"
} else {
    Emit "WARN" "可选模型缺失" ($missingOpt -join ", ") + " （缺这些只影响下拉框对应选项）"
}

$wweDir = Join-Path $Root "WWE-UIE\output\Fishery_WWE_UIEB\UIEB"
$bestPth = Get-ChildItem $wweDir -Recurse -Filter "best_model.pth" -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($bestPth) { Emit "PASS" "WWE-UIE 增强权重" $bestPth.FullName.Replace($Root, ".") }
else { Emit "WARN" "WWE-UIE 增强权重" "未找到 best_model.pth，图像增强功能将不可用（不影响主流程）" }

# =====================================================================
# F. 密钥 / 数据
# =====================================================================
Section "F. 密钥 / 数据"

$envFile = Join-Path $Root ".env"
$hasKeyFile = $false
if (Test-Path $envFile) {
    if (Select-String -Path $envFile -Pattern '^\s*DEEPSEEK_API_KEY\s*=\s*\S+' -Quiet) { $hasKeyFile = $true }
}
$hasKeyEnv = [bool]$env:DEEPSEEK_API_KEY
if ($hasKeyFile -or $hasKeyEnv) {
    Emit "PASS" "DeepSeek API Key" "已配置（值不显示）"
} else {
    Emit "WARN" "DeepSeek API Key" ".env 中未配置 DEEPSEEK_API_KEY，LLM 诊断/对话不可用（不影响视频/AI 检测）"
}

$hasVideo = @(Get-ChildItem (Join-Path $Root "test_video*.mp4") -ErrorAction SilentlyContinue).Count -gt 0
if ($hasVideo) {
    Emit "PASS" "本地推流视频源" "test_video*.mp4 存在"
} else {
    Emit "WARN" "本地推流视频源" "无 test_video*.mp4（需连接真实 RTSP 摄像头或用 Z_script\run\start_all.ps1 推流）"
}

# =====================================================================
# G. 端口占用（提示）
# =====================================================================
Section "G. 端口占用（提示）"

foreach ($prt in @(@(8554, "mediamtx RTSP"), @(5000, "Flask Web"))) {
    $conn = Get-NetTCPConnection -LocalPort $prt[0] -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        Emit "INFO" "端口 $($prt[0])（$($prt[1])）" "已被占用 (PID $($conn.OwningProcess))；若是残留进程可先停止，否则可能端口冲突"
    } else {
        Emit "INFO" "端口 $($prt[0])（$($prt[1])）" "空闲"
    }
}

# =====================================================================
# H. CUDA Toolkit / cuDNN（ONNX GPU 前置，仅提示，不影响退出码）
# =====================================================================
Section "H. CUDA Toolkit / cuDNN（ONNX GPU 前置）"

$cudaPath = $env:CUDA_PATH
if ($cudaPath -and (Test-Path $cudaPath)) {
    Emit "INFO" "系统 CUDA Toolkit" "CUDA_PATH = $cudaPath（仅 ONNX GPU 用；PyTorch 自带 CUDA 不依赖它）"
} else {
    Emit "INFO" "系统 CUDA Toolkit" "未检测到 CUDA_PATH（PyTorch 主力不受影响；仅 onnxruntime GPU 需要独立 CUDA）"
}

# .venv 内可移植的 cuDNN / cuBLAS（pip 包 nvidia-*-cu12）
$venvRoot = Split-Path (Split-Path $py)
$cudnnDir = Join-Path $venvRoot "Lib\site-packages\nvidia\cudnn\bin"
$cublasDir = Join-Path $venvRoot "Lib\site-packages\nvidia\cublas\bin"
$cudnnDll = Get-ChildItem $cudnnDir -Filter "cudnn64*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cudnnDll) {
    Emit "PASS" ".venv 内 cuDNN" "已装：$($cudnnDll.Name)（随 .venv 可移植）"
} else {
    Emit "WARN" ".venv 内 cuDNN" "未装。如需 ONNX GPU：在 .venv 执行 pip install nvidia-cudnn-cu12"
}
$cublasDll = Get-ChildItem $cublasDir -Filter "cublas64*.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cublasDll) {
    Emit "PASS" ".venv 内 cuBLAS" "已装：$($cublasDll.Name)"
} else {
    Emit "WARN" ".venv 内 cuBLAS" "未装（onnxruntime-gpu 依赖）。可执行 pip install nvidia-cublas-cu12"
}

# =====================================================================
# ONNX 检查（可选，-CheckOnnx）
# =====================================================================
if ($CheckOnnx) {
    Section "ONNX（可选，-CheckOnnx）"
    $pkgOut = & $py -m pip show onnxruntime-gpu 2>$null
    $verLine = $pkgOut | Select-String '^Version:\s*'
    if (-not $verLine) {
        Emit "INFO" "onnxruntime-gpu" "未安装（ONNX 模型将无法 GPU 运行）。需用 ONNX 时手动装匹配版，勿让 ultralytics AutoUpdate 自动装最新"
    } else {
        $ver = ($verLine.ToString() -replace '^Version:\s*', "").Trim()
        $vMajor = 0
        if ($ver -match '^(\d+)\.') { $vMajor = [int]$matches[1] }
        if ($ver -match '^1\.(\d+)') { $vMinor = [int]$matches[1] }
        if ($vMajor -ge 1 -and $vMinor -ge 29) {
            Emit "WARN" "onnxruntime-gpu $ver" "该版本要求 CUDA 13 + cuDNN 9。CUDA 12 环境请装 onnxruntime-gpu==1.21.*"
        } elseif ($cudnnDll) {
            Emit "PASS" "onnxruntime-gpu $ver" "就绪（1.21.x = CUDA 12 + cuDNN 9，.venv 内 cuDNN 已配）"
        } else {
            Emit "WARN" "onnxruntime-gpu $ver" "需配 .venv 内 cuDNN：pip install nvidia-cudnn-cu12"
        }
    }
}

# =====================================================================
# 汇总
# =====================================================================
Write-Host ""
if ($NoColor) { Write-Host "===== 汇总 =====" } else { Write-Host "===== 汇总 =====" -ForegroundColor Magenta }
if ($script:fatal -gt 0) {
    Write-Host ("就绪 {0} / 警告 {1} / 失败 {2}" -f $script:pass, $script:warn, $script:fatal)
    if ($NoColor) { Write-Host "存在必查失败：请按上方 [FAIL] 项逐一修复后再启动。" }
    else { Write-Host "存在必查失败：请按上方 [FAIL] 项逐一修复后再启动。" -ForegroundColor Red }
    exit 1
} else {
    Write-Host ("就绪 {0} / 警告 {1} / 失败 {2}" -f $script:pass, $script:warn, $script:fatal)
    if ($NoColor) { Write-Host "环境就绪，可运行 Z_script\run\start_all.ps1 启动。" }
    else { Write-Host "环境就绪，可运行 Z_script\start_all.ps1 启动。" -ForegroundColor Green }
    exit 0
}
