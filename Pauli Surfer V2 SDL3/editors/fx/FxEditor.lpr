program FxEditor;

{ PAULI SURFER 2 - EFFECT EDITOR

  Edits the graphic effects of the game: data\pauli_fx.ini (uPauliData.GFX,
  58 values in 6 groups: COLOURS, CLOUD, BLACK HOLE, QUANTA, PROBE, FLASHES).

    left     the groups, with how many values differ from the default
    middle   one row per value: slider (range from uPauliData.FxInfo), the
             default marker, RESET; colours: swatch, R G B and a #RRGGBB field
    right    LIVE SCENE drawn with the game's own formulas: a 6p cloud from
             the real renderer (cloud values apply), a black hole with
             lensing of that cloud, accretion disc, photon ring, capture ring,
             quanta of the 3 current colours, a Balmer photon, the probe with
             its trail, shield and spin arrow; buttons fire the spin-flip
             flash, the horizon flash, a pop-up and the hole's meal ring
    game     LIVE = every change is written to the file (0.3 s later) and a
             running game reloads it; PREVIEW IN GAME starts PauliSurfer2.exe
             with the bot on a black-hole level next to the editor

  Developer window: F2 (LAYERS + STATE).  --data=DIR, --ui-test=LOG. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, Math, StrUtils, SDL3, uHud, uUI, uOrbital, uRaster, uPauliData, uEdKit;

var
  FxPath, SavedAt: string;
  SavedFx: array[TFxKey] of Double;
  CurGroup: Integer = 2;               { BLACK HOLE }
  HoverKey: Integer = -1;
  LiveOn: Boolean;
  LiveDirty: Boolean;
  LiveT: Double;
  HexText: array[TFxKey] of string;
  { scene }
  Orb: TOrbital;
  Raster: TCloudRaster;
  Tex: PSDL_Texture;
  TexW, TexH: Integer;
  Cam: TCamera;
  View: TSDL_FRect;
  SceneT: Double;
  FlipFlash, HorizonFlash, MealT: Double;
  NodeTint: Boolean;
  PopT: Double = 99;
  TrailX, TrailY: array[0..MaxTrail - 1] of Double;
  TrailPos, TrailN: Integer;
  SceneMs: Double;
  UTGreen: Integer;

function GroupOf(AKey: TFxKey): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FxGroups) do
    if FxInfo[AKey].Group = FxGroups[i] then Exit(i);
  Result := 0;
end;

function ChangedFromDefault(AGroup: Integer): Integer;
var
  k: TFxKey;
begin
  Result := 0;
  for k := Low(TFxKey) to High(TFxKey) do
    if ((AGroup < 0) or (GroupOf(k) = AGroup)) and (Abs(GFX[k] - FxInfo[k].Def) > 1e-9) then Inc(Result);
end;

function ModifiedCount: Integer;
var
  k: TFxKey;
begin
  Result := 0;
  for k := Low(TFxKey) to High(TFxKey) do
    if Abs(GFX[k] - SavedFx[k]) > 1e-9 then Inc(Result);
end;

procedure RememberSaved;
var
  k: TFxKey;
begin
  for k := Low(TFxKey) to High(TFxKey) do
  begin
    SavedFx[k] := GFX[k];
    HexText[k] := '#' + IntToHex(FxC(k), 6);
  end;
end;

procedure Changed;
begin
  LiveDirty := True;
  LiveT := 0;
  ApplyCloudColours;
  if Orb <> nil then Orb.Recolour;
end;

procedure DoLoad;
begin
  LoadFx(FxPath);
  RememberSaved;
  ApplyCloudColours;
  if Orb <> nil then Orb.Recolour;
end;

procedure DoSave(AQuiet: Boolean = False);
begin
  try
    SaveFx(FxPath);
    RememberSaved;
    SavedAt := FormatDateTime('hh:nn:ss', Now);
    LiveDirty := False;
    if not AQuiet then Status('saved ' + FxPath + '  (a running game reloads it)');
  except
    on E: Exception do Status('save failed: ' + E.Message);
  end;
end;

{ ---------------------------------------------------------------- drawing primitives (as in the game) }

function FCol(ACol: UInt32; AAlpha: Single): TSDL_FColor;
begin
  Result.r := ((ACol shr 16) and $FF) / 255;
  Result.g := ((ACol shr 8) and $FF) / 255;
  Result.b := (ACol and $FF) / 255;
  Result.a := EnsureRange(AAlpha, 0, 1);
end;

procedure Disc(CX, CY, R: Single; ACol: UInt32; AAlpha: Single);
var
  v: array[0..32] of TSDL_Vertex;
  idx: array[0..95] of LongInt;
  i: Integer;
  c: TSDL_FColor;
begin
  if R < 0.5 then Exit;
  c := FCol(ACol, AAlpha);
  v[0].position.x := CX; v[0].position.y := CY; v[0].color := c;
  for i := 0 to 31 do
  begin
    v[i + 1].position.x := CX + R * Cos(2 * Pi * i / 32);
    v[i + 1].position.y := CY + R * Sin(2 * Pi * i / 32);
    v[i + 1].color := c;
    idx[3 * i] := 0; idx[3 * i + 1] := i + 1; idx[3 * i + 2] := (i + 1) mod 32 + 1;
  end;
  SDL_RenderGeometry(Ren, nil, @v[0], 33, @idx[0], 96);
