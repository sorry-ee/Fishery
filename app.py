# app.py
import cv2
import time
import os
import json
import threading
import logging
import sys
from functools import wraps
from flask import Flask, render_template, Response, jsonify, request, send_from_directory
from flask_sock import Sock

# ---- 日志 ----
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
LOG_DATE = "%H:%M:%S"
logging.basicConfig(
    level=logging.INFO, format=LOG_FORMAT, datefmt=LOG_DATE,
    handlers=[logging.StreamHandler(sys.stdout), logging.FileHandler("app.log", encoding="utf-8")],
)
logging.getLogger("werkzeug").setLevel(logging.WARNING)
log = logging.getLogger("app")

# ---- 模块 ----
import config
config.validate()
from core.video_stream import VideoCaptureThreading
from core.ai_detector import FisheryAI
from core.enhancer import WWEEnhancer
from core.llm_advisor import FisheryAdvisor
import core.llm_settings as llm_settings_cfg
from core.storage import Storage
from core.frame_processor import create_frame_processor
from core.network_simulator import NetworkSimulator
from core.ws_handler import register_ws

# ---- Flask ----
app = Flask(__name__)
sock = Sock(app)

def require_auth(f):
    @wraps(f)
    def wrapper(*a, **kw):
        expected = f"Bearer {config.AUTH_TOKEN}"
        if request.headers.get("Authorization", "") != expected:
            return jsonify({"status": "error", "message": "未授权访问"}), 401
        return f(*a, **kw)
    return wrapper

# ---- 全局状态 ----
system_state = {
    "ai_enabled": True,
    "enhancement_enabled": False,
    "seg_enabled": False,
    "adaptive_test_bandwidth_kbps": 0,
    "adaptive_runtime_connected": False,
    "adaptive_throughput_kbps": 0.0,
    "adaptive_media_lag_ms": 0.0,
}
network_simulator = NetworkSimulator(system_state)
video_stream = VideoCaptureThreading(config.STREAM_URL)
ai_detector = FisheryAI(config.AVAILABLE_MODELS[config.DEFAULT_MODEL_KEY], model_key=config.DEFAULT_MODEL_KEY)
enhancer = WWEEnhancer()
storage = Storage()
llm_advisor = FisheryAdvisor()
mcu_data = {"temp": "--", "ph": "--", "oxygen": "--", "last_update": "未连接"}
recording = False
video_writer = None
record_lock = threading.Lock()
event_log: list = []
last_processed_frame = None  # 截图复用，避免抢流
perf_state = {"fps": 0.0, "last_update": 0}  # 性能快照，frame_processor 每 0.5s 更新

# 注册 H.264 WebSocket
register_ws(
    sock, video_stream,
    lambda: create_frame_processor(system_state, enhancer, ai_detector, perf_state),
    system_state,
)

# 预创建输出目录（统一放 outputs/：images 截图 / videos 录像 / chats AI 对话文本）
ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUTS_DIR = os.path.join(ROOT, 'outputs')
CAPTURES_DIR = os.path.join(OUTPUTS_DIR, 'images')    # 截图
RECORDINGS_DIR = os.path.join(OUTPUTS_DIR, 'videos')  # 录像
CHATS_DIR = os.path.join(OUTPUTS_DIR, 'chats')        # AI 对话/诊断报告 Markdown
for _d in (CAPTURES_DIR, RECORDINGS_DIR, CHATS_DIR):
    os.makedirs(_d, exist_ok=True)


# -- MJPEG 视频流 --

def generate_frames():
    global last_processed_frame
    processor = create_frame_processor(system_state, enhancer, ai_detector, perf_state)
    while True:
        ret, frame = video_stream.read()
        if not ret or frame is None:
            time.sleep(0.01)
            continue
        display_frame = processor(frame)
        last_processed_frame = display_frame.copy()

        if recording:
            with record_lock:
                if video_writer is not None:
                    video_writer.write(display_frame)

        ret, buffer = cv2.imencode('.jpg', display_frame)
        if not ret:
            continue
        yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + buffer.tobytes() + b'\r\n')


