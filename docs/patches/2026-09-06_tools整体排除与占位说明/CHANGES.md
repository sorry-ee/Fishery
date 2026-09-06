# 修改日期：2026-09-06
# 修改人：[AI + 用户协作]

## 背景
用户选择"tools 仅留占位说明 + 整体排除"方案：与其逐行排除 `mediamtx` 目录内文件，
不如把 `tools/mediamtx/`、`tools/ffmpeg/` 两个目录整体排除，git 中只保留 `tools/README.md`
占位说明（指引从 GitHub Releases 下载 `tools_*.zip` 解压即得）。

## 修改文件
- 修改 `.gitignore`（原 mediamtx 3 行文件级排除 → 整体目录排除）
- 新增 `tools/README.md`（占位说明：目录用途、Release 获取方式、维护者打包命令、auto.* / mediamtx.yml 说明）
- `git rm --cached`：`tools/mediamtx/mediamtx.yml`、`tools/mediamtx/LICENSE`（仅移出 git 索引，本地文件保留）

## 修改原因
- mediamtx.exe / auto.crt / auto.key 为第三方二进制或运行时自生敏感凭证，无需逐行列举；
  整体排除后 `.gitignore` 更简洁、不易遗漏新增的生成文件。
- mediamtx.yml 经核对为官方默认配置（无项目自定义），随 Release zip 分发即可，暂不需要版本化；
  若日后自定义（端口/鉴权），收回入库作为模板即可（届时用 `!tools/mediamtx/mediamtx.yml` 白名单）。

## 修改内容
`.gitignore`：
```diff
-# tools/mediamtx（本地 RTSP 服务器，第三方二进制 + 自动生成的 TLS 证书；yml/License 文本提交）
-tools/mediamtx/mediamtx.exe
-tools/mediamtx/auto.crt
-tools/mediamtx/auto.key
-
-# tools/ffmpeg（本地自带 ffmpeg，第三方工具二进制）
-tools/ffmpeg/
+# tools/ 第三方工具（二进制不入库；从 GitHub Releases 下载 tools_*.zip 解压即得，见 tools/README.md）
+tools/mediamtx/
+tools/ffmpeg/
```

## 影响范围
- git 中 tools/ 现在只剩 `tools/README.md`（占位说明）；ffmpeg/、mediamtx/ 本地文件不受影响。
- `Z_script\pack_tools.ps1` 打包仍基于本地文件（yml/LICENSE 本地仍在），产物 zip 内容不变。
- 运行链路（run/ 脚本、run-common.ps1 本地优先逻辑）不受影响。

## before / after
- before：`.gitignore`（git HEAD 版本，含原 3 行排除）
- after：修改后 `.gitignore` + 新增 `tools/README.md`（副本见 after/README_tools.md）

## 验证
- `git check-ignore`：tools/mediamtx/mediamtx.exe、tools/mediamtx/auto.crt、tools/ffmpeg/bin/ffmpeg.exe 均被忽略；
  tools/README.md 未被忽略（会入库）。
- 本地 tools/mediamtx/mediamtx.yml、LICENSE 仍在（git rm --cached 未删磁盘）。
