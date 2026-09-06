# check_env.ps1 — 环境就绪检查：使用与设计说明

> **状态**：✅ 已实现（2026-09-03，脚本位于 `Z_script\check_env.ps1`）
> **一句话**：把“这台电脑能不能跑起本项目”变成一条命令；分发/接手时先自检，缺什么一目了然。
> **性质**：只读预检 —— **只检测、不修改、不装包、不联网、不触发 ultralytics AutoUpdate**。

### 本机实测验证记录
- 正常环境 → **就绪 22 / 警告 0 / 失败 0**，退出码 0（A6 摄像头为 INFO，不改变就绪计数；本机探测到内置 + 外接共 2 路）
- `-CheckOnnx`（已装 1.21.1 + `.venv` cuDNN）→ 追加 ONNX 1 项 → **就绪 23 / 警告 0 / 失败 0**
- `-SkipGpu` → D 组正确跳过（机器无可用 GPU 时，模型只能 CPU 跑）
- 人为移除 `models/sam2.1_t.pt` → `[FAIL]` 且退出码 1；恢复后正常
- 用 `powershell`（5.1）实测中文无乱码（UTF-8 with BOM 生效）
- 实现要点：探测代码写临时 `.py` 再执行（规避 PS5.1 多行字符串传 `python -c` 的兼容问题）

---

## 1. 快速用法（用法在前）

```powershell
# 基本检查（推荐先跑这条）
powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1

# 组合：追加 ONNX GPU 检查 + 真实推理一次
powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1 -CheckOnnx -Deep
```

| 可选参数 | 作用 |
|----------|------|
| `-Root <path>` | 指定项目根目录（默认 = 脚本所在目录） |
| `-SkipGpu` | 跳过 GPU/CUDA 探测。**机器无可用 GPU 时用**（模型只能走 CPU） |
| `-Deep` | 额外真实加载模型推理一次（较慢，约 10s） |
| `-CheckOnnx` | **加上这条才有 ONNX 相关检测**（默认不做）。用 `pip show` 只读探测，不触发 AutoUpdate |
| `-NoColor` | 纯文本输出（便于重定向到文件 / CI） |

**退出码**：`0` = 无必查失败，可启动；`1` = 存在 `[FAIL]`，按提示修复后重跑。

**检查分组**：A 系统与外部程序（含可选摄像头探测）· B venv · C Python 包 · D GPU(PyTorch) · E 模型 · F 密钥/数据 · G 端口 · H CUDA Toolkit / `.venv` cuDNN、cuBLAS（ONNX GPU 前置）＋（可选，`-CheckOnnx`）ONNX。

---

## 2. 背景与定位

- 启动链路：`Z_script\run\start_all.ps1` → mediamtx + ffmpeg + 传感器模拟(默认) + Flask(`app.py`)；`app.py` 启动会加载 YOLO/SAM2/WWE-UIE/RAG。
- 依赖横跨：venv、GPU 驱动、第三方包、外部程序（ffmpeg/mediamtx）、模型、密钥、端口——任一缺失，新人只能靠“试运行看报错”排查，沟通成本高。
- 本脚本定位 = **只读环境预检（preflight）**，尽量不打扰系统。

## 3. 目标用户与用法

| 用户 | 用途 |
|------|------|
| 项目所有者 | 发给别人前自检一遍，保证“开箱即用” |
| 接收方 / 新人 | 拿到项目先跑一次，得到“缺什么”的明确清单 |
| 日常回归 | 换机器 / 重装环境后确认无遗漏 |

## 4. 分级原则

| 级别 | 含义 | 影响 | 输出 |
|------|------|------|------|
| 必查 `[FAIL]` | 缺失则**无法启动或无法推理** | 阻止运行 | 🔴 红 / 退出码 1 |
| 建议 `[WARN]` | 缺失只**砍掉某功能**（LLM/增强/ONNX） | 降级运行 | 🟡 黄 |
| 提示 `[INFO]` | 仅说明性 | 无 | 🔵 蓝 |

