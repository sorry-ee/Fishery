"""Application-level bandwidth control for the local H.264 experiment path."""
import math
import threading
import time


class NetworkSimulator:
    MODES = {
        "normal": (0, "正常 / 不限速"),
        "light": (3000, "轻度受限"),
        "medium": (1200, "中度受限"),
        "severe": (800, "重度受限"),
    }
    AUTO_PHASES = (
        ("auto_normal", 6000, "自动演示：正常", 10),
        ("auto_medium", 1200, "自动演示：中度受限", 12),
        ("auto_recovery", 6000, "自动演示：恢复", 20),
    )

    def __init__(self, system_state):
        self.state = system_state
        self.lock = threading.Lock()
        self.generation = 0
        initial = int(system_state.get("adaptive_test_bandwidth_kbps", 0))
        mode = next((name for name, item in self.MODES.items()
                     if item[0] == initial), "custom")
        label = (self.MODES[mode][1] if mode in self.MODES
                 else f"启动限速 {initial} kbps")
        system_state.update({
            "network_simulator_mode": mode,
            "network_simulator_label": label,
            "network_simulator_bandwidth_kbps": initial,
            "network_simulator_changed_at": time.time(),
            "network_simulator_event_id": 0,
            "network_simulator_events": [],
            "network_demo_active": False,
            "network_demo_phase": "",
            "network_demo_remaining_s": 0,
        })

    def _apply_locked(self, mode, bandwidth_kbps, label, source,
                      demo_active=False, demo_phase="", remaining_s=0):
        event_id = self.state["network_simulator_event_id"] + 1
        timestamp = time.time()
        self.state.update({
            "adaptive_test_bandwidth_kbps": int(bandwidth_kbps),
            "network_simulator_mode": mode,
            "network_simulator_label": label,
            "network_simulator_bandwidth_kbps": int(bandwidth_kbps),
            "network_simulator_changed_at": timestamp,
            "network_simulator_event_id": event_id,
            "network_demo_active": bool(demo_active),
            "network_demo_phase": demo_phase,
            "network_demo_remaining_s": int(math.ceil(remaining_s)),
        })
        event = {
            "event_id": event_id,
            "timestamp": timestamp,
            "mode": mode,
            "label": label,
            "target_bandwidth_kbps": int(bandwidth_kbps),
            "source": source,
            "demo_phase": demo_phase,
        }
        events = self.state["network_simulator_events"]
        events.append(event)
        del events[:-200]

    def set_mode(self, mode, source="manual"):
        if mode not in self.MODES:
            raise ValueError("未知网络模拟模式")
        bandwidth, label = self.MODES[mode]
        with self.lock:
            self.generation += 1
            self._apply_locked(mode, bandwidth, label, source)
            return self._status_locked()

    def start_demo(self, phase_seconds=None):
        phases = [list(item) for item in self.AUTO_PHASES]
        if phase_seconds is not None:
            if phase_seconds <= 0:
                raise ValueError("自动演示阶段时长必须大于0")
            for phase in phases:
                phase[3] = phase_seconds
        with self.lock:
            self.generation += 1
            generation = self.generation
            mode, bandwidth, label, duration = phases[0]
            self._apply_locked(mode, bandwidth, label, "auto",
                               True, mode, duration)
            status = self._status_locked()
        threading.Thread(
            target=self._run_demo, args=(generation, phases), daemon=True
        ).start()
        return status

    def _run_demo(self, generation, phases):
        for index, phase in enumerate(phases):
            mode, bandwidth, label, duration = phase
            if index:
                with self.lock:
                    if generation != self.generation:
                        return
                    self._apply_locked(mode, bandwidth, label, "auto",
                                       True, mode, duration)
            deadline = time.monotonic() + duration
            while True:
                remaining = deadline - time.monotonic()
                with self.lock:
                    if generation != self.generation:
                        return
                    self.state["network_demo_remaining_s"] = max(
                        0, int(math.ceil(remaining)))
                if remaining <= 0:
                    break
                time.sleep(min(0.25, remaining))
        with self.lock:
            if generation != self.generation:
                return
            bandwidth, label = self.MODES["normal"]
            self._apply_locked("normal", bandwidth, label, "auto_complete")

    def _status_locked(self):
        return {
            "network_simulator_mode": self.state["network_simulator_mode"],
            "network_simulator_label": self.state["network_simulator_label"],
            "network_simulator_bandwidth_kbps": self.state[
                "network_simulator_bandwidth_kbps"],
            "network_simulator_changed_at": self.state[
                "network_simulator_changed_at"],
            "network_demo_active": self.state["network_demo_active"],
            "network_demo_phase": self.state["network_demo_phase"],
            "network_demo_remaining_s": self.state["network_demo_remaining_s"],
        }

    def status(self):
        with self.lock:
            return self._status_locked()

    def latest_event_id(self):
        with self.lock:
            return self.state["network_simulator_event_id"]

    def events_since(self, event_id):
        with self.lock:
            return [dict(event) for event in self.state["network_simulator_events"]
                    if event["event_id"] > event_id]
