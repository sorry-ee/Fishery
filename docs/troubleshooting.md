# 已知问题与踩坑记录

> 修改代码前必读。遇到问题先来这里查。

## 1. Z_script 下 PowerShell 脚本必须为 UTF-8 with BOM 编码

- **现象**：脚本一运行就报"字符串缺少终止符"，所有进程都没启动，浏览器打不开。
- **原因**：Windows PowerShell 5.1（`powershell`）会把无 BOM 的 .ps1 按 ANSI(GBK) 读取，中文注释乱码破坏引号，导致整脚本解析失败。
- **解决**：文件保存为 UTF-8 with BOM（或用 pwsh 7 运行）。
- **验证**：用 `powershell -NoProfile -ExecutionPolicy Bypass -File Z_script\run\start_all.ps1` 实测（勿只用 pwsh 解析，测不出 5.1 的问题；`Z_script/` 下所有 .ps1 同理）。

## 2. AI 报告在网页上无法正常显示（部分修复）

- **现象**：AI 诊断/对话内容空白，或只显示 `**加粗**`、`## 标题` 等原始 Markdown。
- **原因与状态**：
  - ✅ **CDN marked.js 被墙**（cdn.jsdelivr.net）→ 已修复（2026-08-31）：marked.min.js 下载到 `static/js/marked.min.js` 本地化，并加 `simpleMd()` 极简兜底渲染。
  - ⏳ **DeepSeek thinking 模式 content 可能为空**（内容在 `reasoning_content`）→ 仍待确认/处理。
- **备注**：曾实现"空 content 回退"修复后已撤销；需要时可按 `docs/patches/2026-08-31_修复AI报告Markdown显示/` 里的方案重新应用。

## 3. ffmpeg 手动安装后新终端找不到

- 每个新终端需先刷新 PATH：
  `$env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")`
- 一键启动脚本已内置此逻辑。

## 4. 一键启动退出后可能残留 mediamtx / ffmpeg

- **现象**：脚本被强杀（非 Ctrl+C）时，隐藏窗口的 mediamtx/ffmpeg 可能残留，导致端口 8554/5000 被占用。
- **检查/清理**：
  ```powershell
  Get-Process mediamtx,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force
  ```

## 5. 敏感文件切勿提交（.env）

- `.env` 含 `DEEPSEEK_API_KEY`，已被 `.gitignore` 排除。
- 注意：`docs/patches/2026-07-30_环境初始化与Bug修复/after/.env` 是真实 .env 的备份，同样含密钥，**不要**为了"完全上传 docs"而放开 `.env` 忽略规则。

## 6. README.md 与 AGENTS.md 环境信息不一致

- README 写的是 conda + Python 3.9（过时）；当前以 AGENTS.md 为准：venv + Python 3.11。

## 7. Flask 默认静态目录是项目根 static/

- **现象**：`<script src="/static/js/xxx.js">` 返回 404。
- **原因**：Flask 默认 static 路由指向**项目根** `static/` 目录，不是 `templates/static/`。
- **解决**：静态文件放项目根 `static/` 下（2026-08-31 已将 marked.min.js 放在 `static/js/marked.min.js`）。

## 8. onnxruntime / ONNX 模型 GPU 运行（已解决 2026-09-03）

- **现象**：网页/脚本加载 `.onnx` 模型崩溃，或报 `onnxruntime ... require CUDA 13 ...` / `There's no data transfer registered`；或被迫走 CPU 极慢。
- **根因**：
  - **onnxruntime-gpu 不捆绑 CUDA 库**——它运行时要找 cublas / cuDNN；PyTorch 是自带 CUDA 运行时的，所以"PyTorch 能 GPU ≠ onnxruntime 能 GPU"。
  - ultralytics 的 **AutoUpdate** 会自动联网补依赖：曾误装**最新 onnxruntime-gpu 1.29（要求 CUDA 13 + cuDNN 9）**，与 CUDA 12 环境不匹配 → CUDA EP 初始化失败 → 崩溃；且污染 `.venv`。
- **✅ 解决（2026-09-03，.venv 内可移植方案）**：
  1. 卸载 AutoUpdate 误装的 `onnxruntime-gpu 1.29` / `onnxruntime` / `onnx`；
  2. 系统装 **CUDA Toolkit 12.6**（`CUDA_PATH`），并在 `.venv` 内 `pip install nvidia-cudnn-cu12 nvidia-cublas-cu12`（cuDNN 9.25 随 .venv 可移植）；
  3. `.venv` 内 `pip install onnxruntime-gpu==1.21.1 onnx`（**1.21.x = CUDA 12 + cuDNN 9**；勿装 ≥1.29 需 CUDA 13）；
  4. 实测：`onnxruntime 1.21.1 with CUDAExecutionProvider`，`fish_detect.onnx` GPU 推理成功。
- **教训**：环境问题不要靠硬编码改业务代码解决（曾尝试在 `ai_detector.py` 强制 ONNX 走 CPU，已回退——那会让有 CUDA 13 的环境也退化成 CPU）。
- 模型与格式分类见 `docs/deep-dive/models-guide.md`。

## 9. PowerShell `$ErrorActionPreference=Stop` 下 ffmpeg stderr 抛 NativeCommandError（2026-09-03）

