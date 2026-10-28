# 04 — โปรแกรมแก้ไข 3 ตัว: เสียง · ด่าน · Effect Graphics

เกมอ่านเสียง ด่าน และ effect จากไฟล์ใน `app\data\` และ **โหลดใหม่ขณะเล่น** (hot reload) เมื่อไฟล์เปลี่ยน
โปรแกรมแก้ไขทั้ง 3 ตัวเขียนไฟล์เหล่านี้ ถ้าเกมเปิดอยู่ กด SAVE แล้วจะเห็นผลในเกมภายใน 0.5 วินาที

| โปรแกรม | ไฟล์ข้อมูล | แก้อะไร |
|---|---|---|
| `app\PSSoundEditor.exe` | `data\pauli_sounds.ini` | เสียง 22 ตัวของเกม (สูตร preset หรือออกแบบเองทุก layer) |
| `app\PSLevelEditor.exe` | `data\pauli_levels.ini` | 30 ด่าน: orbital, เป้า, เวลา, หลุมดำ, กฎ |
| `app\PSFxEditor.exe` | `data\pauli_fx.ini` | effect ภาพ 61 ค่า ใน 6 กลุ่ม |

ถ้าไม่มีไฟล์ หรือไม่มี key ไหน เกมใช้ค่าที่อยู่ในโค้ด (ค่าเดิมของเกม) ไฟล์ที่ผิด เช่นด่านที่เล่นไม่ได้ หรือค่าเกินช่วง จะถูกแทนด้วยค่าเดิม หรือถูกบีบให้อยู่ในช่วง

## ทุกโปรแกรมใช้โครงเดียวกัน (`editors/common/uEdKit.pas`)

- canvas ออกแบบ 1440 × 900 แล้วย่อขยายตามหน้าต่าง: ตำแหน่งเดิมทุกขนาดหน้าต่าง (ทดสอบที่ 1440×900 และ 1000×640)
- **DEVELOPER window เปิดเองตอนเริ่ม** อยู่ข้างหน้าต่างหลัก (`F2` เปิด/ปิด, `--dev=0` ไม่เปิด)
  - แท็บ **LAYERS**: ทุกส่วนมีชื่อ (`header`, `panel.preview`, `btn.save`, `slider.lens_strength`, `row.flip`, `field.title`, `stepper.bh` …) พร้อมชนิดและ x y w h
    - เอาเมาส์ชี้แถว = ส่วนนั้นถูกไฮไลต์ในหน้าต่างหลัก (เส้นประ 1 px + ชื่อ)
    - คลิกขวา = Copy row / Copy name / Copy all layers
  - แท็บ **STATE**: ไฟล์, จำนวนที่แก้แล้วยังไม่ได้ save, ค่าของรายการที่เลือก, เสียง / preview / ผลบอท
- `F3` เส้นประรอบทุก layer, `F4` แสดงชื่อ layer, `F12` PNG ไปที่ `app\exports\`
- ปุ่มแสดงปุ่มลัดไว้บนตัวปุ่ม (`Ctrl+S`, `SPACE`, `T`, `P` …)
- ส่วนหัวบอกไฟล์, จำนวนที่แก้แล้วยังไม่ save (สีทอง), เวลาที่ save ล่าสุด รายการที่แก้มีเครื่องหมาย `*`
- `--data=DIR` ใช้โฟลเดอร์ข้อมูลอื่น (ใช้ตอนทดสอบ) · ปุ่มเปิดเกมจะส่ง `--data` ต่อให้เกมด้วย

![](../app/screenshots/48_level_editor_dev_window.png)

---

## 1. SOUND EDITOR — `PSSoundEditor.exe`

![](../app/screenshots/40_sound_editor.png)

| ส่วน | ใช้ทำอะไร |
|---|---|
| **GAME SOUNDS** (ซ้าย) | เสียง 22 ตัว พร้อมบอกว่าเล่นตอนไหน · `LOOP` = เล่นวนในเกม · `CUSTOM` = ออกแบบเอง · `*` = แก้แล้ว · `↑` `↓` เลือก |
| **RECIPE** | CATEGORY 15 หมวด × PRESET 5 แบบ ของ SFX Studio, SEED (`R` = สุ่ม), LENGTH, PITCH (สเกล log, 1.0 อยู่กลาง), VOLUME ในมิกซ์ของเกม |
| ฟัง | `PLAY` (`SPACE`), `STOP` (`Esc`), `LOOP`, `PLAY SAVED` (`B`) = เวอร์ชันในไฟล์ไว้เทียบ A/B, `UNDO CHANGES` |
| **DESIGN** | `EDIT LAYERS` (`E`) คัดลอกเสียงที่ preset สร้างเป็น design ของตัวเอง แล้วแก้ทุกอย่างของ uSfxEngine ได้: Duration, Fade, Echo, Reverb และ **6 layer** (source, filter, partials, frequency + glide, vibrato, FM, cutoff sweep, Q, attack / hold / decay, gain, pan, drive, delay) · `BACK TO PRESET` กลับไปใช้สูตร |
| **GAME MIX** | `COMBO RUN` (`C`) เล่นเสียงเก็บ quantum 5 ระดับต่อกันเหมือน combo, `AMBIENT` / `NODE` / `HOLE` เปิด loop 3 ตัวของเกมพร้อมกันที่ระดับเสียงจริง |
| **WAVEFORM** | รูปคลื่น + playhead, ความยาว, frames, peak, rms, เวลา render (แดง = clip) |

![](../app/screenshots/41_sound_editor_custom_design.png)

เสียงที่แก้จะ render ใหม่ไม่เกิน 8 ครั้งต่อวินาทีระหว่างลาก slider · `PLAY GAME` (`G`) เปิดเกม

---

## 2. LEVEL EDITOR — `PSLevelEditor.exe`

![](../app/screenshots/42_level_editor.png)

| ส่วน | ใช้ทำอะไร |
|---|---|
| **LEVELS** | แท็บโลก 1–5, ด่านละแถว (orbital, ชื่อ, เป้า, เวลา, หลุมดำ, กฎ) · `PgUp` `PgDn` · `COPY` / `PASTE` / `<- SWAP` / `SWAP ->` สลับลำดับด่าน |
| **orbital** | n l m (stepper) ตรวจทันที: l < n, \|m\| ≤ l, **l − \|m\| ต้องเป็นเลขคู่** (ไม่อย่างนั้นไม่มีความหนาแน่นในระนาบเกม z = 0) ถ้าผิดจะเป็นสีแดงและ save ไม่ได้ |
| ข้อความ | TITLE, TIP (ข้อความ briefing), BADGE (ป้ายหน้ากฎ เช่น TIME ATTACK) คลิกที่ช่องแล้วพิมพ์ได้ (`Enter` ตกลง, `Esc` ยกเลิก) |
| เป้า | QUANTA TO COLLECT, ON SCREEN, BLACK HOLES (บอกจำนวนจริงของแต่ละโหมด), TIME |
| **RULES** | CURRENT x (CALM / TURBO), PHOTON INTERVAL x (PHOTON RUSH), NODE DRAIN x (NODE STORM), SPIN LOCKED + START UP / DOWN · บรรทัด RULE LINE แสดงข้อความกฎตามที่เกมจะแสดง |
| **PREVIEW** | ใช้ logic ของเกมจริง (TPauliGame) และตัว render cloud จริง: บอทเล่นด่านที่กำลังแก้แบบสด ๆ, เลือกโหมด CLASSIC / BLACK HOLE / SINGULARITY, แสดง node (วงประสีน้ำเงิน), หลุมดำ, quanta, probe · `SPACE` หยุด/เล่น |
| **BOT TEST** (`T`) | บอทเล่น 5 seed × 3 โหมดแบบ headless (เหมือน `game_test`) โดยไม่ต้อง save: ชนะกี่ครั้ง, คะแนนเฉลี่ย, เวลาเฉลี่ย + คำตัดสิน (TOO HARD / OK / EASY) |
| เล่น | `PLAY IN GAME` (`P`) save แล้วเปิดเกมที่ด่านนั้น โหมดที่เลือก · `BOT IN GAME` (`V`) เปิดเกมแบบ `--preview` (บอทเล่นด่านนั้นวนไป) · `RESET` คืนค่าด่านเดิมของเกม |

![](../app/screenshots/43_level_editor_not_playable.png)

---

## 3. EFFECT EDITOR — `PSFxEditor.exe`

![](../app/screenshots/44_effect_editor.png)

| กลุ่ม | ค่า |
|---|---|
| **COLOURS** (13) | สี cloud (CCW / CW / slow), สี quanta (CCW / CW / slow), probe + trail, Balmer photon, danger, accretion disc ใน/นอก, photon ring, horizon flash · แต่ละสีมี R G B + ช่อง `#RRGGBB` |
| **CLOUD** (5) | ความสว่าง, ขนาดอนุภาค, ความหนาจุด (px), gain ของมุมมอง slice, nucleus |
| **BLACK HOLE** (17) | lens radius, Einstein radius (ความแรงของการหักเหแสง), shadow, disc (จำนวน / ใน / กว้าง / ความเร็ว / ขนาดจุด / ความสว่าง), photon ring, halo, capture ring (จำนวนจุด / ความทึบ / การหมุน), meal ring |
| **QUANTA** (9) | glow, core, pulse (ความลึก / ความเร็ว), ring, photon star, photon glow / pulse |
| **PROBE** (8) | glow, body, ring, ความยาวลูกศร spin, trail (ความยาว 0–160 เฟรม / ความทึบ / ความกว้าง) |
| **FLASHES** (9) | สีแดงใน node, flash ตอนพลิก spin, flash ที่ horizon (ความแรง / ความเร็วจาง), pop-up (วง / ความกว้าง / ข้อความลอย / อายุ) |