end;

procedure Ring(CX, CY, R, AThick: Single; ACol: UInt32; AAlpha: Single);
var
  v: array[0..79] of TSDL_Vertex;
  idx: array[0..239] of LongInt;
  i, n: Integer;
  c: TSDL_FColor;
  a: Single;
begin
  if (R < 0.5) or (AThick <= 0) then Exit;
  n := 40;
  c := FCol(ACol, AAlpha);
  for i := 0 to n - 1 do
  begin
    a := 2 * Pi * i / n;
    v[2 * i].position.x := CX + (R - AThick / 2) * Cos(a); v[2 * i].position.y := CY + (R - AThick / 2) * Sin(a);
    v[2 * i + 1].position.x := CX + (R + AThick / 2) * Cos(a); v[2 * i + 1].position.y := CY + (R + AThick / 2) * Sin(a);
    v[2 * i].color := c; v[2 * i + 1].color := c;
    idx[6 * i] := 2 * i; idx[6 * i + 1] := 2 * i + 1; idx[6 * i + 2] := (2 * i + 2) mod (2 * n);
    idx[6 * i + 3] := 2 * i + 1; idx[6 * i + 4] := (2 * i + 3) mod (2 * n); idx[6 * i + 5] := (2 * i + 2) mod (2 * n);
  end;
  SDL_RenderGeometry(Ren, nil, @v[0], 2 * n, @idx[0], 6 * n);
end;

procedure Star(CX, CY, R: Single; ACol: UInt32; AAlpha: Single);
var
  v: array[0..10] of TSDL_Vertex;
  idx: array[0..29] of LongInt;
  i: Integer;
  c: TSDL_FColor;
  a, rr: Single;
begin
  c := FCol(ACol, AAlpha);
  v[0].position.x := CX; v[0].position.y := CY; v[0].color := c;
  for i := 0 to 9 do
  begin
    a := -Pi / 2 + Pi * i / 5;
    if Odd(i) then rr := R * 0.42 else rr := R;
    v[i + 1].position.x := CX + rr * Cos(a);
    v[i + 1].position.y := CY + rr * Sin(a);
    v[i + 1].color := c;
    idx[3 * i] := 0; idx[3 * i + 1] := i + 1; idx[3 * i + 2] := (i + 1) mod 10 + 1;
  end;
  SDL_RenderGeometry(Ren, nil, @v[0], 11, @idx[0], 30);
end;

{ game: LV(x) = HUD units -> pixels; here the scene scale }
function LV(X: Single): Single;
begin
  Result := X * View.h / 900;
end;

procedure ProjectP(X, Y, Z: Double; out SX, SY: Single);
var
  dx, dy, dz, zc, inv, k: Double;
begin
  dx := X - Cam.Pos[0]; dy := Y - Cam.Pos[1]; dz := Z - Cam.Pos[2];
  zc := Max(0.05, dx * Cam.Fwd[0] + dy * Cam.Fwd[1] + dz * Cam.Fwd[2]);
  inv := Cam.Focal / zc;
  k := View.w / Max(1, TexW);
  SX := View.x + (Cam.Cx + (dx * Cam.Right[0] + dy * Cam.Right[1] + dz * Cam.Right[2]) * inv) * k;
  SY := View.y + (Cam.Cy - (dx * Cam.Up[0] + dy * Cam.Up[1] + dz * Cam.Up[2]) * inv) * k;
end;

