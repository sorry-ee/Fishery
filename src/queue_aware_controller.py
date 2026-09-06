"""Queue-aware H/M/L controller with fast downgrade and cautious probing."""
from src.adaptive_controller import LEVELS


class QueueAwareController:
    def __init__(self, recovery_samples=3, minimum_hold_samples=2,
                 congestion_delay_ms=500, severe_delay_ms=1500,
                 require_throughput_for_recovery=True):
        self.recovery_samples = recovery_samples
        self.minimum_hold_samples = minimum_hold_samples
        self.congestion_delay_ms = congestion_delay_ms
        self.severe_delay_ms = severe_delay_ms
        self.require_throughput_for_recovery = require_throughput_for_recovery
        self.level_index = len(LEVELS) - 1
        self.stable_samples = 0
        self.hold_samples = 0
        self.last_reason = 'initial_level'

    @property
    def level(self):
        return LEVELS[self.level_index]

    def update(self, observation):
        previous = self.level_index
        delay = max(observation.queue_delay_ms, observation.media_lag_ms)
        if delay >= self.severe_delay_ms and self.level_index > 0:
            self.level_index = 0
            self.stable_samples = self.hold_samples = 0
            self.last_reason = 'severe_queue_or_media_lag'
        elif delay >= self.congestion_delay_ms and self.level_index > 0:
            self.level_index -= 1
            self.stable_samples = self.hold_samples = 0
            self.last_reason = 'queue_or_media_lag_congestion'
        else:
            self.hold_samples += 1
            healthy = (observation.queue_delay_ms < 100 and
                       observation.media_lag_ms < 500 and
                       (not self.require_throughput_for_recovery or
                        observation.throughput_kbps >=
                        self.level.bitrate_kbps * 0.9))
            self.stable_samples = self.stable_samples + 1 if healthy else 0
            if (self.level_index < len(LEVELS) - 1 and
                    self.stable_samples >= self.recovery_samples and
                    self.hold_samples >= self.minimum_hold_samples):
                self.level_index += 1
                self.stable_samples = self.hold_samples = 0
                self.last_reason = 'cautious_probe_after_queue_cleared'
            else:
                self.last_reason = ('healthy_hold' if healthy
                                    else 'hold_until_queue_and_lag_recover')
        return self.level, self.level_index != previous