- แต่ละแถวมี slider ตามช่วงที่อนุญาต, ขีดเล็กบอกค่าเดิม (สีทอง = ต่างจากค่าเดิม), `RESET` · `RESET GROUP` · `DEFAULTS`
- **LIVE SCENE** วาดด้วยสูตรเดียวกับเกม: cloud 6p จากตัว render จริง (ค่า CLOUD และสี cloud มีผล), หลุมดำพร้อม lensing ของ cloud, disc, photon ring, capture ring, quanta 3 สี, Balmer photon, probe + trail + ลูกศร spin
  - ปุ่ม `FLIP` `HORIZON` `POP-UP` `MEAL` (`1`–`4`) และ `NODE` ไว้ทดสอบ effect ที่เกิดแค่ชั่วครู่
- **LIVE** = save ให้เองหลังแก้ 0.3 วินาที ถ้าเกมเปิดอยู่จะเห็นผลทันที
- **PREVIEW IN GAME** (`G`) เปิด LIVE แล้วเปิดเกม `--preview` ด่าน 17 โหมด SINGULARITY ให้บอทเล่นข้าง ๆ editor: เกมคือตัวอ้างอิงจริงของทุก effect

![](../app/screenshots/45_effect_editor_colours.png)

ทดสอบ hot reload: เกมกำลังเล่น → เขียน `pauli_fx.ini` ใหม่ (quanta เขียว/ชมพู, trail ยาว 160 สีขาว, lens 4.5, disc 220 จุด) → เกมเปลี่ยนทันทีโดยไม่ต้องเริ่มใหม่

