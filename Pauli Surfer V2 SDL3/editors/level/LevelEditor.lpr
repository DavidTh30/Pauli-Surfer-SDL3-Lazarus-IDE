program LevelEditor;

{ PAULI SURFER 2 - LEVEL EDITOR

  Edits the 30 levels (5 worlds x 6) of the game: data\pauli_levels.ini,
  read by uPauliGame.LoadLevels (the game reloads a saved file within 0.5 s).

    LEVEL     orbital n l m (checked: l < n, |m| <= l, l - |m| even = density
              in the game plane z = 0), title, tip, badge (TIME ATTACK ...)
    GOAL      quanta to collect, quanta on screen, time
    HOLES     black holes in BLACK HOLE mode (SINGULARITY = more, shown)
    RULES     current x (TURBO / CALM), photon interval x (PHOTON RUSH),
              node drain x (NODE STORM), spin lock + start spin
    PREVIEW   the real game logic (TPauliGame) and the real cloud renderer:
              the bot plays the edited level live, mode CLASSIC / BLACK HOLE /
              SINGULARITY, black holes, quanta and probe drawn on top
    BOT TEST  5 seeds x 3 modes, headless, a few runs per frame: wins, score,
              time per mode = how hard the level is
    PLAY      saves, then starts PauliSurfer2.exe on this level (P) or the
              bot preview of the game (V)

  Developer window: F2 (LAYERS + STATE).  --data=DIR, --ui-test=LOG. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, Math, StrUtils, SDL3, uHud, uUI, uOrbital, uRaster, uPauliGame, uPauliData, uEdKit;

const
  PreviewPoints = 120000;
  BotSeeds = 5;

type
  TBotRun = record
    Wins, Runs: Integer;
    ScoreSum, TimeSum: Double;
  end;

var
  Cur: Integer;                       { level 0..29 }
  LevWorld: Integer;
  LevelsPath, SavedAt: string;
  SavedDefs: array[0..LevelCount - 1] of string;
  Clip: TLevelDef;
  HasClip: Boolean;
  { preview }
  PG: TPauliGame;
  PMode: TGameMode = gmBlackHole;
  PRun: Boolean = True;
  PNeedStart: Boolean = True;
  PStartT: Double;
  Raster: TCloudRaster;
  Tex: PSDL_Texture;
  TexW, TexH: Integer;
  Cam: TCamera;
  PrevRect: TSDL_FRect;              { pixels }
  BuildMs: Double;
  { bot test }
  BG: TPauliGame;
  BotActive, BotDone: Boolean;
  BotMode: TGameMode;
  BotSeed, BotSteps: Integer;
  Bot: array[TGameMode] of TBotRun;
  BotKey: string;                     { level text the results belong to }
  LaunchFile: string;                 { ui-test: screenshot of the launched game }
  LaunchT: Double;

{ signed integer text: +1, 0, -2 (Format has no %+d) }
function PM(I: Integer): string;
begin
  if I > 0 then Result := '+' + IntToStr(I) else Result := IntToStr(I);
end;

function DefText(const D: TLevelDef): string;
begin
  Result := Format('%d|%d|%d|%s|%s|%s|%d|%d|%s|%d|%s|%s|%s|%d|%d', [D.N, D.L, D.M, D.Title, D.Tip, D.Badge, D.Target,
    D.Quanta, DotF(D.TimeSec), D.BH, DotF(D.FlowMul), DotF(D.PhotonMul), DotF(D.DrainMul), Ord(D.NoFlip), D.StartSpin]);
end;

function Modified(I: Integer): Boolean;
begin
  Result := DefText(LevelTable[I]) <> SavedDefs[I];
end;

function ModifiedCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to LevelCount - 1 do if Modified(i) then Inc(Result);
end;

procedure RememberSaved;
var
  i: Integer;
begin
  for i := 0 to LevelCount - 1 do SavedDefs[i] := DefText(LevelTable[i]);
end;

procedure Changed;
begin
  MakeRuleText(LevelTable[Cur]);
  PNeedStart := True;
end;

procedure DoLoad;
begin
  LoadLevels(LevelsPath);
  RememberSaved;
  PNeedStart := True;
end;

procedure DoSave;
var
  i: Integer;
begin
  for i := 0 to LevelCount - 1 do
    if CheckLevel(LevelTable[i]) <> '' then
    begin
      Status(Format('level %d is not playable: %s - not saved', [i + 1, CheckLevel(LevelTable[i])]));
      Cur := i;
      LevWorld := i div LevelsPerWorld;
      Exit;
    end;
  try
    SaveLevels(LevelsPath);
    RememberSaved;
    SavedAt := FormatDateTime('hh:nn:ss', Now);
    Status('saved ' + LevelsPath + '  (a running game reloads it)');
  except
    on E: Exception do Status('save failed: ' + E.Message);
  end;
end;

procedure SelectLevel(I: Integer);
begin
  I := EnsureRange(I, 0, LevelCount - 1);
  if I = Cur then Exit;
  Cur := I;
  LevWorld := I div LevelsPerWorld;
  FocusKey := '';
  PNeedStart := True;
end;

{ ---------------------------------------------------------------- bot test }

procedure BotStart;
var
  m: TGameMode;
begin
  if CheckLevel(LevelTable[Cur]) <> '' then
  begin
    Status('not playable: ' + CheckLevel(LevelTable[Cur]));
    Exit;
  end;
  for m := Low(TGameMode) to High(TGameMode) do
  begin
    Bot[m].Wins := 0; Bot[m].Runs := 0; Bot[m].ScoreSum := 0; Bot[m].TimeSum := 0;
  end;
  BotMode := gmClassic;
  BotSeed := 0;
  BotSteps := -1;
  BotActive := True;
  BotDone := False;
  BotKey := IntToStr(Cur) + '|' + DefText(LevelTable[Cur]);
end;

{ advances the headless runs for about ABudgetMs; the same play as game_test }
procedure BotTick(ABudgetMs: Double);
var
  t0: QWord;
  ax, ay: Double;
  fl: Boolean;
begin
  if not BotActive then Exit;
  if BotKey <> IntToStr(Cur) + '|' + DefText(LevelTable[Cur]) then
  begin
    BotActive := False;
    BotDone := False;
    Status('bot test stopped: the level changed');
    Exit;
  end;
  t0 := SDL_GetTicksNS;
  while (SDL_GetTicksNS - t0) / 1e6 < ABudgetMs do
  begin
    if BotSteps < 0 then
    begin
      BG.Mode := BotMode;
      BG.StartLevel(Cur, 40000, (BotSeed + 1) * 101);
      BotSteps := 0;
    end;
    BG.BotInput(ax, ay, fl);
    BG.Update(1 / 60, ax, ay, fl);
    Inc(BotSteps);
    if (BG.State <> gsPlaying) or (BotSteps >= 60 * 200) then
    begin
      Inc(Bot[BotMode].Runs);
      if BG.State = gsWon then Inc(Bot[BotMode].Wins);
      Bot[BotMode].ScoreSum := Bot[BotMode].ScoreSum + BG.Score;
      Bot[BotMode].TimeSum := Bot[BotMode].TimeSum + BG.Elapsed;
      BotSteps := -1;
      Inc(BotSeed);
      if BotSeed >= BotSeeds then
      begin
        BotSeed := 0;
        if BotMode = High(TGameMode) then
        begin
          BotActive := False;
          BotDone := True;
          Status(Format('bot test done: CLASSIC %d / BLACK HOLE %d / SINGULARITY %d of %d won',
            [Bot[gmClassic].Wins, Bot[gmBlackHole].Wins, Bot[gmSingularity].Wins, BotSeeds]));
          Exit;
        end;
        BotMode := Succ(BotMode);
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------- preview }