# -- 路由 --

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/video_feed')
def video_feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/health')
def health():
    return jsonify({
        'stream_ok': video_stream.is_connected(),
        'ai_loaded': ai_detector is not None,
        'enhancer_loaded': enhancer is not None,
        'recording': recording,
    })

@app.route('/perf_snapshot')
def perf_snapshot():
    data = {
        'fps': perf_state['fps'],
        'ai_enabled': system_state['ai_enabled'],
        'enhancement_enabled': system_state['enhancement_enabled'],
        'seg_enabled': system_state['seg_enabled'],
        'model_key': ai_detector._model_key if ai_detector else '--',
        'fish_count': ai_detector.last_count if ai_detector else 0,
        'ts': time.time(),
    }
    data.update(network_simulator.status())
    # GPU 显存
    try:
        import pynvml
        pynvml.nvmlInit()
        h = pynvml.nvmlDeviceGetHandleByIndex(0)
        info = pynvml.nvmlDeviceGetMemoryInfo(h)
        util = pynvml.nvmlDeviceGetUtilizationRates(h)
        data['gpu_mem_mb'] = round(info.used / 1024 / 1024, 1)
        data['gpu_mem_total_mb'] = round(info.total / 1024 / 1024, 1)
        data['gpu_util_pct'] = util.gpu
    except Exception:
        pass
    # CPU / RAM
    try:
        import psutil
        data['cpu_pct'] = psutil.cpu_percent(interval=0.1)
        mem = psutil.virtual_memory()
        data['ram_mb'] = round(mem.used / 1024 / 1024, 1)
        data['ram_total_mb'] = round(mem.total / 1024 / 1024, 1)
    except Exception:
        pass
    return jsonify(data)


@app.route('/network_simulator/status')
def network_simulator_status():
    return jsonify(network_simulator.status())


@app.route('/network_simulator', methods=['POST'])
@require_auth
def set_network_simulator():
    data = request.get_json(silent=True) or {}
    try:
        if data.get('action') == 'demo':
            return jsonify(network_simulator.start_demo())
        return jsonify(network_simulator.set_mode(data.get('mode', 'normal')))
    except ValueError as exc:
        return jsonify({'status': 'error', 'message': str(exc)}), 400

# -- AI 控制 --

@app.route('/toggle_ai', methods=['POST'])
@require_auth
def toggle_ai():
    system_state["ai_enabled"] = not system_state["ai_enabled"]
    return jsonify({'ai_enabled': system_state["ai_enabled"]})

@app.route('/toggle_enhancement', methods=['POST'])
@require_auth
def toggle_enhancement():
    system_state["enhancement_enabled"] = not system_state["enhancement_enabled"]
    return jsonify({'enhancement_enabled': system_state["enhancement_enabled"]})

@app.route('/toggle_segmentation', methods=['POST'])
@require_auth
def toggle_segmentation():
    system_state["seg_enabled"] = not system_state["seg_enabled"]
    return jsonify({'seg_enabled': system_state["seg_enabled"]})

@app.route('/switch_model', methods=['POST'])
@require_auth
def switch_model():
    data = request.get_json()
    key = data.get('model_key')
    if key not in config.AVAILABLE_MODELS:
        return jsonify({'status': 'error', 'message': '未知模型'}), 400
    try:
        ai_detector.load_model(config.AVAILABLE_MODELS[key], model_key=key)
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# -- 传感器 --