## 5. 检查项清单（与脚本一致）

### A. 系统与外部程序
| # | 检查项 | 判定方法 | 级别 |
|---|--------|----------|------|
| A1 | 操作系统 | Win32_OperatingSystem | INFO |
| A2 | `ffmpeg` 可用 | `ffmpeg -version` | **FAIL**（推流必需） |
| A3 | `ffmpeg` 支持 `h264_nvenc` | `ffmpeg -encoders` | INFO / WARN（无则回退 CPU 软编 libx264） |
| A4 | `mediamtx\mediamtx.exe` | Test-Path | **FAIL**（本地 RTSP 必需） |
| A5 | NVIDIA 驱动版本 | `nvidia-smi` | INFO / WARN |
| A6 | 可用摄像头（可选） | `ffmpeg -f dshow -list_devices` 读设备名 | INFO（有）/ WARN（无：真实摄像头不可用，可继续用本地视频/RTSP） |

### B. Python 虚拟环境
| # | 检查项 | 判定方法 | 级别 |
|---|--------|----------|------|
| B1 | `.venv\Scripts\python.exe` 存在 | Test-Path | **FAIL**（缺则中止后续 Python 检查） |
| B2 | Python 版本 ≥ 3.9（推荐 3.11） | venv python `--version` | **FAIL** |

### C. Python 第三方包（venv 内 python 逐 import，非全局）
| # | 包 | 级别 |
|---|----|------|
| C1 | torch | 缺→**FAIL**；装了但 CPU 版（版本号无 `+cu`）→ WARN |
| C2 | ultralytics | **FAIL** |
| C3 | opencv-python (`cv2`) | **FAIL** |
| C4 | flask | **FAIL** |
| C5 | flask-sock | **FAIL** |
| C6 | openai | **FAIL** |
| C7 | numpy | **FAIL** |
| C8 | scikit-learn | WARN（缺则 RAG 退化为关键词匹配） |

> 默认**不查** `onnxruntime` / `onnx`：仅 ONNX 模型需要（可选项），且用 `import` 探测会触发 ultralytics 联网 AutoUpdate（隐患）。`-CheckOnnx` 时改用 **`pip show` 读元数据**（不 import、不触发），见 §6。

### D. GPU 与 CUDA（`-SkipGpu` 时整组跳过）
| # | 检查项 | 判定方法 | 级别 |
|---|--------|----------|------|
| D1 | CUDA 对 torch 可用 | `torch.cuda.is_available()` | **FAIL** |
| D2 | torch CUDA 构建 | `torch.version.cuda` 非空 | PASS（随 D1 输出） |
| D3 | 显卡名 / 显存 | `torch.cuda.get_device_name(0)` | INFO |
| D4 | （`-Deep`）真实推理一次 | 加载 `fish_detect_m.pt` 跑 1 帧 | PASS / WARN |

### E. 模型与配置（与 `config.validate()` 一致）
| # | 文件 | 级别 |
|---|------|------|
| E1 | `models/fish_detect_m.pt`（默认检测） | **FAIL** |
| E2 | `models/sam2.1_t.pt`（SAM2 权重） | **FAIL** |
| E3 | `models/sam2_hiera_t.yaml`（SAM2 配置） | **FAIL** |
| E4 | 可选模型（seam/ECA_EMA_BIFPN/disease/seg/onnx 等 9 个） | INFO（全齐）/ WARN（缺只影响下拉框对应选项） |
| E5 | `WWE-UIE/output/.../best_model.pth`（增强权重） | PASS / WARN（缺则图像增强不可用，不影响主流程） |

