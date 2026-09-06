"""Link observations derived from sender/receiver measurements, not shaper settings."""
from dataclasses import dataclass


@dataclass(frozen=True)
class LinkObservation:
    throughput_kbps: float
    queue_kbits: float
    queue_delay_ms: float
    media_lag_ms: float


class LinkMonitor:
    def observe(self, delivered_kbits, interval_s, queue_kbits, media_lag_ms):
        if interval_s <= 0 or delivered_kbits < 0 or queue_kbits < 0 or media_lag_ms < 0:
            raise ValueError('Link measurements must be non-negative and interval positive')
        throughput = delivered_kbits / interval_s
        queue_delay = queue_kbits / max(throughput, 1e-9) * 1000
        return LinkObservation(throughput, queue_kbits, queue_delay, media_lag_ms)