@app.route('/update_sensor', methods=['POST'])
@require_auth
def update_sensor():
    try:
        data = request.get_json()
        if not data: return jsonify({'status': 'error'}), 400
        for k in ("temp", "ph", "oxygen"):
            v = data.get(k)
            if v is not None:
                try:
                    fv = float(v)
                    if not (-50 <= fv <= 100):
                        return jsonify({'status': 'error', 'msg': f'{k} 值 {fv} 超出合理范围'}), 400
                except (ValueError, TypeError):
                    return jsonify({'status': 'error', 'msg': f'{k} 值 "{v}" 无效'}), 400
                mcu_data[k] = str(fv)
        mcu_data["last_update"] = time.strftime("%H:%M:%S")
        storage.add_sensor(mcu_data["temp"], mcu_data["ph"], mcu_data["oxygen"])
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'msg': str(e)}), 500

@app.route('/get_sensor')
def get_sensor():
    return jsonify(mcu_data)

@app.route('/get_sensor_history')
def get_sensor_history():
    return jsonify(storage.get_sensor_history(minutes=120))

# -- 告警 & 事件 --

@app.route('/check_alarm')
def check_alarm():
    alarms = llm_advisor.kb.get_alarms(
        str(mcu_data.get("temp", "--")),
        str(mcu_data.get("ph", "--")),
        str(mcu_data.get("oxygen", "--"))
    )
    now = time.strftime("%m-%d %H:%M:%S")
    recent_keys = {e["message"] for e in event_log if time.time() - e.get("_ts", 0) < 30}
    for level, msg in alarms:
        if level == "critical" and msg not in recent_keys:
            event_log.insert(0, {"time": now, "type": "alarm", "level": level,
                                 "message": msg, "_ts": time.time()})
            recent_keys.add(msg)
            storage.add_event(level, msg)
    now_ts = time.time()
    event_log[:] = [e for e in event_log if (
        e["level"] == "critical" and e.get("_ts", 0) > now_ts - 1800
    ) or (
        e["level"] != "critical" and e.get("_ts", 0) > now_ts - 120
    )][:30]
    return jsonify({"alarms": [{"level": l, "message": m} for l, m in alarms]})

@app.route('/get_events')
def get_events():
    mem = [{k: v for k, v in e.items() if k != "_ts"} for e in event_log[:20]]
    if not mem:
        mem = storage.get_events(20, minutes=30)
    return jsonify({"events": mem})

# -- LLM --

def _llm_default_triple():
    """系统默认三件套（config.py / .env）。"""
    return config.LLM_BASE_URL, config.LLM_API_KEY, config.LLM_MODEL


def _apply_llm_active():
    """启动时若存有已启用方案则热切换，否则保持系统默认。"""
    prof = llm_settings_cfg.get_active_profile()
    if prof:
        llm_advisor.reconfigure(prof["base_url"], prof["api_key"], prof["model"])
        log.info("LLM 已启用保存的方案「%s」→ %s", prof["name"], prof["model"])


def _llm_err_message(e):
    """把 openai SDK 异常翻译成中文可读提示。"""
    import openai
    if isinstance(e, openai.AuthenticationError):
        return "API Key 无效或未授权（401），请检查 Key"
    if isinstance(e, openai.PermissionDeniedError):
        return "该 API Key 无权访问此服务（403）"
    if isinstance(e, openai.NotFoundError):
        return "找不到该模型（404）—— 请点「获取模型」选择服务商真实提供的模型 ID"
    if isinstance(e, openai.RateLimitError):
        return "请求过于频繁或账户余额不足（429）"
    if isinstance(e, openai.APIConnectionError):
        return "无法连接到该地址，请检查 Base URL 是否正确、网络是否可达"
    if isinstance(e, openai.BadRequestError):
        return "请求参数有误（400）：" + str(getattr(e, "message", e))[:120]
    if isinstance(e, openai.APIStatusError):
        return f"服务端异常（HTTP {e.status_code}）：{str(getattr(e, 'message', e))[:120]}"
    return f"连接失败：{str(e)[:160]}"


@app.route('/get_ai_advice', methods=['POST'])
@require_auth
def get_ai_advice():
    advice = llm_advisor.get_advice(mcu_data)
    try:
        _save_exchange_md("report", "", advice, mcu_data)
    except Exception as e:
        log.warning("AI 记录落盘失败: %s", e)
    return jsonify({'advice': advice})

