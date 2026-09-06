# 鐜閰嶇疆涓庤繍琛屾寚鍗?
## 鐜瑕佹眰

- Windows锛堝紑鍙戠幆澧冿級
- Python 3.11锛坴env锛岄潪 conda锛?- NVIDIA GPU + CUDA锛堟湰椤圭洰鐢?RTX 3070 Laptop 8GB锛孭yTorch 2.5.1+cu121锛?- FFmpeg锛堢敤浜?H.264 缂栫爜涓庤棰戞帹娴侊級
- mediamtx锛堟湰鍦?RTSP 鏈嶅姟鍣級

## 涓€銆佺幆澧冨畨瑁?
### 1. 鍒涘缓铏氭嫙鐜

```powershell
cd d:\Fishery_Project
python -m venv .venv
.venv\Scripts\Activate.ps1
```

### 2. 瀹夎渚濊禆

```powershell
pip install ultralytics opencv-python flask flask-sock openai scikit-learn numpy
# 鍙€夛細WWE-UIE 瀹屾暣璁粌鍔熻兘
pip install -r WWE-UIE/requirements.txt
```

> PyTorch 闇€浠庡畼缃戞寜 CUDA 鐗堟湰瀹夎锛歨ttps://pytorch.org

### 3. 瀹夎 FFmpeg / mediamtx

- **FFmpeg**锛堜簩閫変竴锛屾帹鑽愯嚜甯︾増锛夛細
  - 鑷甫鐗堬細鎶?`ffmpeg.exe` 鏀惧埌 `tools\ffmpeg\bin\`銆俙Z_script` 鑴氭湰浼氳嚜鍔ㄤ紭鍏堜娇鐢ㄣ€佹壘涓嶅埌鍐嶅洖閫€绯荤粺 PATH锛堟枃浠朵笉鍏?git锛夈€?  - 绯荤粺鐗堬細涓嬭浇瑙ｅ帇锛屾妸 `bin` 鍔犲叆绯荤粺 PATH銆?- **mediamtx**锛氫粠 https://github.com/bluenviron/mediamtx/releases 涓嬭浇瑙ｅ帇鍒?`tools/mediamtx/`锛坄mediamtx.exe` 涓嶅叆 git锛夈€?
### 4. 妯″瀷鏂囦欢

鏀句簬 `models/`锛堟潈閲嶅潎涓嶅叆 git锛夛細
- 蹇呴渶锛歚fish_detect_m.pt`
- 鍙€夛細`fish_detect_seam.pt`銆乣fish_seg_yolo26.pt`銆乣fish_seg_yolo11n.pt`銆乣sam2.1_t.pt` + `sam2_hiera_t.yaml` 绛?- WWE-UIE 鏉冮噸鑷姩浠?`WWE-UIE/output/Fishery_WWE_UIEB/UIEB/` 鍙栨渶鏂?`best_model.pth`

### 5. 閰嶇疆瀵嗛挜

椤圭洰鏍圭洰褰?`.env`锛?
```
DEEPSEEK_API_KEY=浣犵殑API瀵嗛挜
```

涓嶉厤涔熻兘杩愯锛屼粎 LLM 璇婃柇/瀵硅瘽涓嶅彲鐢ㄣ€?
### 6. 鐜鑷锛堝彲閫夛紝鎺ㄨ崘锛?
瑁呭ソ渚濊禆鍚庡彲涓€閿嚜妫€鐜鏄惁灏辩华锛?*鍙**锛氫笉鑱旂綉銆佷笉鏀圭幆澧冦€佷笉瑙﹀彂 AutoUpdate锛夛細