### F. 密钥 / 数据
| # | 检查项 | 判定 | 级别 |
|---|--------|------|------|
| F1 | DeepSeek API Key（`.env` 或环境变量） | 只报“已配置/未配置”，**不打印值** | PASS / WARN（缺则 LLM 不可用，不影响视频/AI 检测） |
| F2 | 本地推流视频源 `test_video*.mp4` | Test-Path | PASS / WARN（缺则需接真实 RTSP） |

### G. 端口占用（只提示）
| # | 端口 | 级别 |
|---|------|------|
| G1 | 8554（mediamtx RTSP） | INFO（被占提示可能是残留进程） |
| G2 | 5000（Flask Web） | INFO |

### H. CUDA Toolkit / cuDNN（ONNX GPU 前置，仅提示，不计入退出码）
> PyTorch **自带** CUDA 运行时，不依赖本组系统库；本组只影响“ONNX 模型跑 GPU”，故默认仅提示。
| # | 检查项 | 判定方法 | 级别 |
|---|--------|----------|------|
| H1 | 系统 CUDA Toolkit（`CUDA_PATH`） | 环境变量 + Test-Path | INFO |
| H2 | `.venv` 内 cuDNN（`nvidia\cudnn\bin\cudnn64*.dll`） | Test-Path | PASS / WARN（缺：`pip install nvidia-cudnn-cu12`） |
| H3 | `.venv` 内 cuBLAS（`nvidia\cublas\bin\cublas64*.dll`） | Test-Path | PASS / WARN（缺：`pip install nvidia-cublas-cu12`） |

### ONNX（可选，仅 `-CheckOnnx`）
| 场景 | 输出 |
|------|------|
| 未装 onnxruntime-gpu | INFO：ONNX 模型无法 GPU 运行；需用 ONNX 时手动装匹配版，勿让 AutoUpdate 自动装最新 |
| 版本 ≥ 1.29 | WARN：要求 CUDA 13 + cuDNN 9；CUDA 12 环境应装 `onnxruntime-gpu==1.21.*` |
| 1.21.x 且 `.venv` cuDNN 已装 | PASS：就绪（1.21.x = CUDA 12 + cuDNN 9） |
| 其他版本且 cuDNN 未装 | WARN：`pip install nvidia-cudnn-cu12` |

## 6. ONNX 与 ultralytics AutoUpdate（通用坑）

- **现象**：ultralytics 用 `.onnx` 模型时若缺 onnxruntime-gpu，会 AutoUpdate 联网装**最新版**（≥1.29 需 CUDA 13 + cuDNN 9）；若机器独立库只支持 CUDA 12，装上也跑不了 GPU → 崩溃或退化 CPU（本项目踩过，见 `troubleshooting` 第 8 条）。
- **应对**：① 先 `nvidia-smi` 看驱动支持的最高 CUDA；② **匹配安装**——CUDA 12 + cuDNN 9 → `onnxruntime-gpu==1.21.x`，支持 CUDA 13 才用最新版；③ 预先装好匹配版，AutoUpdate 检测到已装就不会覆盖；④ 不用 ONNX 模型无需理会（默认 PT 模型是 GPU 主力）。

## 7. 输出与退出码

- 逐条 `[ OK / FAIL / WARN / INFO] 名称 —— 详情`，按 A→H 分节（`-CheckOnnx` 追加 ONNX 节）；
- 结尾汇总 `就绪 n / 警告 n / 失败 n` + 一句话结论；
- 退出码：0 = 可启动；1 = 存在必查失败。
- 全程**不修改文件、不装包、不联网**（避免和 AutoUpdate 一样帮倒忙）。

## 8. 脚本结构（草案 → 已实现）

```
check_env.ps1
├─ 参数：-Root / -SkipGpu / -Deep / -CheckOnnx / -NoColor
├─ 函数：Emit(级别, 名称, 详情) / Section(标题)
├─ 临时 .py 探测（一次进程完成多包 + CUDA 探测）
├─ 分节执行 A→H；-CheckOnnx 追加 ONNX 节
└─ 汇总 + 退出码
```