{ the game's lens (DrawLens): the cloud texture re-mapped on a radial mesh }
procedure DrawLens(BX, BY, RL, E: Single);
const
  NR = 14;
  NS = 48;
var
  v: array[0..(NR + 1) * NS - 1] of TSDL_Vertex;
  idx: array[0..NR * NS * 6 - 1] of LongInt;
  ir, js, k, n: Integer;
  r, rs, a, f: Single;
  c: TSDL_FColor;
begin
  if (Tex = nil) or (RL < 4) then Exit;
  c.r := 1; c.g := 1; c.b := 1; c.a := 1;
  for ir := 0 to NR do
  begin
    r := RL * (0.02 + 0.98 * ir / NR);
    f := Sqr(1 - Sqr(r / RL));
    rs := r - E * E / r * f;
    if rs < -RL then rs := -RL;
    for js := 0 to NS - 1 do
    begin
      a := 2 * Pi * js / NS;
      k := ir * NS + js;
      v[k].position.x := BX + r * Cos(a);
      v[k].position.y := BY + r * Sin(a);
      v[k].color := c;
      v[k].tex_coord.x := EnsureRange((BX + rs * Cos(a) - View.x) / Max(1, View.w), 0, 1);
      v[k].tex_coord.y := EnsureRange((BY + rs * Sin(a) - View.y) / Max(1, View.h), 0, 1);
    end;
  end;
  n := 0;
  for ir := 0 to NR - 1 do
    for js := 0 to NS - 1 do
    begin
      k := ir * NS + js;
      idx[n] := k; idx[n + 1] := ir * NS + (js + 1) mod NS; idx[n + 2] := k + NS;
      idx[n + 3] := ir * NS + (js + 1) mod NS; idx[n + 4] := (ir + 1) * NS + (js + 1) mod NS; idx[n + 5] := k + NS;
      Inc(n, 6);
    end;
  SDL_RenderGeometry(Ren, Tex, @v[0], (NR + 1) * NS, @idx[0], n);
end;

{ ---------------------------------------------------------------- live scene }

procedure DrawScene(X, Y, W, H: Single);
var
  P: TFrameParams;
  tw, th, i, k, n: Integer;
  d, f, rv, bxw, byw, rh, rc, rr, w2, ang, pa, ps: Double;
  bx, by, ax, ay, px, py, s, a, ppa, ox, oy: Single;
  col: UInt32;
  t0: QWord;
  r: TSDL_FRect;
  qs: array[0..2] of Double;
  qcol: array[0..2] of TFxKey;
begin
  t0 := SDL_GetTicksNS;
  PanelU('scene', X, Y, W, H, 'LIVE SCENE  (game formulas, 6p cloud)');
  View.x := U(X + 10); View.y := U(Y + 36); View.w := U(W - 20); View.h := U(H - 46 - 72);
  AddLayer('view.scene', 'view', View.x, View.y, View.w, View.h);
  Box(X + 10, Y + 36, W - 20, H - 118, $000000);
  SceneT := SceneT + Dt;
  FlipFlash := Max(0, FlipFlash - Dt * GFX[fxFlipDecay]);
  HorizonFlash := Max(0, HorizonFlash - Dt * GFX[fxHorizonDecay]);
  MealT := MealT + Dt;
  PopT := PopT + Dt;
  { cloud texture }
  tw := Max(64, Round(View.w * 0.6));
  th := Max(64, Round(View.h * 0.6));
  if (Tex = nil) or (tw <> TexW) or (th <> TexH) then
  begin
    if Tex <> nil then SDL_DestroyTexture(Tex);
    Tex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, tw, th);
    SDL_SetTextureScaleMode(Tex, SDL_SCALEMODE_LINEAR);
    TexW := tw; TexH := th;
    Raster.Resize(tw, th);
  end;
  rv := Orb.RView;
  LookAtOrigin(Cam, 0, -Cos(DegToRad(62)), Sin(DegToRad(62)), 40, TexW, TexH);
  d := Cam.Focal * 1.15 * rv / (0.46 * Min(TexW, TexH / Sin(DegToRad(62))));
  LookAtOrigin(Cam, 0, -d * Cos(DegToRad(62)), d * Sin(DegToRad(62)), 40, TexW, TexH);
  P.Cam := Cam;
  P.Time := SceneT;
  P.Cut := 5;
  P.Slab := rv * 0.07;
  P.SizeWorld := rv * 0.0030 * GFX[fxCloudSize];
  f := Cam.Focal * rv / d;
  P.Energy := 0.6 * GFX[fxSliceGain] * GFX[fxCloudLight] * (300000 / Orb.Count) * Sqr(f / 300);
  P.NucleusWorld := rv * 0.006 * GFX[fxNucleus];
  P.ThickPx := GFX[fxCloudThick];
  Raster.Render(Orb, P);
  SDL_UpdateTexture(Tex, nil, @Raster.Pix[0], TexW * 4);
  r := View;
  SDL_RenderTexture(Ren, Tex, nil, @r);
  ProjectP(0, 0, 0, ox, oy);
  ProjectP(1, 0, 0, ax, ay);
  ppa := Hypot(ax - ox, ay - oy);

  { black hole (DrawBlackHoles) }
  rc := 0.13 * rv;             { a grown SINGULARITY hole (the game: 0.075 .. 0.14 RView) }
  rh := 0.45 * rc;
  bxw := 0.55 * rv * Cos(SceneT * 0.15);
  byw := 0.55 * rv * Sin(SceneT * 0.15);
  ProjectP(bxw, byw, 0, bx, by);
  AddLayer('scene.blackhole', 'world', bx - rc * ppa, by - rc * ppa, 2 * rc * ppa, 2 * rc * ppa);
  DrawLens(bx, by, rc * ppa * GFX[fxLensRadius], rh * ppa * GFX[fxLensStrength]);
  Disc(bx, by, rh * ppa * GFX[fxShadowSize], $000000, GFX[fxShadowAlpha]);
  Disc(bx, by, rh * ppa * (1 + 0.42 * (GFX[fxShadowSize] - 1)), $000000, Min(1, GFX[fxShadowAlpha] * 1.8));
  Disc(bx, by, Max(4, rh * ppa), $000000, 1);
  for i := 0 to FxI(fxDiscCount) - 1 do
  begin
    rr := rh * (GFX[fxDiscInner] + GFX[fxDiscWidth] * Frac(i * 0.618034));
    w2 := 2.4 * Power(rh / rr, 1.5);
    ang := i * 2.399963 + SceneT * w2 * GFX[fxDiscSpeed];
    ProjectP(bxw + rr * Cos(ang), byw + rr * Sin(ang), 0, ax, ay);
    a := Min(1, (0.35 + 0.5 * (0.5 + 0.5 * Sin(ang))) * GFX[fxDiscAlpha]);
    if rr < rh * (GFX[fxDiscInner] + 0.55) then col := FxC(fxColDiscHot) else col := FxC(fxColDisc);
    Disc(ax, ay, Max(1.2, LV(GFX[fxDiscDot])), col, a);
  end;
  if GFX[fxRingWidth] > 0 then Ring(bx, by, Max(4, rh * ppa) * 1.08, Max(1, LV(GFX[fxRingWidth])), FxC(fxColRing), GFX[fxRingAlpha]);
  Ring(bx, by, Max(4, rh * ppa) * 1.3, 1, $FFFFFF, GFX[fxHaloAlpha]);
  n := FxI(fxCaptureDots);
  for i := 0 to n - 1 do
  begin
    ang := 2 * Pi * i / n + SceneT * GFX[fxCaptureSpin];
    ProjectP(bxw + rc * Cos(ang), byw + rc * Sin(ang), 0, ax, ay);
    Disc(ax, ay, Max(1, LV(1.6)), FxC(fxColDanger), GFX[fxCaptureAlpha]);
  end;
  if MealT < 0.8 then
    Ring(bx, by, Max(4, rh * ppa) * (1.2 + GFX[fxMealRing] * MealT / 0.8), 3, FxC(fxColDisc), 0.8 * (1 - MealT / 0.8));

  { quanta: CCW, CW, slow current }
  qs[0] := 0.30; qs[1] := 0.72; qs[2] := 0.92;
  qcol[0] := fxColCCW; qcol[1] := fxColCW; qcol[2] := fxColSlow;
  rr := Max(4, 0.065 * rv * ppa * 0.42);
  for k := 0 to 2 do
  begin
    ang := 2.2 + k * 1.9 + SceneT * 0.25 * (1 - 2 * Ord(k = 1));
    ProjectP(qs[k] * rv * Cos(ang), qs[k] * rv * Sin(ang), 0, ax, ay);
    AddLayer('scene.quantum.' + IntToStr(k), 'world', ax - rr * 2, ay - rr * 2, rr * 4, rr * 4);
    a := 1 - GFX[fxQuantumPulse] + GFX[fxQuantumPulse] * Sin(SceneT * GFX[fxQuantumPulseSpeed] + k);
    Disc(ax, ay, rr * GFX[fxQuantumGlow], FxC(qcol[k]), GFX[fxQuantumGlowAlpha]);
    Disc(ax, ay, rr * GFX[fxQuantumCore], FxC(qcol[k]), 0.9 * a);
    Disc(ax, ay, rr * GFX[fxQuantumCore] * 0.5, $FFFFFF, 0.95);
    Ring(ax, ay, rr * 1.6, 1.5, $FFFFFF, GFX[fxQuantumRingAlpha]);
  end;
  { Balmer photon }
  ProjectP(-0.5 * rv, -0.35 * rv, 0, ax, ay);
  AddLayer('scene.photon', 'world', ax - rr * 2.4, ay - rr * 2.4, rr * 4.8, rr * 4.8);
  a := 0.6 + 0.4 * Sin(SceneT * GFX[fxPhotonPulseSpeed]);
  Disc(ax, ay, rr * 2.2, FxC(fxColPhoton), GFX[fxPhotonGlowAlpha] * a);
  Star(ax, ay, rr * GFX[fxPhotonStar], FxC(fxColPhoton), 0.95);
  Ring(ax, ay, rr * 2.4, 2, FxC(fxColPhoton), 0.7 * (0.5 + 0.5 * Cos(SceneT * 0.7)));

  { probe on a circle, trail }
  pa := SceneT * 0.55;
  ps := 0.42 * rv * (1 + 0.25 * Sin(SceneT * 0.9));
  TrailX[TrailPos] := ps * Cos(pa);
  TrailY[TrailPos] := ps * Sin(pa);
  TrailPos := (TrailPos + 1) mod MaxTrail;
  TrailN := Min(MaxTrail, TrailN + 1);
  n := Min(TrailN, FxI(fxTrailLength));
  rr := Max(5, 0.03 * rv * ppa);
  for i := 0 to n - 1 do
  begin
    k := (TrailPos - 1 - i + MaxTrail) mod MaxTrail;
    ProjectP(TrailX[k], TrailY[k], 0, ax, ay);
    Disc(ax, ay, Max(1.5, rr * (1 - i / n) * GFX[fxTrailWidth]), FxC(fxColProbe), GFX[fxTrailAlpha] * (1 - i / n));
  end;
  ProjectP(ps * Cos(pa), ps * Sin(pa), 0, px, py);
  AddLayer('scene.probe', 'world', px - rr * 2.6, py - rr * 2.6, rr * 5.2, rr * 5.2);
  if NodeTint then Ring(px, py, rr * 2.4, 3, FxC(fxColDanger), 0.8 * (0.5 + 0.5 * Sin(SceneT * 18)));
  Disc(px, py, rr * GFX[fxProbeGlow], FxC(fxColProbe), GFX[fxProbeGlowAlpha]);
  Disc(px, py, rr * 1.4, FxC(fxColProbe), GFX[fxProbeMidAlpha]);
  Disc(px, py, rr * 0.8, $FFFFFF, 1);
  Ring(px, py, rr * 1.9, 2, $FFFFFF, GFX[fxProbeRingAlpha]);
  if HorizonFlash > 0 then Ring(px, py, rr * (2.8 + 0.4 * Sin(SceneT * 12)), 3, FxC(fxColPhoton), Min(1, HorizonFlash * 2));
  s := 1;
  a := GFX[fxSpinArrow];
  if a > 0.3 then
  begin
    SDL_SetRenderDrawColor(Ren, 255, 255, 255, 230);
    SDL_RenderLine(Ren, px, py - s * rr * 0.3, px, py + s * rr * a);
    SDL_RenderLine(Ren, px - rr * 0.8, py + s * rr * (a - 0.9), px, py + s * rr * a);
    SDL_RenderLine(Ren, px + rr * 0.8, py + s * rr * (a - 0.9), px, py + s * rr * a);
  end;
  { pop-up (+100) }
  if PopT < GFX[fxPopLife] * 0.9 then
  begin
    a := 1 - PopT / (GFX[fxPopLife] * 0.9);
    ProjectP(0.3 * rv * Cos(2.2), 0.3 * rv * Sin(2.2), 0, ax, ay);
    if GFX[fxPopWidth] > 0 then Ring(ax, ay, LV(20) + LV(GFX[fxPopRing]) * (1 - a), GFX[fxPopWidth], FxC(fxColSlow), a);
    Hud.Text(fkBodyBold, '+100', ax, ay - LV(40) - LV(GFX[fxPopRise]) * (1 - a), FxC(fxColSlow), alCenter, Round(255 * a));
  end;
  { screen flashes over the scene }
  if NodeTint then Hud.Rect(View.x, View.y, View.w, View.h, FxC(fxColDanger), Round(GFX[fxNodeTint]));
  if FlipFlash > 0 then Hud.Rect(View.x, View.y, View.w, View.h, $FFFFFF, Round(GFX[fxFlipFlash] * FlipFlash));
  if HorizonFlash > 0 then Hud.Rect(View.x, View.y, View.w, View.h, FxC(fxColHorizonFlash), Round(GFX[fxHorizonFlash] * HorizonFlash));
  SceneMs := (SDL_GetTicksNS - t0) / 1e6;

  { triggers }
  GrpBegin('scene.triggers', 'group');
  Txt(fkTiny, 'FIRE', X + 14, Y + H - 70, cFaint);
  w2 := (W - 28 - 4 * 6) / 5;
  if Btn('FLIP', X + 14, Y + H - 54, w2, 28, False, 'flash_flip', '1') then FlipFlash := 1;
  if Btn('HORIZON', X + 14 + (w2 + 6), Y + H - 54, w2, 28, False, 'flash_horizon', '2') then HorizonFlash := 1;
  if Btn('POP-UP', X + 14 + 2 * (w2 + 6), Y + H - 54, w2, 28, False, 'popup', '3') then PopT := 0;
  if Btn('MEAL', X + 14 + 3 * (w2 + 6), Y + H - 54, w2, 28, False, 'meal', '4') then MealT := 0;
  Toggle('node_tint', 'NODE', X + 14 + 4 * (w2 + 6), Y + H - 54, w2, 28, NodeTint);
  GrpEnd;
  Txt(fkTiny, Format('scene %.1f ms   .   the game is the reference: PREVIEW IN GAME shows every effect live', [SceneMs]),
    X + 14, Y + H - 20, cFaint);