procedure ProjectP(X, Y, Z: Double; out SX, SY: Single);
var
  dx, dy, dz, zc, inv, k: Double;
begin
  dx := X - Cam.Pos[0]; dy := Y - Cam.Pos[1]; dz := Z - Cam.Pos[2];
  zc := Max(0.05, dx * Cam.Fwd[0] + dy * Cam.Fwd[1] + dz * Cam.Fwd[2]);
  inv := Cam.Focal / zc;
  k := PrevRect.w / Max(1, TexW);
  SX := PrevRect.x + (Cam.Cx + (dx * Cam.Right[0] + dy * Cam.Right[1] + dz * Cam.Right[2]) * inv) * k;
  SY := PrevRect.y + (Cam.Cy - (dx * Cam.Up[0] + dy * Cam.Up[1] + dz * Cam.Up[2]) * inv) * k;
end;

procedure Ring(CX, CY, R: Single; ACol: UInt32; AAlpha: Byte; ADash: Boolean = False);
var
  i, n: Integer;
  a: Single;
begin
  n := Max(16, Round(R * 0.8));
  for i := 0 to n - 1 do
  begin
    if ADash and Odd(i) then Continue;
    a := 2 * Pi * i / n;
    Hud.Rect(CX + R * Cos(a) - 0.75, CY + R * Sin(a) - 0.75, 1.5, 1.5, ACol, AAlpha);
  end;
end;

procedure StartPreview;
var
  t0: QWord;
begin
  if CheckLevel(LevelTable[Cur]) <> '' then Exit;
  t0 := SDL_GetTicksNS;
  PG.Mode := PMode;
  PG.StartLevel(Cur, PreviewPoints, 1000 + Cur, Random(100000) + 1);
  BuildMs := (SDL_GetTicksNS - t0) / 1e6;
  PNeedStart := False;
  PStartT := NowS;
end;

procedure DrawPreview(X, Y, W, H: Single);
var
  P: TFrameParams;
  tw, th, k, i: Integer;
  d, cx, cy, cz, f: Double;
  bx, by, ax, ay, rr: Single;
  o: TOrbital;
  r: TSDL_FRect;
  msg: string;
  m: TGameMode;
  fl: Boolean;
  tx, ty: Double;
