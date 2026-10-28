# PAULI SURFER 2 — หลุมดำในกระแสความน่าจะเป็น (SDL3 + Lazarus)

> เวอร์ชัน 2 ของ [Pauli Surfer](../Pauli%20Surfer%20Game%20SDL3/README.md): **เพิ่มความยากด้วยหลุมดำ**
> หลุมดำจะ **ดูด** probe เข้าไป (เข้าในวงประแดงแล้วหนีไม่ได้) ถ้าโดน **event horizon** จะเสีย coherence และถูก **ดีดออก** ไปอีกฝั่งของ orbital หลุมดำ **ลอยไปตามกระแส** (พลิก spin แล้วหลุมดำก็หันทิศตาม) **กิน quanta** และในโหมด SINGULARITY จะ **โตขึ้น** ทุกครั้งที่กิน
> เวอร์ชัน 1 ยังอยู่ครบในโฟลเดอร์เดิม (ไม่ได้แก้ไข) และเล่นแบบเดิมได้ในโหมด **CLASSIC**

| Title: เลือกโหมด | 6p · SINGULARITY · หลุมดำ 5 หลุม | Hawking ejection |
|---|---|---|
| ![](app/screenshots/01_title.png) | ![](app/screenshots/12_play_6p_singularity.png) | ![](app/screenshots/10_hawking_ejection.png) |

| เลือกด่าน (แยกตามโหมด) | Briefing | SPAGHETTIFIED |
|---|---|---|
| ![](app/screenshots/08_levels_singularity.png) | ![](app/screenshots/09_briefing_singularity.png) | ![](app/screenshots/11_spaghettified.png) |

---

## โปรแกรมแก้ไข: เสียง · ด่าน · Effect Graphics

| SOUND EDITOR | LEVEL EDITOR | EFFECT EDITOR |
|---|---|---|
| ![](app/screenshots/40_sound_editor.png) | ![](app/screenshots/42_level_editor.png) | ![](app/screenshots/44_effect_editor.png) |

| โปรแกรม | ไฟล์ | สิ่งที่แก้ได้ |
|---|---|---|
| `app\PSSoundEditor.exe` | `data\pauli_sounds.ini` | เสียง 22 ตัว: preset + seed / ความยาว / pitch / volume หรือ **ออกแบบเองทุก layer**, ฟังเทียบ A/B, COMBO RUN, loop ของเกม |
| `app\PSLevelEditor.exe` | `data\pauli_levels.ini` | 30 ด่าน: n l m (ตรวจว่าเล่นได้), ชื่อ / tip, เป้า, เวลา, หลุมดำ, กฎ · **preview ที่บอทเล่นด่านที่กำลังแก้** · **BOT TEST** 5 seed × 3 โหมด · เปิดเกมที่ด่านนั้น |
| `app\PSFxEditor.exe` | `data\pauli_fx.ini` | effect 61 ค่า: สี cloud / quanta, cloud, หลุมดำ (lensing, disc, rings), quanta, probe + trail, flash · **LIVE SCENE** · LIVE save → เกมที่เปิดอยู่เปลี่ยนทันที |

- เกม **โหลดไฟล์ใหม่ขณะเล่น** (ทุก 0.5 วินาที) ไม่ต้องปิดเกม · ไม่มีไฟล์ = ค่าเดิมของเกม
- ทุกโปรแกรม: developer window เปิดเองข้าง ๆ (LAYERS ที่มีชื่อ + STATE, คลิกขวา copy), `F3` เส้นประ 1 px, ปุ่มลัดอยู่บนปุ่ม
- คู่มือ: [docs/04_editors.md](docs/04_editors.md)

## 0. 30 ด่าน ใน 5 โลก

| เลือกด่าน: แท็บ WORLD 1–5 | ด่าน 30: 9g PAULI STORM | ด่าน 14: LOCKED DOWN (4p) |
|---|---|---|
| ![](app/screenshots/38_levels_world4.png) | ![](app/screenshots/39_level_30.png) | ![](app/screenshots/39_level_14.png) |