end;

{ ---------------------------------------------------------------- parameter rows }

procedure ColorRow(K: TFxKey; X, Y, W: Single);
var
  c: UInt32;
  ch: Integer;
  v: Double;
  t: string;
  sw: Single;
  vv: Int64;
const
  ChName: array[0..2] of string = ('R', 'G', 'B');
  ChShift: array[0..2] of Integer = (16, 8, 0);
begin
  c := FxC(K);
  GrpBegin('row.' + FxInfo[K].Key, 'row');
  Box(X, Y + 2, 34, 34, c);
  Frame(X, Y + 2, 34, 34, $FFFFFF, 80);
  if c <> UInt32(Round(FxInfo[K].Def)) then Frame(X - 2, Y, 38, 38, cGold, 200);
  Txt(fkSmall, FxInfo[K].Caption, X + 44, Y, cText);
  t := HexText[K];
  if TextField(FxInfo[K].Key + '.hex', X + 44, Y + 18, 84, 22, t, 7) then
  begin
    HexText[K] := t;
    if (Length(t) = 7) and (t[1] = '#') and TryStrToInt64('$' + Copy(t, 2, 6), vv) then
    begin
      GFX[K] := vv and $FFFFFF;
      Changed;
    end;
  end;
  sw := (W - 200 - 80 - 20) / 3;
  for ch := 0 to 2 do
  begin
    v := (c shr ChShift[ch]) and $FF;
    if SliderU(600 + Ord(K) * 3 + ch, FxInfo[K].Key + '.' + LowerCase(ChName[ch]), ChName[ch], IntToStr(Round(v)),
      X + 200 + ch * (sw + 10), Y, sw, v, 0, 255) then
    begin
      c := (c and not (UInt32($FF) shl ChShift[ch])) or (UInt32(Round(v)) shl ChShift[ch]);
      GFX[K] := c;
      HexText[K] := '#' + IntToHex(c, 6);
      Changed;
    end;
  end;
  if Btn('RESET', X + W - 70, Y + 6, 66, 24, False, 'reset.' + FxInfo[K].Key) then
  begin
    GFX[K] := FxInfo[K].Def;
    HexText[K] := '#' + IntToHex(FxC(K), 6);
    Changed;
  end;
  GrpEnd;
  if FocusKey <> FxInfo[K].Key + '.hex' then HexText[K] := '#' + IntToHex(FxC(K), 6);