begin
  PanelU('preview', X, Y, W, H, 'PREVIEW');
  GrpBegin('preview.modes', 'group');
  for m := Low(TGameMode) to High(TGameMode) do
    if Btn(ModeNames[m], X + W - 14 - (3 - Ord(m)) * 124, Y + 6, 120, 24, m = PMode, 'mode.' + ModeIds[m]) then
    begin
      PMode := m;
      PNeedStart := True;
    end;
  GrpEnd;
  PrevRect.x := U(X + 10); PrevRect.y := U(Y + 36); PrevRect.w := U(W - 20); PrevRect.h := U(H - 46 - 36);
  AddLayer('view.preview', 'view', PrevRect.x, PrevRect.y, PrevRect.w, PrevRect.h);
  Box(X + 10, Y + 36, W - 20, H - 82, $000000);
  msg := CheckLevel(LevelTable[Cur]);
  if msg <> '' then
  begin
    Txt(fkSmallBold, 'NOT PLAYABLE', X + W / 2, Y + H / 2 - 30, cRed, alCenter);
    Txt(fkSmall, msg, X + W / 2, Y + H / 2, cRed, alCenter);
    Exit;
  end;
  if PNeedStart then StartPreview;
  { simulate }
  if PRun and (PG.State = gsPlaying) then
  begin
    PG.BotInput(tx, ty, fl);
    PG.Update(Min(Dt, 1 / 30), tx, ty, fl);
    while PG.PopEvent <> geNone do ;
  end
  else if PRun and (NowS - PStartT > 1) and (PG.State <> gsPlaying) then
  begin
    { replay after a finished run }
    PStartT := NowS;
    PG.Mode := PMode;
    PG.StartLevel(Cur, PreviewPoints, 1000 + Cur, Random(100000) + 1);
  end;
  { texture }
  tw := Max(64, Round(PrevRect.w * 0.6));
  th := Max(64, Round(PrevRect.h * 0.6));
  if (Tex = nil) or (tw <> TexW) or (th <> TexH) then
  begin
    if Tex <> nil then SDL_DestroyTexture(Tex);
    Tex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, tw, th);
    SDL_SetTextureScaleMode(Tex, SDL_SCALEMODE_LINEAR);
    TexW := tw; TexH := th;
    Raster.Resize(tw, th);
  end;
  o := PG.Active;
  if o.Count = 0 then Exit;
  { camera as in the game: az -90, el 62, fov 40, the disc of 1.15 RView fits }
  { the disc of 1.15 RView: 92 % of the width, or of the height (squeezed by sin 62 deg) }
  LookAtOrigin(Cam, 0, -Cos(DegToRad(62)), Sin(DegToRad(62)), 40, TexW, TexH);
  d := Cam.Focal * 1.15 * o.RView / (0.46 * Min(TexW, TexH / Sin(DegToRad(62))));
  cx := 0; cy := -d * Cos(DegToRad(62)); cz := d * Sin(DegToRad(62));
  LookAtOrigin(Cam, cx, cy, cz, 40, TexW, TexH);
  P.Cam := Cam;
  P.Time := PG.SimTime;
  P.Cut := 5;
  P.Slab := o.RView * 0.07;
  P.SizeWorld := o.RView * 0.0030;
  f := Cam.Focal * o.RView / d;
  P.Energy := 0.6 * 4.0 * (300000 / o.Count) * Sqr(f / 300);
  P.NucleusWorld := o.RView * 0.006;
  P.ThickPx := 0;
  Raster.Render(o, P);
  SDL_UpdateTexture(Tex, nil, @Raster.Pix[0], TexW * 4);
  r := PrevRect;
  SDL_RenderTexture(Ren, Tex, nil, @r);
  { radial nodes (dashed), black holes, quanta, probe }
  for i := 0 to High(o.RadialNodes) do
    for k := 0 to 71 do
      if not Odd(k) then
      begin
        ProjectP(o.RadialNodes[i] * Cos(k * Pi / 36), o.RadialNodes[i] * Sin(k * Pi / 36), 0, bx, by);
        Hud.Rect(bx - 0.75, by - 0.75, 1.5, 1.5, cBlue, 200);
      end;
  for k := 0 to PG.BHCount - 1 do
  begin
    PG.BHPos(k, tx, ty);
    ProjectP(tx, ty, 0, bx, by);
    ProjectP(tx + PG.BH[k].Rc, ty, 0, ax, ay);
    rr := Max(4, Abs(ax - bx));
    Hud.Dot(bx, by, Max(3, rr * PG.BH[k].Rh / PG.BH[k].Rc), $000000);
    Ring(bx, by, rr * PG.BH[k].Rh / PG.BH[k].Rc * 1.1, $FFC870, 230);
    Ring(bx, by, rr, cRed, 160, True);
    AddLayer('preview.blackhole.' + IntToStr(k), 'world', bx - rr, by - rr, 2 * rr, 2 * rr);
  end;
  for k := 0 to MaxQuanta - 1 do
    if PG.Quanta[k].Alive then
    begin
      ProjectP(PG.Quanta[k].S * Cos(PG.Quanta[k].Phi), PG.Quanta[k].S * Sin(PG.Quanta[k].Phi), 0, bx, by);
      if PG.Quanta[k].Bonus then Hud.Dot(bx, by, U(5), cGold) else Hud.Dot(bx, by, U(3.5), $FFFFFF);
    end;
  ProjectP(PG.PX, PG.PY, 0, bx, by);
  Hud.Dot(bx, by, U(7), cCyan);
  Hud.Dot(bx, by, U(3.5), $FFFFFF);
  AddLayer('preview.probe', 'world', bx - U(7), by - U(7), U(14), U(14));
  { info line }
  GrpBegin('preview.info', 'text');
  Txt(fkTiny, Format('%s  %s   .   %d / %d quanta   .   %.0f s left   .   coherence %.0f %%   .   %s   .   %d black holes',
    [PG.Active.Name, ModeNames[PG.Mode], PG.Collected, PG.Def.Target, PG.TimeLeft, PG.Coherence * 100,
    IfThen(PG.State = gsPlaying, 'playing', IfThen(PG.State = gsWon, 'WON', 'LOST')), PG.BHCount]), X + 14, Y + H - 40, cDim);
  Txt(fkTiny, Format('%d radial nodes   .   RView %.1f a0   .   %dk points, start %.0f ms', [Length(o.RadialNodes), o.RView,
    PreviewPoints div 1000, BuildMs]), X + 14, Y + H - 24, cFaint);
  GrpEnd;
  if Btn(IfThen(PRun, 'PAUSE', 'RUN BOT'), X + 18, Y + 44, 96, 24, False, 'run_bot', 'SPACE') then PRun := not PRun;
  if Btn('RESTART', X + 118, Y + 44, 90, 24, False, 'restart') then PNeedStart := True;
