# tools/ — 第三方工具目录（占位说明）

> 本目录中的工具是**第三方二进制**，体积大且不入 git——克隆仓库后 `ffmpeg/`、`mediamtx/` 为空/缺失**属正常现象**。

| 子目录 | 用途 | 体积 |
|--------|------|------|
| `ffmpeg/` | H.264 编码与视频推流（`bin/ffmpeg.exe`） | ~208MB |
| `mediamtx/` | 本地 RTSP 服务器（`mediamtx.exe` + 配置） | ~52MB |

## 获取方式（Clone 即用，推荐）

从本仓库 GitHub **Releases** 下载 `tools_*.zip`，解压到**项目根**即得 `tools/`
（内含 `mediamtx.exe` + `ffmpeg` + `mediamtx.yml` 配置），**无需单独安装 ffmpeg / mediamtx**。
`Z_script\run\*.ps1` 会自动优先使用本目录、找不到再回退系统 PATH。

## 维护者：重新打包

```powershell
powershell -ExecutionPolicy Bypass -File Z_script\pack_tools.ps1
# 产物：dist\tools_<日期>.zip（dist/ 已 gitignore，不会入库）→ 上传到 GitHub Releases
```

## 说明

- `auto.crt` / `auto.key`：mediamtx 运行时自动生成的本地 TLS 凭证，不入库、无需分发。
- `mediamtx.yml`：官方默认配置，随 zip 分发；若日后项目需自定义（端口 / 鉴权等），
  建议将其收回 git 作为可版本化模板。
