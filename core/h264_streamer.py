"""
H.264 编码器：通过 FFmpeg 子进程将 BGR 帧编码为 H.264 fMP4 格式。

方案：stdin 写入原始帧，stdout 用 read1() 非阻塞读取编码数据。
（Windows 上文件轮询不可靠，FFmpeg 不实时刷盘）
"""
import subprocess
import struct
import threading
import queue
import time
import os
import numpy as np
import cv2


class EncodedPacket:
    def __init__(self, data):
        self.data = data
        self.created_at = time.perf_counter()


class MP4BoxParser:
    """解析 ISO BMFF (fMP4) 顶层 box。"""

    def __init__(self):
        self.buf = bytearray()

    def feed(self, data: bytes):
        self.buf.extend(data)

    def pop_boxes(self):
        boxes = []
        while True:
            if len(self.buf) < 8:
                break
            size = struct.unpack('>I', self.buf[0:4])[0]
            box_type = self.buf[4:8].decode('ascii', errors='replace')

            if size == 0:
                payload = bytes(self.buf[8:])
                boxes.append((box_type, payload))
                self.buf.clear()
                break
            elif size == 1:
                if len(self.buf) < 16:
                    break
                ext_size = struct.unpack('>Q', self.buf[8:16])[0]
                if len(self.buf) < ext_size:
                    break
                boxes.append((box_type, bytes(self.buf[16:ext_size])))
                self.buf = self.buf[ext_size:]
            else:
                if len(self.buf) < size:
                    break
                boxes.append((box_type, bytes(self.buf[8:size])))
                self.buf = self.buf[size:]
        return boxes


def _pack_mp4_box(box_type: str, payload: bytes) -> bytes:
    header = struct.pack('>I', 8 + len(payload)) + box_type.encode()
    return header + payload


def _find_ffmpeg():
    candidates = ['ffmpeg']
    for c in candidates:
        try:
            subprocess.run([c, '-version'], capture_output=True, check=True, timeout=5)
            return c
        except (subprocess.SubprocessError, FileNotFoundError, OSError):
            continue
    return None


