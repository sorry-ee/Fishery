# run-common.ps1 — Z_script\run 启动脚本的公共函数库
# 被 run\start_*.ps1 通过 dot-source 加载（. "$PSScriptRoot\run-common.ps1"）。
# 本文件只定义函数、不执行任何副作用；进程启动/清理由各 start 脚本自己 try/finally 管理。
#
# 注意：本文件必须以 UTF-8 with BOM 保存（否则 Windows PowerShell 5.1 中文乱码解析失败）。

function Get-ProjectRoot {
    # 本文件位于 <项目根>\Z_script\run\ 下 → 项目根 = 本文件所在目录上两级
    return Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

function Get-LocalFfmpeg {
    # 优先用项目内自带 tools\ffmpeg\bin\ffmpeg.exe，找不到回退系统 PATH 的 ffmpeg
    param([string]$Root)
    $local = Join-Path $Root 'tools\ffmpeg\bin\ffmpeg.exe'
    if (Test-Path $local) { return $local }
    return 'ffmpeg'
}

function Select-PushVideoSource {
    # 本地视频 → RTSP 推流源：优先 test_video*.mp4，其次 outputs/videos 里最新的录像
    param([string]$Root)
    foreach ($cand in @((Join-Path $Root 'test_video.mp4'), (Join-Path $Root 'test_video_2.mp4'))) {
        if (Test-Path $cand) { return $cand }
    }
    $latest = Get-ChildItem (Join-Path $Root 'outputs\videos') -Include *.mp4 -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Get-CameraList {
    # 枚举 ffmpeg(dshow) 可用的视频捕获设备名；失败返回空数组。
    # ffmpeg 设备清单写 stderr，$ErrorActionPreference=Stop 下原生 stderr 会抛 NativeCommandError，
    # 故调用期间临时降为 Continue 并用 2>&1 捕获（同 troubleshooting 记录）。
    param([string]$Ffmpeg)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Ffmpeg -hide_banner -f dshow -list_devices true -i dummy 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $prev
    }
    $cams = @()
    foreach ($m in [regex]::Matches($out, '"(.*?)"\s*\(video')) {
        if ($m.Groups[1].Value) { $cams += $m.Groups[1].Value }
    }
    return $cams
}

function Resolve-CameraDevice {
    # 校验指定摄像头名是否存在；不存在时：
    #   -Strict（用户显式 -DeviceName）：直接报错并列出可用设备；
    #   非 Strict（用的是参数默认名）：唯一可用则自动选用，多个则交互选择，无则报错。
    param(
        [string]$Ffmpeg,
        [string]$Wanted,
        [switch]$Strict
    )
    $cams = @(Get-CameraList -Ffmpeg $Ffmpeg)
    if ($cams -contains $Wanted) { return $Wanted }
    if ($cams.Count -eq 0) {
        throw "未检测到任何摄像头。请确认摄像头已连接/启用（dshow 视频设备），或重新运行加 -DeviceName 指定设备名。"
    }
    if ($Strict) {
        throw "找不到摄像头设备「$Wanted」。可用设备：" + ($cams -join ' | ') + "（用 -DeviceName 指定其一）"
    }
    if ($cams.Count -eq 1) {
        Write-Host "  [提示] 默认设备「$Wanted」未找到，检测到唯一可用摄像头「$($cams[0])」，自动选用。" -ForegroundColor Yellow
        return $cams[0]
    }
    Write-Host "  [提示] 默认设备「$Wanted」未找到，可用摄像头如下（下次运行加 -DeviceName 指定其一即可免选）：" -ForegroundColor Yellow
    for ($i = 0; $i -lt $cams.Count; $i++) { Write-Host "    $($i + 1). $($cams[$i])" }
    $choice = Read-Host "  输入序号使用该设备（直接回车取消）"
    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $cams.Count) { return $cams[$idx] }
    }
    throw "未选择摄像头，退出。"
}

function Start-SensorSim {
    # 启动传感器模拟器（默认启动）；-Skip 时跳过。返回进程对象（未启动返回 $null）。
    # 输出写 scratch\sensor_sim.log / sensor_sim.err.log（退出清理）。
    param(
        [string]$Root,
        [switch]$Skip
    )
    if ($Skip) {
        Write-Host "  [跳过] 未启用传感器模拟（-NoSensor）" -ForegroundColor DarkGray
        return $null
    }
    Write-Host "[3/4] 启动传感器模拟器 (datatran_test.py)..." -ForegroundColor Cyan
    $scratch = Join-Path $Root 'scratch'
    if (-not (Test-Path $scratch)) { New-Item -ItemType Directory -Force $scratch | Out-Null }
    $sim = Start-Process -FilePath (Join-Path $Root '.venv\Scripts\python.exe') `
        -ArgumentList (Join-Path $Root 'tests\datatran_test.py') `
        -WorkingDirectory $Root -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $scratch 'sensor_sim.log') `
        -RedirectStandardError (Join-Path $scratch 'sensor_sim.err.log')
    Start-Sleep -Seconds 1
    return $sim
}