end;

procedure ValueRow(K: TFxKey; X, Y, W: Single);
var
  v: Double;
  dx: Single;
begin
  GrpBegin('row.' + FxInfo[K].Key, 'row');
  v := GFX[K];
  if SliderU(100 + Ord(K), FxInfo[K].Key, FxInfo[K].Caption + IfThen(FxInfo[K].Hint <> '', '   ' + FxInfo[K].Hint, ''),
    FxValueText(K), X, Y, W - 80, v, FxInfo[K].Lo, FxInfo[K].Hi) then
  begin
    if FxInfo[K].Kind = fkInt then v := Round(v);
    GFX[K] := v;
    Changed;
  end;
  { default marker }
  dx := X + (W - 80) * (FxInfo[K].Def - FxInfo[K].Lo) / Max(1e-9, FxInfo[K].Hi - FxInfo[K].Lo);
  Box(dx - 0.6, Y + 26, 1.2, 12, IfThen(Abs(GFX[K] - FxInfo[K].Def) > 1e-9, cGold, $FFFFFF), 150);
  if Btn('RESET', X + W - 70, Y + 10, 66, 24, Abs(GFX[K] - FxInfo[K].Def) > 1e-9, 'reset.' + FxInfo[K].Key) then
  begin
    GFX[K] := FxInfo[K].Def;
    Changed;
  end;
  GrpEnd;