class H264Encoder:
    """
    通过 FFmpeg 子进程实时编码 H.264 fMP4 流（stdin/stdout 管道）。

    encoder: "libx264" (CPU软编) 或 "h264_nvenc" (NVIDIA硬编)
    """

    def __init__(self, width: int, height: int, fps: int = 30,
                 encoder: str = "libx264", bitrate_kbps: int | None = None):
        self.width = width
        self.height = height
        self.fps = fps
        self.encoder = encoder
        self.bitrate_kbps = bitrate_kbps

        if not _find_ffmpeg():
            raise RuntimeError("找不到 FFmpeg，请安装后重试。")

        self.process: subprocess.Popen | None = None
        self.parser = MP4BoxParser()
        self.init_segment: bytes | None = None
        self._seg_queue: queue.Queue = queue.Queue(maxsize=2)
        self._queue_lock = threading.Lock()
        self._queued_bytes = 0
        self._dropped_segments = 0
        self.running = False
        self._reader_thread: threading.Thread | None = None
        self._drain_thread: threading.Thread | None = None

    def start(self):
        """启动 FFmpeg 子进程和 stdout/stderr 读取线程。"""
        self.running = True

        if self.encoder == "h264_nvenc":
            codec_args = ['-c:v', 'h264_nvenc', '-preset', 'p1',
                          '-tune', 'll',
                          '-pix_fmt', 'yuv420p']
        elif self.encoder == "h264_videotoolbox":
            codec_args = ['-c:v', 'h264_videotoolbox', '-realtime', '1',
                          '-prio_speed', '1', '-profile:v', 'baseline',
                          '-level:v', '4.0', '-pix_fmt', 'yuv420p']
        else:
            codec_args = ['-c:v', 'libx264', '-preset', 'ultrafast',
                          '-tune', 'zerolatency',
                          '-profile:v', 'baseline', '-level:v', '3.1',
                          '-pix_fmt', 'yuv420p']

        rate_args = []
        if self.bitrate_kbps:
            rate_args = [
                '-b:v', f'{self.bitrate_kbps}k',
                '-maxrate', f'{self.bitrate_kbps}k',
                '-bufsize', f'{self.bitrate_kbps * 2}k',
            ]

        cmd = [
            'ffmpeg',
            '-f', 'rawvideo', '-vcodec', 'rawvideo',
            '-pix_fmt', 'bgr24', '-s', f'{self.width}x{self.height}',
            '-r', str(self.fps),
            '-i', '-',
            *codec_args,
            *rate_args,
            '-g', str(self.fps),
            '-f', 'mp4',
            '-movflags', 'empty_moov+default_base_moof+frag_every_frame',
            '-flush_packets', '1',
            '-fflags', 'nobuffer',
            '-an',
            '-loglevel', 'error',
            '-y',
            'pipe:1'
        ]

        self.process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        def _drain_stderr():
            stderr_fd = self.process.stderr.fileno()
            while self.running and self.process and self.process.stderr:
                try:
                    os.read(stderr_fd, 4096)
                except Exception:
                    break

        self._drain_thread = threading.Thread(target=_drain_stderr, daemon=True)
        self._drain_thread.start()

        self._reader_thread = threading.Thread(target=self._read_loop, daemon=True)
        self._reader_thread.start()

    def _build_init_segment(self, init_boxes):
        """将 ftyp, moov 等 box 装配为 init segment。"""
        seg = bytearray()
        for bt, pl in init_boxes:
            seg.extend(_pack_mp4_box(bt, pl))
        self.init_segment = bytes(seg)

    def _put_latest_segment(self, segment):
        """网络发送变慢时丢弃旧分片，保证客户端拿到最新画面。"""
        packet = EncodedPacket(segment)
        while True:
            try:
                self._seg_queue.put_nowait(packet)
                if segment is not None:
                    with self._queue_lock:
                        self._queued_bytes += len(segment)
                return
            except queue.Full:
                try:
                    dropped = self._seg_queue.get_nowait()
                    if dropped.data is not None:
                        with self._queue_lock:
                            self._queued_bytes -= len(dropped.data)
                            self._dropped_segments += 1
                except queue.Empty:
                    pass

    def _read_loop(self):
        init_boxes = []
        init_ready = False
        pending_moof = None
        raw_fd = self.process.stdout.fileno()

        while self.running:
            try:
                data = os.read(raw_fd, 65536)
            except (ValueError, OSError, AttributeError):
                break
            if not data:
                break

            self.parser.feed(data)
            for box_type, payload in self.parser.pop_boxes():
                if not init_ready:
                    init_boxes.append((box_type, payload))
                    if box_type == 'moov':
                        self._build_init_segment(init_boxes)
                        init_ready = True
                elif box_type == 'moof':
                    pending_moof = payload
                elif box_type == 'mdat' and pending_moof is not None:
                    combined = bytearray()
                    combined.extend(_pack_mp4_box('moof', pending_moof))
                    combined.extend(_pack_mp4_box('mdat', payload))
                    self._put_latest_segment(bytes(combined))
                    pending_moof = None

        # 读取流关闭前的剩余数据
        try:
            while True:
                remaining = os.read(raw_fd, 65536)
                if not remaining:
                    break
                self.parser.feed(remaining)
                for box_type, payload in self.parser.pop_boxes():
                    if not init_ready:
                        init_boxes.append((box_type, payload))
                        if box_type == 'moov':
                            self._build_init_segment(init_boxes)
                            init_ready = True
        except Exception:
            pass

        self._put_latest_segment(None)

    def encode_frame(self, frame: np.ndarray):
        """将一帧 BGR 图像写入 FFmpeg 标准输入。"""
        if not (self.process and self.running and self.process.stdin):
            return
        expected = self.width * self.height * 3
        # 帧尺寸不一致时 resize 而非跳过，避免 rawvideo 流偏移导致 H.264 解码错误
        h, w = frame.shape[:2]
        if w != self.width or h != self.height:
            frame = cv2.resize(frame, (self.width, self.height), interpolation=cv2.INTER_LINEAR)
        try:
            self.process.stdin.write(frame.tobytes())
            self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            self.running = False

    def get_segment(self, block=True, timeout=0.5):
        """获取下一个 media segment，流结束时返回 None。"""
        packet = self.get_segment_packet(block=block, timeout=timeout)
        return packet.data if packet is not None else None

    def get_segment_packet(self, block=True, timeout=0.5):
        """获取带产生时间的分片，供实时链路计算排队和媒体滞后。"""
        try:
            packet = self._seg_queue.get(block=block, timeout=timeout)
            if packet.data is not None:
                with self._queue_lock:
                    self._queued_bytes -= len(packet.data)
            return packet
        except queue.Empty:
            return None

    def queue_stats(self):
        with self._queue_lock:
            return {
                'queued_bytes': self._queued_bytes,
                'dropped_segments': self._dropped_segments,
                'queued_segments': self._seg_queue.qsize(),
            }

    def stop(self):
        """终止 FFmpeg 子进程。"""
        if self.process:
            try:
                self.process.stdin.close()
            except Exception:
                pass
            if self._reader_thread and self._reader_thread.is_alive():
                self._reader_thread.join(timeout=5)
            try:
                self.process.terminate()
                self.process.wait(timeout=3)
            except Exception:
                try:
                    self.process.kill()
                    self.process.wait(timeout=2)
                except Exception:
                    pass
        self.running = False
        if self._drain_thread and self._drain_thread.is_alive():
            self._drain_thread.join(timeout=2)
