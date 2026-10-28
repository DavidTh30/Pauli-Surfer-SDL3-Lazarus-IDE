# 02 — Developer window และชื่อของแต่ละส่วน (layers)

## 0. แท็บของ Developer window

| PHYSICS | PARAMETERS |
|---|---|
| ![](../app/screenshots/28_dev_physics.png) | ![](../app/screenshots/31_dev_parameters.png) |

| LAYERS | STATE |
|---|---|
| ![](../app/screenshots/32_dev_layers.png) | ![](../app/screenshots/33_dev_state.png) |

| แท็บ | เนื้อหา |
|---|---|
| **PHYSICS** (เปิดเป็นค่าเริ่มต้น) | **QUANTUM STATE**: orbital n l m, current model (Pauli spin up/down, sigma_z), พลังงาน −1/(2n²) Ha / eV, degeneracy, สูตรกระแส ω = m/s² − (σ/2s) ∂ln ρ/∂s · **ORBITAL GEOMETRY**: radial / angular nodes พร้อมตำแหน่ง, ⟨r⟩, r50 / r95 / r99.9, ρ_c, สัดส่วน CCW / CW, band ที่ probe อยู่ · **กราฟ** radial probability r²R² (เส้นน้ำเงิน = node, ฟ้า = probe, แดง = หลุมดำ), polar probability sin θ P² (ฟ้า = ระนาบเกม z = 0) · **CURRENT IN THE GAME PLANE**: ω ที่ probe (a.u. และ rad/s), ความเร็วกระแสเทียบความเร็วสูงสุดของ probe, ρ ที่ probe, กราฟความเร็วกระแส v = ω s ของ spin up (ส้ม) และ spin down (น้ำเงิน) ตาม s พร้อมเส้น ± ความเร็วสูงสุดของ probe · **SAMPLING \|ψ\|²**: จำนวนอนุภาค, เวลา sampling, median / p97 ของ \|ω\|, time scale |
| **PARAMETERS** | ค่าทุกตัวของเกม (record `GP` ใน `uPauliGame.pas`) เป็น **slider ปรับได้ทันทีระหว่างเล่น** พร้อมหน่วยและบอกค่า default เมื่อถูกเปลี่ยน: FLOW / PROBE (FlowScale, MaxFlowSpeed, MaxQuantumSpeed, MaxSelfSpeed, Accel, Drag), RADIAL NODES / COHERENCE (NodeProb, DrainNode, Recover), SCORING / TIMING (ComboWindow, FlipCooldown, BonusEvery, BonusLife), BLACK HOLES ของโหมดปัจจุบัน (BHRc, BHHorizon, BHDrift, BHHit, BHGrow, BHRcMax, BHMaxSink, ImmuneTime, EdgeFactor; การเปลี่ยน Rc / Rh มีผลกับหลุมดำที่อยู่บนจอทันที), LEVEL (อ่านอย่างเดียว), VIEW (zoom, HUD size) · ปุ่ม **RESET DEFAULTS** |
| **LAYERS** | ตารางชื่อทุกส่วนของจอ (ดูหัวข้อ 2) |
| **STATE** | window / layout, กล้อง + cloud, เกม, probe, หลุมดำ, quanta, performance |

ค่าใน PARAMETERS ไม่ถูกบันทึกลงไฟล์ (เริ่มโปรแกรมใหม่ = ค่า default) เมื่อได้ค่าที่ชอบแล้วให้นำไปแก้ใน `DefaultGameParams` ของ `uPauliGame.pas`


| เส้นประรอบทุก layer (F3) | Developer window (F2) |
|---|---|
| ![](../app/screenshots/27_layer_outlines.png) | ![](../app/screenshots/28_dev_window.png) |

## 1. ใช้งาน