end;

procedure DrawParams(X, Y, W, H: Single);
var
  k: TFxKey;
  yy, rh: Single;
  n: Integer;
begin
  PanelU('params', X, Y, W, H, FxGroups[CurGroup] + Format('   (%d changed from the default)', [ChangedFromDefault(CurGroup)]));
  n := 0;
  for k := Low(TFxKey) to High(TFxKey) do if GroupOf(k) = CurGroup then Inc(n);
  rh := Min(46, (H - 50) / Max(1, n));
  yy := Y + 40;
  for k := Low(TFxKey) to High(TFxKey) do
  begin
    if GroupOf(k) <> CurGroup then Continue;
    if UI.Inside(U(X), U(yy), U(W), U(rh)) then HoverKey := Ord(k);
    if FxInfo[k].Kind = fkColor then ColorRow(k, X + 14, yy, W - 28) else ValueRow(k, X + 14, yy, W - 28);
    yy := yy + rh;
  end;
end;

procedure DrawGroups;
var
  i, c: Integer;
  y: Single;
begin
  PanelU('groups', 16, 64, 300, CHu - 104, 'EFFECT GROUPS');
  y := 96;
  GrpBegin('list.groups', 'list');
  for i := 0 to High(FxGroups) do
  begin
    c := ChangedFromDefault(i);
    if Btn(FxGroups[i] + IfThen(c > 0, Format('   (%d)', [c]), ''), 24, y, 284, 34, i = CurGroup,
      'group.' + LowerCase(ReplaceStr(FxGroups[i], ' ', '_'))) then
    begin
      CurGroup := i;
      FocusKey := '';
    end;
    y := y + 40;
  end;
  GrpEnd;
  y := y + 10;
  GrpBegin('groups.info', 'text');
  Txt(fkTiny, Format('%d values . %d changed from the default', [Ord(High(TFxKey)) + 1, ChangedFromDefault(-1)]), 24, y, cDim);
  Txt(fkTiny, 'gold marker = differs from the default', 24, y + 18, cFaint);
  Txt(fkTiny, '1 2 3 4 = fire flip / horizon / pop-up / meal', 24, y + 36, cFaint);
  GrpEnd;
  y := y + 70;
  if Btn('RESET GROUP', 24, y, 284, 30, False, 'reset_group') then
  begin
    for i := 0 to Ord(High(TFxKey)) do
      if GroupOf(TFxKey(i)) = CurGroup then GFX[TFxKey(i)] := FxInfo[TFxKey(i)].Def;
    Changed;
    Status(FxGroups[CurGroup] + ' back to the defaults');
  end;
  if HoverKey >= 0 then
  begin
    GrpBegin('groups.hover', 'text');
    Txt(fkTiny, 'VALUE UNDER THE MOUSE', 24, y + 50, cFaint);
    Txt(fkSmallBold, FxInfo[TFxKey(HoverKey)].Key, 24, y + 66, cOrange);
    Txt(fkTiny, Format('[%s]  default %s  range %s .. %s', [FxInfo[TFxKey(HoverKey)].Group, DotF(FxInfo[TFxKey(HoverKey)].Def),
      DotF(FxInfo[TFxKey(HoverKey)].Lo), DotF(FxInfo[TFxKey(HoverKey)].Hi)]), 24, y + 86, cDim);
    Txt(fkTiny, FxInfo[TFxKey(HoverKey)].Hint, 24, y + 102, cDim);
    GrpEnd;
  end;