| โลก | ด่าน | แนวคิด |
|---|---|---|
| 1 GROUND RULES | 1–6 | ด่านเดิม 2p → 6p |
| 2 MIRROR CURRENTS | 7–12 | m ติดลบ (กระแสกลับทาง), TURBO / CALM, PHOTON RUSH |
| 3 SPIN LOCK | 13–18 | พลิก spin ไม่ได้ (ล็อก UP / DOWN), NODE STORM |
| 4 RYDBERG | 19–24 | 7s ถึง 9p: node 5–7 วง, TIME ATTACK, MARATHON 26 quanta |
| 5 SINGULARITY TRIALS | 25–30 | กฎผสมหลายอย่าง + หลุมดำมากขึ้น, ปิดท้าย 9g |

- หน้าเลือกด่านมีแท็บ WORLD 1–5 (`←` `→` เปลี่ยนโลก, `1`–`6` เลือกด่านในโลกนั้น) แสดงกฎของแต่ละด่าน, จำนวนหลุมดำ, เป้า / เวลา, ดาว
- briefing และ HUD บอก `LEVEL n / 30`, โลก และกฎของด่าน · developer window (แท็บ PARAMETERS) แสดงค่ากฎทั้งหมด
- ปลดล็อกทีละด่านต่อเนื่องข้ามโลก แยกตามโหมด · ตารางด่านครบพร้อมผลบอททุกด่าน: [docs/03_levels.md](docs/03_levels.md)

## 1. สิ่งที่เพิ่มในเวอร์ชัน 2

### 3 โหมด

| โหมด | หลุมดำต่อด่าน (1 → 6) | Rc (รัศมีจับ) | ลอยตามกระแส | โดน horizon | พิเศษ |
|---|---|---|---|---|---|
| **CLASSIC** | 0 0 0 0 0 0 | — | — | — | เหมือนเวอร์ชัน 1 ทุกอย่าง |
| **BLACK HOLE** (ค่าเริ่มต้น) | ตามด่าน 1–4 (ดู docs/03) | 0.075 RView | 35 % ของกระแส | −35 % coherence | — |
| **SINGULARITY** | ตามด่าน 2–6 | 0.09 RView | 60 % ของกระแส | −50 % coherence | กิน quantum 1 ตัว → Rc ×1.08 (สูงสุด 0.14 RView) |

ความคืบหน้า (ด่านที่ปลดล็อก, คะแนนสูงสุด, ดาว) **แยกตามโหมด** และเก็บใน `progress_v2.ini` (ไม่ทับไฟล์ของเวอร์ชัน 1)

### กลไกของหลุมดำ

| กลไก | รายละเอียด | บนจอ |
|---|---|---|
| **แรงดูด** | ความเร็วดูดแบบ sink 2D: `v = vmax · Rc/d · exp(−((d−Rc)/3Rc)²)` ที่ **Rc** เท่ากับความเร็วสูงสุดของ probe (0.34 RView/s) **ข้างในวงนี้หนีไม่ได้** ที่ 3 Rc ยังหนีได้ ที่ 4 Rc แทบไม่มีแรง | **วงจุดสีแดง** = จุดที่ไม่มีทางกลับ · แถบ **TIDAL PULL** ใต้ coherence (แดง "NO ESCAPE") · เสียงหึ่งต่ำดังขึ้นตามแรงดูด |
| **Event horizon** (Rh = 0.45 Rc) | coherence −35 % / −50 % แล้วถูก **Hawking ejection**: ดีดไปที่แถบนอกสุด ฝั่งตรงข้ามกับหลุม และ **อมตะ 2 s** (ไม่โดนแรงดูด) ถ้า coherence หมด = **SPAGHETTIFIED** (แพ้) | จอวาบสีส้ม, ข้อความ "HAWKING EJECTION", วงทองรอบ probe ระหว่างอมตะ |
| **ลอยตามกระแส** | หลุมดำหมุนตามกระแส Pauli ที่รัศมีของมัน **พลิก spin แล้วหลุมดำก็เปลี่ยนทิศด้วย** (ด่าน 5s กลับทิศพอดี มี test) | — |
| **กิน quanta** | quantum ที่ลอยเข้าใกล้ (1.3 Rh) จะหายไป แล้วมีตัวใหม่เกิดที่อื่น | วงส้มขยายออกจากหลุม + เสียง |
| **EDGE x2** | เก็บ quantum ในระยะ 2.5 Rc จากหลุมดำ ได้คะแนน ×2 (เสี่ยงแลกคะแนน) | "EDGE x2" |
| การวาง | ห่างจุดเริ่ม ≥ 0.45 RView, อยู่ในแถบที่หนาแน่น, ห่างกันเอง ≥ 5 Rc · quanta ไม่เกิดใกล้หลุม (< 2 Rc) | — |

