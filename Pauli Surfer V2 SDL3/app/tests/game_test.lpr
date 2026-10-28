program game_test;

{ Headless test of PAULI SURFER V2: physics of the current, black holes,
  determinism, and a bot that plays every level in every mode (balance numbers
  for docs/01_game_design.md).
  exit 0 = all checks passed }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, StrUtils, uOrbital, uPauliGame, IniFiles, uSfxEngine, uPauliData;

var
  Fails, Checks: Integer;
  GMode: TGameMode = gmClassic;

procedure Check(ACond: Boolean; const AMsg: string);
begin
  Inc(Checks);
  if ACond then WriteLn('  ok   ', AMsg)
  else
  begin
    Inc(Fails);
    WriteLn('  FAIL ', AMsg);
  end;
end;

procedure TestField;
var
  g: TPauliGame;
  o: TOrbital;
  i, n, bad: Integer;
  rho, w, err: Double;
begin
  WriteLn('== field ==');
  g := TPauliGame.Create;
  g.Mode := GMode;
  try
    g.StartLevel(5, 40000, 11);
    o := g.Orb[0];
    { FieldAt reproduces the omega of every particle }
    n := 0; bad := 0;
    for i := 0 to o.Count - 1 do
    begin
      w := o.FieldAt(o.S[i], o.Z[i], 1, rho);
      err := Abs(w - o.RawW[i]) / Max(1e-9, Abs(o.RawW[i]));
      if err > 1e-3 then Inc(bad);
      Inc(n);
    end;
    Check(bad < n div 100, Format('FieldAt = particle omega (rel. err < 1e-3) for %d particles, %d outside (single-precision positions next to nodes)', [n, bad]));
    Check((o.N = 6) and (o.L = 1) and (o.M = 1) and (Length(o.RadialNodes) = 4), Format('6p has 4 radial nodes (%d)', [Length(o.RadialNodes)]));
    n := 0;
    for i := 0 to o.Count - 1 do
      if (o.S[i] <> g.Orb[1].S[i]) or (o.Z[i] <> g.Orb[1].Z[i]) or (o.Phi0[i] <> g.Orb[1].Phi0[i]) then Inc(n);
    Check(n = 0, 'spin up / down orbitals share the particle positions');
    { bands alternate across the nodes for one spin }
    n := 0;
    for i := 0 to High(o.RadialNodes) do
      if Sign(o.FieldAt(o.RadialNodes[i] * 0.97, 0, 1, rho)) <> Sign(o.FieldAt(o.RadialNodes[i] * 1.03, 0, 1, rho)) then Inc(n);
    Check(n >= 3, Format('current changes direction across %d of 4 nodes (spin up)', [n]));
    Check(Abs(o.RadialProb(o.RadialNodes[0])) < 0.01, Format('r^2 R^2 at node 1 = %.4f', [o.RadialProb(o.RadialNodes[0])]));

    g.StartLevel(4, 40000, 11);
    w := g.Orb[0].FieldAt(3, 0, 1, rho);
    Check((g.Orb[0].M = 0) and (Abs(w + g.Orb[0].FieldAt(3, 0, -1, rho)) < 1e-9),
      Format('5s (m = 0): spin flip reverses the current exactly (%.4f)', [w]));
  finally
    g.Free;
  end;
end;

procedure TestMotion;
var
  g: TPauliGame;
  a0, a1, s0, w, expect, da: Double;
  i: Integer;
