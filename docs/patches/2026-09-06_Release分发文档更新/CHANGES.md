# 修改日期：2026-09-06
# 修改人：[AI + 用户协作]

## 背景
用户已把 `dist/tools_20260906.zip`（107.1MB，mediamtx + ffmpeg）与 `dist/models_20260906.zip`
（493.6MB，全部模型 + .yaml）上传到 GitHub Releases 并验证可下载。
使用者流程定为：**Releases 下载两个 zip → 解压到项目根 → 得到 `tools/`、`models/`**。
本补丁把 README / AGENTS / BUILD_RUN 三份说明同步为该流程（此前仅覆盖 tools，模型仍写"需自行准备"）。

## 修改文件
- `README.md`（快速开始 ①：tools+models 双 zip；末尾"说明"段同步）
- `docs/BUILD_RUN.md`（第 4 节"模型文件"改为 Release 推荐 + 手动兜底）
- `AGENTS.md`（环境信息补充"大文件分发走 Releases"一条）

## 修改内容
- README 快速开始 ①：改为 `tools_*.zip` / `models_*.zip` 两个 zip 均解压到项目根；前置要求行去掉"模型权重"
  （已并入 ①）；末尾说明改为"权重/工具从 Releases 下载，.env 自行配置"。
- BUILD_RUN 第 4 节：加"推荐（Clone 即用）models_*.zip 解压即得 models/"块 + 维护者打包脚本
  `Z_script\pack_models.ps1`（产物 dist/models_*.zip），原"放于 models/"清单降级为手动兜底。
- AGENTS.md：环境信息新增"大文件分发：tools/ 与 models/ 不入 git，走 Releases（tools_*.zip / models_*.zip），
  维护者用 pack_tools.ps1 / pack_models.ps1 重新打包"。

## 影响范围
- 纯文档更新，不影响运行/打包逻辑。
- 提醒使用者：解压目标为**项目根**（zip 顶层含 `tools\`、`models\` 文件夹，不要单独解压到 tools/ 里）。

## before / after
- before：本轮改动前工作区版本（含此前会话的 tools Release 说明）
- after：修改后版本

## 验证
- Select-String 检查 README/AGENTS/BUILD_RUN 无旧表述残留（"需自行准备"等）→ 通过。