end;

procedure DrawHeader;
var
  x: Single;
  n: Integer;
begin
  GrpBegin('header', 'panel');
  Txt(fkBodyBold, 'PAULI SURFER 2  .  EFFECT EDITOR', 20, 12, cOrange);
  n := ModifiedCount;
  Txt(fkTiny, FxPath + IfThen(FileExists(FxPath), '', '   (new file)') +
    IfThen(n > 0, Format('   .   %d value(s) not saved', [n]), '   .   saved') +
    IfThen(SavedAt <> '', '   .   last save ' + SavedAt, '') + IfThen(LiveOn, '   .   LIVE: saves as you edit', ''),
    20, 36, IfThen(n > 0, cGold, cDim));
  GrpEnd;
  x := CWu - 16;
  x := x - 190; if Btn('PREVIEW IN GAME', x, 12, 186, 32, False, 'preview_game', 'G') then
  begin
    LiveOn := True;
    DoSave(True);
    LaunchGame(['--preview', '--level=17', '--mode=singularity', '--data=' + PauliDataDir, '--size=1100x700']);
    Status('game preview started; LIVE is on: every change reaches the game');
  end;
  x := x - 104; Toggle('live', 'LIVE', x, 12, 100, 32, LiveOn);
  x := x - 120; if Btn('DEFAULTS', x, 12, 116, 32, False, 'defaults') then
  begin
    DefaultFx;
    Changed;
    Status('all effects back to the defaults');
  end;
  x := x - 110; if Btn('RELOAD', x, 12, 106, 32, False, 'reload') then
  begin
    DoLoad;
    Status('reloaded ' + FxPath);
  end;
  x := x - 120; if Btn('SAVE', x, 12, 116, 32, n > 0, 'save', 'Ctrl+S') then DoSave;
end;

procedure DrawAll;
var
  x2, w2: Single;
begin
  HoverKey := -1;
  if LiveOn and LiveDirty then
  begin
    LiveT := LiveT + Dt;
    if LiveT > 0.3 then DoSave(True);
  end;
  DrawHeader;
  DrawGroups;
  DrawParams(328, 64, 560, CHu - 104);
  x2 := 900;
  w2 := CWu - x2 - 16;
  DrawScene(x2, 64, w2, CHu - 104);
end;

{ ---------------------------------------------------------------- keys / state / test }

procedure KeyDown(AKey: TSDL_Keycode; AMod: TSDL_Keymod);
begin
  case AKey of
    SDLK_S: if (AMod and SDL_KMOD_CTRL) <> 0 then DoSave;
    SDLK_1: FlipFlash := 1;
    SDLK_2: HorizonFlash := 1;
    SDLK_3: PopT := 0;
    SDLK_4: MealT := 0;
    SDLK_UP: CurGroup := Max(0, CurGroup - 1);
    SDLK_DOWN: CurGroup := Min(High(FxGroups), CurGroup + 1);
  end;
end;

procedure DevState(L: TStrings);
var
  k: TFxKey;
