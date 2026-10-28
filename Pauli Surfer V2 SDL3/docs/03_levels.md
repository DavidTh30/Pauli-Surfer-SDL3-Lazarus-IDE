# 03 — 30 ด่าน ใน 5 โลก

![](../app/screenshots/38_levels_world4.png)

| โลก | แนวคิด |
|---|---|
| 1 GROUND RULES | ด่านเดิมของเวอร์ชัน 2.0 (2p → 6p) สอนกระแส, node, spin |
| 2 MIRROR CURRENTS | **m ติดลบ** กระแสหมุนกลับทาง + กระแสเร็ว (TURBO) / ช้า (CALM) + PHOTON RUSH |
| 3 SPIN LOCK | **พลิก spin ไม่ได้** (ล็อก UP หรือ DOWN) ต้องใช้แถบที่ได้มาให้เป็น + NODE STORM |
| 4 RYDBERG | **n สูง** (7s ถึง 9p) node 5–7 วง แถบแคบหลายชั้น + TIME ATTACK / MARATHON |
| 5 SINGULARITY TRIALS | กฎหลายอย่างพร้อมกัน และหลุมดำมากขึ้น ปิดท้ายด้วย 9g PAULI STORM |

กฎของด่าน (`TLevelDef` ใน `uPauliGame.pas`):

| กฎ | ผล |
|---|---|
| MIRRORED (m < 0) | กระแส Schrödinger m/s² กลับทิศ: แถบส้ม / น้ำเงินสลับกัน |
| TURBO xF / CALM xF | ความเร็วกระแสทั้งหมด (probe, quanta, หลุมดำ, การหมุนของ cloud) × F |
| SPIN LOCKED UP / DOWN | เริ่มด้วย spin นั้นและพลิกไม่ได้ (กด SPACE = เสียงปฏิเสธ) |
| PHOTON RUSH | Balmer photon ทุก 0.35 × 12 s = 4.2 s |
| NODE STORM | อยู่ใน node เสีย coherence เร็วขึ้น 1.8 เท่า |
| TIME ATTACK / MARATHON | เวลาน้อย (60–65 s) / เป้ามาก (24–26 quanta, 120–140 s) |

ทุก orbital เลือกให้มีความหนาแน่นในระนาบเกม z = 0 (l − |m| เป็นเลขคู่ จึงไม่มี angular node บนระนาบ) — มี test ตรวจ

จำนวนหลุมดำ: CLASSIC 0 · BLACK HOLE = BH ของด่าน · SINGULARITY = min(6, BH + 1 + BH div 3)

## ตารางด่านทั้งหมด

ผลบอท: `app/tests/game_test` เล่นทุกด่าน 5 seed ต่อโหมด (C = CLASSIC, BH = BLACK HOLE, S = SINGULARITY)