@app.route('/chat_ai', methods=['POST'])
@require_auth
def chat_ai():
    try:
        data = request.get_json()
        msg = data.get('message', '')
        if not msg:
            return jsonify({'response': '你想问我什么呢？'}), 400
        log.info("收到用户咨询: %s", msg[:100])
        resp = llm_advisor.ask_question(msg, mcu_data)
        try:
            _save_exchange_md("chat", msg, resp, mcu_data)
        except Exception as e:
            log.warning("AI 记录落盘失败: %s", e)
        return jsonify({'response': resp})
    except Exception as e:
        return jsonify({'response': f'对话引擎出了一点小状况: {str(e)}'}), 500


# -- LLM 流式（打字机）端点：对话与诊断报告走 SSE；旧非流式端点保留作回退 --

def _save_exchange_md(kind, question, answer, snapshot=None):
    """把一轮 AI 交互落盘为 Markdown（outputs/chats/）。kind: chat | report"""
    if not answer:
        return None
    ts_file = time.strftime("%Y%m%d_%H%M%S")
    ts_disp = time.strftime("%Y-%m-%d %H:%M:%S")
    prof = llm_settings_cfg.get_active_profile()
    _model = prof["model"] if prof else _llm_default_triple()[2]
    lines = [
        "# AI 记录",
        "",
        f"- 时间：{ts_disp}",
        f"- 类型：{'养殖对话' if kind == 'chat' else '环境诊断报告'}",
        f"- 模型：{_model}",
    ]
    if snapshot:
        lines.append(
            f"- 环境快照：水温 {snapshot.get('temp', '--')}℃ / pH {snapshot.get('ph', '--')} / "
            f"溶氧 {snapshot.get('oxygen', '--')} mg/L"
        )
    if question:
        lines += ["", "## 用户提问", "", question]
    lines += ["", "## 回复", "", answer, ""]
    fname = f"{kind}_{ts_file}.md"
    path = os.path.join(CHATS_DIR, fname)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    log.info("AI 记录已保存: %s", path)
    return fname


def _sse(generator, kind=None, question=""):
    """把内容生成器包装成 SSE 事件流；出错也推送 done 避免前端一直等。
    kind/question 提供时，流结束会把整轮内容落盘为 Markdown（outputs/chats/）。"""
    buf = []
    try:
        for piece in generator:
            buf.append(piece)
            yield "data: " + json.dumps({"delta": piece}, ensure_ascii=False) + "\n\n"
    except Exception as e:
        log.error("SSE 流中断: %s", e)
        yield "data: " + json.dumps({"delta": f"\n\n⚠️ 流式输出中断: {e}"}, ensure_ascii=False) + "\n\n"
    finally:
        if kind:
            try:
                _save_exchange_md(kind, question, "".join(buf), mcu_data)
            except Exception as e:
                log.warning("AI 记录落盘失败: %s", e)
        yield "data: " + json.dumps({"done": True}) + "\n\n"


