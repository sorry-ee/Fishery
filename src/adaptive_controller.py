"""Explainable three-level bandwidth controller for the paper experiments."""
from dataclasses import dataclass


@dataclass(frozen=True)
class VideoLevel:
    name: str
    width: int
    height: int
    fps: int
    bitrate_kbps: int


LEVELS = (
    VideoLevel('L', 640, 360, 10, 800),
    VideoLevel('M', 1280, 720, 15, 2000),
    VideoLevel('H', 1920, 1080, 25, 4000),
)


class AdaptiveController:
    """Drop immediately; rise one level after several stable observations."""

    def __init__(self, safety_factor=0.8, recovery_samples=3, minimum_hold_samples=2):
        if (not 0 < safety_factor <= 1 or recovery_samples < 1 or
                minimum_hold_samples < 0):
            raise ValueError('Invalid controller parameters')
        self.safety_factor = safety_factor
        self.recovery_samples = recovery_samples
        self.minimum_hold_samples = minimum_hold_samples
        self.level_index = len(LEVELS) - 1
        self.recovery_count = 0
        self.hold_count = 0
        self.last_reason = 'initial_level'

    @property
    def level(self):
        return LEVELS[self.level_index]

    def update(self, bandwidth_kbps):
        if bandwidth_kbps <= 0:
            raise ValueError('Bandwidth must be positive')
        budget = bandwidth_kbps * self.safety_factor
        sustainable = 0
        for index, level in enumerate(LEVELS):
            if level.bitrate_kbps <= budget:
                sustainable = index
        previous = self.level_index
        if sustainable < self.level_index:
            self.level_index = sustainable
            self.recovery_count = 0
            self.hold_count = 0
            self.last_reason = 'fast_downgrade_bandwidth_insufficient'
        elif sustainable > self.level_index:
            self.recovery_count += 1
            self.hold_count += 1
            if (self.recovery_count >= self.recovery_samples and
                    self.hold_count >= self.minimum_hold_samples):
                self.level_index += 1
                self.recovery_count = 0
                self.hold_count = 0
                self.last_reason = 'slow_upgrade_after_stable_recovery'
            else:
                self.last_reason = 'hold_waiting_for_stable_recovery'
        else:
            self.recovery_count = 0
            self.hold_count += 1
            self.last_reason = 'hold_current_level'
        return self.level, LEVELS[previous].name != self.level.name