- **现象**：`Z_script/start_pc_camera.ps1` / `start_usb_camera.ps1` 一运行就报错退出，错误消息是 ffmpeg 的**设备清单第一行**（如 `错误: [in#0 @ ...] "HP Wide Vision HD Camera" (video)`），随后直接进 finally 清理退出，摄像头根本没被用。
- **根因**：脚本顶部 `$ErrorActionPreference="Stop"`；而 `ffmpeg -f dshow -list_devices true -i dummy` 把设备清单写到 **stderr**。Windows PowerShell 5.1 会把原生程序的 stderr 包装成 ErrorRecord，在 `Stop` 模式下**第一条 stderr 即触发 NativeCommandError 终止**（即使 `2> 文件` 重定向也一样会抛）。
- **✅ 解决**：调用 ffmpeg 前临时把 `$ErrorActionPreference` 降为 `Continue`（用完在 `finally` 恢复），再用 `2>&1 | Out-String` 捕获整段文本做设备名匹配：
  ```powershell
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $out = & ffmpeg -hide_banner -f dshow -list_devices true -i dummy 2>&1 | Out-String }
  finally { $ErrorActionPreference = $prev }
  return $out -match [regex]::Escape($Name)
  ```
  （注意：降为 `SilentlyContinue` 会把 stderr 一并吞掉导致匹配不到，必须用 `Continue`；或用 `cmd /c '... 2>&1'` 让 cmd 合并 stderr 也能绕开。）
- **验证**：`$ErrorActionPreference='Stop'` 下实测——内置 `HP Wide Vision HD Camera` / 外接 `USB Video Device` 均匹配成功，不存在的设备返回 False，全程不抛错。

## 10. 启动脚本退出：Ctrl+C 正常清理；强杀会残留孤儿进程（2026-09-04）

- **现象**：`Z_script\run\start_all.ps1`（及 pc/usb camera 版，默认带传感器模拟）若被**强制结束**（任务管理器 / 杀终端进程 / 调试器 Kill），后台的 mediamtx、ffmpeg、传感器模拟器（`datatran_test.py`）不会自动退出，成为孤儿进程继续占用 8554/5000 端口；`scratch\sensor_sim*.log` 也不被清理。
- **原因**：这些子进程由脚本 `Start-Process` 启动，`finally` 里的清理只在脚本进程**正常收尾**（如收到 `Ctrl+C` 中断）时执行；进程被外部强杀时 `finally` 不会运行。
- **✅ 正常用法**：在脚本自己的窗口按 `Ctrl+C` 退出即可自动清理，无需手动处理。
- **若已残留**，手动清理：
  ```powershell
  Stop-Process -Name ffmpeg,mediamtx -Force
  # 若模拟器仍在跑：结束含 datatran_test 的 python 进程，再删日志
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -like '*datatran_test*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Remove-Item D:\Fishery_Project\scratch\sensor_sim*.log -ErrorAction SilentlyContinue
  ```

## 11. OpenAI SDK：非标准参数必须放 extra_body（2026-09-05）

- **现象**：调用 DeepSeek / Qwen 报 `Completions.create() got an unexpected keyword argument 'thinking'`；切到任一“可关思考”的模型都失败。
- **原因**：`thinking` / `enable_thinking` 是各平台**非标准参数**，OpenAI SDK 只接受放在 `extra_body={...}` 里透传；若用 `**dict` 展开成顶层关键字（`thinking=...`），SDK 直接报“未知关键字”。
- **解决**：一律写成 `extra_body=self._extra_no_thinking() or {}`（见 `core/llm_advisor.py` 4 处 create）。注意：`scratch/stream_compare_server.py` 一直正确，正式代码曾误用 `**_eb` 展开——两处必须保持一致。
- **验证**：`scratch/verify_extra_body.py`（假 client 离线拦截 create 入参，零成本）确认三种模型分支：qwen→enable_thinking=False；deepseek-v4→thinking.disabled；mimo→不传/空。
- **教训**：SDK 扩展参数先查官方文档/用 `extra_body`，别想当然 `**dict` 展开成 kwargs。

## 12. 思考型模型：max_tokens 预算“含思考”→ 正文被挤掉、只见草稿（2026-09-05）

- **现象**：MIMO（mimo-v2.5，无法关思考）自由问答慢；曾出现“输出像思考草稿、无组织”；思考过长时**没有正式回答**（content 为空）。
- **解释（计费 ≠ 预算，勿混淆）**：
  - 计费：思考(reasoning)与正文(content)都是输出 token，**都计费**（各家皆同）。
  - 预算：部分平台（MiMo、DeepSeek-R1-0528 等）的 `max_tokens` 是“思考+正文**总额**上限”；思考很长会先把额度吃光 → `length` 截断 → `content` 为空，只剩草稿（草稿仍计费）。
  - 所以不是“都计费所以正文必有”，而是“思考占满额度 → 正文来不及生成”。
- **解决（本项目已落地）**：
  - 能关思考的（DeepSeek/Qwen）：默认 `extra_body` 关思考 → 又快又省（实测 DeepSeek 关思考后 3 次提问约 ¥0.1，原因=不再生成大量 reasoning token）。
  - 关不了的（MiMo）：`config.LLM_REPORT_MAX_TOKENS/LLM_CHAT_MAX_TOKENS` 调大给足预算（2026-09-05 已 4096/2048）；
    流式只发 `content`、思考不进正文；思考过长仍无正文 → 给出换模型提示（补丁 `2026-09-05_MIMO思考不进正文`）。
- **费用经验**：思考 token 是烧钱大头；关思考 / 用 flash 档 / 控制输出预算，是省钱三招。