begin
  WriteLn('== motion ==');
  g := TPauliGame.Create;
  g.Mode := GMode;
  try
    g.StartLevel(0, 30000, 3);
    s0 := Hypot(g.PX, g.PY);
    a0 := ArcTan2(g.PY, g.PX);
    for i := 1 to 60 do g.Update(1 / 60, 0, 0, False);
    a1 := ArcTan2(g.PY, g.PX);
    w := g.ProbeOmega;
    da := a1 - a0;
    if da < -Pi then da := da + 2 * Pi;
    if da > Pi then da := da - 2 * Pi;
    expect := w;
    Check(Abs(da - expect) < 0.05 * Abs(expect) + 0.01, Format('no thrust: probe turns with the current %.3f rad/s (omega %.3f)', [da, expect]));
    Check(Abs(Hypot(g.PX, g.PY) - s0) < 0.002 * g.RView, 'pure current keeps the radius (exact rotation)');
    for i := 1 to 120 do g.Update(1 / 60, 1, 0, False);
    Check(Hypot(g.VX, g.VY) <= 0.34 * g.RView + 1e-9, Format('thrust speed limited: %.3f RView/s', [Hypot(g.VX, g.VY) / g.RView]));
    { spin flip }
    g.Update(1 / 60, 0, 0, True);
    Check((g.Spin = -1) and (g.Flips = 1), 'spin flip');
    g.Update(1 / 60, 0, 0, True);
    Check((g.Spin = -1) and (g.Flips = 1), 'flip cooldown blocks a second flip');
    { node drains coherence }
    g.StartLevel(1, 30000, 3);
    g.PX := g.Orb[0].RadialNodes[0]; g.PY := 0;
    for i := 1 to 60 do g.Update(1 / 60, 0, 0, False);
    Check(g.Coherence < 0.85, Format('sitting on the node drains coherence: %.2f after 1 s', [g.Coherence]));
  finally
    g.Free;
  end;
end;

procedure PlayBot(ALevel: Integer; ASeed: Cardinal; out AScore, AState: Integer; out ATime: Double; AVerbose: Boolean;
  AMode: TGameMode = gmClassic);
var
  g: TPauliGame;
  ax, ay: Double;
  fl: Boolean;
  steps: Integer;
begin
  g := TPauliGame.Create;
  g.Mode := AMode;
  try
    g.StartLevel(ALevel, 40000, ASeed);
    steps := 0;
    while (g.State = gsPlaying) and (steps < 60 * 200) do
    begin
      g.BotInput(ax, ay, fl);
      g.Update(1 / 60, ax, ay, fl);
      Inc(steps);
    end;
    AScore := g.Score;
    AState := Ord(g.State);
    ATime := g.Elapsed;
    if AVerbose then
      WriteLn(Format('  L%d %-17s %s %5.1f s  %2d/%2d  score %5d  stars %d  flips %2d  nodes %2d  combo %2d  coh %.2f  BH %d hits %d eaten %2d edge %d%s',
        [ALevel + 1, g.Def.Title, IfThen(g.State = gsWon, 'WON ', 'LOST'), g.Elapsed, g.Collected, g.Def.Target, g.Score,
        g.Stars, g.Flips, g.NodeCrossings, g.BestCombo, g.Coherence, g.BHCount, g.HorizonHits, g.Swallowed, g.EdgeBonuses,
        IfThen(g.LostToBH, '  SPAGHETTIFIED', '')]));
  finally
    g.Free;
  end;
end;

procedure TestBlackHoles;
var
  g: TPauliGame;
  i, n, k: Integer;
  bx, by, sx, sy, v, rc, c0, d, rc0: Double;
  m: TGameMode;
  ok: Boolean;
