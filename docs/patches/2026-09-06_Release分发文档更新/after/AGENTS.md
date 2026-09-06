# AGENTS.md — 项目指南与修改规范

## 项目简介

**智慧渔业水下协同控制系统** — 实时水下视频监测与分析平台。

- **入口**：`python app.py`（或一键启动 `Z_script\run\start_all.ps1`，默认带传感器模拟数据）
- **Web**：`http://127.0.0.1:5000`
- **Git 仓库**：`https://github.com/Mikorchara/Fishery.git`
- **视频源**：RTSP 流（真实摄像头 / ffmpeg 推本地文件模拟）
- **AI 能力**：YOLO 鱼群检测 + SAM2 实例分割 + WWE-UIE 水下增强
- **LLM**：DeepSeek API（诊断 + 对话）
- **传感器**：水温 / pH / 溶氧（通过 API 上报）

### 技术栈

| 层 | 技术 |
|----|------|
| 后端 | Python 3.11 + Flask + Flask-Sock |
| AI | PyTorch 2.5.1+cu121 + Ultralytics YOLO + SAM2 |
| 视频 | OpenCV + FFmpeg（H.264 编码） |
| 存储 | SQLite（传感器 / 事件） |
| 前端 | 纯 HTML/CSS/JS（`templates/index.html` + `static/`） |
| LLM | DeepSeek API + 自建 RAG（TF-IDF） |

### 核心模块

| 文件 | 职责 |
|------|------|
| `app.py` | Flask 主入口、路由 |
| `config.py` | 全局配置（模型路径、阈值、API Key） |
| `core/video_stream.py` | RTSP 双线程异步采集 |
| `core/ai_detector.py` | YOLO 检测/分割 + SAM2 |
| `core/enhancer.py` | WWE-UIE 水下图像增强 |
| `core/llm_advisor.py` | LLM 诊断 + RAG 对话（`reconfigure` 支持运行时切换服务） |
| `core/llm_settings.py` | LLM 多服务方案管理（新增/启用/禁用/测试；`llm_settings.json` 持久化，Key 脱敏入库 gitignore） |
| `core/frame_processor.py` | 帧处理流水线 |
| `core/h264_streamer.py` | FFmpeg H.264 编码 |
| `core/ws_handler.py` | WebSocket 视频推流 |
| `core/storage.py` | SQLite 持久化 |
| `knowledge/` | 鳗鲡知识图谱 + RAG 引擎 |
| `templates/index.html` | Web 控制台 SPA |
| `static/` | 前端静态资源（`static/js/marked.min.js` 本地化，避免依赖 CDN 不稳定） |

> **运行产物 & 记录回看**：截图/录像/AI 对话文本统一落盘 `outputs/{images,videos,chats}`（gitignore）；
> Web 视频区标题栏「记录回看」按钮进入独立视图：左=对话记录（自动存档 .md，左键查看 / 右键重命名·删除），
> 右=现场记录（图片/视频切换缩略图；左键系统查看器打开、右键重命名·删除）；产物以时间命名。
> 设计复用见 `scratch/记录回看outputs界面_设计复用.md`。

---

### 文档（docs/）

| 路径 | 说明 |
|------|------|
| `docs/ROADMAP.md` | 开发路线图 / 接下来的计划 |
| `docs/troubleshooting.md` | 已知问题与踩坑记录（改前必读） |
| `docs/code_review.md` | 代码审查报告（初始空白） |
| `docs/BUILD_RUN.md` | 环境配置与运行指南 |
| `docs/structure.md` | 项目详细结构 |
| `docs/patches/` | 修改补丁记录（before/after 对比） |
| `docs/deep-dive/` | 分模块深入讲解 |

---



## 修改规范

### 原则

1. **任何对已有代码的修改，必须先备份记录。**
2. **优先新增文件，而非改动已有文件。**
3. **修改最小化** — 只改必要的，不动无关代码。

### 修改记录流程

每次修改已有文件时，按以下步骤操作：

```
docs/patches/
└── YYYY-MM-DD_简要描述/
    ├── CHANGES.md          # 修改说明：改了什么、为什么改
    ├── before/             # 修改前的原始文件副本
    │   └── xxx.py
    └── after/              # 修改后的文件副本
        └── xxx.py
```

#### CHANGES.md 模板

```markdown
# 修改日期：YYYY-MM-DD
# 修改人：[姓名]

## 修改文件
- `path/to/file.py`

## 修改原因
[简述为什么要改]

## 修改内容
- 改了 A
- 加了 B

## 影响范围
[哪些功能会受影响]
```

### 安全规范

