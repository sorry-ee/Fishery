# start_pc_camera.ps1 - 用「电脑内置摄像头」启动智慧渔业系统（默认带传感器模拟数据）
# 依次启动：mediamtx + ffmpeg(内置摄像头→RTSP) + 传感器模拟器(datatran_test.py) + Flask(Web)，
# 按 Ctrl+C 退出时自动清理本次启动的所有子进程。
#
# 用法（在项目根下执行；脚本用 $PSScriptRoot 自动定位项目根，不依赖固定盘符）：
#   powershell -ExecutionPolicy Bypass -File .\Z_script\run\start_pc_camera.ps1             # 默认：带模拟数据
#   powershell -ExecutionPolicy Bypass -File .\Z_script\run\start_pc_camera.ps1 -NoSensor   # 去掉模拟数据
#   powershell -ExecutionPolicy Bypass -File .\Z_script\run\start_pc_camera.ps1 -DeviceName "其它摄像头名" -Fps 30
#
# 摄像头：本机内置摄像头通常是 "HP Wide Vision HD Camera"（MJPEG 720p@30），为参数默认值并非写死；
#         默认名找不到时脚本会自动枚举可用摄像头：唯一则自动选用、多个则交互选择（-DeviceName 可跳过选择）。
# 注意：本文件必须以 UTF-8 with BOM 保存（否则 Windows PowerShell 5.1 中文乱码解析失败）。

param(
    [string]$DeviceName = "HP Wide Vision HD Camera",  # 内置摄像头设备名（可 -DeviceName 覆盖）
    [string]$VideoSize  = "1280x720",                  # 采集分辨率
    [int]$Fps           = 30,                          # 采集帧率
    [switch]$NoSensor                                  # 去掉传感器模拟数据
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\run-common.ps1"          # 先加载公共函数库（须 UTF-8 BOM）
$Root = Get-ProjectRoot
Set-Location $Root

# 刷新 PATH（ffmpeg 手动安装时，新终端可能拿不到；项目自带 tools 版优先无需）
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

$ffmpegExe = Get-LocalFfmpeg -Root $Root

$mtx = $null
$startedMtx = $false
$ffmpeg = $null
$sim = $null

try {
    # ---------- 0. 确认摄像头（默认名找不到 → 自动检测/交互选择；显式 -DeviceName 找不到则报错列出） ----------
    $device = Resolve-CameraDevice -Ffmpeg $ffmpegExe -Wanted $DeviceName -Strict:($PSBoundParameters.ContainsKey('DeviceName'))
    Write-Host "[0/4] 使用摄像头: $device ($VideoSize @ ${Fps}fps)" -ForegroundColor Cyan

    # ---------- 1. mediamtx（本地 RTSP 服务器） ----------
    if (Get-NetTCPConnection -LocalPort 8554 -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "[1/4] mediamtx 已在运行 (:8554)，跳过启动" -ForegroundColor Yellow
    } elseif (Test-Path (Join-Path $Root 'tools\mediamtx\mediamtx.exe')) {
        Write-Host "[1/4] 启动 mediamtx (RTSP 服务器)..." -ForegroundColor Cyan
        $mtx = Start-Process -FilePath (Join-Path $Root 'tools\mediamtx\mediamtx.exe') `
            -WorkingDirectory (Join-Path $Root 'tools\mediamtx') -PassThru -WindowStyle Hidden
        $startedMtx = $true
        Start-Sleep -Seconds 2
    } else {
        throw "找不到 mediamtx.exe：$Root\tools\mediamtx\mediamtx.exe"
    }

    # ---------- 2. ffmpeg 推摄像头 → RTSP（原始帧必须实时重编码 H.264，不能用 -c copy） ----------
    Write-Host "[2/4] ffmpeg 推流摄像头 -> rtsp://127.0.0.1:8554/mystream" -ForegroundColor Cyan
    $argStr = "-hide_banner -loglevel warning -f dshow -video_size $VideoSize -framerate $Fps -i `"video=$device`" -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/mystream"
    $ffmpeg = Start-Process -FilePath $ffmpegExe -ArgumentList $argStr -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 2
    if ($ffmpeg.HasExited) {
        Write-Host "  [警告] ffmpeg 启动即退出：摄像头可能被其它程序占用，或设备名/分辨率不对。" -ForegroundColor Yellow
    }

    # ---------- 3. 传感器模拟器（默认启动；-NoSensor 关闭） ----------
    $sim = Start-SensorSim -Root $Root -Skip:$NoSensor

    # ---------- 4. Flask（前台运行，Ctrl+C 退出） ----------
    Write-Host "[4/4] 启动 Flask..." -ForegroundColor Cyan
    $py = Join-Path $Root '.venv\Scripts\python.exe'
    if (-not (Test-Path $py)) { throw "找不到虚拟环境 Python：$py" }
    $env:PYTHONPATH = $Root
    Start-Job -ScriptBlock { Start-Sleep -Seconds 15; Start-Process "http://127.0.0.1:5000" } | Out-Null
    Write-Host ("[{0}] 15 秒后自动打开浏览器: http://127.0.0.1:5000" -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor Green
    Write-Host "按 Ctrl+C 退出。" -ForegroundColor Green
    & $py (Join-Path $Root 'app.py')
}
catch {
    Write-Host ("错误: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    # ---------- 清理：只关本次启动的 模拟器 / ffmpeg / mediamtx ----------
    Write-Host "正在关闭 传感器模拟器 / ffmpeg / mediamtx ..." -ForegroundColor Yellow
    if ($sim -and -not $sim.HasExited) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
    if ($ffmpeg -and -not $ffmpeg.HasExited) { Stop-Process -Id $ffmpeg.Id -Force -ErrorAction SilentlyContinue }
    if ($startedMtx -and $mtx -and -not $mtx.HasExited) { Stop-Process -Id $mtx.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item (Join-Path $Root 'scratch\sensor_sim.log'), (Join-Path $Root 'scratch\sensor_sim.err.log') -ErrorAction SilentlyContinue
    Write-Host "已退出。" -ForegroundColor Green
}