![](../app/screenshots/46_game_hot_reload_fx.png)

---

## 4. เกมกับไฟล์ข้อมูล

| | |
|---|---|
| โหลด | ตอนเริ่มเกม จาก `app\data\` (หรือ `--data=DIR`) |
| hot reload | ตรวจเวลาของไฟล์ทุก 0.5 วินาที · **effects** มีผลทันที (สี cloud ใช้ `TOrbital.Recolour` ไม่ต้องสุ่มอนุภาคใหม่) · **sounds** สร้างเสียงใหม่ทั้งหมด · **levels** ใช้กับด่านถัดไปที่เริ่ม (ด่านที่กำลังเล่นอยู่เล่นต่อ หน้า title / briefing โหลดใหม่) · มีข้อความ `data reloaded: …` ที่ด้านล่าง |
| developer window ของเกม | แท็บ STATE → `DATA FILES`: ไฟล์ที่ใช้อยู่ หรือ built-in และเวลาที่โหลดใหม่ล่าสุด |
| `--preview` | บอทเล่นด่าน `--level` ในโหมด `--mode` วนไปเรื่อย ๆ ไม่แตะ progress ไม่เปิด developer window (ใช้โดย editor) |

ไฟล์เป็น INI อ่านง่าย แก้ด้วยมือได้:

```ini
[level7]
orbital=2p
n=2
l=1
m=-1
title=MIRROR
badge=
target=10
time=80
black_holes=1
current_x=1
spin_locked=0
start_spin=1

[sound.flip]
when=spin flip (SPACE)
preset=scifi:teleport
seed=4
length=0.55
pitch=1
volume=0.5
custom=0

