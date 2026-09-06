# 环境配置与运行指南

## 环境要求

- Windows（开发环境）
- Python 3.11（venv，非 conda）
- NVIDIA GPU + CUDA（本项目用 RTX 3070 Laptop 8GB，PyTorch 2.5.1+cu121）
- FFmpeg（用于 H.264 编码与视频推流）
- mediamtx（本地 RTSP 服务器）

## 一、环境安装

### 1. 创建虚拟环境

```powershell
cd d:\Fishery_Project
python -m venv .venv
.venv\Scripts\Activate.ps1
```

### 2. 安装依赖

```powershell
pip install ultralytics opencv-python flask flask-sock openai scikit-learn numpy
# 可选：WWE-UIE 完整训练功能
pip install -r WWE-UIE/requirements.txt
```

> PyTorch 需从官网按 CUDA 版本安装：https://pytorch.org

### 3. 安装 FFmpeg / mediamtx

- **FFmpeg**（二选一，推荐自带版）：
  - 自带版：把 `ffmpeg.exe` 放到 `tools\ffmpeg\bin\`。`Z_script` 脚本会自动优先使用、找不到再回退系统 PATH（文件不入 git）。
  - 系统版：下载解压，把 `bin` 加入系统 PATH。
- **mediamtx**：从 https://github.com/bluenviron/mediamtx/releases 下载解压到 `tools/mediamtx/`（`mediamtx.exe` 不入 git）。

### 4. 模型文件

放于 `models/`（权重均不入 git）：
- 必需：`fish_detect_m.pt`
- 可选：`fish_detect_seam.pt`、`fish_seg_yolo26.pt`、`fish_seg_yolo11n.pt`、`sam2.1_t.pt` + `sam2_hiera_t.yaml` 等
- WWE-UIE 权重自动从 `WWE-UIE/output/Fishery_WWE_UIEB/UIEB/` 取最新 `best_model.pth`

### 5. 配置密钥

项目根目录 `.env`：

```
DEEPSEEK_API_KEY=你的API密钥
```

不配也能运行，仅 LLM 诊断/对话不可用。

### 6. 环境自检（可选，推荐）

装好依赖后可一键自检环境是否就绪（**只读**：不联网、不改环境、不触发 AutoUpdate）：

```powershell
powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1
# 可选参数：
#   -SkipGpu    跳过 GPU 探测（无显卡机）
#   -Deep       额外真实加载模型推理一次（较慢）
#   -CheckOnnx  只读探测 onnxruntime-gpu 版本并提示 CUDA 匹配（pip show，不触发 AutoUpdate）
#   -NoColor    纯文本输出（便于重定向到文件）
```

退出码：**0 = 可启动；1 = 存在必查失败**（按上方 `[FAIL]` 项逐一修复）。脚本设计说明见 `docs/env_check_plan.md`。

## 二、运行

### 方式一：一键启动（推荐）

启动脚本统一在 `Z_script/run/`，在项目根按需选用（**默认带传感器模拟数据**，`-NoSensor` 去掉）：

```powershell
cd d:\Fishery_Project
.\Z_script\run\start_all.ps1                  # ① 本地视频推流（默认带模拟数据）
.\Z_script\run\start_pc_camera.ps1            # ② 电脑内置摄像头
.\Z_script\run\start_usb_camera.ps1           # ③ 外接 USB 摄像头（真实场景）
.\Z_script\run\start_all.ps1 -NoSensor        # ④ 不带模拟数据
```

自动完成：mediamtx → 推流 → 传感器模拟器（默认）→ Flask → 约 15 秒后自动打开浏览器。
摄像头脚本启动前会自动检测设备名：默认名找不到时自动枚举（唯一自动选用 / 多个交互选择）；也可用 `-DeviceName` 显式指定（找不到会报错并列出可用设备）。

### 方式二：手动 3 终端

见 `AGENTS.md`「启动流程 · 方式二」。

## 三、访问

| 地址 | 说明 |
|------|------|
| http://127.0.0.1:5000 | Web 控制台 |
| http://127.0.0.1:5000/video_feed | MJPEG 视频流 |
| ws://127.0.0.1:5000/ws_video | H.264 WebSocket 视频流 |

## 四、停止

- 一键启动：直接 `Ctrl+C`（自动关闭 ffmpeg / mediamtx）
- 手动 3 终端：按顺序停 Flask → ffmpeg → mediamtx

## 五、验证

```powershell
python -c "import torch; print('CUDA:', torch.cuda.is_available())"
python -c "import cv2; print('OpenCV:', cv2.__version__)"
python -c "from ultralytics import YOLO; print('Ultralytics: OK')"
python -c "import flask; print('Flask:', flask.__version__)"
```