### ภาพของหลุมดำ

- **Gravitational lensing**: นำ texture ของ cloud มา map ใหม่บน mesh แบบรัศมีรอบหลุมดำ (14 วง × 48 ส่วน) จุดบนจอที่รัศมี r แสดงภาพของ cloud จากรัศมี `r − E²/r` (เลนส์มวลจุด, E = Einstein radius = 2.4 Rh) ค่อย ๆ กลับเป็นภาพปกติที่ขอบเลนส์ (3.6 Rc) จึงไม่มีรอยต่อ แถบสีของ orbital จึงโค้งรอบหลุมดำ
- เงาดำ + event horizon, **photon ring** สีทอง, **accretion disc** 60 จุดหมุนแบบ Kepler ในระนาบเดียวกับ orbital (ด้านหนึ่งสว่างกว่าอีกด้านแบบ Doppler), วงจุดแดงที่ Rc

### เสียงใหม่ (จาก SFX Studio)

| เหตุการณ์ | preset |
|---|---|
| หลุมดำกิน quantum | `scifi:laser` pitch 0.35 |
| โดน horizon | `breakdown:power_down` |
| EDGE x2 | `scifi:power_up` pitch 1.4 |
| เริ่มถูกดูด (tidal > 0.5) | `alarm:nuclear_alert` |
| เสียงหึ่งต่อเนื่องตามแรงดูด | loop `atom:nucleus` pitch 0.6 |

### ขนาดหน้าจอ: layout แบบกว้าง (WIDE)

| เล่นในหน้าต่างกว้าง 1638×1096 | Title | ผลการเล่น |
|---|---|---|
| ![](app/screenshots/13_wide_4f.png) | ![](app/screenshots/14_wide_title.png) | ![](app/screenshots/15_wide_result.png) |

- หน้าต่างที่ **กว้างกว่าสูง** จะใช้ layout แบบกว้างอัตโนมัติ HUD แยกเป็น **2 คอลัมน์ข้าง**: ซ้ายเป็น orbital, คะแนน, coherence, หลุมดำ, probe ส่วนขวาเป็น inset, legend และปุ่ม ตัวอักษรใหญ่ขึ้นราว 2 เท่าจากเดิม (canvas สูง 900 หน่วยแทน 1600)
- **cloud** ปรับขนาดให้เต็มที่ว่างระหว่างคอลัมน์ (หรือเต็มความสูง 88 %) แบบตั้ง portrait ก็ใหญ่ขึ้นราว 12 %
- เมนู (title, เลือกด่าน, briefing, pause, ผลการเล่น, วิธีเล่น) ในหน้าต่างกว้างจะวาดใหญ่ขึ้นราว 1.5 เท่า
- หน้าต่างเริ่มต้น = **90 % ของจอ** (แบบกว้าง) ถ้าอยากได้แบบตั้งเหมือนเวอร์ชัน 1 ให้ย่อหน้าต่างให้สูงกว่ากว้าง หรือใช้ `--size=607x1080`

### HUD กลืนไปกับเกม + ปุ่มลัดบนทุกปุ่ม

| เล่น (แบบกว้าง) | Pause |
|---|---|
| ![](app/screenshots/20_wide_play_keys.png) | ![](app/screenshots/21_wide_paused_keys.png) |

- ไม่มี panel พื้นทึบแล้ว: ตัวอักษรและแถบสถานะวางบนฉากของเกมโดยตรง ปุ่มเป็นกรอบบางโปร่งแสง (hover = กรอบส้ม, ปุ่มหลัก = สีส้มอ่อน) หน้าเมนูไม่มีกล่องแล้ว ใช้การหรี่ฉากหลังแทน
- **ทุกปุ่มแสดงปุ่มลัด** เป็น key chip สีทองข้างชื่อปุ่ม เช่น `FLIP SPIN [SPACE]` `PAUSE [P]` `VIEW [V]`