end;

procedure DrawBotTest(X, Y, W, H: Single);
var
  m: TGameMode;
  y2, done, total: Single;
  verdict: string;
  col: UInt32;
begin
  PanelU('bottest', X, Y, W, H, Format('BOT TEST  (%d seeds x 3 modes, like game_test)', [BotSeeds]));
  if Btn(IfThen(BotActive, 'RUNNING ...', 'TEST BOT'), X + W - 164, Y + 6, 150, 26, BotActive, 'test_bot', 'T') then
    if not BotActive then BotStart;
  y2 := Y + 40;
  GrpBegin('bottest.table', 'text');
  Txt(fkTiny, 'MODE', X + 14, y2, cFaint);
  Txt(fkTiny, 'BLACK HOLES', X + 150, y2, cFaint);
  Txt(fkTiny, 'WON', X + 250, y2, cFaint);
  Txt(fkTiny, 'AVG SCORE', X + 310, y2, cFaint);
  Txt(fkTiny, 'AVG TIME', X + 400, y2, cFaint);
  y2 := y2 + 20;
  for m := Low(TGameMode) to High(TGameMode) do
  begin
    Txt(fkSmallBold, ModeNames[m], X + 14, y2, cText);
    Txt(fkSmall, IntToStr(Min(MaxBlackHoles, BlackHolesFor(m, Cur))), X + 150, y2, cDim);
    if (Bot[m].Runs > 0) and (BotActive or (BotKey = IntToStr(Cur) + '|' + DefText(LevelTable[Cur]))) then
    begin
      if Bot[m].Wins = 0 then col := cRed else if Bot[m].Wins = Bot[m].Runs then col := cGreen else col := cGold;
      Txt(fkSmallBold, Format('%d / %d', [Bot[m].Wins, Bot[m].Runs]), X + 250, y2, col);
      Txt(fkSmall, Format('%.0f', [Bot[m].ScoreSum / Bot[m].Runs]), X + 310, y2, cDim);
      Txt(fkSmall, Format('%.1f s', [Bot[m].TimeSum / Bot[m].Runs]), X + 400, y2, cDim);
    end
    else Txt(fkSmall, '-', X + 250, y2, cFaint);
    y2 := y2 + 22;
  end;
  GrpEnd;
  total := 3 * BotSeeds;
  done := Bot[gmClassic].Runs + Bot[gmBlackHole].Runs + Bot[gmSingularity].Runs;
  if not BotActive and (BotKey <> IntToStr(Cur) + '|' + DefText(LevelTable[Cur])) then done := 0;
  Box(X + 14, y2 + 4, W - 28, 4, $1A1E28);
  Box(X + 14, y2 + 4, (W - 28) * done / total, 4, IfThen(BotDone, cGreen, cOrange));
  if BotDone and (BotKey = IntToStr(Cur) + '|' + DefText(LevelTable[Cur])) then
  begin
    if Bot[gmClassic].Wins = 0 then verdict := 'TOO HARD: the bot never wins CLASSIC'
    else if Bot[gmSingularity].Wins = 0 then verdict := 'SINGULARITY never won by the bot: very hard for a person'
    else if Bot[gmSingularity].Wins = BotSeeds then verdict := 'EASY: the bot wins every run, even SINGULARITY'
    else verdict := 'OK: winnable in every mode, harder with the mode';
    Txt(fkTiny, verdict, X + 14, y2 + 14, IfThen(Pos('OK', verdict) = 1, cGreen, cGold));
  end
  else if not BotActive then Txt(fkTiny, 'T = run the bot on the edited level (no file needed)', X + 14, y2 + 14, cFaint);
end;

{ ---------------------------------------------------------------- form }

function StepRow(const AKey, ACap, AVal: string; X, Y, W: Single): Integer;
begin
  Result := StepperU(AKey, ACap, AVal, X, Y, W, 28);
end;

procedure DrawForm;
var
  D: ^TLevelDef;
  x0, y, cw: Single;
  i: Integer;
  v: Double;
  msg, t: string;
  b: Boolean;