```powershell
powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1
# 鍙€夊弬鏁帮細
#   -SkipGpu    璺宠繃 GPU 鎺㈡祴锛堟棤鏄惧崱鏈猴級
#   -Deep       棰濆鐪熷疄鍔犺浇妯″瀷鎺ㄧ悊涓€娆★紙杈冩參锛?#   -CheckOnnx  鍙鎺㈡祴 onnxruntime-gpu 鐗堟湰骞舵彁绀?CUDA 鍖归厤锛坧ip show锛屼笉瑙﹀彂 AutoUpdate锛?#   -NoColor    绾枃鏈緭鍑猴紙渚夸簬閲嶅畾鍚戝埌鏂囦欢锛?```

閫€鍑虹爜锛?*0 = 鍙惎鍔紱1 = 瀛樺湪蹇呮煡澶辫触**锛堟寜涓婃柟 `[FAIL]` 椤归€愪竴淇锛夈€傝剼鏈璁¤鏄庤 `docs/env_check_plan.md`銆?
## 浜屻€佽繍琛?
### 鏂瑰紡涓€锛氫竴閿惎鍔紙鎺ㄨ崘锛?
鍚姩鑴氭湰缁熶竴鍦?`Z_script/run/`锛屽湪椤圭洰鏍规寜闇€閫夌敤锛?*榛樿甯︿紶鎰熷櫒妯℃嫙鏁版嵁**锛宍-NoSensor` 鍘绘帀锛夛細

```powershell
cd d:\Fishery_Project
.\Z_script\run\start_all.ps1                  # 鈶?鏈湴瑙嗛鎺ㄦ祦锛堥粯璁ゅ甫妯℃嫙鏁版嵁锛?.\Z_script\run\start_pc_camera.ps1            # 鈶?鐢佃剳鍐呯疆鎽勫儚澶?.\Z_script\run\start_usb_camera.ps1           # 鈶?澶栨帴 USB 鎽勫儚澶达紙鐪熷疄鍦烘櫙锛?.\Z_script\run\start_all.ps1 -NoSensor        # 鈶?涓嶅甫妯℃嫙鏁版嵁
```

鑷姩瀹屾垚锛歮ediamtx 鈫?鎺ㄦ祦 鈫?浼犳劅鍣ㄦā鎷熷櫒锛堥粯璁わ級鈫?Flask 鈫?绾?15 绉掑悗鑷姩鎵撳紑娴忚鍣ㄣ€?鎽勫儚澶磋剼鏈惎鍔ㄥ墠浼氳嚜鍔ㄦ娴嬭澶囧悕锛氶粯璁ゅ悕鎵句笉鍒版椂鑷姩鏋氫妇锛堝敮涓€鑷姩閫夌敤 / 澶氫釜浜や簰閫夋嫨锛夛紱涔熷彲鐢?`-DeviceName` 鏄惧紡鎸囧畾锛堟壘涓嶅埌浼氭姤閿欏苟鍒楀嚭鍙敤璁惧锛夈€?
### 鏂瑰紡浜岋細鎵嬪姩 3 缁堢

瑙?`AGENTS.md`銆屽惎鍔ㄦ祦绋?路 鏂瑰紡浜屻€嶃€?
## 涓夈€佽闂?
| 鍦板潃 | 璇存槑 |
|------|------|
| http://127.0.0.1:5000 | Web 鎺у埗鍙?|
| http://127.0.0.1:5000/video_feed | MJPEG 瑙嗛娴?|
| ws://127.0.0.1:5000/ws_video | H.264 WebSocket 瑙嗛娴?|

## 鍥涖€佸仠姝?
- 涓€閿惎鍔細鐩存帴 `Ctrl+C`锛堣嚜鍔ㄥ叧闂?ffmpeg / mediamtx锛?- 鎵嬪姩 3 缁堢锛氭寜椤哄簭鍋?Flask 鈫?ffmpeg 鈫?mediamtx

## 浜斻€侀獙璇?
```powershell
python -c "import torch; print('CUDA:', torch.cuda.is_available())"
python -c "import cv2; print('OpenCV:', cv2.__version__)"
python -c "from ultralytics import YOLO; print('Ultralytics: OK')"
python -c "import flask; print('Flask:', flask.__version__)"
```
