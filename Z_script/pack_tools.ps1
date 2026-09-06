<#
.SYNOPSIS
  打包 tools/ 为 Release 分发包 zip（mediamtx.exe + ffmpeg + 文本配置）。

.DESCRIPTION
  mediamtx.exe 与 ffmpeg 为第三方二进制、不入 git（他人 clone 后缺失）。
  本脚本把本地可运行版打成 zip，供维护者上传 GitHub Release；
  使用者在 Release 下载后解压到项目根即得 tools/。
  不打包 auto.crt / auto.key（mediamtx 首次运行自动生成的 TLS 私钥/证书，不入库）。

  产物：项目根 dist\tools_yyyyMMdd.zip（dist/ 已 gitignore，不会入库）
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Tools = Join-Path $Root 'tools'
$DestDir = Join-Path $Root 'dist'
$Date = Get-Date -Format 'yyyyMMdd'
$Zip = Join-Path $DestDir "tools_$Date.zip"

# 1. 检查必需文件（缺失即退出，避免打出残缺 zip）
$need = @(
  "$Tools\mediamtx\mediamtx.exe",
  "$Tools\mediamtx\mediamtx.yml",
  "$Tools\mediamtx\LICENSE",
  "$Tools\ffmpeg\bin\ffmpeg.exe"
)
$missing = $need | Where-Object { -not (Test-Path $_) }
if ($missing) {
  Write-Host "缺少必需文件，无法打包：" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  $_" }
  Write-Host ""
  Write-Host "提示：tools\mediamtx\mediamtx.exe 与 tools\ffmpeg 为第三方二进制、不入 git，"
  Write-Host "      需先在本地放置（下载来源见 docs/BUILD_RUN.md 第 3 节）。" -ForegroundColor Yellow
  exit 1
}

# 2. staging 组装（只含分发必需文件，排除运行时自生的 auto.crt / auto.key）
$Stage = Join-Path $env:TEMP 'fishery_tools_stage'
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Path "$Stage\tools\mediamtx", "$Stage\tools\ffmpeg\bin" -Force | Out-Null
Copy-Item "$Tools\mediamtx\mediamtx.exe" "$Stage\tools\mediamtx\"
Copy-Item "$Tools\mediamtx\mediamtx.yml" "$Stage\tools\mediamtx\"
Copy-Item "$Tools\mediamtx\LICENSE"      "$Stage\tools\mediamtx\"
Copy-Item "$Tools\ffmpeg\bin\ffmpeg.exe" "$Stage\tools\ffmpeg\bin\"

# 3. 打包（200MB 级文件，压缩需一点时间）
if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Write-Host "正在压缩（ffmpeg 较大，请稍候）..." -ForegroundColor Cyan
Compress-Archive -Path "$Stage\tools" -DestinationPath $Zip -CompressionLevel Optimal

# 4. 清理 staging 并输出结果
Remove-Item -Recurse -Force $Stage
$mb = [math]::Round((Get-Item $Zip).Length / 1MB, 1)
Write-Host ""
Write-Host "打包完成: $Zip  ($mb MB)" -ForegroundColor Green
Write-Host "下一步：上传到 GitHub Releases，并在描述中写明"
Write-Host "  '下载后解压到项目根即得 tools/（内含 mediamtx.exe + ffmpeg）'" -ForegroundColor Cyan
