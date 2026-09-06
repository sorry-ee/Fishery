# 项目详细结构

```
Fishery_Project/
├── app.py                  # Flask 主入口（“接线员”：路由+鉴权；另含截图/录制、记录回看（媒体+对话）端点与对话自动存档）
├── config.py               # 全局配置：模型路径、阈值、LLM、编码器、认证
├── Z_script/                 # PowerShell 脚本（须 UTF-8 with BOM）
│   ├── run/                  # 一键启动脚本（默认带传感器模拟数据，-NoSensor 去掉）
│   │   ├── start_all.ps1     # 本地视频推流启动
│   │   ├── start_pc_camera.ps1  # 电脑内置摄像头启动（设备自动检测）
│   │   ├── start_usb_camera.ps1 # 外接 USB 摄像头启动（设备自动检测）
│   │   └── run-common.ps1    # 启动公共函数库（被 start_*.ps1 dot-source）
│   ├── check_env.ps1         # 环境就绪自检（只读）
│   └── clean_outputs.ps1     # 清理运行产出
├── AGENTS.md               # 项目指南与修改规范
├── README.md               # 开发者指南（环境部分已过时，以 BUILD_RUN.md 为准）
├── .gitignore              # Git 忽略规则
├── .env                    # 密钥配置（gitignore，不提交）
│
├── core/                   # 核心业务模块
│   ├── video_stream.py     # RTSP 双线程异步采集 + 断线重连（指数退避）
│   ├── frame_processor.py  # 帧处理流水线（增强→AI→叠加文字），工厂闭包
│   ├── ai_detector.py      # YOLO 检测/跟踪 + SAM2/YOLO-seg 分割 + MaskTracker
│   ├── custom_yolo.py      # 自定义 YOLO 模型注册
│   ├── mask_tracker.py     # 掩码跨帧跟踪 + ID 绘制
│   ├── enhancer.py         # WWE-UIE 水下图像增强（FP16 + 预热）
│   ├── llm_advisor.py      # LLM 诊断 + 对话（规则诊断 + RAG；reconfigure 热切换）
│   ├── llm_settings.py     # LLM 多服务方案管理（新增/启用/禁用，llm_settings.json 持久化）
│   ├── storage.py          # SQLite 持久化（传感器历史 / 事件）
│   ├── h264_streamer.py    # FFmpeg 子进程 H.264 fMP4 编码 + MP4 box 解析
│   └── ws_handler.py       # WebSocket 视频推流端点
│
├── knowledge/              # 知识库
│   ├── knowledge_base.py   # EelKnowledgeBase 规则诊断 + RAGEngine(TF-IDF)
│   └── eel_knowledge.json  # 鳗鲡养殖知识图谱（数据源）
│
├── templates/
│   └── index.html          # Web 控制台 SPA（MJPEG/H.264、传感器、AI 对话）
│
├── static/                 # 前端静态资源（Flask 默认静态目录）
│   └── js/
│       └── marked.min.js   # Markdown 渲染库（本地化，避免依赖 CDN 被墙导致不渲染）
│
├── tools/                  # 第三方工具
│   ├── mediamtx/           # 本地 RTSP 服务器
│   │   ├── mediamtx.exe    # （gitignore，不提交）
│   │   └── mediamtx.yml    # RTSP 服务器配置
│   └── ffmpeg/
│       └── bin/ffmpeg.exe  # 本地自带 ffmpeg（gitignore；脚本优先使用，缺省回退 PATH）
│
├── outputs/                # 运行产物（gitignore）：images 截图 / videos 录像 / chats AI 对话文本
│
├── models/                 # 模型权重（.pt/.onnx/.om，全部 gitignore）
│   └── sam2_hiera_t.yaml   # SAM2 配置文件（文本，提交）
│
├── scripts/                # 辅助脚本（批量增强、基准测试、PPT 生成等）
├── tests/                  # pytest 测试（LLM / 增强 / H.264）
├── WWE-UIE/                # 水下增强模型仓库（训练 + 推理）
│
└── docs/                   # 项目文档
    ├── ROADMAP.md          # 开发路线图
    ├── troubleshooting.md  # 已知问题与踩坑
    ├── code_review.md      # 代码审查报告
    ├── BUILD_RUN.md        # 环境配置与运行指南
    ├── structure.md        # 本文档
    ├── patches/            # 修改补丁记录（before/after）
    └── deep-dive/          # 分模块深入讲解
```

## 关键调用链

三条主线互不相干，各看各的。

### ① 视频

```
RTSP 流 → video_stream（后台抓帧）→ frame_processor（增强→AI→叠加文字）
         ├─ MJPEG  → GET /video_feed（<img> 显示）
         └─ H.264  → ws_handler → h264_streamer → WS /ws_video
```

### ② LLM / AI 建议（核心）

一条消息从“点击”到“回显”的完整链路：

```
前端 templates/index.html
 ├─「生成当前环境实时诊断报告」按钮 → POST /get_ai_advice   # 诊断报告
 ├─ 聊天框「发送」                    → POST /chat_ai        # 自由对话
 └─ 每隔几秒自动轮询                  → GET  /check_alarm    # 顶部告警条（本地规则，不走 AI）

            ▼ 所有请求都先进 app.py（Flask 主入口 = 接线员，只转发不干活）

app.py（路由层）
 ├─ /get_ai_advice → llm_advisor.get_advice(mcu_data)          # ① 诊断报告
 ├─ /chat_ai       → llm_advisor.ask_question(msg, mcu_data)   # ② 自由对话
 ├─ /check_alarm   → llm_advisor.kb.get_alarms(...)            # ③ 规则告警（本地规则，不调 LLM）
 ├─ /llm_profiles… /llm_test /llm_models …                     # ④ 「LLM 服务设置」弹窗的接口
 └─ /video_feed /ws_video /toggle_ai …                         # ⑤ 视频/控制（与 AI 无关）

            ▼ 真正“动脑”的地方（逐行讲解见 deep-dive/llm-advisor.md）

core/llm_advisor.py（FisheryAdvisor —— 养殖专家大脑）
 ├─ self.client = OpenAI(base_url, api_key, model)  # 连“当前启用”的模型服务
 ├─ get_advice()   报告：本地规则诊断 + RAG 检索 → 发模型（无 thinking）
 └─ ask_question() 对话：RAG 检索 → 发模型（普通模式，已去 thinking 省 token）

            ▼ 连哪家服务由谁定？

config.py（系统默认）              llm_settings.py + llm_settings.json（运行时用户配置）
 LLM_BASE_URL / LLM_MODEL   ←———   「LLM 服务设置」弹窗保存的启用方案
 （仅作“禁用自定义”后的兜底）          reconfigure() 热替换，改完立即生效、无需重启
```

### ③ 传感器

```
上报 POST /update_sensor → storage（SQLite 落库）→ 前端轮询 GET /get_sensor 实时显示
                      └→ 规则告警 check_alarm → 事件日志（画面右下角）
```

> 深挖某一部分可看 `docs/deep-dive/`。
