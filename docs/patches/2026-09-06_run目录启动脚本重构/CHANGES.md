# 修改日期：2026-09-06
# 修改人：AI（用户确认）

## 修改文件
- 新增：`Z_script/run/run-common.ps1`（启动公共函数库）
- 新增（重写）：`Z_script/run/start_all.ps1`、`Z_script/run/start_pc_camera.ps1`、`Z_script/run/start_usb_camera.ps1`
- 删除（并入/迁移）：`Z_script/start_all.ps1`、`Z_script/start_all_with_sensor.ps1`、`Z_script/start_pc_camera.ps1`、`Z_script/start_usb_camera.ps1`
- `Z_script/check_env.ps1`（提示路径 ×3）
- 文档：`AGENTS.md`、`README.md`、`docs/BUILD_RUN.md`、`docs/ROADMAP.md`、`docs/structure.md`、`docs/troubleshooting.md`、`docs/deep-dive/outputs.md`、`docs/env_check_plan.md`
- 备份：旧 4 脚本在 `docs/patches/2026-09-06_run目录启动脚本重构/before/`；新文件见 `Z_script/run/`（after 同步副本在同目录补丁 `after/`）

## 修改原因
- 完善 PowerShell 脚本结构：把「运行/启动脚本」与「维护脚本」分层 —— 启动类收进 `Z_script/run/`，维护类（check_env/clean_outputs）留在 `Z_script/`。
- 三个启动脚本此前结构重复（mediamtx/推流/Flask/清理几乎相同），且 `start_all.ps1` 与 `start_all_with_sensor.ps1` 高度重复。
- 用户要求：所有启动脚本**默认带传感器模拟数据、可用参数去除**；确认外接摄像头为参数默认值非硬编码后，补「默认名找不到时自动枚举/交互选择」能力。

## 修改内容
1. 目录：`Z_script/run/`（含 `run-common.ps1` 公共函数库 + 3 个 `start_*.ps1`）；删除 `start_all_with_sensor.ps1`（并入 start_all）。
2. 公共库 `run-common.ps1`（纯函数，dot-source 加载，无副作用）：
   - `Get-ProjectRoot`（run 上两级）；`Get-LocalFfmpeg`（tools 优先/回退 PATH）
   - `Select-PushVideoSource`（test_video*.mp4 → outputs/videos 最新）
   - `Get-CameraList` / `Resolve-CameraDevice`（摄像头枚举与解析：默认名找不到 → 唯一自动选用 / 多个交互选序号；显式 `-DeviceName` 找不到 → 报错并列出可用设备）
   - `Start-SensorSim`（默认启动 datatran_test.py；`-Skip` 跳过；日志 scratch/sensor_sim.*）
3. 三个 `start_*.ps1`：统一参数 `-NoSensor`（默认带模拟数据），4 步流程
   mediamtx → ffmpeg 推流（本地视频或摄像头实时采集）→ 传感器模拟 → Flask；Ctrl+C 自动清理本次启动的子进程。
4. 摄像头脚本：设备名是参数默认值（非写死）；增加 `Resolve-CameraDevice` 自动检测交互。

## 影响范围
- 运行方式改变：启动脚本路径 `Z_script\start_*.ps1` → `Z_script\run\start_*.ps1`；`start_all_with_sensor.ps1` 删除（功能并入 `run\start_all.ps1`，默认即带模拟、`-NoSensor` 去掉）。相关文档/脚本提示已全部同步。
- 行为：三个启动脚本默认都启动传感器模拟器（此前 camera 版不带）；摄像头缺省名找不到时不再直接报错，而是自动枚举/交互。

## 验证
- 6 个 Z_script ps1：AST 语法 0 错误、UTF-8 BOM 全保留。
- 公共函数实测：Root=D:\Fishery_Project、ffmpeg=tools 版、视频源=test_video.mp4、枚举到 2 个摄像头（HP Wide Vision HD Camera / USB Video Device）。
- 真机启动 `run\start_all.ps1`（默认）：mediamtx / ffmpeg 推流 / 传感器模拟器启动 / Flask 全通，`/health` 正常，`get_sensor` 返回实时模拟水质（temp/ph/oxygen 波动）。
- 测试后已清理：5000/8554 空闲，无 mediamtx/ffmpeg/datatran 残留。
- `-NoSensor` 分支：由 Start-SensorSim -Skip 处理（输出“[跳过]”）并返回 $null，finally 容错；未单独跑整链路。

## 备注
- 交互选摄像头使用 `Read-Host`，仅在默认设备名找不到且存在多个候选时触发（正常设备直接跳过）。