@app.route('/chat_ai_stream', methods=['POST'])
@require_auth
def chat_ai_stream():
    data = request.get_json() or {}
    msg = data.get('message', '')
    if not msg:
        return jsonify({'error': '空消息'}), 400
    log.info("流式咨询: %s", msg[:100])
    return Response(_sse(llm_advisor.stream_answer(msg, mcu_data), kind="chat", question=msg),
                    mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


@app.route('/get_ai_advice_stream', methods=['POST'])
@require_auth
def get_ai_advice_stream():
    return Response(_sse(llm_advisor.stream_advice(mcu_data), kind="report"),
                    mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


# -- LLM 服务配置管理（新增 / 保存 / 启用 / 禁用，见设置弹窗） --

@app.route('/llm_profiles', methods=['GET'])
@require_auth
def llm_profiles():
    """返回所有已保存方案（Key 打码）与当前生效状态。"""
    profiles, active_id = llm_settings_cfg.list_profiles_masked()
    base_url, _, model = _llm_default_triple()
    return jsonify({
        "profiles": profiles,
        "active_id": active_id,
        "default": {"base_url": base_url, "model": model},
    })


@app.route('/llm_profiles/save', methods=['POST'])
@require_auth
def llm_profile_save():
    """新增或更新一套方案；若更新的正是当前启用项则同步热切换（保存即生效）。"""
    try:
        profile, is_new = llm_settings_cfg.upsert(request.get_json() or {})
        active = llm_settings_cfg.get_active_profile()
        if not is_new and active and profile["id"] == active["id"]:
            llm_advisor.reconfigure(profile["base_url"], profile["api_key"], profile["model"])
        return jsonify({"status": "success", "id": profile["id"], "is_new": is_new})
    except ValueError as e:
        return jsonify({"status": "error", "message": str(e)}), 400
    except Exception as e:
        log.error("保存 LLM 方案失败: %s", e)
        return jsonify({"status": "error", "message": f"保存失败: {e}"}), 500


@app.route('/llm_profiles/activate', methods=['POST'])
@require_auth
def llm_profile_activate():
    """启用某方案：立即重建连接并持久化 active_id，重启后仍生效。"""
    pid = (request.get_json() or {}).get("id") or ""
    try:
        prof = llm_settings_cfg.activate(pid)
        llm_advisor.reconfigure(prof["base_url"], prof["api_key"], prof["model"])
        return jsonify({"status": "success", "name": prof["name"], "model": prof["model"]})
    except ValueError as e:
        return jsonify({"status": "error", "message": str(e)}), 400


@app.route('/llm_profiles/disable', methods=['POST'])
@require_auth
def llm_profile_disable():
    """禁用自定义方案：回落到系统默认（config.py / .env），无需重启。"""
    llm_settings_cfg.deactivate()
    base_url, api_key, model = _llm_default_triple()
    llm_advisor.reconfigure(base_url, api_key, model)
    return jsonify({"status": "success", "model": model, "base_url": base_url})


@app.route('/llm_profiles/delete', methods=['POST'])
@require_auth
def llm_profile_delete():
    """删除方案；若删的正是启用项则自动回落到系统默认。"""
    pid = (request.get_json() or {}).get("id") or ""
    was_active = llm_settings_cfg.delete_profile(pid)
    if was_active:
        base_url, api_key, model = _llm_default_triple()
        llm_advisor.reconfigure(base_url, api_key, model)
    return jsonify({"status": "success"})


@app.route('/llm_test', methods=['POST'])
@require_auth
def llm_test():
    """用界面填写的 地址/Key/模型 做一次 1-token 探针，校验三件套。"""
    d = request.get_json() or {}
    base_url = (d.get("base_url") or "").strip().rstrip("/")
    api_key = (d.get("api_key") or "").strip()
    model = (d.get("model") or "").strip()
    # Key 留空但给了方案 id → 复用已保存的明文 Key（编辑未改 Key 也能测试）
    if not api_key and (d.get("id") or ""):
        saved = llm_settings_cfg.get_profile_by_id(d.get("id"))
        if saved:
            api_key = saved.get("api_key", "")
            base_url = base_url or saved.get("base_url", "")
            model = model or saved.get("model", "")
    if not (base_url and api_key and model):
        return jsonify({"status": "error", "message": "Base URL / API Key / 模型 ID 均需填写（编辑已有方案可留空 Key）"}), 400
    try:
        from openai import OpenAI
        client = OpenAI(base_url=base_url, api_key=api_key, timeout=15)
        client.chat.completions.create(
            model=model, messages=[{"role": "user", "content": "ping"}], max_tokens=1)
        return jsonify({"status": "success", "message": f"连接成功，模型可用：{model}"})
    except Exception as e:
        return jsonify({"status": "error", "message": _llm_err_message(e)})


@app.route('/llm_models', methods=['POST'])
@require_auth
def llm_models():
    """用 地址+Key 从服务商拉取该 Key 真实可用的模型列表，避免手填错模型 ID。"""
    d = request.get_json() or {}
    base_url = (d.get("base_url") or "").strip().rstrip("/")
    api_key = (d.get("api_key") or "").strip()
    if not api_key and (d.get("id") or ""):
        saved = llm_settings_cfg.get_profile_by_id(d.get("id"))
        if saved:
            api_key = saved.get("api_key", "")
            base_url = base_url or saved.get("base_url", "")
    if not (base_url and api_key):
        return jsonify({"status": "error", "message": "请先填写 Base URL 与 API Key（编辑已有方案可留空 Key）"}), 400
    try:
        from openai import OpenAI
        client = OpenAI(base_url=base_url, api_key=api_key, timeout=15)
        ids = sorted(m.id for m in client.models.list().data)
        if not ids:
            return jsonify({"status": "error", "message": "该服务未返回任何模型"})
        return jsonify({"status": "success", "models": ids})
    except Exception as e:
        return jsonify({"status": "error", "message": _llm_err_message(e)})


# -- 截图 & 录制 --

@app.route('/capture_frame', methods=['POST'])
@require_auth
def capture_frame():
    global last_processed_frame
    frame = last_processed_frame
    if frame is None:
        return jsonify({'status': 'error', 'message': '暂无已处理帧'}), 500
    ts = time.strftime("%Y%m%d_%H%M%S")
    cv2.imwrite(os.path.join(CAPTURES_DIR, f"{ts}.jpg"), frame)   # 直接用时间命名
    return jsonify({'status': 'success', 'filename': f"{ts}.jpg"})

@app.route('/start_recording', methods=['POST'])
@require_auth
def start_recording():
    global video_writer, recording
    with record_lock:
        if recording:
            return jsonify({'status': 'error', 'message': '已在录制中'})
        ret, frame = video_stream.read()
        if not ret or frame is None:
            return jsonify({'status': 'error', 'message': '无法获取视频帧'}), 500
        h, w = frame.shape[:2]
        ts = time.strftime('%Y%m%d_%H%M%S')
        filename = f"{ts}.mp4"   # 直接用时间命名
        for codec in ['mp4v', 'XVID', 'avc1']:
            fourcc = cv2.VideoWriter_fourcc(*codec)
            video_writer = cv2.VideoWriter(os.path.join(RECORDINGS_DIR, filename), fourcc, 30.0, (w, h))
            if video_writer.isOpened():
                break
        if not video_writer or not video_writer.isOpened():
            video_writer = None
            return jsonify({'status': 'error', 'message': '编码器打开失败'}), 500
        recording = True
        return jsonify({'status': 'success', 'filename': filename})

@app.route('/stop_recording', methods=['POST'])
@require_auth
def stop_recording():
    global video_writer, recording
    with record_lock:
        if not recording:
            return jsonify({'status': 'error', 'message': '未在录制'})
        recording = False
        if video_writer:
            video_writer.release()
            video_writer = None
        return jsonify({'status': 'success'})


# -- 记录回看（outputs 媒体浏览：截图/录像；对话存档在 outputs/chats，页面待接入） --

_MEDIA_DIRS = {"images": CAPTURES_DIR, "videos": RECORDINGS_DIR}
_MEDIA_EXTS = {"images": (".jpg", ".jpeg", ".png"), "videos": (".mp4", ".avi", ".mov", ".mkv")}


@app.route('/media_api/list')
@require_auth
def media_list():
    """返回 outputs 截图/录像清单（时间倒序），供「记录回看」页渲染缩略图。"""
    out = {"images": [], "videos": []}
    for cat, base in _MEDIA_DIRS.items():
        try:
            names = sorted(os.listdir(base), reverse=True)
        except OSError:
            names = []
        for fn in names:
            if os.path.splitext(fn)[1].lower() not in _MEDIA_EXTS[cat]:
                continue
            p = os.path.join(base, fn)
            if not os.path.isfile(p):
                continue
            st = os.stat(p)
            out[cat].append({
                "name": fn,
                "url": f"/media/{cat}/{fn}",
                "size": st.st_size,
                "time": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime)),
            })
    return jsonify(out)