- **严禁随意发起付费 LLM/API 联网调用**（对话/诊断报告/测试连接等）。改动代码或验证功能时默认走 `--dry`/本地规则/mock；确需真实调用**必须先征得用户同意**，且限制 `max_tokens`、控制在 1 次请求。
- `.env`（含 `DEEPSEEK_API_KEY`）已被 `.gitignore` 排除，**禁止提交**。
- `docs/patches/` 下补丁备份若含 `.env` 等敏感文件，**必须先脱敏**（真实密钥替换为占位符）再入库，并在 `.gitignore` 显式放行（`!docs/patches/**/after/.env`）。
- 提交前用 `git status` / `git diff --cached` 检查是否混入密钥、大二进制（如 `mediamtx.exe`）。



### 环境信息

- **Python 版本**：3.11（`venv`，非 conda）
- **虚拟环境**：`d:\Fishery_Project\.venv`
- **PyTorch**：2.5.1+cu121（从 PyTorch 官网安装）
- **GPU**：NVIDIA RTX 3070 Laptop 8GB
- **大文件分发**：`tools/`（mediamtx/ffmpeg）与 `models/`（权重）不入 git，统一走 GitHub **Releases**（`tools_*.zip` / `models_*.zip`）——解压到项目根即得；维护者用 `Z_script\pack_tools.ps1` / `Z_script\pack_models.ps1` 重新打包。详见 `docs/BUILD_RUN.md`

### 运行前检查

- [ ] `.env` 中 `DEEPSEEK_API_KEY` 已配置
- [ ] 虚拟环境已激活：`.venv\Scripts\Activate.ps1`
- [ ] `models/fish_detect_m.pt` 存在
- [ ] RTSP 视频源可访问（或接受启动延迟）

---

## 启动流程

### 方式一：一键启动（推荐）

启动脚本统一放在 `Z_script/run/`（公共函数在 `run-common.ps1`），在项目根按需选用：
**默认都附带传感器模拟数据**（`tests/datatran_test.py` 后台循环上报，开箱即有波动水质、可直接生成完整 AI 报告）；加 `-NoSensor` 可去掉。

```powershell
cd d:\Fishery_Project

# ① 本地视频文件推流（默认带模拟数据）
.\Z_script\run\start_all.ps1

# ② 电脑内置摄像头（HP Wide Vision HD Camera，默认带模拟数据）
.\Z_script\run\start_pc_camera.ps1

# ③ 外接 USB 摄像头（USB Video Device，默认带模拟数据）
.\Z_script\run\start_usb_camera.ps1

# 例：不要模拟数据 / 指定摄像头设备
.\Z_script\run\start_all.ps1 -NoSensor
.\Z_script\run\start_pc_camera.ps1 -NoSensor -DeviceName "其它摄像头名"
```

- 启动顺序：mediamtx（已在跑则跳过）→ ffmpeg 推流（`start_all` 选 `test_video*.mp4` / `outputs/videos` 最新；摄像头脚本实时采集）→ 传感器模拟器 → Flask → 约 15 秒自动开浏览器。
- 摄像头脚本：分辨率 `-VideoSize` / 帧率 `-Fps` 可调；设备名为参数默认值（非写死），默认名找不到时会自动枚举——唯一则自动选用、多个则交互选择，或用 `-DeviceName` 显式指定。
- 按 `Ctrl+C` 退出自动关闭本次启动的 模拟器/ffmpeg/mediamtx（已在运行的 mediamtx 不会误关）。

> **注意**：以上脚本均须保持 **UTF-8 with BOM** 编码，否则 Windows PowerShell 5.1 会因中文乱码导致整脚本解析失败。

### 方式二：手动 3 终端（排障/调试用）

> **说明**：项目已在 `tools\ffmpeg\bin` 自带 ffmpeg，`Z_script` 一键启动脚本会自动优先使用，无需手动安装。
> 若在本手动方式下系统 PATH 无 ffmpeg，可用项目内版本 `tools\ffmpeg\bin\ffmpeg.exe`；
> 若 ffmpeg 是手动安装的，新终端可能需先刷新 PATH：
> ```powershell
> $env:Path = [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + [System.Environment]::GetEnvironmentVariable("Path","Machine")
> ```

### 终端 1 — mediamtx（RTSP 服务器）

```powershell
cd d:\Fishery_Project\tools\mediamtx
.\mediamtx.exe
```

看到 `[RTSP] started with listeners on :8554` 即成功，保持运行。

### 终端 2 — ffmpeg（推流）

```powershell
ffmpeg -re -stream_loop -1 -i d:\Fishery_Project\test_video.mp4 -c copy -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/mystream
```

终端 1 出现 `[RTSP] [conn ...] opened` 表示推流成功，保持运行。

### 终端 3 — Flask（Web 服务）

```powershell
cd d:\Fishery_Project
.venv\Scripts\Activate.ps1
python app.py
```

看到 `系统启动: http://127.0.0.1:5000` 后，浏览器打开该地址。

### 停止

- **一键启动**：直接 `Ctrl+C`，脚本自动关闭 ffmpeg 与 mediamtx。
- **手动 3 终端**：按顺序反向关闭：先 `Ctrl+C` 停 Flask → ffmpeg → mediamtx。