[BLACK HOLE]
lens_strength=2.4
disc_count=60
```

## 5. ทดสอบ

| การทดสอบ | ผล |
|---|---|
| `PSSoundEditor --ui-test` | **22 checks, 0 failure**: 22 แถว, เลือกเสียง, เปลี่ยน preset → modified, pitch log กลาง = 1.000, PLAY, EDIT LAYERS, layer 2 ความถี่ log กลาง 89.4 Hz, render ใหม่, SAVE → โหลดกลับได้ custom design เดิม, BACK TO PRESET, COMBO RUN, loop AMBIENT, STOP เงียบหมด, หน้าต่าง 1000×640 |
| `PSLevelEditor --ui-test` | **21 checks, 0 failure**: preview บอทเล่น, โลก 2, ด่าน 7, 2p m 0 ถูกปฏิเสธ, 3p m −1 ผ่าน, หลุมดำ 1 → 2 (preview เริ่มใหม่ 2 หลุม), SPIN LOCKED → กฎ, ช่อง TITLE รับ focus / ปล่อย, BOT TEST 15 รอบเสร็จ, SAVE → โหลดกลับ, RESET, preview SINGULARITY, หน้าต่างเล็ก, **PLAY IN GAME เปิดเกมจริงแล้วเกมบันทึกภาพได้** |
| `PSFxEditor --ui-test` | **17 checks, 0 failure**: 17 slider ของ BLACK HOLE, scene มีหลุมดำ / probe / photon, slider กลาง = 3.0, RESET = 2.4, ค่า int คงเป็น int, HORIZON flash, 13 แถวสี, G slider + ช่อง hex ตามกัน, SAVE → โหลดกลับ, DEFAULTS, NODE, หน้าต่างเล็ก |
| `game_test` | **137 checks, 0 failure** รวม: 30 ด่าน save → load เหมือนเดิมทุกด่าน (รวมข้อความกฎ), แก้ไฟล์ด่าน 3 → ตารางตาม, ด่านผิด → ใช้ค่าเดิม, CheckLevel, fx round trip (สี / float / int), ค่าเกินช่วงถูกบีบ, ค่าเริ่มต้นอยู่ในช่วงทั้ง 61 ค่า, sounds round trip พร้อม custom design, เสียง 22 ตัว render ได้, **สี cloud ค่าเริ่มต้น = สีเดิมของ HydrogenFlow ทุกอนุภาค** |
| เกม `--ui-test` | 0 failure (หลังเปลี่ยนมาอ่านไฟล์ข้อมูล) |
| hot reload | เกมกำลังเล่น → เขียน `pauli_fx.ini` → เปลี่ยนในเกม (ภาพ 46) |

รันทดสอบ (ใช้โฟลเดอร์ข้อมูลแยก ไม่แตะ `app\data`):

```bash
cd "F:/Claude/Lazarus/UI08/Pauli Surfer V2 SDL3/app" && ./PSLevelEditor.exe --ui-test=tests/level_editor_test.txt --ui-shots=tests/ed_shots --size=1440x900 --data=tests/ed_data
```

## 6. Build

```bash
C:/lazarus/lazbuild.exe "F:/Claude/Lazarus/UI08/Pauli Surfer V2 SDL3/editors/sound/SoundEditor.lpi"
```
```bash
C:/lazarus/lazbuild.exe "F:/Claude/Lazarus/UI08/Pauli Surfer V2 SDL3/editors/level/LevelEditor.lpi"
```
```bash
C:/lazarus/lazbuild.exe "F:/Claude/Lazarus/UI08/Pauli Surfer V2 SDL3/editors/fx/FxEditor.lpi"
```

exe ทั้ง 3 ตัวออกไปที่ `app\` ข้างเกม (ใช้ DLL และโฟลเดอร์ `data\` ร่วมกัน)

```
editors/
├─ common/uEdKit.pas        หน้าต่าง, widget, layer + เส้นประ, developer window, ui-test, เปิดเกม
├─ sound/SoundEditor.lpr    -> app/PSSoundEditor.exe
├─ level/LevelEditor.lpr    -> app/PSLevelEditor.exe
└─ fx/FxEditor.lpr          -> app/PSFxEditor.exe
app/uPauliData.pas          ข้อมูลเสียง + effect (ใช้ร่วมกันระหว่างเกมกับ editor)
app/uPauliGame.pas          + LevelTable, LoadLevels / SaveLevels, CheckLevel, MakeRuleText
```
