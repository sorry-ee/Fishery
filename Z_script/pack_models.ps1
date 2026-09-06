<#
.SYNOPSIS
  打包 models/ 为 Release 分发包 zip（单个 zip）。

.DESCRIPTION
  模型权重（*.pt / *.onnx / *.om）均不入 git，他人 clone 后 models/ 缺失。
  本脚本把整个 models/（含配套 .yaml 配置）打成单个 zip，供维护者上传 GitHub Release；
  使用者在 Release 下载后解压到项目根即得 models/。

  产物：项目根 dist\models_yyyyMMdd.zip（dist/ 已 gitignore，不会入库）
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Models = Join-Path $Root 'models'
$DestDir = Join-Path $Root 'dist'
$Date = Get-Date -Format 'yyyyMMdd'
$Zip = Join-Path $DestDir "models_$Date.zip"

# 1. 检查模型目录非空
if (-not (Test-Path $Models)) {
  Write-Host "未找到 models/ 目录：$Models" -ForegroundColor Red
  exit 1
}
$files = Get-ChildItem $Models -Recurse -File
if (-not $files) {
  Write-Host "models/ 为空，没有可打包的模型。" -ForegroundColor Yellow
  exit 1
}
$totalMB = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 0)

# 2. 打包（zip 顶层为 models\，解压到项目根即得 models/）
if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Write-Host "正在压缩 models/（$($files.Count) 个文件，约 ${totalMB}MB，请稍候）..." -ForegroundColor Cyan
Compress-Archive -Path $Models -DestinationPath $Zip -CompressionLevel Optimal

# 3. 结果
$mb = [math]::Round((Get-Item $Zip).Length / 1MB, 1)
Write-Host ""
Write-Host "打包完成: $Zip  ($mb MB)" -ForegroundColor Green
Write-Host "下一步：上传到 GitHub Releases（单个资产上限 2GB，本包远小于该值）。"
Write-Host "下载后解压到项目根即得 models/。" -ForegroundColor Cyan
