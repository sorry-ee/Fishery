# 智慧渔业水下协同控制系统

实时水下视频监测与分析平台：从 RTSP 摄像头或本地视频拉流，经水下图像增强（WWE-UIE）、鱼群检测/分割（YOLO + SAM2）、目标跟踪，结合传感器数据（水温 / pH / 溶解氧）与 DeepSeek 大模型 + 自建 RAG 知识库，通过 Web 控制台实时展示与智能诊断。

## 功能特性

- 双通道实时视频：MJPEG（HTTP）+ H.264（WebSocket）
- AI 检测 / 分割 / 跟踪：YOLO 多模型运行时热切换 + SAM2 实例分割 + 跨帧 ID 跟踪
- 水下图像增强：WWE-UIE 自动还原清晰画面
- 传感器监测：水温 / pH / 溶解氧上报、曲线与历史
- 智能告警：规则阈值诊断 + 事件日志
- AI 顾问：DeepSeek 大模型 + 鳗鲡养殖知识库（RAG）实时问答与诊断
- 一键启动：`Z_script\run\start_all.ps1`（本地视频推流）/ `Z_script\run\start_pc_camera.ps1`、`Z_script\run\start_usb_camera.ps1`（真实摄像头）——默认都带传感器模拟数据，`-NoSensor` 去掉

## 快速开始

**① 准备大文件（第三方工具/模型权重，不入 git）**：从本仓库 **Releases** 下载以下 zip，解压到**项目根**即可（得到 `tools/`、`models/` 两个文件夹）：

- `tools_*.zip` → 解压得 `tools/`（内含 `mediamtx.exe` + `ffmpeg`，无需单独安装；`auto.crt`/`auto.key` 由 mediamtx 运行时自动生成，无需理会）
- `models_*.zip` → 解压得 `models/`（全部模型权重 + 配置，含必需 `fish_detect_m.pt`）

其余前置要求：Python 3.11（venv）、NVIDIA GPU（CUDA）、`.env` 中的 DeepSeek Key（详见 `docs/BUILD_RUN.md`）。

> 不确定环境是否就绪？先一键自检（只读，不联网）：
> `powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1`，退出码 0 后再启动。

```powershell
cd d:\Fishery_Project
.\Z_script\run\start_all.ps1            # 本地视频推流（默认带模拟数据）
.\Z_script\run\start_usb_camera.ps1     # 外接 USB 摄像头（真实场景）
.\Z_script\run\start_all.ps1 -NoSensor  # 不带模拟数据
```

脚本自动启动 mediamtx → 推流 → 启动 Flask，约 15 秒后自动打开浏览器。

- 控制台：http://127.0.0.1:5000
- 停止：按 `Ctrl+C`（自动关闭 mediamtx / ffmpeg）

## 技术栈

Flask / Flask-Sock ｜ OpenCV + FFmpeg ｜ PyTorch + Ultralytics YOLO + SAM2 ｜ WWE-UIE ｜ SQLite ｜ DeepSeek API

## 文档

| 文档 | 说明 |
|------|------|
| `docs/ROADMAP.md` | 开发路线图 |
| `docs/BUILD_RUN.md` | 环境配置与运行指南 |
| `docs/troubleshooting.md` | 已知问题与踩坑 |
| `docs/structure.md` | 详细项目结构 |
| `docs/deep-dive/` | 深入讲解（含原开发者指南 `developer_guide.md`） |

## 目录结构

```
app.py             Flask 主入口与路由
config.py          全局配置（模型 / 阈值 / LLM / 认证）
core/              核心模块（视频采集、帧处理、AI 检测、增强、LLM、存储）
knowledge/         鳗鲡知识图谱 + RAG 引擎
templates/         Web 控制台（SPA）
docs/              项目文档
scripts/           辅助脚本
models/            模型权重（不入 git）
```

## 说明

- 模型权重（`models/*.pt` 等）与第三方工具（`tools/`）不入 git——从本仓库 **Releases** 下载 `models_*.zip` / `tools_*.zip` 解压到项目根即可（见「快速开始 ①」）。
- `.env`（DeepSeek Key）不入 git，需自行创建配置。
- 详细的模块调用链与开发指南见 `docs/deep-dive/developer_guide.md`。
