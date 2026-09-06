# 开发路线图

> 状态标记：✅ 已完成 ｜ 🔄 进行中 ｜ 📋 计划中

## 已完成 ✅

- 环境初始化（venv Python 3.11 + PyTorch 2.5.1+cu121 + RTX 3070）
- 视频双通道：MJPEG（HTTP）+ H.264（WebSocket）实时推流
- YOLO 鱼群检测 / 分割（多模型热切换 + SAM2 / YOLO-seg）
- WWE-UIE 水下图像增强（FP16 + 可选 torch.compile）
- DeepSeek LLM 诊断 + RAG（TF-IDF）对话
- LLM 服务自由切换（2026-09-04）：设置界面多方案管理 —— 地址+Key+模型 新增/保存/启用/禁用/测试连接/获取模型；`core/llm_settings.py` 持久化 `llm_settings.json`（含 Key，gitignore）；`llm_advisor.reconfigure` 运行时热切换，无需重启
- `ask_question` 去 thinking 改普通模式，省 token（2026-09-04）
- 默认关闭 LLM 思考（2026-09-05）：`core/llm_advisor.py` 按模型注入关闭参数 —— deepseek-v4 → `thinking.disabled`；qwen3.x → `enable_thinking=false`；MiMo-V2.5 暂无公开关闭参数保持原样
- 对话与诊断报告**流式打字机**（2026-09-05）：`llm_advisor` 新增 `stream_advice/stream_answer`；`app.py` 新增 SSE `/chat_ai_stream`、`/get_ai_advice_stream`（旧非流式保留回退）；前端逐字显示、完成渲染 Markdown；`finish_reason=length` 追加截断提示
- 传感器上报 + SQLite 持久化 + 规则告警
- 一键启动脚本 `Z_script\run\start_all.ps1`（mediamtx + ffmpeg + 传感器模拟(默认) + Flask；另有电脑/外接摄像头版 `start_pc_camera.ps1` / `start_usb_camera.ps1`，默认同样带模拟数据，`-NoSensor` 去掉）
- Git 化并上传 GitHub（https://github.com/Mikorchara/Fishery.git）
- docs/ 文档整理（ROADMAP / troubleshooting / code_review / BUILD_RUN / structure / deep-dive）
- 工程化（2026-09-05）：启动/自检脚本去硬编码（`$PSScriptRoot` 自动定位）；自带 ffmpeg（`tools/ffmpeg/bin`）优先、缺省回退 PATH；mediamtx 与 ffmpeg 统一归拢 `tools/`
- 运行产物归拢（2026-09-05）：截图/录像/AI 对话文本统一 `outputs/{images,videos,chats}`（gitignore）；对话与诊断报告**自动落盘 Markdown**（时间/模型/环境快照/提问/回复）
- 记录回看界面（2026-09-05~06）：视频区标题栏入口按钮 → 独立视图（返回监控可切回）；左侧对话记录浏览（左键查看·右键重命名/删除）；右侧图片/视频缩略图（可切换·左键系统查看器·右键重命名/删除）；截图/录像以时间命名；设计思路见 `scratch/记录回看outputs界面_设计复用.md`
- 脚本结构（2026-09-06）：启动脚本归拢 `Z_script/run/`（公共库 `run-common.ps1`，被 start_*.ps1 dot-source）；三个启动脚本统一**默认带传感器模拟数据、`-NoSensor` 去掉**（`start_all_with_sensor.ps1` 已合并入 `start_all.ps1`）；摄像头脚本设备名自动检测（默认名找不到时唯一自动选用 / 多个交互选择，`-DeviceName` 可显式指定并校验）

## 进行中 🔄

- 暂无

## 计划中 📋

- [ ] **修复 AI 报告 Markdown 显示问题**（见 `troubleshooting.md`）：CDN 加载 marked.js 可能被墙；后端 thinking 模式 content 可能为空
- [ ] 补充单元测试与集成测试（pytest），覆盖 `core/` 各模块
- [ ] LLM 思考/推理做成**可选项**：per-方案配置（当前默认全关，2026-09-05 硬编码），需要深度思考的场景按需开启，并用 `thinking_budget`/`reasoning_effort` 限制思考长度。注意：MiMo-V2.5 无公开关闭参数（带“深度思考”属性），只能靠换模型规避
- [ ] **对话记忆 / 会话历史**（滑动窗口 N 轮，追问能接上文）—— ⏸ **暂缓**（2026-09-06 决定以后再处理）；设计与任务拆分见 `docs/memory-plan.md`
- [ ] 传感器真实硬件（MCU）接入联调——方案 B：PC 作采集网关，新建 `scripts/sensor_bridge.py`（pyserial 读 RS485/Modbus RTU 探头 → POST `/update_sensor`）；探头在远处时才需 ESP32/DTU 独立转发。开发进度：仅在 ROADMAP 排期，代码待采购探头后实现
- [ ] 模型热切换的异步预加载，避免切换卡顿
- [ ] H.264 / MJPEG 双通道异常自动切换的稳定性测试
- [ ] 部署文档：从本地开发环境迁移到服务器（Linux）

## 待评估（暂缓）

- 全局快捷键（pynput）
- 接入本地 LLM（Ollama / llama.cpp）作为离线备选