| หน้าจอ | ปุ่มบนจอ → ปุ่มลัด |
|---|---|
| เล่น | FLIP SPIN `SPACE` · PAUSE `P` (หรือ `Esc`) · VIEW `V` · ซูม `+` `-` / ล้อเมาส์ · ขนาด HUD `[` `]` · ปิดเสียง `M` |
| Title | PLAY `ENTER` · LEVELS `L` · HOW TO PLAY `H` · QUIT `Q` · โหมด CLASSIC / BLACK HOLE / SINGULARITY `1` `2` `3` |
| เลือกด่าน | ด่าน `1`–`6` · BACK `Esc` |
| Briefing | START `ENTER` · BACK `Esc` |
| Pause | RESUME `P` (หรือ `Esc`) · RESTART `R` · MENU `Q` |
| ผลการเล่น | NEXT LEVEL `ENTER` (แพ้ = RETRY) · RETRY `R` · MENU `Q` / `Esc` |
| วิธีเล่น | BACK `Esc` |

ค่าซูม (0.70–1.50) และขนาด HUD (0.3–1.5, layout แบบกว้าง) จะถูกจำไว้

### Layout เดียวทุกขนาดหน้าต่าง

| 838×935 | 600×1000 | 1728×934 |
|---|---|---|
| ![](app/screenshots/23_layout_838x935.png) | ![](app/screenshots/24_layout_600x1000.png) | ![](app/screenshots/25_layout_1728x934.png) |

- ระหว่างเล่นใช้ **layout แบบยึดมุม** อย่างเดียวทุกขนาดหน้าต่าง (ไม่สลับไปใช้ layout แนวตั้งของเวอร์ชัน 1 อีกแล้ว): ข้อมูล orbital และคะแนนอยู่ **มุมซ้ายบน**, TRADITIONAL ORBITAL อยู่ **มุมขวาบน**, legend อยู่ **ใต้ inset**, ปุ่มอยู่ **มุมขวาล่าง**
- ขนาดของกล่องและแถบ (coherence, tidal pull) คิดจาก **ความสูงของหน้าต่าง** เมื่อย่อหรือขยายหน้าต่าง ตำแหน่งและสัดส่วนจะเหมือนเดิม แถบไม่ยืดตามความกว้างแล้ว
- cloud ใช้พื้นที่ที่เหลือ: ในหน้าต่างกว้างจะอยู่ระหว่างกล่องสองข้าง ในหน้าต่างแคบ cloud ใช้ความกว้าง 90 % และลอดใต้กล่องที่มุม (ไม่มี panel บังแล้ว)
- เมนูต่าง ๆ จะวาดตรงกลางและปรับตามขนาดหน้าต่างเหมือนกันทุกขนาด
- ใช้เมาส์บังคับ probe ได้ทั่วจอ ยกเว้นบนปุ่ม

### SUPER BOT DEMO — ดูบอทระดับยากสุดเล่น

| บอทกำลังเล่น (เห็นปุ่มที่กดและตำแหน่งเมาส์) | ผลของแต่ละด่าน (ไปต่อเอง) |
|---|---|
| ![](app/screenshots/36_demo_play.png) | ![](app/screenshots/37_demo_result.png) |