begin
  D := @LevelTable[Cur];
  x0 := 332;
  PanelU('level', x0, 64, 516, CHu - 104, Format('LEVEL %d  .  WORLD %d  %s', [Cur + 1, D^.World + 1, WorldNames[D^.World]]));
  { orbital }
  y := 108;
  cw := 150;
  i := StepRow('n', 'n  (shell)', IntToStr(D^.N), x0 + 14, y, cw);
  if i <> 0 then begin D^.N := EnsureRange(D^.N + i, 1, 9); Changed; end;
  i := StepRow('l', 'l  (' + OrbitalLetters[EnsureRange(D^.L, 0, 12) + 1] + ')', IntToStr(D^.L), x0 + 14 + cw + 12, y, cw);
  if i <> 0 then begin D^.L := EnsureRange(D^.L + i, 0, 8); Changed; end;
  i := StepRow('m', 'm  (< 0 = mirrored)', Format('%s', [ PM(D^.M)]), x0 + 14 + 2 * (cw + 12), y, cw);
  if i <> 0 then begin D^.M := EnsureRange(D^.M + i, -8, 8); Changed; end;
  msg := CheckLevel(D^);
  GrpBegin('level.check', 'text');
  if msg = '' then
    Txt(fkSmallBold, Format('%s  m = %s   .   %d radial nodes   .   playable', [OrbitalName(D^.N, D^.L), PM(D^.M),
      D^.N - D^.L - 1]), x0 + 14, y + 36, cGreen)
  else
    Txt(fkSmallBold, msg, x0 + 14, y + 36, cRed);
  GrpEnd;
  { texts }
  y := 178;
  Txt(fkTiny, 'TITLE', x0 + 14, y, cFaint);
  TextField('title', x0 + 14, y + 16, 488, 28, D^.Title, 28);
  y := y + 52;
  Txt(fkTiny, 'TIP  (briefing text)', x0 + 14, y, cFaint);
  if TextField('tip', x0 + 14, y + 16, 488, 28, D^.Tip, 140) then ;
  y := y + 52;
  Txt(fkTiny, 'BADGE  (own label in front of the rules, e.g. TIME ATTACK)', x0 + 14, y, cFaint);
  t := D^.Badge;
  if TextField('badge', x0 + 14, y + 16, 488, 28, t, 20) then
  begin
    D^.Badge := UpperCase(t);
    Changed;
  end;
  { goal }
  y := 352;
  i := StepRow('target', 'QUANTA TO COLLECT', IntToStr(D^.Target), x0 + 14, y, cw);
  if i <> 0 then begin D^.Target := EnsureRange(D^.Target + i, 1, 99); Changed; end;
  i := StepRow('quanta', 'ON SCREEN', IntToStr(D^.Quanta), x0 + 14 + cw + 12, y, cw);
  if i <> 0 then begin D^.Quanta := EnsureRange(D^.Quanta + i, 1, MaxQuanta); Changed; end;
  i := StepRow('bh', 'BLACK HOLES', IntToStr(D^.BH), x0 + 14 + 2 * (cw + 12), y, cw);
  if i <> 0 then begin D^.BH := EnsureRange(D^.BH + i, 0, MaxBlackHoles); Changed; end;
  Txt(fkTiny, Format('black holes in the game:  CLASSIC 0   .   BLACK HOLE %d   .   SINGULARITY %d',
    [BlackHolesFor(gmBlackHole, Cur), BlackHolesFor(gmSingularity, Cur)]), x0 + 14, y + 34, cFaint);
  y := 418;
  v := D^.TimeSec;
  if SliderU(1, 'time', 'TIME', Format('%.0f s', [D^.TimeSec]), x0 + 14, y, 488, v, 10, 300) then
  begin
    D^.TimeSec := Round(v / 5) * 5;
    Changed;
  end;
  { rules }
  y := 468;
  Txt(fkSmallBold, 'RULES', x0 + 14, y, cDim);
  y := y + 24;
  v := D^.FlowMul;
  if SliderU(2, 'current', 'CURRENT x  (< 1 CALM, > 1 TURBO)', Format('%.1f x', [D^.FlowMul]), x0 + 14, y, 488, v, 0.3, 2.5) then
  begin
    D^.FlowMul := Round(v * 10) / 10;
    Changed;
  end;
  y := y + 44;
  v := D^.PhotonMul;
  if SliderU(3, 'photon', 'PHOTON INTERVAL x  (< 1 = PHOTON RUSH, base 12 s)', Format('%.2f x  = %.1f s', [D^.PhotonMul,
    GP.BonusEvery * D^.PhotonMul]), x0 + 14, y, 488, v, 0.2, 2) then
  begin
    D^.PhotonMul := Round(v * 20) / 20;
    Changed;
  end;
  y := y + 44;
  v := D^.DrainMul;
  if SliderU(4, 'drain', 'NODE DRAIN x  (> 1 = NODE STORM)', Format('%.1f x', [D^.DrainMul]), x0 + 14, y, 488, v, 0.5, 3) then
  begin
    D^.DrainMul := Round(v * 10) / 10;
    Changed;
  end;
  y := y + 50;
  b := D^.NoFlip;
  if Toggle('spin_lock', 'SPIN LOCKED', x0 + 14, y, 180, 30, b) then begin D^.NoFlip := b; Changed; end;
  if Btn('START UP', x0 + 206, y, 140, 30, D^.StartSpin > 0, 'spin_up') then begin D^.StartSpin := 1; Changed; end;
  if Btn('START DOWN', x0 + 352, y, 150, 30, D^.StartSpin < 0, 'spin_down') then begin D^.StartSpin := -1; Changed; end;
  { result }
  y := y + 48;
  GrpBegin('level.rules', 'text');
  Txt(fkTiny, 'RULE LINE IN THE GAME', x0 + 14, y, cFaint);
  Txt(fkSmallBold, IfThen(D^.Rule <> '', D^.Rule, 'standard rules'), x0 + 14, y + 16, cGold);
  GrpEnd;
  y := y + 48;
  if Btn('PLAY IN GAME', x0 + 14, y, 186, 32, False, 'play_level', 'P') then
  begin
    if ModifiedCount > 0 then DoSave;
    if ModifiedCount = 0 then
      LaunchGame(['--level=' + IntToStr(Cur + 1), '--mode=' + ModeIds[PMode], '--data=' + PauliDataDir]);
  end;
  if Btn('BOT IN GAME', x0 + 206, y, 160, 32, False, 'preview_game', 'V') then
  begin
    if ModifiedCount > 0 then DoSave;
    if ModifiedCount = 0 then
      LaunchGame(['--preview', '--level=' + IntToStr(Cur + 1), '--mode=' + ModeIds[PMode], '--data=' + PauliDataDir,
        '--size=1100x700']);
  end;
  if Btn('RESET', x0 + 372, y, 130, 32, False, 'reset_level') then
  begin
    LevelTable[Cur] := BuiltinLevel(Cur);
    Changed;
    Status(Format('level %d back to the built-in level (not saved yet)', [Cur + 1]));
  end;