begin
  L.Add('#FILE');
  L.Add('effects file'#9 + FxPath);
  L.Add('exists'#9 + BoolToStr(FileExists(FxPath), 'yes', 'no (defaults until SAVE)'));
  L.Add('not saved'#9 + IntToStr(ModifiedCount));
  L.Add('changed from default'#9 + IntToStr(ChangedFromDefault(-1)) + ' of ' + IntToStr(Ord(High(TFxKey)) + 1));
  L.Add('live'#9 + BoolToStr(LiveOn, 'on (saves 0.3 s after a change)', 'off'));
  L.Add('last save'#9 + IfThen(SavedAt <> '', SavedAt, '-'));
  L.Add('#GROUP ' + FxGroups[CurGroup]);
  for k := Low(TFxKey) to High(TFxKey) do
    if GroupOf(k) = CurGroup then
      L.Add(FxInfo[k].Key + #9 + FxValueText(k) + IfThen(Abs(GFX[k] - FxInfo[k].Def) > 1e-9, '   (default ' +
        IfThen(FxInfo[k].Kind = fkColor, '#' + IntToHex(Round(FxInfo[k].Def), 6), DotF(FxInfo[k].Def)) + ')', ''));
  L.Add('#SCENE');
  L.Add('cloud'#9 + Format('%s  %dk points  RView %.1f a0', [Orb.Name, Orb.Count div 1000, Orb.RView]));
  L.Add('time'#9 + Format('%.1f ms per frame (cloud %.1f + %.1f ms)', [SceneMs, Raster.ProjectMs, Raster.DrawMs]));
  L.Add('flashes'#9 + Format('flip %.2f  horizon %.2f  node %s', [FlipFlash, HorizonFlash, BoolToStr(NodeTint, 'on', 'off')]));
end;

function TestStep(AStep: Integer): Boolean;
var
  r: TSDL_FRect;
  n: Integer;
  k: TFxKey;
  ok: Boolean;
begin
  Result := True;
  UTWait := 2;
  case AStep of
    0: begin
         UTCheck(FindLayer('panel.groups', r) and FindLayer('panel.params', r) and FindLayer('view.scene', r),
           'panels groups / params / scene');
         n := 0;
         for k := Low(TFxKey) to High(TFxKey) do if FindLayer('slider.' + FxInfo[k].Key, r) then Inc(n);
         UTCheck(n = 17, Format('BLACK HOLE group: 17 sliders (%d)', [n]));
         UTCheck(FindLayer('scene.blackhole', r) and FindLayer('scene.probe', r) and FindLayer('scene.photon', r),
           'scene: black hole, probe, photon');
         UTShot('21_fx_editor');
         UTClick('slider.lens_strength');
       end;
    1: begin
         UTCheck(Abs(GFX[fxLensStrength] - 3) < 0.05, Format('lens strength slider centre = 3.0 (%.2f)', [GFX[fxLensStrength]]));
         UTCheck(ModifiedCount = 1, 'one value not saved');
         UTClick('reset.lens_strength');
       end;
    2: begin
         UTCheck(Abs(GFX[fxLensStrength] - 2.4) < 1e-9, 'RESET -> default 2.4');
         UTClick('slider.disc_count');
       end;
    3: begin
         UTCheck(FxI(fxDiscCount) = 150, Format('disc particles centre = 150 (%d), integer', [FxI(fxDiscCount)]));
         UTCheck(Frac(GFX[fxDiscCount]) = 0, 'integer value stays integer');
         UTClick('flash_horizon');
         UTWait := 3;
       end;
    4: begin
         UTCheck(HorizonFlash > 0.5, Format('HORIZON fires the flash (%.2f)', [HorizonFlash]));
         UTShot('22_horizon_flash');
         UTClick('group.colours');
         UTWait := 20;
       end;
    5: begin
         n := 0;
         for k := Low(TFxKey) to High(TFxKey) do if FindLayer('row.' + FxInfo[k].Key, r) then Inc(n);
         UTCheck(n = 13, Format('COLOURS: 13 colour rows (%d)', [n]));
         UTClick('slider.col_ccw.g');
       end;
    6: begin
         UTGreen := (FxC(fxColCCW) shr 8) and $FF;
         UTCheck(Abs(UTGreen - 127.5) <= 1, Format('G slider centre: CCW green %d -> %s', [UTGreen, FxValueText(fxColCCW)]));
         UTCheck(HexText[fxColCCW] = '#' + IntToHex(FxC(fxColCCW), 6), 'hex field follows the slider: ' + HexText[fxColCCW]);
         UTShot('23_colours');
         UTClick('save');
       end;
    7: begin
         UTCheck(FileExists(FxPath) and (ModifiedCount = 0), 'SAVE writes ' + FxPath);
         DefaultFx;
         LoadFx(FxPath);
         UTCheck(((FxC(fxColCCW) shr 8) and $FF = UTGreen) and (FxI(fxDiscCount) = 150), 'the file loads back (colour + disc count)');
         RememberSaved;
         UTClick('defaults');
       end;
    8: begin
         ok := True;
         for k := Low(TFxKey) to High(TFxKey) do if GFX[k] <> FxInfo[k].Def then ok := False;
         UTCheck(ok and (ModifiedCount = 2), 'DEFAULTS: every value = default (2 not saved)');
         UTClick('group.flashes');
         UTWait := 4;
       end;
    9: begin
         UTClick('node_tint');
         UTWait := 4;
       end;
    10: begin
         UTCheck(NodeTint, 'IN NODE tint on');
         UTClick('popup');
         UTWait := 8;
       end;
    11: begin
         UTShot('24_flashes');
         SDL_SetWindowSize(Win, 1000, 640);
         UTWait := 10;
       end;
    12: begin
         UTCheck(FindLayer('btn.preview_game', r) and (r.x + r.w <= OutW + 0.5) and FindLayer('panel.scene', r) and
           (r.x + r.w <= OutW + 0.5), Format('small window %d x %d: everything inside', [OutW, OutH]));
         UTShot('25_small_window');
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
  d := ArgValue('data', '');
  if d <> '' then DataDirOverride := d;
  FxPath := DataPath(FxFileName);
  EdInit('PAULI SURFER 2 - EFFECT EDITOR');
  OnKey := @KeyDown;
  OnDevState := @DevState;
  OnTestStep := @TestStep;
  OnQuit := @Quit;
  Orb := TOrbital.Create;
  DoLoad;
  RandSeed := 4242;
  Orb.Build(6, 1, 1, 150000, 1);
  Raster := TCloudRaster.Create;
  EdRun(@DrawAll);
  if LiveOn and LiveDirty then DoSave(True);
  Raster.Free;
  Orb.Free;
  EdDone;
end.