begin
  WriteLn('== black holes ==');
  g := TPauliGame.Create;
  try
    for m := Low(TGameMode) to High(TGameMode) do
    begin
      ok := True;
      for i := 0 to LevelCount - 1 do
      begin
        g.Mode := m;
        g.StartLevel(i, 30000, 5);
        if g.BHCount <> BlackHolesFor(m, i) then ok := False;
        for k := 0 to g.BHCount - 1 do
        begin
          g.BHPos(k, bx, by);
          if Hypot(bx - g.PX, by - g.PY) < 0.45 * g.RView then ok := False;
        end;
      end;
      Check(ok, Format('%s: black holes per level %d %d %d %d %d %d, all >= 0.45 RView from the start',
        [ModeNames[m], BlackHolesFor(m, 0), BlackHolesFor(m, 1), BlackHolesFor(m, 2), BlackHolesFor(m, 3),
        BlackHolesFor(m, 4), BlackHolesFor(m, 5)]));
    end;

    g.Mode := gmBlackHole;
    g.StartLevel(0, 30000, 5);
    g.BHPos(0, bx, by);
    rc := g.BH[0].Rc;
    g.SinkAt(bx + rc, by, sx, sy);
    v := Hypot(sx, sy) / g.RView;
    Check((Abs(v - 0.34) < 0.005) and (sx < 0), Format('pull at the capture radius = top speed 0.34 RView/s (%.3f), towards the hole', [v]));
    g.SinkAt(bx + 4 * rc, by, sx, sy);
    Check(Hypot(sx, sy) / g.RView < 0.05, Format('pull at 4 Rc is weak: %.3f RView/s', [Hypot(sx, sy) / g.RView]));

    { inside Rc: full thrust away is not enough }
    g.PX := bx + 0.8 * rc; g.PY := by;
    n := 0;
    while (g.HorizonHits = 0) and (n < 180) do
    begin
      g.BHPos(0, bx, by);
      d := Max(1e-9, Hypot(g.PX - bx, g.PY - by));
      g.Update(1 / 60, (g.PX - bx) / d, (g.PY - by) / d, False);
      Inc(n);
    end;
    Check(g.HorizonHits = 1, Format('inside Rc the probe falls in despite full thrust (%.2f s)', [n / 60]));
    Check(Abs(g.Coherence - 0.65) < 0.02, Format('horizon costs 35 %% coherence (%.2f)', [g.Coherence]));
    g.BHPos(0, bx, by);
    Check((Hypot(g.PX - bx, g.PY - by) > 0.5 * g.RView) and (g.Immune > 1.9) and (g.State = gsPlaying),
      'Hawking ejection: far side of the orbital, 2 s immune, still playing');

    { outside: at 3 Rc full thrust escapes }
    g.StartLevel(0, 30000, 5);
    g.BHPos(0, bx, by);
    g.PX := bx + 3 * rc; g.PY := by;
    for i := 1 to 120 do
    begin
      g.BHPos(0, bx, by);
      d := Max(1e-9, Hypot(g.PX - bx, g.PY - by));
      g.Update(1 / 60, (g.PX - bx) / d, (g.PY - by) / d, False);
    end;
    g.BHPos(0, bx, by);
    Check((g.HorizonHits = 0) and (Hypot(g.PX - bx, g.PY - by) > 3 * rc), Format('at 3 Rc full thrust escapes (now %.1f Rc)', [Hypot(g.PX - bx, g.PY - by) / rc]));

    { low coherence + horizon = spaghettified }
    g.StartLevel(0, 30000, 5);
    g.BHPos(0, g.PX, g.PY);
    g.Coherence := 0.2;
    g.Update(1 / 60, 0, 0, False);
    Check((g.State = gsLost) and g.LostToBH, 'horizon with coherence 0.2 -> SPAGHETTIFIED (lost)');

    { a quantum on the hole is swallowed; SINGULARITY grows }
    g.Mode := gmSingularity;
    g.StartLevel(0, 30000, 5);
    rc0 := g.BH[0].Rc;
    g.BHPos(0, bx, by);
    g.Quanta[0].S := g.BH[0].S; g.Quanta[0].Phi := g.BH[0].Phi;
    g.PX := -bx; g.PY := -by;
    g.Immune := 5;
    g.Update(1 / 60, 0, 0, False);
    Check((g.Swallowed >= 1) and (g.BH[0].Rc > rc0 * 1.07) and g.Quanta[0].Alive,
      Format('quantum swallowed, singularity grows Rc x%.2f, a new quantum spawns', [g.BH[0].Rc / rc0]));

    { edge bonus x2 }
    g.Mode := gmBlackHole;
    g.StartLevel(0, 30000, 5);
    g.BHPos(0, bx, by);
    rc := g.BH[0].Rc;
    c0 := g.Score;
    g.PX := bx + 2 * rc; g.PY := by;
    g.Quanta[1].S := Hypot(g.PX, g.PY); g.Quanta[1].Phi := ArcTan2(g.PY, g.PX); g.Quanta[1].Alive := True; g.Quanta[1].Bonus := False;
    g.Update(1 / 60, 0, 0, False);
    Check((g.EdgeBonuses = 1) and (g.Score - c0 = 200), Format('edge bonus: quantum at 2 Rc scores x2 (%d)', [Round(g.Score - c0)]));

    { holes drift with the current and turn with a spin flip (5s: the current reverses exactly) }
    g.StartLevel(4, 30000, 5);
    g.Immune := 99;
    c0 := g.BH[0].Phi;
    for i := 1 to 60 do g.Update(1 / 60, 0, 0, False);
    d := g.BH[0].Phi - c0;
    c0 := g.BH[0].Phi;
    g.Update(1 / 60, 0, 0, True);
    for i := 1 to 59 do g.Update(1 / 60, 0, 0, False);
    v := g.BH[0].Phi - c0;
    Check((Abs(d) > 1e-3) and (Sign(d) = -Sign(v)), Format('black hole drifts with the current (%.3f rad/s) and turns round after a spin flip (%.3f rad/s)', [d, v]));
  finally
    g.Free;
  end;