- กดปุ่ม **SUPER BOT DEMO** (หรือ `B`) ที่หน้า title: บอทเล่นโหมด **SINGULARITY** (ยากที่สุด) ตั้งแต่ด่าน 1 ถึง 30 **ต่อเนื่องจนจบ**: briefing → เล่น → ผล → ด่านถัดไป เป็นไปเอง ถ้าแพ้จะเล่นด่านเดิมใหม่ (นับ attempt) จบแล้วแสดงตารางสรุปคะแนน, จำนวนครั้ง และเวลาของทุกด่าน (REPLAY `ENTER` · MENU `Q`)
- บอท **กดปุ่มจริงแบบผู้เล่น** ผ่านทางเดียวกับคน: กดเมาส์ซ้ายค้างที่จุดบนจอ (probe วิ่งเข้าหาเคอร์เซอร์) หรือกด **W A S D** เมื่อทิศที่ต้องการตรงกับทิศของปุ่ม (8 ทิศ) และกด **SPACE** เพื่อพลิก spin, `ENTER` เริ่ม/ไปด่านถัดไป, `R` เล่นใหม่
- บนจอเห็น: **คีย์บอร์ด** (W A S D SPACE ENTER R สว่างเมื่อกด), **เมาส์** (ปุ่ม L / R สว่าง, `LMB HOLD`, พิกัด x y px, วิธีบังคับ MOUSE / KEYBOARD), **เคอร์เซอร์** ที่ตำแหน่งที่บอทกด + วงคลื่นตอนกด + เส้นจุดไปยัง probe, **BOT INPUT LOG** 6 รายการล่าสุด และแถบ SUPER-HARD BOT · LEVEL · attempt · total ด้านบน
- `Esc` (หยุดชั่วคราว) / `Q` ออกจาก demo ได้ทุกเมื่อ · ผลของ demo **ไม่บันทึก** ลง progress ของผู้เล่น และโหมดเดิมของผู้เล่นจะกลับมา
- command line: `--demo` (เริ่ม demo ทันที), `--demo-exit` (ปิดโปรแกรมเมื่อครบทุกด่าน), `--demo-log=FILE` (บันทึกผลทีละด่าน)
- ผลการรันเต็มจริง (`--demo-exit --demo-log`, [docs/demo_full_run_log.txt](docs/demo_full_run_log.txt)): ผ่านครบ 6 ด่านใน 5 นาที 23 วินาที — ด่าน 1–5 ผ่านในครั้งแรก, ด่าน 6 (6p, หลุมดำ 5 หลุม) แพ้ครั้งแรกเพราะหมดเวลา แล้วผ่านในครั้งที่ 2 · คะแนนรวม 33,472 (รันตอนที่ยังมี 6 ด่าน)
- ผลการรันเต็ม **30 ด่าน** ([docs/demo_full_run_30_levels.txt](docs/demo_full_run_30_levels.txt)): ผ่านครบ 30 ด่านใน 31 นาที (เวลาเล่นจริง 27.5 นาที) คะแนนรวม 150,908 — 23 ด่านผ่านในครั้งแรก, 6p / NODE STORM / STORM RUSH / FAST F / 9g ใช้ 2 ครั้ง, LOCK 6f ใช้ 5 ครั้ง

### Developer window (F2) + เส้นประบอกตำแหน่ง layer (F3)

| เส้นประรอบทุกส่วน (F3) | Developer: PHYSICS | Developer: PARAMETERS |
|---|---|---|
| ![](app/screenshots/27_layer_outlines.png) | ![](app/screenshots/28_dev_physics.png) | ![](app/screenshots/31_dev_parameters.png) |

- แท็บ LAYERS: **คลิกขวาที่แถว** = เมนู Copy row / Copy name / Copy all layers (ใช้ส่งตำแหน่งและขนาดที่ถูกต้องให้ Claude)
- `hud.coherence` และ `hud.blackholes` กว้าง **ไม่เกิน 140 px** · ชื่อโหมดกับจำนวนหลุมดำใช้ font ขนาดเดียวกัน
- Developer window มี 4 แท็บ: **PHYSICS** (สถานะควอนตัม, เรขาคณิตของ orbital, กราฟ r²R² / sin θ P² / ความเร็วกระแสในระนาบเกม, ข้อมูล sampling), **PARAMETERS** (ค่าทุกตัวของเกมเป็น slider ปรับสด + RESET DEFAULTS), **LAYERS**, **STATE**