| ปุ่ม | ผล |
|---|---|
| (เปิดโปรแกรม) | **Developer window เปิดขึ้นมาเองทันที** วางข้างหน้าต่างเกม (หน้าต่างเกมจะกว้าง = จอ − 700 − 36 px เพื่อให้วางคู่กันได้) · ปิดการเปิดอัตโนมัติด้วย `--dev=0` · ตอนรัน `--shot` / `--ui-test` จะไม่เปิดเอง เว้นแต่ใส่ `--dev=1` |
| **F2** | เปิด / ปิด **Developer window** (หน้าต่างแยก วางไว้ข้างหน้าต่างเกมถ้ามีที่ ไม่งั้นวางชิดขวาของจอ) · `Esc` ในหน้าต่างนั้นก็ปิดได้ |
| **F3** | วาด **กรอบเส้นประ** รอบทุก layer บนหน้าต่างเกม (สีตามชนิด) |
| **F4** | เปิด / ปิด **ชื่อ** ของแต่ละกรอบ |
| hover แถวในตาราง LAYERS | ไฮไลต์ layer นั้นบนหน้าต่างเกม (เส้นประบาง 1 px สีสว่าง + ระบายสีจาง ๆ) แม้ไม่ได้เปิด F3 |
| คลิกแถว | **pin** ไฮไลต์ไว้ (คลิกซ้ำ = ยกเลิก) |
| **คลิกขวาที่แถว** (แท็บ LAYERS) | popup menu: **Copy row** · **Copy name** · **Copy all layers** · Close (`Esc` ปิดเมนู) — คัดลอกลง clipboard เพื่อวางในข้อความถึง Claude ได้ตรง ๆ |
| ล้อเมาส์ในหน้าต่าง dev | เลื่อนดูข้อมูล |
| `EXPORT LAYOUT` | เขียน `exports/layout.json` และ `exports/layout.md` (ชื่อ, ชนิด, x y w h เป็น px และ % ของหน้าต่าง) |
| `PNG GAME` / `PNG DEV` | ภาพหน้าจอของหน้าต่างเกม / หน้าต่าง dev ลง `screenshots/` |

ข้อมูลในหน้าต่าง dev (อัปเดต 12 ครั้ง/วินาที):

| หมวด | รายการ |
|---|---|
| **LAYERS** | ทุกส่วนที่มีชื่อ: ชนิด, x y w h (px), x% y% w% h% ของหน้าต่าง |
| WINDOW / LAYOUT | ขนาดหน้าต่าง, ขนาด HUD, K (px ต่อหน่วย canvas), ขนาด canvas, inset, render scale + texture |
| CAMERA / CLOUD | มุมกล้อง, ระยะ (a0 และ × RView), zoom, **ระยะเลื่อนเพื่อจัดกึ่งกลาง**, กรอบของ cloud และจุดกึ่งกลางเทียบกับกึ่งกลางหน้าต่าง, view |
| GAME | โหมด, ด่าน, สถานะ, เวลา, คะแนน, combo, coherence, spin, flips |
| PROBE | ตำแหน่ง, ความเร็วตัวเอง, กระแส + ω, P(r), band, tidal, immune |
| BLACK HOLES | s, φ, Rc, Rh, จำนวนที่กิน, horizon hits / swallowed / edge x2 |
| QUANTA | s, φ, อนุภาคที่เกาะ, อายุที่เหลือ (photon) |
| PERFORMANCE | fps, เวลา render cloud (project + splat), จำนวนอนุภาค, threads, จำนวนเสียงที่เล่น |

เส้นประทุกเส้น (ทั้งตอนเปิด F3 และตอนเลือก/hover) เป็น **เส้นบาง 1 px** ขีด 4 px เว้น 4 px:

![](../app/screenshots/30_thin_outlines.png)

ตัวอย่างข้อความจาก **Copy row**:

```
hud.coherence  hud  x=14.3 y=201.7 w=140.0 h=20.3 px  (x 0.8% y 21.6% w 8.1% h 2.2%)  window 1728x934
```

**Copy all layers** ให้หัวข้อ (ขนาดหน้าต่าง) ตามด้วยบรรทัดแบบเดียวกันของทุก layer

![](../app/screenshots/34_dev_popup.png)

## 2. ชื่อ layer (ใช้เรียกแต่ละส่วนได้ตรงกัน)