| # | world | orbital | m | title | rules | quanta / time | black holes BH / SING | bot wins of 5  C / BH / S |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 GROUND RULES | 2p | +1 | FIRST CURRENT | - | 10 / 80 s | 1 / 2 | 5 / 5 / 5 |
| 2 | 1 GROUND RULES | 3p | +1 | ONE RADIAL NODE | - | 12 / 80 s | 1 / 2 | 5 / 4 / 5 |
| 3 | 1 GROUND RULES | 3d | +2 | DOUBLE TWIST | - | 14 / 80 s | 2 / 3 | 5 / 5 / 5 |
| 4 | 1 GROUND RULES | 4f | +3 | F-RING | - | 14 / 80 s | 2 / 3 | 5 / 5 / 5 |
| 5 | 1 GROUND RULES | 5s | +0 | SPIN ONLY | - | 16 / 80 s | 3 / 5 | 4 / 5 / 4 |
| 6 | 1 GROUND RULES | 6p | +1 | PAULI CURRENT 6p | - | 20 / 95 s | 3 / 5 | 5 / 3 / 2 |
| 7 | 2 MIRROR CURRENTS | 2p | -1 | MIRROR | mirrored | 10 / 80 s | 1 / 2 | 5 / 5 / 5 |
| 8 | 2 MIRROR CURRENTS | 3d | -2 | COUNTER TWIST | mirrored | 12 / 80 s | 2 / 3 | 5 / 5 / 5 |
| 9 | 2 MIRROR CURRENTS | 3d | +0 | STILL WATER | - | 12 / 80 s | 1 / 2 | 5 / 5 / 5 |
| 10 | 2 MIRROR CURRENTS | 4d | -2 | TURBO 4d | turbo x1.6, mirrored | 14 / 80 s | 2 / 3 | 5 / 4 / 3 |
| 11 | 2 MIRROR CURRENTS | 4f | -1 | CALM 4f | calm x0.6, mirrored | 14 / 70 s | 2 / 3 | 5 / 5 / 5 |
| 12 | 2 MIRROR CURRENTS | 5d | +2 | PHOTON RUSH | photon rush | 18 / 85 s | 3 / 5 | 5 / 2 / 4 |
| 13 | 3 SPIN LOCK | 3p | +1 | LOCKED UP | spin locked UP | 12 / 80 s | 1 / 2 | 5 / 5 / 5 |
| 14 | 3 SPIN LOCK | 4p | +1 | LOCKED DOWN | spin locked DOWN | 12 / 85 s | 2 / 3 | 5 / 5 / 4 |
| 15 | 3 SPIN LOCK | 5f | -3 | F-LOCK | spin locked UP, mirrored | 14 / 85 s | 2 / 3 | 5 / 5 / 3 |
| 16 | 3 SPIN LOCK | 5s | +0 | FROZEN SPIN | spin locked DOWN | 14 / 85 s | 2 / 3 | 5 / 5 / 4 |
| 17 | 3 SPIN LOCK | 6d | -2 | NODE STORM | spin locked UP, node storm, mirrored | 16 / 90 s | 2 / 3 | 5 / 4 / 2 |
| 18 | 3 SPIN LOCK | 6f | +1 | LOCK 6f | spin locked UP | 18 / 95 s | 3 / 5 | 5 / 5 / 3 |
| 19 | 4 RYDBERG | 7s | +0 | RYDBERG 7s | - | 16 / 95 s | 2 / 3 | 5 / 4 / 5 |
| 20 | 4 RYDBERG | 7p | -1 | RYDBERG 7p | mirrored | 18 / 100 s | 2 / 3 | 5 / 5 / 5 |
| 21 | 4 RYDBERG | 7d | +2 | TIME ATTACK | time attack | 14 / 60 s | 3 / 5 | 5 / 4 / 3 |
| 22 | 4 RYDBERG | 8p | +1 | 8p | - | 18 / 105 s | 3 / 5 | 5 / 5 / 2 |
| 23 | 4 RYDBERG | 8g | -4 | TURBO 8g | turbo x1.4, mirrored | 18 / 100 s | 3 / 5 | 4 / 4 / 2 |
| 24 | 4 RYDBERG | 9p | +1 | MARATHON 9p | marathon | 26 / 140 s | 3 / 5 | 5 / 3 / 3 |
| 25 | 5 SINGULARITY TRIALS | 4f | +3 | STORM RUSH | photon rush, node storm | 16 / 80 s | 3 / 5 | 5 / 5 / 5 |
| 26 | 5 SINGULARITY TRIALS | 5g | -4 | LOCKED TURBO | spin locked UP, turbo x1.4, mirrored | 16 / 80 s | 3 / 5 | 5 / 5 / 3 |
| 27 | 5 SINGULARITY TRIALS | 6p | -1 | MIRROR MARATHON | marathon, mirrored | 24 / 120 s | 3 / 5 | 5 / 3 / 3 |
| 28 | 5 SINGULARITY TRIALS | 7f | +3 | FAST F | time attack | 14 / 65 s | 4 / 6 | 5 / 5 / 1 |
| 29 | 5 SINGULARITY TRIALS | 8d | +0 | DEEP FREEZE | spin locked DOWN, node storm | 16 / 100 s | 3 / 5 | 3 / 3 / 1 |
| 30 | 5 SINGULARITY TRIALS | 9g | +4 | PAULI STORM 9g | turbo x1.3, photon rush | 24 / 140 s | 4 / 6 | 4 / 4 / 3 |

รวม: CLASSIC 145 / 150 · BLACK HOLE 132 / 150 · SINGULARITY 110 / 150 — ทุกด่านชนะได้ในทุกโหมด และยากขึ้นตามโหมด

> บอทตอบสนองเร็วกว่าคน ด่านที่บอทชนะเพียง 1–2 จาก 5 ในโหมด SINGULARITY จะยากมากสำหรับคน ยังไม่มีใครลองเล่นด้วยมือ