## 9. 存放与命名

- 脚本位于 `Z_script\check_env.ps1`（与 `start_all.ps1` 等启动脚本同目录），UTF-8 with BOM。
- 使用说明已同步进根 `README.md`、`docs/BUILD_RUN.md`，并在 `docs/deep-dive/README.md` 登记。

## 10. 验收方式（实测结果见文首）

1. 本机就绪环境运行 → 全部 PASS/INFO，退出码 0；
2. 人为改名 `models/fish_detect_m.pt`（配 `-NoColor` 重定向）→ 对应 `[FAIL]` 且退出码 1，缺项提示清晰；
3. `-SkipGpu` → D 组不误报；
4. `-CheckOnnx` 在 未装 / 1.21.x 匹配 / ≥1.29 三种情况分别给出正确提示；
5. 用 `powershell`（5.1）而非仅 pwsh 实测编码无乱码。

## 11. 注意事项 / 红线

- **绝不**调用 `pip install`、不触发 ultralytics AutoUpdate（onnxruntime 污染教训）；
- **绝不**打印密钥明文，只报“已配置/未配置”；
- 检测一律走 **venv 内 python**，避免把系统全局 python 环境误判成项目环境；
- 输出尽量带“下一步怎么做”提示（如缺包给安装命令文案），让新人能自助。

---

## 附 1：依赖事实依据（供实现引用）

- `config.validate()` 已强制检查：默认 YOLO、SAM2 权重、SAM2 配置、阈值范围；`DEEPSEEK_API_KEY` 仅告警。
- `app.py` / `core/*` 真实第三方依赖：flask、flask-sock、cv2、openai、torch(+torchvision)、ultralytics、numpy、scikit-learn(可回退)。
- 外部程序：ffmpeg（推流 + H.264 编码）、mediamtx.exe（RTSP）。
- 自定义模块：鱼模型依赖 `core/custom_yolo.py` 运行时注册（D4 深度检查已内置 register）。
- 运行时自动创建：`outputs/images`、`outputs/videos`、`outputs/chats`、`data.db`、`app.log` —— 无需预置，不纳入必查。

---

## 附 2：推荐依赖版本（CUDA 12 方案，2026-09-03 实测跑通）

> 目标环境：NVIDIA GPU + Windows + CUDA 12。PyTorch 走自带 CUDA（cu121），ONNX 走系统独立 CUDA + `.venv` 内 cuDNN。

| 依赖 | 推荐版本 | 备注 |
|------|----------|------|
| Python | 3.11（venv） | |
| PyTorch / torchvision | `torch==2.5.1+cu121`（+torchvision/torchaudio） | PyTorch 官网 cu121 index 安装，自带 CUDA 运行时 |
| ultralytics | 8.4.x | |
| opencv-python / flask / flask-sock / openai / numpy / scikit-learn | 最新稳定 | |
| 系统 NVIDIA 驱动 | ≥ 支持 CUDA 12（本机 592.82） | `nvidia-smi` 可查 |
| 系统 CUDA Toolkit | **12.6**（设 `CUDA_PATH`） | 仅 onnxruntime GPU 需要 |
| `.venv` cuDNN | `nvidia-cudnn-cu12==9.25.1.1` | pip 装，随 .venv 可移植 |
| `.venv` cuBLAS | `nvidia-cublas-cu12==12.9.2.10` | cuDNN 自动依赖 |
| **onnxruntime-gpu** | **==1.21.1** | CUDA 12 + cuDNN 9；勿 ≥1.29（需 CUDA 13） |
| onnx | 1.22.x | 装齐避免 ultralytics AutoUpdate |

> 红线：onnxruntime-gpu **1.21.x = CUDA 12 + cuDNN 9**；**≥1.29 需 CUDA 13**。不同 CUDA 配不同版本，勿让 ultralytics AutoUpdate 自动装最新（它只会装最新版）。