end;

procedure DrawList;
var
  w, i, lv: Integer;
  y, h, rh: Single;
  D: TLevelDef;
  col: UInt32;
begin
  h := CHu - 104;
  PanelU('levels', 16, 64, 304, h, 'LEVELS');
  GrpBegin('levels.worlds', 'group');
  for w := 0 to WorldCount - 1 do
    if Btn(IntToStr(w + 1), 20 + w * 59.6, 92, 56, 28, w = LevWorld, 'world' + IntToStr(w + 1)) then LevWorld := w;
  GrpEnd;
  Txt(fkSmallBold, WorldNames[LevWorld], 24, 128, cOrange);
  rh := Min(78, (h - 210) / LevelsPerWorld);
  y := 152;
  GrpBegin('list.levels', 'list');
  for i := 0 to LevelsPerWorld - 1 do
  begin
    lv := LevWorld * LevelsPerWorld + i;
    D := LevelTable[lv];
    if lv = Cur then Box(20, y, 296, rh - 4, cOrange, 55)
    else if UI.Inside(U(20), U(y), U(296), U(rh - 4)) then Box(20, y, 296, rh - 4, $FFFFFF, 14);
    AddLayer('lvl' + IntToStr(lv + 1), 'row', U(20), U(y), U(296), U(rh - 4));
    if CheckLevel(D) <> '' then col := cRed else col := cText;
    Txt(fkSmallBold, Format('%d   %s  m %s', [lv + 1, OrbitalName(D.N, D.L), PM(D.M)]), 28, y + 4, col);
    Txt(fkSmall, D.Title, 28, y + 22, $C8CCD2);
    Txt(fkTiny, Format('%d quanta . %.0f s . %d holes  %s', [D.Target, D.TimeSec, D.BH, D.Rule]), 28, y + 42, cFaint);
    if Modified(lv) then Txt(fkSmallBold, '*', 310, y + 4, cGold, alRight);
    if RowHit(20, y, 296, rh - 4) then SelectLevel(lv);
    y := y + rh;
  end;
  GrpEnd;
  y := y + 8;
  if Btn('COPY', 20, y, 70, 28, False, 'copy', '') then begin Clip := LevelTable[Cur]; HasClip := True; Status('level copied'); end;
  if Btn('PASTE', 94, y, 72, 28, False, 'paste') and HasClip then
  begin
    LevelTable[Cur] := Clip;
    LevelTable[Cur].World := Cur div LevelsPerWorld;
    Changed;
  end;
  if Btn('<- SWAP', 170, y, 72, 28, False, 'swap_up') and (Cur > 0) then
  begin
    Clip := LevelTable[Cur]; LevelTable[Cur] := LevelTable[Cur - 1]; LevelTable[Cur - 1] := Clip;
    LevelTable[Cur].World := Cur div LevelsPerWorld; LevelTable[Cur - 1].World := (Cur - 1) div LevelsPerWorld;
    SelectLevel(Cur - 1);
  end;
  if Btn('SWAP ->', 246, y, 70, 28, False, 'swap_down') and (Cur < LevelCount - 1) then
  begin
    Clip := LevelTable[Cur]; LevelTable[Cur] := LevelTable[Cur + 1]; LevelTable[Cur + 1] := Clip;
    LevelTable[Cur].World := Cur div LevelsPerWorld; LevelTable[Cur + 1].World := (Cur + 1) div LevelsPerWorld;
    SelectLevel(Cur + 1);
  end;
  Txt(fkTiny, 'PgUp / PgDn = level, Ctrl+S = save', 24, y + 36, cFaint);
end;

procedure DrawHeader;
var
  x: Single;
  n: Integer;
begin
  GrpBegin('header', 'panel');
  Txt(fkBodyBold, 'PAULI SURFER 2  .  LEVEL EDITOR', 20, 12, cOrange);
  n := ModifiedCount;
  Txt(fkTiny, LevelsPath + IfThen(FileExists(LevelsPath), '', '   (new file)') +
    IfThen(n > 0, Format('   .   %d level(s) modified', [n]), '   .   saved') +
    IfThen(SavedAt <> '', '   .   last save ' + SavedAt, ''), 20, 36, IfThen(n > 0, cGold, cDim));
  GrpEnd;
  x := CWu - 16;
  x := x - 130; if Btn('RESET ALL', x, 12, 126, 32, False, 'reset_all') then
  begin
    ResetLevels;
    PNeedStart := True;
    Status('all 30 levels back to the built-in ones (not saved yet)');
  end;
  x := x - 110; if Btn('RELOAD', x, 12, 106, 32, False, 'reload') then
  begin
    DoLoad;
    Status('reloaded ' + LevelsPath);
  end;
  x := x - 120; if Btn('SAVE', x, 12, 116, 32, n > 0, 'save', 'Ctrl+S') then DoSave;
end;

procedure DrawAll;
var
  x2, w2, hb: Single;
begin
  BotTick(6);
  DrawHeader;
  DrawList;
  DrawForm;
  x2 := 860;
  w2 := CWu - x2 - 16;
  hb := 196;
  DrawPreview(x2, 64, w2, CHu - 104 - hb - 10);
  DrawBotTest(x2, CHu - 40 - hb, w2, hb);
end;

{ ---------------------------------------------------------------- keys / state / test }