| ชื่อ | ชนิด / สีกรอบ | คือ |
|---|---|---|
| `hud.orbital` | hud · ฟ้า | เส้นส้ม + "HYDROGEN / PAULI CURRENT" + ชื่อ orbital (เช่น 5s) |
| `hud.quantum_numbers` | hud | n = … l = … m = … |
| `hud.spin` | hud | SPIN UP / DOWN, sigma |
| `hud.score` | hud | SCORE, QUANTA, TIME, COMBO |
| `hud.coherence` | hud | ป้าย + แถบ coherence (กว้างไม่เกิน 140 px) |
| `hud.blackholes` | hud | ชื่อโหมดและจำนวนหลุมดำ (font เดียวกัน; ถ้าไม่พอจะขึ้นบรรทัดใหม่), แถบ TIDAL PULL (กว้างไม่เกิน 140 px) |
| `hud.probe` | hud | PROBE: r, band, ทิศ, P(r) |
| `hud.node_warning` | hud | RADIAL NODE (แสดงเฉพาะตอนอยู่ใน node) |
| `hud.bot` | hud | ป้าย BOT |
| `inset.label` | inset · ชมพู | "TRADITIONAL ORBITAL" + คำอธิบาย |
| `inset.orbital` | inset | ภาพ orbital สีตาม phase |
| `legend` | hud | DIRECTION OF CIRCULATION + 3 สี |
| `hud.zoom` | hud | บรรทัด zoom / HUD size |
| `btn.flip` `btn.pause` `btn.view` | button · ส้ม | ปุ่มในเกม |
| `btn.play` `btn.levels` `btn.help` `btn.quit` `btn.mode-…` `btn.lvl1…6` `btn.start` `btn.brief-back` `btn.resume` `btn.restart` `btn.menu` `btn.next` `btn.retry` `btn.back` | button | ปุ่มในเมนู |
| `menu.title` `menu.levels` `menu.help` `menu.briefing` `menu.paused` `menu.result` | menu · ทอง | ทุกอย่างที่วาดในหน้าเมนูนั้น |
| `cloud` | world · เขียว | กรอบของ cloud (วงรัศมี 1.15 RView ที่ฉายลงจอ) |
| `probe` | world | probe + วงรอบ |
| `quantum.N` / `photon.N` | world | quantum / Balmer photon ช่องที่ N |
| `blackhole.N` | world | หลุมดำที่ N (กรอบ = วงจับ Rc) |

ตัวอย่างตารางจริงที่ 838×935: [layout_838x935.md](layout_838x935.md)

## 3. วิธีทำงานในโค้ด (`PauliSurfer2.lpr`)

- ทุก frame เรียก `LayersReset` แล้ววาดตามปกติ
- `GrpBegin('ชื่อ', 'ชนิด')` … `GrpEnd`: ทุกอย่างที่ `TextV` / `RectV` / `BtnV` วาดระหว่างนั้นจะขยายกรอบของกลุ่ม (กลุ่มที่ว่างจะถูกทิ้ง)
- `BtnV` สร้าง layer `btn.<key>` ให้เอง ส่วนวัตถุในโลก (cloud, probe, quantum, หลุมดำ) เรียก `AddLayer` ด้วยกรอบ px โดยตรง
- `DrawLayerOutlines` วาดเส้นประด้วย `HudLbl` (font set แยก ไม่ทำให้ font ของ HUD ต้องโหลดใหม่)
- เพิ่มส่วนใหม่: ครอบโค้ดที่วาดด้วย `GrpBegin('hud.ชื่อใหม่', 'hud'); … GrpEnd;` แล้วจะเห็นในตาราง, เส้นประ และไฟล์ export ทันที

## 4. สิ่งที่แก้ใน layout ไปพร้อมกัน

| ปัญหา | แก้ |
|---|---|
| กลุ่ม legend ยื่นเข้ามา ไม่ชิดขอบขวา | legend จัดชิดขวาตามบรรทัดที่กว้างที่สุด ขอบขวาตรงกับขอบขวาของ inset (test: 1714 = 1714 ที่ 1728×934, 824 = 824 ที่ 838×935) และบรรทัด zoom ชิดขวา |
| ด้านบนของ cloud มีที่ว่าง แต่ด้านล่างชนขอบ | กล้องเอียง 62° ทำให้ด้านใกล้ (ล่าง) ใหญ่กว่า: วัดขอบของ cloud ที่ฉายลงจอจริง (72 จุดรอบวง) ปรับระยะกล้องให้พอดีพื้นที่ แล้วเลื่อนจุดกึ่งกลางภาพ (`Cam.Cy`) ให้ cloud อยู่กึ่งกลางแนวตั้ง (test: กึ่งกลาง 467 / หน้าต่าง 934) |
| font ของเมนูโหลดใหม่ทุก frame | `SetScale` จะเปิด font ใหม่ทุกครั้งที่ scale เปลี่ยน ตอนนี้ HUD, เมนู และป้ายเส้นประใช้ THud แยกกัน 3 ชุด |
