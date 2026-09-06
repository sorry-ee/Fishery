# 项目输出内容（产物）全览

> 本文整理本项目**运行/脚本/训练产生的所有输出文件**：分别说明其**产生来源**、**内容与格式**、**用途**，以及**清理方式**（对应 `Z_script\clean_outputs.ps1`）。
> 修改代码前可先看这里，避免误删有用数据或对运行依赖文件动手。

---

## 一、Web 服务运行时输出（`app.py` 产生）

### 1. `app.log` — 服务运行日志

- **来源**：`app.py` 第 17 行 `logging.basicConfig(..., FileHandler("app.log", encoding="utf-8"))`，与终端 stdout 双写。所有模块（`app` / `ai` / `enhance` / `advisor` / `httpx`）的 INFO 级日志都落在这里。
- **内容**：启动流程（YOLO/SAM2 加载、WWE-UIE 权重路径、RAG 索引数、服务地址）、收到用户咨询、DeepSeek API 调用状态、退出信号与资源清理。
- **用途**：**排障第一手资料**——启动是否成功、模型是否加载、AI 是否在调用、哪里报错。
- **清理**：`Z_script\clean_outputs.ps1` 第 1 步（`*.log`）。删掉后重启会重新生成。

### 2. `outputs/images/` — 网页截图（原 `captures/`）

- **来源**：网页「📷 截图」按钮 → `POST /capture_frame` → `cv2.imwrite(outputs/images/{时间戳}.jpg)`。
- **内容**：当前**最新处理帧**（`last_processed_frame`，即经过增强/AI 叠加后的画面）的 JPEG 快照。默认文件名即时间戳，可在记录回看页右键重命名/删除。
- **用途**：保存现场证据，事后回看鱼群密度、病害、水质异常；也常被拿去当训练/演示素材。
- **清理**：`Z_script\clean_outputs.ps1` 第 2 步（整目录删除）。

### 3. `outputs/videos/` — 网页录像（原 `recordings/`）

- **来源**：网页「⏺ 录制」按钮 → `POST /start_recording` → `cv2.VideoWriter` 尝试 `mp4v → XVID → avc1` 编码；录制期间在视频流线程里把**处理后的帧** `video_writer.write(display_frame)` 写入；「停止」→ `/stop_recording` 释放 writer。
- **内容**：`{时间戳}.mp4`（存于 `outputs/videos/`，默认文件名即时间戳），30 FPS，编码后的**增强/AI 叠加画面**（非原始流）；记录回看页可右键重命名/删除。
- **用途**：录制可疑时段做回放分析、喂给标注工具做训练数据集。
- **清理**：`Z_script\clean_outputs.ps1 -KeepRecordings N` 保留最新 N 个，否则整目录删。

### 4. `data.db`（+ `data.db-wal` / `data.db-shm`）— SQLite 数据库

- **来源**：`core/storage.py` 的 `Storage`，`PRAGMA journal_mode=WAL`（WAL 模式下运行中会伴随 `-wal` / `-shm` 两个临时文件，正常关闭时合并回主库）。
- **内容**，两张表：
  - `sensor_history`：`ts` / `temp` / `ph` / `oxygen` —— 传感器历史记录。
  - `event_log`：`ts` / `level` / `message` —— 异常事件日志。
- **用途**：网页端**传感器趋势图**（`get_sensor_history` 取最近 120 分钟）、异常事件列表（`get_events`）。
- **注意**：属**有价值历史数据**，默认清理**不删除**；`Z_script\clean_outputs.ps1 -All` 才会连 `-wal/-shm` 一起删。删后传感器图/事件从零开始。

### 5. `outputs/chats/` — AI 对话 / 诊断报告记录（新增）

- **来源**：AI 对话（`/chat_ai_stream`、`/chat_ai`）与诊断报告（`/get_ai_advice_stream`、`/get_ai_advice`）**每次完成后自动落盘**为 Markdown（`app.py` 的 `_save_exchange_md`）。
- **内容**：`chat_{时间戳}.md` / `report_{时间戳}.md`，含时间、类型、所用模型、环境快照（报告）、用户提问与完整回复。
- **用途**：记录回看页左侧「对话记录」已接入（左键查看 / 右键重命名·删除）；人工复盘对话/报告；后续"记忆/参考"功能的原始文本来源。
- **清理**：属**有价值历史**，默认保留；`Z_script\clean_outputs.ps1 -All` 才会删除整个目录。

---

## 二、基准测试与验证输出（`scripts/` 产生）

### 6. `bench_output/` — 性能基准 + ONNX 验证

