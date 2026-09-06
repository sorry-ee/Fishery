# 修改日期：2026-09-06
# 修改人：[AI + 用户协作]

## 背景
`tools/` 中的第三方二进制（`mediamtx.exe` 52MB、`ffmpeg.exe` 208MB）因体积与"密钥不入库"原则被 `.gitignore` 排除，
他人 clone 后 `tools/` 不全（只有 mediamtx.yml/LICENSE），无法直接启动。本补丁引入 **Release 分发包 zip** 方案：
维护者用打包脚本生成 `tools_*.zip` 传 GitHub Releases，使用者下载解压到项目根即得 `tools/`。

> 为什么不把 `auto.crt`/`auto.key` 也打进去：它们是 mediamtx 运行时自动生成的 TLS 私钥/证书
> （见 mediamtx.yml `moqServerKey: auto.key` 注释），属本地敏感凭证，删掉会自动重生，不入库、无需分发。

## 修改文件
- 新增 `Z_script/pack_tools.ps1`（打包脚本，UTF-8 BOM）
- 修改 `README.md`（快速开始顶部加"① 准备 tools（Release 解压）"步骤，前置要求行去掉 FFmpeg/mediamtx）
- 修改 `docs/BUILD_RUN.md`（第 3 节顶部加"推荐：Clone 即用 Release 解压"，原手动下载降级为兜底）

## 修改内容
- 新增脚本逻辑：校验 4 个必需文件 → staging 组装（仅 mediamtx.exe/yml/LICENSE + ffmpeg.exe，排除 auto.*）→
  Compress-Archive 打成 `dist/tools_yyyyMMdd.zip`（dist/ 已 gitignore，不会入库）→ 清理 staging → 提示上传 Releases。
  缺文件时红字报错并给下载指引，避免打出残缺 zip。
- 文档同步：README 面向使用者，BUILD_RUN 面向安装者，均写清"Releases 下载 → 解压到项目根 → 得 tools/"。

## 影响范围
- 仅新增打包脚本与文档说明；启动/运行链路（`Z_script/run/`、run-common.ps1 的 Get-LocalFfmpeg 本地优先逻辑）不变。
- `pack_tools.ps1` 依赖本地已放置的 mediamtx.exe / ffmpeg.exe，未放置时脚本退出并提示。

## before / after
- before：`git HEAD` 版本（README.md、docs/BUILD_RUN.md；注：工作区含此前未提交改动，此处仅作基线对照）
- after：修改后当前工作区版本

## 验证
- pack_tools.ps1：UTF-8 BOM = True、PowerShell 解析器语法 OK；实际运行生成 zip 成功（见会话记录）。