@app.route('/media/<cat>/<fname>')
def media_file(cat, fname):
    """提供截图/录像文件访问（<img>/<video> 缩略图用；本机演示故不加鉴权）。"""
    base = _MEDIA_DIRS.get(cat)
    if not base or os.path.basename(fname) != fname:  # 防目录穿越
        return "not found", 404
    return send_from_directory(base, fname)


@app.route('/media/open', methods=['POST'])
@require_auth
def media_open():
    """用系统默认程序（Windows 自带查看器/播放器）打开指定截图/录像。"""
    data = request.get_json(silent=True) or {}
    cat, name = data.get("cat"), data.get("name", "")
    base = _MEDIA_DIRS.get(cat)
    if not base or not name or os.path.basename(name) != name:
        return jsonify({"status": "error", "message": "参数非法"}), 400
    p = os.path.join(base, name)
    if not os.path.isfile(p):
        return jsonify({"status": "error", "message": "文件不存在"}), 404
    try:
        os.startfile(p)  # Windows 默认查看器打开（图片查看器 / 播放器）
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# -- 图片/视频 文件 删除 / 重命名（供缩略图右键菜单） --

@app.route('/media_api/file/delete', methods=['POST'])
@require_auth
def media_file_delete():
    data = request.get_json(silent=True) or {}
    cat, name = data.get("cat"), data.get("name", "")
    base = _MEDIA_DIRS.get(cat)
    if not base or not name or os.path.basename(name) != name:
        return jsonify({"status": "error", "message": "参数非法"}), 400
    p = os.path.join(base, name)
    if not os.path.isfile(p):
        return jsonify({"status": "error", "message": "文件不存在"}), 404
    try:
        os.remove(p)
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/media_api/file/rename', methods=['POST'])
@require_auth
def media_file_rename():
    data = request.get_json(silent=True) or {}
    cat = data.get("cat")
    old_raw, new_raw = data.get("old", ""), data.get("new", "")
    base = _MEDIA_DIRS.get(cat)
    # 拒绝带路径分隔的输入（防穿越：显式报错，而非 os.path.basename 静默剥壳）
    if not base or os.path.basename(old_raw) != old_raw or os.path.basename(new_raw) != new_raw:
        return jsonify({"status": "error", "message": "参数非法"}), 400
    old, new = old_raw, new_raw
    old_ext = os.path.splitext(old)[1].lower()   # 保留原扩展名（缩略图/播放依赖）
    new = os.path.splitext(new)[0] + old_ext
    if old == new:
        return jsonify({"status": "error", "message": "名称未变化"}), 400
    if any(c in new for c in ('/', '\\', ':', '*', '?', '"', '<', '>', '|')):
        return jsonify({"status": "error", "message": "名称包含非法字符"}), 400
    src, dst = os.path.join(base, old), os.path.join(base, new)
    if not os.path.isfile(src):
        return jsonify({"status": "error", "message": "源文件不存在"}), 404
    if os.path.exists(dst):
        return jsonify({"status": "error", "message": "已存在同名文件"}), 400
    try:
        os.rename(src, dst)
        return jsonify({"status": "success", "name": new})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# -- 对话记录（outputs/chats 的 Markdown）管理 --