- **F2** เปิดหน้าต่างแยกสำหรับนักพัฒนา: ตาราง **LAYERS** แสดงทุกส่วนของจอพร้อม **ชื่อ** (เช่น `hud.coherence`, `legend`, `inset.orbital`, `btn.flip`, `blackhole.2`), ตำแหน่ง/ขนาดเป็น px และ % ของหน้าต่าง รวมถึง layout, กล้อง, สถานะเกม, probe, หลุมดำ, quanta และประสิทธิภาพ · ชี้เมาส์ที่แถว = ไฮไลต์ส่วนนั้นในเกม, คลิก = pin
- **Developer window เปิดขึ้นมาพร้อมเกมทันที** (หน้าต่างเกมย่อความกว้างให้วางคู่กันได้) ไม่ต้องการให้ใช้ `--dev=0`
- **F3** วาดกรอบ **เส้นประบาง 1 px** รอบทุก layer บนหน้าต่างเกม (ฟ้า = HUD, ส้ม = ปุ่ม, ชมพู = inset, เขียว = วัตถุในเกม, ทอง = เมนู) · **F4** เปิด/ปิดชื่อ
- `EXPORT LAYOUT` → `app/exports/layout.json` + `layout.md`
- รายชื่อ layer ทั้งหมดและวิธีเพิ่มส่วนใหม่: [docs/02_developer_window.md](docs/02_developer_window.md)
- แก้ไปพร้อมกัน: **legend ชิดขอบขวา** ตรงกับ inset และ **cloud อยู่กึ่งกลางแนวตั้ง** (วัดขอบที่ฉายลงจอจริงแล้วเลื่อนภาพ ไม่มีที่ว่างด้านบนอีก)

### ปรับขนาดล่าสุด

![](app/screenshots/26_hud_plus15_inset_minus10.png)

- ข้อมูล HUD ทั้งหมด (ชื่อ orbital, spin, คะแนน, coherence, จำนวนหลุมดำ, probe, legend, บรรทัด zoom และปุ่ม) **ใหญ่ขึ้น 15 %**: ค่าเริ่มต้นของขนาด HUD เปลี่ยนจาก 0.5 เป็น **0.575**
- inset TRADITIONAL ORBITAL **เล็กลง 10 %**: จาก 175 เหลือ **157.5** หน่วย (ประมาณ 163 px ที่ความสูงหน้าต่าง 934 px) และยังขยาย/ย่อตาม `[` `]` ด้วย
- ค่านี้บันทึกด้วย key ใหม่ `hud_size` ใน `progress_v2.ini` (ค่าเก่า `hud_compact` = 0.5 จะไม่ทับค่าเริ่มต้นใหม่)

### HUD แบบกะทัดรัด + atom ใหญ่ขึ้น

![](app/screenshots/22_compact_hud_5s.png)

- ใน layout แบบกว้าง ค่าเริ่มต้นของ HUD คือ **0.5** ทำให้ข้อมูลด้านซ้าย (ชื่อ orbital, n l m, spin, คะแนน, quanta, เวลา, coherence, tidal pull), legend และปุ่มด้านขวา **เล็กลง 50 %** ส่วน inset TRADITIONAL ORBITAL **เล็กลง 30 %** (70 % ของเดิม)
- ปุ่ม FLIP SPIN / PAUSE / VIEW ยึดมุมขวาล่างของหน้าต่าง legend อยู่ใต้ inset
- **cloud ของ hydrogen ใหญ่ขึ้น** ไปใช้พื้นที่ที่ว่าง: สูงได้ถึง 96 % ของหน้าต่าง (เดิม 88 %) และซูมได้ถึง 1.5 เท่า (เดิม 1.25)
- ถ้าตัวอักษรเล็กเกินไปบนจอของคุณ ให้กด `]` เพื่อขยาย HUD ทีละ 0.1 (`[` เพื่อย่อ) ระบบจะจำค่านี้ไว้ (`hud_compact` ใน `progress_v2.ini`) ส่วนค่า `hud` เก่า (1.0) จะไม่ถูกใช้แล้ว

ค่าซูมและขนาด HUD จะถูกจำไว้ใน `progress_v2.ini` (`[view]`)

## 2. Build & Run

```bash
C:/lazarus/lazbuild.exe "F:/Claude/Lazarus/UI08/Pauli Surfer V2 SDL3/app/PauliSurfer2.lpi"
```
```bash
"F:/Claude/Lazarus/UI08/Pauli Surfer V2 SDL3/app/PauliSurfer2.exe"
```

ใช้ unit ร่วมเหมือนเวอร์ชัน 1 (`uOrbital`, `uRaster`, `uHud`, `uUI` จาก HydrogenFlow · `uSfxEngine`, `uSfxGen` จาก SFX Studio) · `uOrbital` ได้ `Recolour` เพิ่ม (สี cloud จาก `FlowCCW / FlowCW / FlowSlow`) ค่าเริ่มต้นให้สีเหมือนเดิมทุกอนุภาค (มี test) HydrogenFlow จึงเหมือนเดิม

