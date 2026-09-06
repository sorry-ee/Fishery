# start_all.ps1 - 智慧渔业系统一键启动脚本
# 依次启动 mediamtx(RTSP服务器) + ffmpeg(本地视频推流) + Flask(Web服务)，
# 退出时自动关闭 mediamtx 和 ffmpeg。
#
# 用法（在项目根下执行；脚本用 $PSScriptRoot 自动定位项目根，不依赖固定盘符）：
#   powershell -ExecutionPolicy Bypass -File .\Z_script\start_all.ps1
#
# 浏览器打开 http://127.0.0.1:5000 ，按 Ctrl+C 停止。
# 注意：本文件必须以 UTF-8 with BOM 保存，否则 Windows PowerShell 5.1 会乱码报错。

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent   # Z_script 的上一级 = 项目根
Set-Location $Root

# 刷新 PATH（ffmpeg 手动安装时，新终端可能拿不到）
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

$mtx = $null
$ffmpeg = $null

# ffmpeg：优先用项目内自带 (tools\ffmpeg\bin)，找不到回退系统 PATH
if (Test-Path "$Root\tools\ffmpeg\bin\ffmpeg.exe") { $ffmpegExe = "$Root\tools\ffmpeg\bin\ffmpeg.exe" }
else { $ffmpegExe = "ffmpeg" }

try {
    # ---------- 1. mediamtx（本地 RTSP 服务器） ----------
    Write-Host "[1/3] 启动 mediamtx (RTSP 服务器)..." -ForegroundColor Cyan
    if (Test-Path "$Root\tools\mediamtx\mediamtx.exe") {
        try {
            $mtx = Start-Process -FilePath "$Root\tools\mediamtx\mediamtx.exe" `
                -WorkingDirectory "$Root\tools\mediamtx" -PassThru -WindowStyle Hidden
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "  [警告] mediamtx 启动失败: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [警告] 找不到 mediamtx.exe，跳过" -ForegroundColor Yellow
    }

    # ---------- 2. ffmpeg 推流（本地视频 → RTSP） ----------
    # 自动挑选视频源：优先项目根目录的 test_video*.mp4，其次 outputs/videos 里最新的
    $video = $null
    foreach ($cand in @("$Root\test_video.mp4", "$Root\test_video_2.mp4")) {
        if (Test-Path $cand) { $video = $cand; break }
    }
    if (-not $video) {
        $latest = Get-ChildItem "$Root\outputs\videos" -Include *.mp4 -File -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $video = $latest.FullName }
    }
    if ($video) {
        Write-Host "[2/3] ffmpeg 推流: $video" -ForegroundColor Cyan
        try {
            $ffmpeg = Start-Process -FilePath $ffmpegExe -ArgumentList @(
                "-re", "-stream_loop", "-1", "-i", $video,
                "-c", "copy", "-rtsp_transport", "tcp",
                "-f", "rtsp", "rtsp://127.0.0.1:8554/mystream"
            ) -PassThru -WindowStyle Hidden
            Start-Sleep -Seconds 1
        } catch {
            Write-Host "  [警告] ffmpeg 推流失败: $_ （可稍后手动推流）" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[2/3] 未找到视频文件，跳过推流" -ForegroundColor Yellow
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
finally {
    # ---------- 清理：关闭 ffmpeg / mediamtx ----------
    Write-Host "正在关闭 ffmpeg / mediamtx ..." -ForegroundColor Yellow
    if ($ffmpeg -and -not $ffmpeg.HasExited) {
        Stop-Process -Id $ffmpeg.Id -Force -ErrorAction SilentlyContinue
    }
    if ($mtx -and -not $mtx.HasExited) {
        Stop-Process -Id $mtx.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "已退出。" -ForegroundColor Green
}