@app.route('/media_api/chats')
@require_auth
def chats_list():
    """列出 outputs/chats 下的对话/报告 .md（按修改时间倒序）。"""
    items = []
    try:
        names = os.listdir(CHATS_DIR)
    except OSError:
        names = []
    for fn in names:
        if not fn.lower().endswith(".md"):
            continue
        p = os.path.join(CHATS_DIR, fn)
        if not os.path.isfile(p):
            continue
        st = os.stat(p)
        items.append({
            "name": fn,
            "mtime": int(st.st_mtime),
            "time_str": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime)),
            "size": st.st_size,
        })
    items.sort(key=lambda x: x["mtime"], reverse=True)
    return jsonify({"items": items})


@app.route('/media_api/chat')
@require_auth
def chat_view():
    """读取单个对话/报告 .md 内容（返回 Markdown 原文）。"""
    name = request.args.get("name", "")
    if not name or os.path.basename(name) != name or not name.lower().endswith(".md"):
        return jsonify({"error": "参数非法"}), 400
    p = os.path.join(CHATS_DIR, name)
    if not os.path.isfile(p):
        return jsonify({"error": "文件不存在"}), 404
    with open(p, "r", encoding="utf-8") as f:
        return jsonify({"name": name, "content": f.read()})


@app.route('/media_api/chat/delete', methods=['POST'])
@require_auth
def chat_delete():
    data = request.get_json(silent=True) or {}
    name = data.get("name", "")
    if not name or os.path.basename(name) != name or not name.lower().endswith(".md"):
        return jsonify({"status": "error", "message": "参数非法"}), 400
    p = os.path.join(CHATS_DIR, name)
    if not os.path.isfile(p):
        return jsonify({"status": "error", "message": "文件不存在"}), 404
    try:
        os.remove(p)
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/media_api/chat/rename', methods=['POST'])
@require_auth
def chat_rename():
    data = request.get_json(silent=True) or {}
    old_raw, new_raw = data.get("old", ""), data.get("new", "")
    # 拒绝带路径分隔的输入（防穿越：显式报错，而非静默剥壳）
    if os.path.basename(old_raw) != old_raw or os.path.basename(new_raw) != new_raw:
        return jsonify({"status": "error", "message": "参数非法"}), 400
    old, new = old_raw, new_raw
    if not old.lower().endswith(".md"):
        old += ".md"
    if not new.lower().endswith(".md"):
        new += ".md"
    if not old or not new or old == new:
        return jsonify({"status": "error", "message": "名称未变化"}), 400
    if any(c in new for c in ('/', '\\', ':', '*', '?', '"', '<', '>', '|')):
        return jsonify({"status": "error", "message": "名称包含非法字符"}), 400
    src, dst = os.path.join(CHATS_DIR, old), os.path.join(CHATS_DIR, new)
    if not os.path.isfile(src):
        return jsonify({"status": "error", "message": "源文件不存在"}), 404
    if os.path.exists(dst):
        return jsonify({"status": "error", "message": "已存在同名文件"}), 400
    try:
        os.rename(src, dst)
        return jsonify({"status": "success", "name": new})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# -- 启动 --

if __name__ == '__main__':
    import signal
    import atexit

    def cleanup():
        log.info("正在清理资源...")
        video_stream.stop()
        if video_writer is not None:
            try: video_writer.release()
            except Exception: pass
        storage.close()
        log.info("资源清理完成")

    atexit.register(cleanup)
    def _signal_handler(sig, frame):
        log.info("收到信号 %s，正在退出...", sig)
        cleanup()
        sys.exit(0)
    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    _apply_llm_active()   # 启动时恢复上次启用的 LLM 方案（若存在）
    log.info("系统启动: http://127.0.0.1:%d", config.WEB_PORT)
    log.info("  MJPEG  (HTTP): http://127.0.0.1:%d/video_feed", config.WEB_PORT)
    log.info("  H.264   (WS):  ws://127.0.0.1:%d/ws_video", config.WEB_PORT)
    app.run(host=config.WEB_HOST, port=config.WEB_PORT, threaded=True)

#ffmpeg -re -stream_loop -1 -i test_video_2.mp4 -c copy -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/mystream
# ffmpeg -re -loop 1 -i optest_img.jpg -c:v libx264 -tune stillimage -pix_fmt yuv420p -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8554/mystream
