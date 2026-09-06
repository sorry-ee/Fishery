# 鏅烘収娓斾笟姘翠笅鍗忓悓鎺у埗绯荤粺

瀹炴椂姘翠笅瑙嗛鐩戞祴涓庡垎鏋愬钩鍙帮細浠?RTSP 鎽勫儚澶存垨鏈湴瑙嗛鎷夋祦锛岀粡姘翠笅鍥惧儚澧炲己锛圵WE-UIE锛夈€侀奔缇ゆ娴?鍒嗗壊锛圷OLO + SAM2锛夈€佺洰鏍囪窡韪紝缁撳悎浼犳劅鍣ㄦ暟鎹紙姘存俯 / pH / 婧惰В姘э級涓?DeepSeek 澶фā鍨?+ 鑷缓 RAG 鐭ヨ瘑搴擄紝閫氳繃 Web 鎺у埗鍙板疄鏃跺睍绀轰笌鏅鸿兘璇婃柇銆?
## 鍔熻兘鐗规€?
- 鍙岄€氶亾瀹炴椂瑙嗛锛歁JPEG锛圚TTP锛? H.264锛圵ebSocket锛?- AI 妫€娴?/ 鍒嗗壊 / 璺熻釜锛歒OLO 澶氭ā鍨嬭繍琛屾椂鐑垏鎹?+ SAM2 瀹炰緥鍒嗗壊 + 璺ㄥ抚 ID 璺熻釜
- 姘翠笅鍥惧儚澧炲己锛歐WE-UIE 鑷姩杩樺師娓呮櫚鐢婚潰
- 浼犳劅鍣ㄧ洃娴嬶細姘存俯 / pH / 婧惰В姘т笂鎶ャ€佹洸绾夸笌鍘嗗彶
- 鏅鸿兘鍛婅锛氳鍒欓槇鍊艰瘖鏂?+ 浜嬩欢鏃ュ織
- AI 椤鹃棶锛欴eepSeek 澶фā鍨?+ 槌楅病鍏绘畺鐭ヨ瘑搴擄紙RAG锛夊疄鏃堕棶绛斾笌璇婃柇
- 涓€閿惎鍔細`Z_script\run\start_all.ps1`锛堟湰鍦拌棰戞帹娴侊級/ `Z_script\run\start_pc_camera.ps1`銆乣Z_script\run\start_usb_camera.ps1`锛堢湡瀹炴憚鍍忓ご锛夆€斺€旈粯璁ら兘甯︿紶鎰熷櫒妯℃嫙鏁版嵁锛宍-NoSensor` 鍘绘帀

## 蹇€熷紑濮?
鍓嶇疆瑕佹眰锛歅ython 3.11锛坴env锛夈€丯VIDIA GPU锛圕UDA锛夈€丗Fmpeg銆乵ediamtx銆佹ā鍨嬫潈閲嶃€乣.env` 涓殑 DeepSeek Key锛堣瑙?`docs/BUILD_RUN.md`锛夈€?
> 涓嶇‘瀹氱幆澧冩槸鍚﹀氨缁紵鍏堜竴閿嚜妫€锛堝彧璇伙紝涓嶈仈缃戯級锛?> `powershell -ExecutionPolicy Bypass -File Z_script\check_env.ps1`锛岄€€鍑虹爜 0 鍚庡啀鍚姩銆?
```powershell
cd d:\Fishery_Project
.\Z_script\run\start_all.ps1            # 鏈湴瑙嗛鎺ㄦ祦锛堥粯璁ゅ甫妯℃嫙鏁版嵁锛?.\Z_script\run\start_usb_camera.ps1     # 澶栨帴 USB 鎽勫儚澶达紙鐪熷疄鍦烘櫙锛?.\Z_script\run\start_all.ps1 -NoSensor  # 涓嶅甫妯℃嫙鏁版嵁
```

鑴氭湰鑷姩鍚姩 mediamtx 鈫?鎺ㄦ祦 鈫?鍚姩 Flask锛岀害 15 绉掑悗鑷姩鎵撳紑娴忚鍣ㄣ€?
- 鎺у埗鍙帮細http://127.0.0.1:5000
- 鍋滄锛氭寜 `Ctrl+C`锛堣嚜鍔ㄥ叧闂?mediamtx / ffmpeg锛?
## 鎶€鏈爤

Flask / Flask-Sock 锝?OpenCV + FFmpeg 锝?PyTorch + Ultralytics YOLO + SAM2 锝?WWE-UIE 锝?SQLite 锝?DeepSeek API

## 鏂囨。

| 鏂囨。 | 璇存槑 |
|------|------|
| `docs/ROADMAP.md` | 寮€鍙戣矾绾垮浘 |
| `docs/BUILD_RUN.md` | 鐜閰嶇疆涓庤繍琛屾寚鍗?|
| `docs/troubleshooting.md` | 宸茬煡闂涓庤俯鍧?|
| `docs/structure.md` | 璇︾粏椤圭洰缁撴瀯 |
| `docs/deep-dive/` | 娣卞叆璁茶В锛堝惈鍘熷紑鍙戣€呮寚鍗?`developer_guide.md`锛?|

## 鐩綍缁撴瀯

```
app.py             Flask 涓诲叆鍙ｄ笌璺敱
config.py          鍏ㄥ眬閰嶇疆锛堟ā鍨?/ 闃堝€?/ LLM / 璁よ瘉锛?core/              鏍稿績妯″潡锛堣棰戦噰闆嗐€佸抚澶勭悊銆丄I 妫€娴嬨€佸寮恒€丩LM銆佸瓨鍌級
knowledge/         槌楅病鐭ヨ瘑鍥捐氨 + RAG 寮曟搸
templates/         Web 鎺у埗鍙帮紙SPA锛?docs/              椤圭洰鏂囨。
scripts/           杈呭姪鑴氭湰
models/            妯″瀷鏉冮噸锛堜笉鍏?git锛?```

## 璇存槑

- 妯″瀷鏉冮噸锛坄models/*.pt` 绛夛級涓?`.env`锛圖eepSeek Key锛変笉鍏?git锛岄渶鑷鍑嗗銆?- 璇︾粏鐨勬ā鍧楄皟鐢ㄩ摼涓庡紑鍙戞寚鍗楄 `docs/deep-dive/developer_guide.md`銆?
