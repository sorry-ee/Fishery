# start_pc_camera.ps1 - 用「电脑内置摄像头」启动智慧渔业系统
# 依次启动 mediamtx + ffmpeg(内置摄像头→RTSP) + Flask(Web)，Ctrl+C 退出自动清理。
#
# 用法（在项目根下执行；脚本用 $PSScriptRoot 自动定位项目根）：
#   powershell -ExecutionPolicy Bypass -File Z_script\start_pc_camera.ps1
#   powershell -ExecutionPolicy Bypass -File Z_script\start_pc_camera.ps1 -DeviceName "其它摄像头名" -Fps 30
#
# 说明：本机内置摄像头通常是 "HP Wide Vision HD Camera"（支持 MJPEG 720p@30）。
#       若设备名不同，用 -DeviceName 覆盖即可。
#
# 注意：本文件必须以 UTF-8 with BOM 保存，否则 Windows PowerShell 5.1 中文乱码解析失败。

param(
    [string]$DeviceName = "HP Wide Vision HD Camera",  # 内置摄像头设备名
    [string]$VideoSize  = "1280x720",                  # 采集分辨率
    [int]$Fps           = 30                           # 采集帧率
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent   # Z_script 的上一级 = 项目根
Set-Location $Root

# 刷新 PATH（ffmpeg 手动安装时，新终端可能拿不到）
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

$mtx = $null
$startedMtx = $false
$ffmpeg = $null

# ffmpeg：优先用项目内自带 (tools\ffmpeg\bin)，找不到回退系统 PATH
if (Test-Path "$Root\tools\ffmpeg\bin\ffmpeg.exe") { $ffmpegExe = "$Root\tools\ffmpeg\bin\ffmpeg.exe" }
else { $ffmpegExe = "ffmpeg" }

function Test-Camera {
    param([string]$Name)
    # ffmpeg 把设备清单写 stderr；脚本 $ErrorActionPreference=Stop 下原生 stderr 会抛 NativeCommandError，
    # 故调用期间临时降为 Continue 并用 2>&1 捕获，再匹配设备名。
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $ffmpegExe -hide_banner -f dshow -list_devices true -i dummy 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $prev
    }
    return $out -match [regex]::Escape($Name)
}

try {
    # ---------- 0. 确认摄像头存在 ----------
    if (-not (Test-Camera $DeviceName)) {
        throw "找不到摄像头设备: $DeviceName`n请先确认摄像头已启用，或用 -DeviceName 指定实际设备名（ffmpeg -f dshow -list_devices true -i dummy 可查看）。"
    }
    Write-Host "[0/3] 使用摄像头: $DeviceName ($VideoSize @ ${Fps}fps)" -ForegroundColor Cyan

    # ---------- 1. mediamtx（本地 RTSP 服务器） ----------
    if (Get-NetTCPConnection -LocalPort 8554 -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[1/3] mediamtx 已在运行 (:8554)，跳过启动" -ForegroundColor Yellow
    } elseif (Test-Path "$Root\tools\mediamtx\mediamtx.exe") {
        Write-Host "[1/3] 启动 mediamtx (RTSP 服务器)..." -ForegroundColor Cyan
        $mtx = Start-Process -FilePath "$Root\tools\mediamtx\mediamtx.exe" `
            -WorkingDirectory "$Root\tools\mediamtx" -PassThru -WindowStyle Hidden
        $startedMtx = $true
        Start-Sleep -Seconds 2
    } else {
        throw "找不到 mediamtx.exe：$Root\tools\mediamtx\mediamtx.exe"
    }

    # ---------- 2. ffmpeg 推摄像头 → RTSP ----------
    # 摄像头输出原始帧，必须实时重编码 H.264（不能用 -c copy / -stream_loop）
    Write-Host "[2/3] ffmpeg 推流摄像头 -> rtsp://127.0.0.1:8554/mystream" -ForegroundColor Cyan
    $argStr = "-hide_banner -loglevel warning -f dshow -video_size $VideoSize -framerate $Fps -i `"video=$DeviceName`" -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/mystream"
    $ffmpeg = Start-Process -FilePath $ffmpegExe -ArgumentList $argStr -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    if ($ffmpeg.HasExited) {
        Write-Host "  [警告] ffmpeg 启动即退出：摄像头可能被其它程序占用，或设备名不对。" -ForegroundColor Yellow
    }

    # ---------- 3. Flask（前台运行，Ctrl+C 退出） ----------
    Write-Host "[3/3] 启动 Flask..." -ForegroundColor Cyan
    if (-not (Test-Path "$Root\.venv\Scripts\python.exe")) {
        throw "找不到虚拟环境 Python：$Root\.venv\Scripts\python.exe"
    }
    $env:PYTHONPATH = $Root
    # 后台延迟 15 秒后自动打开浏览器（等 Flask 起来）
    Start-Job -ScriptBlock { Start-Sleep -Seconds 15; Start-Process "http://127.0.0.1:5000" } | Out-Null
    Write-Host ("[{0}] 15 秒后自动打开浏览器: http://127.0.0.1:5000" -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor Green
    Write-Host "若届时未自动打开，请手动刷新页面；按 Ctrl+C 退出。" -ForegroundColor Green
    & "$Root\.venv\Scripts\python.exe" "$Root\app.py"
}
catch {
    Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    # ---------- 清理：只关本次启动的 ffmpeg / mediamtx ----------
    Write-Host "正在关闭 ffmpeg / mediamtx ..." -ForegroundColor Yellow
    if ($ffmpeg -and -not $ffmpeg.HasExited) {
        Stop-Process -Id $ffmpeg.Id -Force -ErrorAction SilentlyContinue
    }
    if ($startedMtx -and $mtx -and -not $mtx.HasExited) {
        Stop-Process -Id $mtx.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "已退出。" -ForegroundColor Green
}
