# start_all.ps1 - 智慧渔业系统一键启动（本地视频推流，默认带传感器模拟数据）
# 依次启动：mediamtx + ffmpeg(本地视频→RTSP) + 传感器模拟器(datatran_test.py) + Flask(Web)，
# 按 Ctrl+C 退出时自动清理本次启动的所有子进程。
#
# 用法（在项目根下执行；脚本用 $PSScriptRoot 自动定位项目根，不依赖固定盘符）：
#   powershell -ExecutionPolicy Bypass -File .\Z_script\run\start_all.ps1            # 默认：带传感器模拟数据
#   powershell -ExecutionPolicy Bypass -File .\Z_script\run\start_all.ps1 -NoSensor  # 去掉模拟数据
#
# 说明：默认启动传感器模拟器（datatran_test.py 后台循环上报，网页即见实时波动水质，可直接生成完整 AI 报告）；
#       加 -NoSensor 则不启动（改用真实传感器桥接或跳过水质上报）。
# 注意：本文件必须以 UTF-8 with BOM 保存（否则 Windows PowerShell 5.1 中文乱码解析失败）。

param(
    [switch]$NoSensor   # 去掉传感器模拟数据（默认启动模拟器）
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
    # ---------- 1. mediamtx（本地 RTSP 服务器） ----------
    Write-Host "[1/4] 启动 mediamtx (RTSP 服务器)..." -ForegroundColor Cyan
    if (Get-NetTCPConnection -LocalPort 8554 -State Listen -ErrorAction SilentlyContinue) {
        Write-Host "  [提示] mediamtx 已在运行 (:8554)，跳过启动" -ForegroundColor Yellow
    } elseif (Test-Path (Join-Path $Root 'tools\mediamtx\mediamtx.exe')) {
        $mtx = Start-Process -FilePath (Join-Path $Root 'tools\mediamtx\mediamtx.exe') `
            -WorkingDirectory (Join-Path $Root 'tools\mediamtx') -PassThru -WindowStyle Hidden
        $startedMtx = $true
        Start-Sleep -Seconds 2
    } else {
        Write-Host "  [警告] 找不到 mediamtx.exe，跳过" -ForegroundColor Yellow
    }

    # ---------- 2. ffmpeg 推流（本地视频 → RTSP） ----------
    $video = Select-PushVideoSource -Root $Root
    if ($video) {
        Write-Host "[2/4] ffmpeg 推流: $video" -ForegroundColor Cyan
        $ffmpeg = Start-Process -FilePath $ffmpegExe -ArgumentList @(
            "-re", "-stream_loop", "-1", "-i", $video,
            "-c", "copy", "-rtsp_transport", "tcp",
            "-f", "rtsp", "rtsp://127.0.0.1:8554/mystream"
        ) -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 1
    } else {
        Write-Host "[2/4] 未找到视频文件，跳过推流（可改用 .\Z_script\run\start_pc_camera.ps1 / start_usb_camera.ps1 接真实摄像头）" -ForegroundColor Yellow
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
    # ---------- 清理：关闭本次启动的 模拟器 / ffmpeg / mediamtx ----------
    Write-Host "正在关闭 传感器模拟器 / ffmpeg / mediamtx ..." -ForegroundColor Yellow
    if ($sim -and -not $sim.HasExited) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
    if ($ffmpeg -and -not $ffmpeg.HasExited) { Stop-Process -Id $ffmpeg.Id -Force -ErrorAction SilentlyContinue }
    if ($startedMtx -and $mtx -and -not $mtx.HasExited) { Stop-Process -Id $mtx.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item (Join-Path $Root 'scratch\sensor_sim.log'), (Join-Path $Root 'scratch\sensor_sim.err.log') -ErrorAction SilentlyContinue
    Write-Host "已退出。" -ForegroundColor Green
}