procedure KeyDown(AKey: TSDL_Keycode; AMod: TSDL_Keymod);
begin
  case AKey of
    SDLK_PAGEUP, SDLK_UP: SelectLevel(Cur - 1);
    SDLK_PAGEDOWN, SDLK_DOWN: SelectLevel(Cur + 1);
    SDLK_S: if (AMod and SDL_KMOD_CTRL) <> 0 then DoSave;
    SDLK_T: if not BotActive then BotStart;
    SDLK_SPACE: PRun := not PRun;
    SDLK_P: LaunchGame(['--level=' + IntToStr(Cur + 1), '--mode=' + ModeIds[PMode], '--data=' + PauliDataDir]);
    SDLK_V: LaunchGame(['--preview', '--level=' + IntToStr(Cur + 1), '--mode=' + ModeIds[PMode], '--data=' + PauliDataDir,
      '--size=1100x700']);
  end;
end;

procedure DevState(L: TStrings);
var
  D: TLevelDef;
  m: TGameMode;
begin
  D := LevelTable[Cur];
  L.Add('#FILE');
  L.Add('levels file'#9 + LevelsPath);
  L.Add('exists'#9 + BoolToStr(FileExists(LevelsPath), 'yes', 'no (built-in levels until SAVE)'));
  L.Add('modified levels'#9 + IntToStr(ModifiedCount));
  L.Add('last save'#9 + IfThen(SavedAt <> '', SavedAt, '-'));
  L.Add(Format('#LEVEL %d  (world %d)', [Cur + 1, D.World + 1]));
  L.Add('orbital'#9 + Format('%s  n %d  l %d  m %s', [OrbitalName(D.N, D.L), D.N, D.L, PM(D.M)]));
  L.Add('check'#9 + IfThen(CheckLevel(D) = '', 'playable', CheckLevel(D)));
  L.Add('title'#9 + D.Title);
  L.Add('badge / rule'#9 + D.Badge + '  /  ' + D.Rule);
  L.Add('goal'#9 + Format('%d quanta, %d on screen, %.0f s', [D.Target, D.Quanta, D.TimeSec]));
  L.Add('black holes'#9 + Format('BH %d  SING %d', [BlackHolesFor(gmBlackHole, Cur), BlackHolesFor(gmSingularity, Cur)]));
  L.Add('rules x'#9 + Format('current %.2f  photon %.2f  drain %.2f  spin lock %s  start %s', [D.FlowMul, D.PhotonMul,
    D.DrainMul, BoolToStr(D.NoFlip, 'yes', 'no'), PM(D.StartSpin)]));
  L.Add('modified'#9 + BoolToStr(Modified(Cur), 'yes', 'no'));
  L.Add('#PREVIEW');
  L.Add('mode'#9 + ModeNames[PG.Mode] + IfThen(PRun, '  (bot running)', '  (paused)'));
  L.Add('state'#9 + Format('%s  %d / %d  score %d  time left %.1f  coherence %.2f', [IfThen(PG.State = gsPlaying, 'playing',
    IfThen(PG.State = gsWon, 'won', 'lost')), PG.Collected, PG.Def.Target, PG.Score, PG.TimeLeft, PG.Coherence]));
  L.Add('cloud'#9 + Format('%dk points  RView %.2f  sample %.0f ms  render %.1f + %.1f ms', [PreviewPoints div 1000,
    PG.RView, BuildMs, Raster.ProjectMs, Raster.DrawMs]));
  L.Add('probe'#9 + Format('(%.2f, %.2f) a0  prob %.3f  omega %.3f', [PG.PX, PG.PY, PG.ProbeProb, PG.ProbeOmega]));
  L.Add('#BOT TEST');
  L.Add('status'#9 + IfThen(BotActive, Format('running %s seed %d', [ModeNames[BotMode], BotSeed + 1]),
    IfThen(BotDone, 'done', 'idle')));
  for m := Low(TGameMode) to High(TGameMode) do
    if Bot[m].Runs > 0 then
      L.Add(ModeNames[m] + #9 + Format('%d / %d won  avg score %.0f  avg %.1f s', [Bot[m].Wins, Bot[m].Runs,
        Bot[m].ScoreSum / Bot[m].Runs, Bot[m].TimeSum / Bot[m].Runs]));
end;

function TestStep(AStep: Integer): Boolean;
var
  r: TSDL_FRect;
  n, i: Integer;
  D: TLevelDef;
begin
  Result := True;
  UTWait := 2;
  case AStep of
    0: begin
         n := 0;
         for i := 1 to 6 do if FindLayer('lvl' + IntToStr(i), r) then Inc(n);
         UTCheck(n = 6, Format('world 1: 6 level rows (%d)', [n]));
         UTCheck(FindLayer('view.preview', r) and FindLayer('panel.bottest', r) and FindLayer('panel.level', r),
           'panels level / preview / bot test');
         UTCheck(PG.Active.Count > 0, Format('preview cloud sampled: %s, %d points', [PG.Active.Name, PG.Active.Count]));
         UTWait := 30;
       end;
    1: begin
         UTCheck(PG.Elapsed > 0.1, Format('the preview bot plays (%.1f s)', [PG.Elapsed]));
         UTShot('11_level_editor');
         UTClick('world2');
       end;
    2: begin
         UTCheck(LevWorld = 1, 'world tab 2');
         UTClick('lvl7');
       end;
    3: begin
         D := LevelTable[6];
         UTCheck((Cur = 6) and (D.N = 2) and (D.M = -1), Format('level 7 selected: %s m %s "%s"', [OrbitalName(D.N, D.L), PM(D.M), D.Title]));
         UTClick('m+');
       end;
    4: begin
         UTCheck((LevelTable[6].M = 0) and (CheckLevel(LevelTable[6]) <> ''), 'm -1 -> 0 on 2p: refused (' + CheckLevel(LevelTable[6]) + ')');
         UTShot('12_not_playable');
         UTClick('n+');
       end;
    5: begin
         UTClick('m-');
       end;
    6: begin
         D := LevelTable[6];
         UTCheck((D.N = 3) and (D.L = 1) and (D.M = -1) and (CheckLevel(D) = ''), 'n + 1 and m back: 3p m -1 playable');
         UTCheck(Modified(6) and (ModifiedCount = 1), 'level 7 marked modified');
         UTClick('bh+');
         UTWait := 4;
       end;
    7: begin
         UTCheck((LevelTable[6].BH = 2) and (PG.BHCount = BlackHolesFor(PMode, 6)),
           Format('black holes 1 -> 2, preview restarted with %d holes', [PG.BHCount]));
         UTClick('spin_lock');
       end;
    8: begin
         UTCheck(LevelTable[6].NoFlip and (Pos('SPIN LOCKED UP', LevelTable[6].Rule) > 0), 'SPIN LOCKED -> rule "' + LevelTable[6].Rule + '"');
         UTClick('field.title');
       end;
    9: begin
         UTCheck(FocusKey = 'title', 'click on TITLE focuses the text field');
         UTClick('panel.preview');
       end;
    10: begin
         UTCheck(FocusKey = '', 'click outside: the field lets go');
         UTClick('test_bot');
         UTWait := 10;
       end;
    11: begin
         if BotActive then begin UTWait := 10; UTStep := 10; Exit; end;
         UTCheck(BotDone and (Bot[gmClassic].Runs = BotSeeds) and (Bot[gmSingularity].Runs = BotSeeds),
           Format('bot test finished: CLASSIC %d / BH %d / SING %d of %d', [Bot[gmClassic].Wins, Bot[gmBlackHole].Wins,
           Bot[gmSingularity].Wins, BotSeeds]));
         UTShot('13_bot_test');
         UTClick('save');
       end;
    12: begin
         UTCheck(FileExists(LevelsPath) and (ModifiedCount = 0), 'SAVE writes ' + LevelsPath);
         ResetLevels;
         LoadLevels(LevelsPath);
         D := LevelTable[6];
         UTCheck((D.N = 3) and (D.BH = 2) and D.NoFlip and (LevelTable[0].Title = BuiltinLevel(0).Title),
           'the file loads back: level 7 = 3p, 2 holes, spin locked; level 1 unchanged');
         UTClick('reset_level');
       end;
    13: begin
         UTCheck(DefText(LevelTable[6]) = DefText(BuiltinLevel(6)), 'RESET = built-in level 7 again');
         UTClick('mode.singularity');
         UTWait := 6;
       end;
    14: begin
         UTCheck((PMode = gmSingularity) and (PG.BHCount = BlackHolesFor(gmSingularity, 6)),
           Format('preview in SINGULARITY: %d holes', [PG.BHCount]));
         UTShot('14_singularity_preview');
         SDL_SetWindowSize(Win, 1000, 640);
         UTWait := 10;
       end;
    15: begin
         UTCheck(FindLayer('btn.save', r) and (r.x + r.w <= OutW + 0.5) and FindLayer('panel.bottest', r) and
           (r.x + r.w <= OutW + 0.5) and (r.y + r.h <= OutH + 0.5), Format('small window %d x %d: everything inside', [OutW, OutH]));
         UTShot('15_small_window');
         LaunchFile := ExpandFileName('tests/ed_shots/16_launched_game.png');
         if FileExists(LaunchFile) then DeleteFile(LaunchFile);
         UTCheck(LaunchGame(['--level=7', '--mode=blackhole', '--data=' + PauliDataDir, '--size=900x600', '--dev=0', '--mute',
           '--shot=' + LaunchFile, '--shot-delay=2']), 'PLAY IN GAME starts PauliSurfer2.exe (level 7)');
         LaunchT := NowS;
       end;
    16: begin
         if not FileExists(LaunchFile) and (NowS - LaunchT < 25) then begin UTWait := 10; UTStep := 15; Exit; end;
         UTCheck(FileExists(LaunchFile), Format('the launched game ran and saved its screenshot (%.1f s)', [NowS - LaunchT]));
       end;
  else
    Result := False;
  end;
end;

procedure Quit;
begin
  if Tex <> nil then SDL_DestroyTexture(Tex);
  Tex := nil;
end;

var
  d: string;
begin
  Randomize;
  d := ArgValue('data', '');
  if d <> '' then DataDirOverride := d;
  LevelsPath := DataPath(LevelsFileName);
  EdInit('PAULI SURFER 2 - LEVEL EDITOR');
  OnKey := @KeyDown;
  OnDevState := @DevState;
  OnTestStep := @TestStep;
  OnQuit := @Quit;
  PG := TPauliGame.Create;
  BG := TPauliGame.Create;
  Raster := TCloudRaster.Create;
  DoLoad;
  Cur := StrToIntDef(ArgValue('level', '1'), 1) - 1;
  Cur := EnsureRange(Cur, 0, LevelCount - 1);
  LevWorld := Cur div LevelsPerWorld;
  NowS := SDL_GetTicksNS / 1e9;
  StartPreview;
  EdRun(@DrawAll);
  Raster.Free;
  PG.Free;
  BG.Free;
  EdDone;
end.