โปรแกรมแก้ไข: `editors/sound/SoundEditor.lpi`, `editors/level/LevelEditor.lpi`, `editors/fx/FxEditor.lpi` (exe ออกไปที่ `app\`)

| Option ใหม่ | ผล |
|---|---|
| `--mode=classic\|blackhole\|singularity` | เลือกโหมด (ค่าเดิมจะถูกจำไว้ใน `progress_v2.ini`) |
| `--progress=FILE` | ค่าปกติ `progress_v2.ini` |
| `--data=DIR` | โฟลเดอร์ไฟล์ข้อมูล (ค่าปกติ `app\data\`) |
| `--preview` | บอทเล่นด่าน `--level` วนไปเรื่อย ๆ ไม่แตะ progress (editor ใช้) |

option อื่น (`--level` `--bot` `--points` `--scale` `--size` `--mute` `--shot` `--ui-test` …) ใช้ได้เหมือนเวอร์ชัน 1

## 3. ผลการทดสอบ

| การทดสอบ | ผล |
|---|---|
| `app/tests/game_test` (headless, **137 checks**) | **0 failure** — ไฟล์ข้อมูล (ด่าน / เสียง / effect save → load, ค่าผิดใช้ค่าเดิม, สี cloud เริ่มต้น = เดิม), 30 ด่านครบ, ทุก orbital มีความหนาแน่นในระนาบ z = 0, กฎ SPIN LOCK / TURBO ×1.60 / MIRROR / PHOTON RUSH 4.2 s / NODE STORM 0.54 /s ทำงานจริง, บอทชนะได้ทุกด่านในทุกโหมด (5 seed: CLASSIC 145 / BLACK HOLE 132 / SINGULARITY 110 จาก 150) · 19 checks ของเวอร์ชัน 1 (ในโหมด CLASSIC) ยังผ่าน + หลุมดำ: จำนวนต่อด่านถูกทุกโหมด, ห่างจุดเริ่ม ≥ 0.45 RView, แรงดูดที่ Rc = 0.340 RView/s, ที่ 4 Rc = 0.031, **ข้างใน Rc ออกแรงเต็มที่ก็ยังตกลงไป**, ที่ 3 Rc หนีออกได้, horizon −35 % + ejection + อมตะ, coherence 0.2 + horizon = SPAGHETTIFIED, quantum ถูกกิน + singularity โต ×1.08, EDGE x2 = 200 คะแนน, ลอยตามกระแส 0.122 rad/s และกลับทิศ −0.122 หลังพลิก spin, replay deterministic |
| บอทเล่นทุกด่าน × 3 seed ต่อโหมด | CLASSIC **18/18** (เฉลี่ย 23.8 s) · BLACK HOLE **16/18** (25.7 s) · SINGULARITY **14/18** (29.5 s) → ยากขึ้นตามโหมดจริง |
| `--ui-test` (คลิกจริง + กดปุ่มลัด **75 checks**, รันที่ 838×935 และ 1728×934) | **0 failure** ทั้งสองขนาด รวมปุ่มอยู่มุมขวาล่าง, developer window (F2) มี 23 layer ที่มีชื่อครบ, legend ชิดขวาตรงกับ inset, cloud อยู่กึ่งกลางแนวตั้ง, ปุ่ม OUTLINES / EXPORT LAYOUT / PNG DEV, แท็บ PHYSICS วาดกราฟ 3 รูป, slider FlowScale 0.50 → 0.80 มีผลกับเกมทันที, RESET DEFAULTS, hud.coherence / hud.blackholes = 140.0 px, คลิกขวา → popup → Copy row ลง clipboard, SUPER BOT DEMO: เริ่มเอง, บอทกดเมาส์ / W A S D จริง, ผลไปด่านถัดไปเอง, Esc หยุดและคืนโหมดเดิม, ไม่แตะ progress รวม layout, ซูม +/−, ขนาด HUD [ / ], ปุ่มลัด H Esc 2 L 1 Enter P R Q — title (attract: 6p + หลุมดำ 3 หลุม), เสียง 22 ตัว, ด่าน 1 มีหลุมดำ 1 หลุม, บอทชนะ, progress แยกตามโหมด, เลือก SINGULARITY → ด่าน 1 มี 2 หลุม, วาง probe บน horizon → −50 % + ejection + อมตะ + เสียง, ครั้งที่สอง → SPAGHETTIFIED, กลับโหมด BLACK HOLE และการทดสอบทั้งหมดของเวอร์ชัน 1 |
| editor `--ui-test` | SOUND **22** · LEVEL **21** (รวมเปิดเกมจริง) · EFFECT **17** checks — 0 failure ทั้งหมด ([docs/04_editors.md](docs/04_editors.md)) |
| hot reload | เกมกำลังเล่น → แก้ `pauli_fx.ini` → เปลี่ยนในเกมทันที ([ภาพ](app/screenshots/46_game_hot_reload_fx.png)) |
| ประสิทธิภาพ | 58 fps (300k อนุภาค, 607×1080) |

ผลบอทรายด่าน (ชนะ / 3 seed):

| ด่าน | CLASSIC | BLACK HOLE | SINGULARITY |
|---|---|---|---|
| 1 · 2p | 3 | 3 | 3 |
| 2 · 3p | 3 | 3 | 3 |
| 3 · 3d | 3 | 3 | 3 |
| 4 · 4f | 3 | 3 | 3 |
| 5 · 5s | 3 | 2 | **1** |
| 6 · 6p | 3 | 2 | **1** |

> บอทตอบสนองเร็วกว่าคน ความยากที่คนรู้สึกจริงจึงจะสูงกว่าตารางนี้ (โดยเฉพาะ 5s / 6p ใน SINGULARITY) ยังไม่มีใครลองเล่นด้วยมือ ถ้ายากเกินให้ลด `BHCountTab` / `BHRc` หรือ `BHDrift` ใน `uPauliGame.pas`

## 4. เอกสาร

| ไฟล์ | เนื้อหา |
|---|---|
| [docs/01_black_holes.md](docs/01_black_holes.md) | ออกแบบกลไกหลุมดำ, สูตร, lensing, ค่าปรับ, balance |
| [docs/02_developer_window.md](docs/02_developer_window.md) | developer window, ชื่อ layer ทุกส่วน, เส้นประ, export layout, วิธีเพิ่มส่วนใหม่ |
| [docs/03_levels.md](docs/03_levels.md) | 30 ด่าน, กฎ, ผลบอท |
| [docs/04_editors.md](docs/04_editors.md) | โปรแกรมแก้ไขเสียง / ด่าน / effect, ไฟล์ข้อมูล, hot reload, การทดสอบ |
| เวอร์ชัน 1: [../Pauli Surfer Game SDL3/docs](../Pauli%20Surfer%20Game%20SDL3/docs) | ฟิสิกส์ของกระแส Pauli, กลไกพื้นฐาน, คู่มือนักพัฒนา (ใช้กับ V2 ได้ทั้งหมด) |

## 5. โครงสร้างไฟล์

```
Pauli Surfer V2 SDL3/
├─ README.md
├─ docs/01_black_holes.md  02_developer_window.md  03_levels.md  04_editors.md
├─ editors/
│  ├─ common/uEdKit.pas        shared editor frame: widgets, named layers, developer window, ui-test
│  ├─ sound/  level/  fx/      SoundEditor / LevelEditor / FxEditor (.lpr .lpi)
└─ app/
   ├─ PauliSurfer2.lpr / .lpi   SDL3: + mode select, black hole render (lensing), HUD, sounds, ui-test, hot reload
   ├─ uPauliGame.pas            game logic + TBlackHole, modes, ... + LevelTable, Load/SaveLevels, CheckLevel
   ├─ uPauliData.pas            sounds + effects data (game and editors)
   ├─ PSSoundEditor.exe  PSLevelEditor.exe  PSFxEditor.exe
   ├─ data/                     pauli_sounds.ini  pauli_levels.ini  pauli_fx.ini (written by the editors)
   ├─ screenshots/              01-48 *.png
   └─ tests/  game_test.lpr/.lpi  game_test_log.txt  ui_test_log.txt  *_editor_test.txt
```