- **来源**：
  - `scripts/bench_full.py` → `bench_output/bench_full_result.json`：用 `test_video_2.mp4` 取 100 帧（5 帧预热），遍历**全部 9 个模型 × 增强开关（无增强 / 开 WWE-UIE）**组合，测单帧耗时 / FPS / 检出数。
  - `scripts/plot_bench.py` → 读上面 JSON，用 matplotlib 生成 **4 张性能图表**（PNG，输出到同目录）：
    - `fig1_enhance_bars.png` — 各模型**增强前后延迟对比**柱状图（无增强 vs +WWE-UIE）
    - `fig2_fps_overview.png` — 各配置**吞吐量（FPS）**横向柱状总览
    - `fig3_latency_ts.png` — 纯检测 / 检测+增强的**逐帧延迟时序**折线（观察波动）
    - `fig4_detections.png` — 各模型**平均检出数**对比（带标准差）
  - `scripts/verify_wwe_uie_onnx.py` → `verify_input.jpg` / `verify_pt_output.jpg` / `verify_onnx_output.jpg`：同一帧分别过 PyTorch 版与 ONNX 版增强模型，输出对比图验证一致性。
- **用途**：模型**选型依据**（对比 9 个模型的延迟 / FPS / 检出数，答辩 PPT 里的性能对比图常来自这里）、确认 ONNX 导出没跑偏。
- **注意**：目录默认被 `Z_script\clean_outputs.ps1` 清掉；需要时依次运行 `python scripts/bench_full.py` → `python scripts/plot_bench.py` 重新生成。
- **清理**：`Z_script\clean_outputs.ps1` 第 3 步（整目录删）。

---

## 三、模型训练 / 导出产物

### 7. `WWE-UIE/output/.../best_model.pth` — 增强模型权重

- **来源**：`scripts/finetune_enhancer.py`（或 WWE-UIE 仓库的 `train.py`）微调训练，产物落在 `WWE-UIE/output/Fishery_WWE_UIEB/UIEB/{时间或描述}/best_model.pth`（含训练日志、checkpoint）。
- **用途**：**运行时被 `core/enhancer.py` 自动加载**——启动时扫描该目录、取**最新子目录**的 `best_model.pth` 作为水下增强权重（见 `app.log` 里的加载路径）。**动它会影响图像增强效果**。
- **清理**：一般不清理（模型权重）。想回退/重训可整理子目录，但需保证至少留一个有效权重。

### 8. `models/wwe_uie.onnx` — 增强模型 ONNX 导出

- **来源**：`scripts/export_wwe_uie_onnx.py` 把 `best_model.pth` 导出为 ONNX（`models/wwe_uie.onnx`）。
- **用途**：无 PyTorch 依赖的 onnxruntime 部署推理（与 PT 版增强结果一致性由 `verify_wwe_uie_onnx.py` 校验）。
- **清理**：可重新导出，一般保留。

---

## 四、离线数据处理脚本输出（`scripts/` 一次性任务）

| 脚本 | 产物 | 用途 |
|------|------|------|
| `batch_enhance.py` | `--output` 指定目录下的增强图片 | 批量预处理水下图片（如为标注/训练准备增强数据集；中文路径用 `imencode` 绕坑） |
| `head_to_body_track.py` | 默认视频同目录 `{视频名}_tracked/`，带 ID 的追踪视频 | 鱼头-鱼身关联追踪结果可视化 |
| `mot_to_yolo.py` | `OUT_DIR/images/train` 图片帧 | 把 MOT 标注转成 YOLO 训练集 |
| `sam2_segment_image.py` | 指定输出的分割图 | SAM2 单图分割效果预览 |
| `generate_ppt.py` | 项目根 `毕业答辩_智慧渔业水下协同控制系统.pptx` | 毕业答辩演示 PPT |

---

## 五、Python 运行时缓存

### 9. `__pycache__/`

- **来源**：Python 解释器自动生成的字节码缓存（各包/模块目录下）。
- **用途**：加速 `import`，无业务价值，可随时删除。
- **清理**：`Z_script\clean_outputs.ps1` 附加步（自动跳过 `.venv` 内的，避免影响虚拟环境）。

---

## 六、测试媒体（输入素材，非输出）

| 文件 | 说明 |
|------|------|
| `test_video.mp4` / `test_video_2.mp4` | `Z_script\run\start_all.ps1` 优先选择的 ffmpeg 推流源（本地视频模拟 RTSP）。**是运行依赖**，`Z_script\clean_outputs.ps1` 明确不删 |
| `test_img.png` | 单帧测试图，供离线脚本验证 |

---

## 七、清理速查表（对应 `Z_script\clean_outputs.ps1`）

| 目标 | 命令 | 影响 |
|------|------|------|
| 日志 + 截图/录像 + 基准 + 缓存 | `Z_script\clean_outputs.ps1` | 常见运行垃圾，可安全清 |
| 保留最新 N 个录像 | `Z_script\clean_outputs.ps1 -KeepRecordings 3` | 录像留 3 个 |
| 预览将删内容 | `Z_script\clean_outputs.ps1 -WhatIf` | 不真删 |
| **连历史数据一起删** | `Z_script\clean_outputs.ps1 -All` | 额外删 `data.db` + `outputs/chats`（传感器/事件/对话历史归零） |

> 红线：**不会**也不应删除 `.venv/`、`models/`、源码、`WWE-UIE/output` 权重、`test_video*.mp4`。