end;

procedure TestLevels;
var
  g: TPauliGame;
  i, n, flips0: Integer;
  d: TLevelDef;
  rho, w1, w2, c0: Double;
  plane: Boolean;
begin
  WriteLn('== 30 levels and their rules ==');
  n := 0;
  plane := True;
  for i := 0 to LevelCount - 1 do
  begin
    d := LevelDef(i);
    if (d.L - Abs(d.M)) mod 2 <> 0 then plane := False;
    if (d.World = i div LevelsPerWorld) and (d.Target > 0) and (d.TimeSec > 0) and (d.Title <> '') then Inc(n);
  end;
  Check((n = LevelCount) and (LevelCount = 30), Format('%d levels in %d worlds, all complete', [n, WorldCount]));
  Check(plane, 'every orbital has density in the game plane z = 0 (l - |m| even)');
  g := TPauliGame.Create;
  try
    g.Mode := gmClassic;
    { spin lock }
    g.StartLevel(13, 30000, 3);
    flips0 := g.Flips;
    g.Update(1 / 60, 0, 0, True);
    Check((g.Spin = -1) and (g.Flips = flips0) and g.Def.NoFlip, Format('level 14 "%s": starts spin DOWN, flip blocked (%s)', [g.Def.Title, g.Def.Rule]));
    { turbo: the current at the same radius is 1.6 x level 7's 2p...: compare 4d m=-2 with FlowMul 1.6 against 1.0 }
    g.StartLevel(9, 30000, 3);
    w1 := g.OmegaAt(g.RView * 0.6, 1);
    GP.FlowScale := GP.FlowScale / 1.6;
    w2 := g.OmegaAt(g.RView * 0.6, 1);
    GP := DefaultGameParams;
    Check(Abs(w1 / w2 - 1.6) < 0.01, Format('level 10 TURBO: current x %.2f', [w1 / w2]));
    { mirror: m < 0 reverses the orbital current }
    g.StartLevel(6, 30000, 3);
    w1 := g.Orb[0].FieldAt(g.RView * 0.5, 0, 0, rho);
    g.StartLevel(0, 30000, 3);
    w2 := g.Orb[0].FieldAt(g.RView * 0.5 * LevelDef(0).N * LevelDef(0).N / 4, 0, 0, rho);
    Check((w1 < 0) and (w2 > 0), Format('level 7 MIRROR: Schroedinger current clockwise (%.4f), level 1 counter-clockwise (%.4f)', [w1, w2]));
    { photon rush }
    g.StartLevel(11, 30000, 3);
    Check(Abs(g.BonusT - GP.BonusEvery * 0.35) < 1e-9, Format('level 12 PHOTON RUSH: a photon every %.1f s', [g.BonusT]));
    { node storm drains 1.8 x }
    g.StartLevel(16, 30000, 3);
    g.PX := g.Orb[0].RadialNodes[1]; g.PY := 0;
    c0 := g.Coherence;
    g.Update(0.05, 0, 0, False);
    Check(Abs((c0 - g.Coherence) / 0.05 - GP.DrainNode * 1.8) < 0.01, Format('level 17 NODE STORM: drain %.2f /s', [(c0 - g.Coherence) / 0.05]));
  finally
    g.Free;
  end;
end;

procedure TestBot;
var
  lv, sc, st, sc2, st2, won, seed, total: Integer;
  rate: array[TGameMode] of Integer;
  t, t2: Double;
  m: TGameMode;
const
  Seeds = 5;
  Need: array[TGameMode] of Integer = (2, 1, 1);   { of 5 seeds: every level must be winnable }
begin
  for m := Low(TGameMode) to High(TGameMode) do
  begin
    WriteLn('== bot plays every level (3 seeds), mode ', ModeNames[m], ' ==');
    total := 0;
    for lv := 0 to LevelCount - 1 do
    begin
      won := 0;
      for seed := 1 to Seeds do
      begin
        PlayBot(lv, seed * 101, sc, st, t, True, m);
        if st = Ord(gsWon) then Inc(won);
      end;
      Inc(total, won);
      Check(won >= Need[m], Format('%s level %d %s winnable by the bot: %d / %d', [ModeNames[m], lv + 1, LevelDef(lv).Title, won, Seeds]));
    end;
    WriteLn(Format('  %s: bot won %d of %d', [ModeNames[m], total, Seeds * LevelCount]));
    rate[m] := total;
  end;
  Check((rate[gmClassic] > rate[gmBlackHole]) and (rate[gmBlackHole] > rate[gmSingularity]),
    Format('difficulty rises with the mode: bot wins %d > %d > %d of %d', [rate[gmClassic], rate[gmBlackHole], rate[gmSingularity],
    Seeds * LevelCount]));
  PlayBot(5, 7, sc, st, t, False, gmSingularity);
  PlayBot(5, 7, sc2, st2, t2, False, gmSingularity);
  Check((sc = sc2) and (st = st2) and (t = t2), Format('deterministic replay: score %d = %d', [sc, sc2]));
end;

procedure TestData;
var
  f: string;
  i, same: Integer;
  a, b: TLevelDef;
  ini: TMemIniFile;
  k: TFxKey;
  id: TSoundId;
  buf: TSoundBuf;
  d: TSfxDef;
  ok: Boolean;
  o: TOrbital;
  c0: array of TRGB;
begin
  WriteLn('-- data files (levels / sounds / effects)');
  f := GetTempDir + 'ps2_levels_test.ini';
  SaveLevels(f);
  Check(LoadLevels(f), 'pauli_levels.ini saved and loaded');
  same := 0;
  for i := 0 to LevelCount - 1 do
  begin
    a := BuiltinLevel(i); b := LevelDef(i);
    if (a.N = b.N) and (a.L = b.L) and (a.M = b.M) and (a.Title = b.Title) and (a.Tip = b.Tip) and (a.Target = b.Target)
      and (a.Quanta = b.Quanta) and (Abs(a.TimeSec - b.TimeSec) < 1e-6) and (a.BH = b.BH) and (Abs(a.FlowMul - b.FlowMul) < 1e-6)
      and (Abs(a.PhotonMul - b.PhotonMul) < 1e-6) and (Abs(a.DrainMul - b.DrainMul) < 1e-6) and (a.NoFlip = b.NoFlip)
      and (a.StartSpin = b.StartSpin) and (a.Rule = b.Rule) then Inc(same);
  end;
  Check(same = LevelCount, Format('levels round trip: %d / %d identical (rules text too)', [same, LevelCount]));
  { edit one level in the file -> the table follows; a broken level falls back }
  ini := TMemIniFile.Create(f);
  ini.WriteInteger('level3', 'n', 4); ini.WriteInteger('level3', 'l', 2); ini.WriteInteger('level3', 'm', 0);
  ini.WriteString('level3', 'current_x', '1.5');
  ini.WriteInteger('level4', 'l', 2);   { 4f -> l 2, m 3: |m| > l = invalid }
  ini.UpdateFile; ini.Free;
  LoadLevels(f);
  b := LevelDef(2);
  Check((b.N = 4) and (b.L = 2) and (b.M = 0) and (Pos('TURBO x1.5', b.Rule) > 0), Format('edited level 3 = 4d m 0, rule "%s"', [b.Rule]));
  Check(LevelDef(3).L = BuiltinLevel(3).L, 'invalid level 4 (|m| > l) falls back to the built-in level');
  Check(CheckLevel(BuiltinLevel(0)) = '', 'built-in level 1 passes CheckLevel');
  a := BuiltinLevel(0); a.M := 0;   { 2p m 0: l - |m| odd }
  Check(CheckLevel(a) <> '', 'CheckLevel refuses an orbital without density in z = 0: ' + CheckLevel(a));
  ResetLevels;
  DeleteFile(f);

  f := GetTempDir + 'ps2_fx_test.ini';
  DefaultFx;
  GFX[fxColCCW] := $123456; GFX[fxLensStrength] := 3.25; GFX[fxDiscCount] := 120;
  SaveFx(f);
  DefaultFx;
  Check(LoadFx(f) and (FxC(fxColCCW) = $123456) and (Abs(GFX[fxLensStrength] - 3.25) < 1e-9) and (FxI(fxDiscCount) = 120),
    'pauli_fx.ini round trip (colour, float, int)');
  ini := TMemIniFile.Create(f);
  ini.WriteString('BLACK HOLE', 'lens_strength', '99');
  ini.UpdateFile; ini.Free;
  LoadFx(f);
  Check(Abs(GFX[fxLensStrength] - FxInfo[fxLensStrength].Hi) < 1e-9, 'an effect value out of range is clamped');
  ok := True;
  for k := Low(TFxKey) to High(TFxKey) do
    if (FxInfo[k].Def < FxInfo[k].Lo) or (FxInfo[k].Def > FxInfo[k].Hi) then ok := False;
  Check(ok, Format('%d effect parameters, all defaults inside their range', [Ord(High(TFxKey)) + 1]));
  DefaultFx;
  DeleteFile(f);

  { cloud colours: the defaults reproduce uOrbital exactly, a new colour changes only the colours }
  o := TOrbital.Create;
  try
    RandSeed := 77;
    o.Build(4, 3, 3, 20000, 1);
    SetLength(c0, o.Count);
    for i := 0 to o.Count - 1 do c0[i] := o.Col[i];
    DefaultFx;
    ApplyCloudColours;
    o.Recolour;
    same := 0;
    for i := 0 to o.Count - 1 do
      if (o.Col[i].R = c0[i].R) and (o.Col[i].G = c0[i].G) and (o.Col[i].B = c0[i].B) then Inc(same);
    Check(same = o.Count, Format('default cloud colours = the original HydrogenFlow colours (%d / %d particles)', [same, o.Count]));
    GFX[fxCloudCCW] := $00FF00;
    ApplyCloudColours;
    o.Recolour;
    same := 0;
    for i := 0 to o.Count - 1 do
      if (o.W[i] >= 0) and (o.Col[i].G > o.Col[i].R) then Inc(same);
    Check(same > 0, Format('cloud_ccw = green recolours the CCW particles (%d)', [same]));
    DefaultFx;
    ApplyCloudColours;
  finally
    o.Free;
  end;

  f := GetTempDir + 'ps2_sounds_test.ini';
  DefaultSounds;
  Sounds[snFlip].Pitch := 1.5;
  d := SoundDesign(snWin);
  d.Layers[0].Freq := 777;
  SetSoundCustom(snWin, d);
  SaveSounds(f);
  DefaultSounds;
  Check(LoadSounds(f) and (Abs(Sounds[snFlip].Pitch - 1.5) < 1e-9) and (Sounds[snWin].Custom <> nil) and
    (Abs(Sounds[snWin].Custom.Layers[0].Freq - 777) < 1e-6), 'pauli_sounds.ini round trip (pitch + a custom design)');
  ok := True;
  for id := Low(TSoundId) to High(TSoundId) do
  begin
    RenderSound(id, buf);
    if buf.Frames < 100 then ok := False;
  end;
  Check(ok, 'all 22 sounds render');
  DefaultSounds;
  DeleteFile(f);
end;

begin
  Fails := 0;
  Checks := 0;
  TestField;
  TestMotion;
  TestBlackHoles;
  TestLevels;
  TestData;
  TestBot;
  WriteLn;
  WriteLn(Format('%d checks, %d failures', [Checks, Fails]));
  if Fails > 0 then Halt(1);
end.
