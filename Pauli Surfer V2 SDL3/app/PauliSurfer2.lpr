program PauliSurfer2;

{ PAULI SURFER 2 - a game on the hydrogen probability current (SDL3 + Lazarus).

  VERSION 2: black holes. Three modes: CLASSIC (version 1), BLACK HOLE (1-3 holes
  per orbital) and SINGULARITY (2-5 hungry holes that grow). A hole pulls the
  probe (no escape inside the dashed ring), costs coherence at the horizon and
  throws the probe out (Hawking ejection), drifts with the current, eats quanta;
  pickups at its edge score x2. Holes are drawn with gravitational lensing of
  the cloud (the cloud texture re-mapped on a radial mesh), a photon ring and
  an accretion disc.


  You steer a probe through the equatorial slice of a hydrogen eigenstate.
  The cloud is the real |psi|^2 sample of HydrogenFlow (uOrbital, uRaster),
  coloured by the Pauli current: orange = counterclockwise, blue = clockwise,
  white = slow. The current carries the probe and the quanta; radial nodes
  (|psi|^2 = 0) drain coherence; SPACE flips the electron spin, which flips
  the magnetisation current and moves the bands.

  6 levels: 2p, 3p, 3d (m=2), 4f (m=3), 5s (spin current only), 6p (the
  picture: n = 6, l = 1, m = +1). Sound: SFX Studio engine (uSfxEngine).

  Keys: WASD / arrows or hold the mouse = thrust, SPACE / right click = flip
  spin, P / Esc = pause, V = view (slice / half / full), M = mute, F12 = PNG,
  mouse wheel or + / - = zoom the cloud, [ / ] = HUD size (wide windows).

  SUPER BOT DEMO (title button / B / --demo): the bot plays SINGULARITY, the
  hardest mode, level 1 to 6 by itself (briefing, play, result and the next
  level advance automatically, a lost level is retried). It plays through the
  same input path as a person - left mouse held at a screen point or W A S D,
  SPACE to flip the spin - and the screen shows a keyboard and a mouse with the
  keys / buttons it presses, the cursor where it clicks, and an input log.
  Player progress is not touched. --demo-exit quits when all 6 are done,
  --demo-log=FILE writes one line per level.

  Developer: F2 opens a separate DEVELOPER window (every HUD / world part by
  name with its rectangle, layout + camera numbers, game state, black holes,
  quanta, timings, EXPORT LAYOUT -> exports/layout.json + .md); F3 draws dashed
  outlines of all named layers on the game window, F4 toggles their labels.

  Layout: a window wider than tall uses the WIDE layout (HUD in two side
  columns, 1600 x 900 canvas, larger text, the cloud sized to the space
  between them); a tall window uses the portrait layout of version 1. Menus
  are drawn on an enlarged centre canvas in wide windows.

  Command line: --mode=classic|blackhole|singularity
                --level=N (1..6) --bot --points=N --scale=F --size=WxH --mute
                --progress=FILE --shot=F.png --shot-delay=S --ui-test=LOG --ui-shots=DIR }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, Math, StrUtils, IniFiles, SDL3, SDL3_image, uHud, uUI, uOrbital, uRaster, uPauliGame,
  uSfxEngine, uSfxGen, uPauliData;

const
  VW = 900;
  VH = 1600;
  cOrange = $FF8C1A;
  cBlue = $3A6BFF;
  cWhite = $EEF0F6;
  cGold = $FFD24A;
  cText = $E8E8E8;
  cDim = $9AA0A8;
  cFaint = $5E6570;
  cRed = $FF3B3B;
  cCyan = $6FE6FF;
  ViewNames: array[0..2] of string = ('SLICE z = 0', 'HALF', 'FULL CLOUD');

type
  TScreen = (scTitle, scLevels, scHelp, scBriefing, scPlaying, scPaused, scResult);
  TVoice = record
    Active, Loop: Boolean;
    Id: TSoundId;
    Pos: Integer;
    Gain: Single;
  end;

  TFx = record
    T, Life: Double;
    X, Y: Single;               { screen pixels }
    Col: UInt32;
    Text: string;
  end;

var
  Win: PSDL_Window;
  Ren: PSDL_Renderer;
  Hud: THud;                     { current HUD font set (HudMain or HudMenu) }
  HudMain, HudMenu, HudLbl: THud;  { game HUD, menus, outline labels: separate font scales, no reload per frame }
  UI: TUI;
  G: TPauliGame;
  Raster: TCloudRaster;
  Inset: TInsetRaster;
  Tex, InsetTex: PSDL_Texture;
  TexW, TexH, InsetSz, OutW, OutH, WinW, WinH: Integer;
  K, OX, OY: Single;
  YShift, CW: Single;            { canvas: y origin shift (overlays) and width in canvas units }
  CamDist, CamShift: Double;     { cloud camera distance (a.u.) and vertical image shift (texture px) }
  FpsAvg: Double;
  IsWide: Boolean;               { window wider than tall -> side-column layout }
  ZoomF: Double = 1;             { cloud zoom (wheel, + / -) }
  HudScale: Double = 0.575;      { HUD size ([ / ]); 0.575 = compact HUD (half of v2.0 + 15 %), big cloud }
  CH: Single;                    { wide canvas height in canvas units (bottom anchor) }
  Cam: TCamera;
  Screen: TScreen;
  CurLevel, PendingLevel, ViewMode, Points: Integer;
  PendingScreen: TScreen;
  RenderScale: Double;
  Running, BotOn, AttractMode, Muted: Boolean;
  NowS, ScreenT, FlipFlash, NodeGlow, InsetAz: Double;
  StatusMsg: string;
  StatusT: Double;
  { progress }
  BestScore, BestStars: array[TGameMode, 0..LevelCount - 1] of Integer;
  Unlocked: array[TGameMode] of Integer;
  CurMode: TGameMode = gmBlackHole;
  LevWorld: Integer;             { world page shown on the level select screen }
  HorizonFlash, BHGlow: Double;
  ProgressPath: string;
  NewBest: Boolean;
  { input }
  KeyL, KeyR, KeyU, KeyD, FlipReq: Boolean;
  MouseDownL: Boolean;
  MouseX, MouseY: Single;
  { effects }
  Fx: array[0..31] of TFx;
  TrailX, TrailY: array[0..MaxTrail - 1] of Double;
  TrailPos, TrailN: Integer;
  { audio }
  Stream: PSDL_AudioStream;
  Snd: array[TSoundId] of TSoundBuf;
  Voices: array[0..15] of TVoice;
  MixF: array of Single;
  MixS: array of SmallInt;
  AudioError: string;
  SoundCount: Integer;
  FrameCount: Integer;
  FrameTime: Double;
  { cli / test }
  ShotFile, UITestLog, UIShotDir: string;
  ShotDelay: Double;
  CliLevel: Integer;
  CliMode: string;
  CliDemo: Boolean;              { --demo: start the SUPER BOT DEMO at launch }
  DevAuto: Boolean = True;       { open the developer window at start (--dev=0: no) }
  DevArg: Boolean;               { --dev given explicitly }
  PreviewMode: Boolean;          { --preview: the bot plays one level again and again (editor preview) }
  PreviewT, ReloadT: Double;
  StampSounds, StampLevels, StampFx: Int64;
  ReloadMsg: string;             { last hot reload (developer window) }

function Pick(ACond: Boolean; A, B: UInt32): UInt32; inline;
begin
  if ACond then Result := A else Result := B;
end;

function SDLErr: string;
begin
  Result := StrPas(SDL_GetError);
end;

function ExeDir: string;
begin
  Result := ExtractFilePath(ExpandFileName(ParamStr(0)));
end;

procedure Flash(const S: string);
begin
  StatusMsg := S;
  StatusT := 3;
end;

{ ---------------------------------------------------------------- virtual canvas 900 x 1600 }

function XV(X: Single): Single; inline;
begin
  Result := OX + X * K;
end;

function YV(Y: Single): Single; inline;
begin
  Result := OY + (Y - YShift) * K;
end;

function LV(L: Single): Single; inline;
begin
  Result := L * K;
end;

{ portrait canvas 900 x 1600 (version 1 layout) }
procedure UsePortrait;
begin
  Hud := HudMain;
  K := Min(OutW / VW, OutH / VH);
  OX := (OutW - VW * K) / 2;
  OY := (OutH - VH * K) / 2;
  YShift := 0;
  CW := VW;
  Hud.SetScale(K * 1.75);
end;

{ wide canvas: 900 units high, as wide as the window; text 1.3 x, HUD size [ / ] }
procedure UseWide;
begin
  Hud := HudMain;
  K := OutH / 900 * HudScale;
  OX := 0;
  OY := 0;
  YShift := 0;
  CW := OutW / K;
  CH := OutH / K;
  Hud.SetScale(K * 1.3);
end;

{ menus / overlays: the portrait canvas rows 280 .. 1360 scaled to the window
  height, so in a wide window they are about 1.5 x larger }
procedure UseOverlay;
begin
  Hud := HudMenu;
  K := Min(OutW / VW, OutH / 1080);
  OX := (OutW - VW * K) / 2;
  OY := (OutH - 1080 * K) / 2;
  YShift := 280;
  CW := VW;
  Hud.SetScale(K * 1.75);
end;

{ one HUD layout at every window size: blocks anchored to the corners, sized by
  the window height (so they keep their place and proportions when the window
  is resized); the version-1 portrait layout is no longer used in game }
procedure SetView;
begin
  IsWide := True;
  UseWide;
end;

{ ---------------------------------------------------------------- named layers

  Every part of the screen registers a named rectangle (output pixels) each
  frame: groups collect what TextV / RectV / BtnV draw between GrpBegin and
  GrpEnd, world objects add theirs directly. Used by the developer window
  (F2), the dashed outlines (F3) and EXPORT LAYOUT. }

type
  TLayer = record
    Name, Kind: string;
    R: TSDL_FRect;
  end;

var
  Layers: array[0..299] of TLayer;
  LayerN: Integer;
  GrpIdx: Integer = -1;
  ShowOutlines: Boolean;
  ShowLabels: Boolean = True;
  HoverLayer, PinnedLayer: string;

procedure LayersReset;
begin
  LayerN := 0;
  GrpIdx := -1;
end;

function AddLayer(const AName, AKind: string; X, Y, W, H: Single): Integer;
begin
  Result := -1;
  if LayerN > High(Layers) then Exit;
  Layers[LayerN].Name := AName;
  Layers[LayerN].Kind := AKind;
  Layers[LayerN].R.x := X; Layers[LayerN].R.y := Y; Layers[LayerN].R.w := W; Layers[LayerN].R.h := H;
  Result := LayerN;
  Inc(LayerN);
end;

procedure Extend(AX, AY, AW, AH: Single);
var
  x1, y1: Single;
  r: ^TSDL_FRect;
begin
  if (GrpIdx < 0) or (AW <= 0) or (AH <= 0) then Exit;
  r := @Layers[GrpIdx].R;
  if r^.w < 0 then
  begin
    r^.x := AX; r^.y := AY; r^.w := AW; r^.h := AH;
  end
  else
  begin
    x1 := Max(r^.x + r^.w, AX + AW);
    y1 := Max(r^.y + r^.h, AY + AH);
    r^.x := Min(r^.x, AX);
    r^.y := Min(r^.y, AY);
    r^.w := x1 - r^.x;
    r^.h := y1 - r^.y;
  end;
end;

procedure GrpBegin(const AName, AKind: string);
begin
  GrpIdx := AddLayer(AName, AKind, 0, 0, -1, -1);
end;

procedure GrpEnd;
begin
  { an empty group is dropped }
  if (GrpIdx >= 0) and (GrpIdx = LayerN - 1) and (Layers[GrpIdx].R.w < 0) then Dec(LayerN);
  GrpIdx := -1;
end;

function FindLayer(const AName: string; out R: TSDL_FRect): Boolean;
var
  i: Integer;
begin
  for i := 0 to LayerN - 1 do
    if (Layers[i].Name = AName) and (Layers[i].R.w >= 0) then
    begin
      R := Layers[i].R;
      Exit(True);
    end;
  Result := False;
end;

function TextV(AKind: TFontKind; const S: string; X, Y: Single; ACol: UInt32; AAlign: TAlign = alLeft;
  AAlpha: Byte = 255): Single;
var
  w, px: Single;
begin
  w := Hud.Text(AKind, S, XV(X), YV(Y), ACol, AAlign, AAlpha);
  px := XV(X);
  if AAlign = alRight then px := px - w
  else if AAlign = alCenter then px := px - w / 2;
  Extend(px, YV(Y), w, Hud.LineHeight(AKind));
  Result := w / K;
end;

procedure RectV(X, Y, W, H: Single; ACol: UInt32; AAlpha: Byte = 255);
begin
  Hud.Rect(XV(X), YV(Y), LV(W), LV(H), ACol, AAlpha);
  Extend(XV(X), YV(Y), LV(W), LV(H));
end;

{ ---------------------------------------------------------------- seamless buttons

  No solid panel: a faint veil, a thin outline and the caption sit directly on
  the game; the keyboard shortcut is shown as a small key chip next to the
  caption (AHint). Rectangles are kept by key for --ui-test (FindBtn). }

var
  BtnKeys: array of string;
  BtnRects: array of TSDL_FRect;

procedure RegBtn(const AName: string; const R: TSDL_FRect);
var
  i: Integer;
begin
  for i := 0 to High(BtnKeys) do
    if BtnKeys[i] = AName then
    begin
      BtnRects[i] := R;
      Exit;
    end;
  SetLength(BtnKeys, Length(BtnKeys) + 1);
  SetLength(BtnRects, Length(BtnRects) + 1);
  BtnKeys[High(BtnKeys)] := AName;
  BtnRects[High(BtnRects)] := R;
end;

function FindBtn(const AName: string; out R: TSDL_FRect): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(BtnKeys) do
    if BtnKeys[i] = AName then
    begin
      R := BtnRects[i];
      Exit(True);
    end;
  Result := False;
end;

procedure FramePx(X, Y, W, H, T: Single; ACol: UInt32; AAlpha: Byte);
begin
  Hud.Rect(X, Y, W, T, ACol, AAlpha);
  Hud.Rect(X, Y + H - T, W, T, ACol, AAlpha);
  Hud.Rect(X, Y + T, T, H - 2 * T, ACol, AAlpha);
  Hud.Rect(X + W - T, Y + T, T, H - 2 * T, ACol, AAlpha);
end;

function BtnV(const ACaption: string; X, Y, W, H: Single; ASel: Boolean = False; const AKey: string = '';
  const AHint: string = ''): Boolean;
var
  r: TSDL_FRect;
  hot: Boolean;
  px, py, pw, ph, wc, wk, gap, th, tx, kx, ky, kh, t: Single;
  fg, edge: UInt32;
  ea: Byte;
begin
  px := XV(X); py := YV(Y); pw := LV(W); ph := LV(H);
  r.x := px; r.y := py; r.w := pw; r.h := ph;
  if AKey <> '' then RegBtn(AKey, r) else RegBtn(ACaption, r);
  AddLayer('btn.' + IfThen(AKey <> '', AKey, LowerCase(ACaption)), 'button', px, py, pw, ph);
  Extend(px, py, pw, ph);
  hot := (UI.Active = 0) and UI.Inside(px, py, pw, ph);
  t := Max(1, LV(1.5));
  if ASel then
  begin
    Hud.Rect(px, py, pw, ph, cOrange, 55);
    fg := $FFB45A; edge := cOrange; ea := 230;
  end
  else
  begin
    Hud.Rect(px, py, pw, ph, $000000, 60);
    fg := cText; edge := $FFFFFF; ea := 70;
  end;
  if hot then
  begin
    Hud.Rect(px, py, pw, ph, $FFFFFF, 24);
    edge := cOrange; ea := 255;
    if not ASel then fg := $FFFFFF;
  end;
  FramePx(px, py, pw, ph, t, edge, ea);
  th := Hud.LineHeight(fkSmallBold);
  wc := Hud.TextWidth(fkSmallBold, ACaption);
  if AHint <> '' then wk := Hud.TextWidth(fkTiny, AHint) + LV(16) else wk := 0;
  if (wk > 0) and (wc > 0) then gap := LV(14) else gap := 0;
  tx := px + (pw - (wc + gap + wk)) / 2;
  if wc > 0 then Hud.Text(fkSmallBold, ACaption, tx, py + (ph - th) / 2 + th * 0.05, fg);
  if wk > 0 then
  begin
    kh := Hud.LineHeight(fkTiny) + LV(8);
    kx := tx + wc + gap;
    ky := py + (ph - kh) / 2;
    Hud.Rect(kx, ky, wk, kh, $FFFFFF, 20);
    FramePx(kx, ky, wk, kh, Max(1, LV(1)), $FFFFFF, 110);
    Hud.Text(fkTiny, AHint, kx + LV(8), ky + LV(4), cGold);
  end;
  Result := hot and UI.Pressed;
end;

{ filled disc / ring with alpha, pixel coordinates }
procedure Disc(CX, CY, R: Single; ACol: UInt32; AAlpha: Single);
var
  v: array[0..32] of TSDL_Vertex;
  idx: array[0..95] of LongInt;
  i: Integer;
  c: TSDL_FColor;
begin
  if R < 0.5 then Exit;
  c.r := ((ACol shr 16) and $FF) / 255; c.g := ((ACol shr 8) and $FF) / 255; c.b := (ACol and $FF) / 255; c.a := AAlpha;
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
  if R < 0.5 then Exit;
  n := 40;
  c.r := ((ACol shr 16) and $FF) / 255; c.g := ((ACol shr 8) and $FF) / 255; c.b := (ACol and $FF) / 255; c.a := AAlpha;
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
  c.r := ((ACol shr 16) and $FF) / 255; c.g := ((ACol shr 8) and $FF) / 255; c.b := (ACol and $FF) / 255; c.a := AAlpha;
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

{ ---------------------------------------------------------------- progress }

procedure LoadProgress;
var
  ini: TMemIniFile;
  i: Integer;
  m: TGameMode;
begin
  for m := Low(TGameMode) to High(TGameMode) do
  begin
    Unlocked[m] := 1;
    for i := 0 to LevelCount - 1 do begin BestScore[m, i] := 0; BestStars[m, i] := 0; end;
  end;
  if not FileExists(ProgressPath) then Exit;
  ini := TMemIniFile.Create(ProgressPath);
  try
    CurMode := TGameMode(EnsureRange(ini.ReadInteger('game', 'mode', Ord(gmBlackHole)), 0, Ord(High(TGameMode))));
    ZoomF := EnsureRange(StrToFloatDef(ini.ReadString('view', 'zoom', '1'), 1, SfxFS), 0.7, 1.5);
    HudScale := EnsureRange(StrToFloatDef(ini.ReadString('view', 'hud_size', '0.575'), 0.575, SfxFS), 0.3, 1.5);
    for m := Low(TGameMode) to High(TGameMode) do
    begin
      Unlocked[m] := EnsureRange(ini.ReadInteger(ModeIds[m], 'unlocked', 1), 1, LevelCount);
      for i := 0 to LevelCount - 1 do
      begin
        BestScore[m, i] := ini.ReadInteger(ModeIds[m] + '.level' + IntToStr(i + 1), 'best', 0);
        BestStars[m, i] := ini.ReadInteger(ModeIds[m] + '.level' + IntToStr(i + 1), 'stars', 0);
      end;
    end;
  finally
    ini.Free;
  end;
end;

procedure SaveProgress;
var
  ini: TMemIniFile;
  i: Integer;
  m: TGameMode;
begin
  try
    ini := TMemIniFile.Create(ProgressPath);
    try
      ini.WriteInteger('game', 'mode', Ord(CurMode));
      ini.WriteString('view', 'zoom', FloatToStrF(ZoomF, ffFixed, 6, 3, SfxFS));
      ini.WriteString('view', 'hud_size', FloatToStrF(HudScale, ffFixed, 6, 3, SfxFS));
      for m := Low(TGameMode) to High(TGameMode) do
      begin
        ini.WriteInteger(ModeIds[m], 'unlocked', Unlocked[m]);
        for i := 0 to LevelCount - 1 do
        begin
          ini.WriteInteger(ModeIds[m] + '.level' + IntToStr(i + 1), 'best', BestScore[m, i]);
          ini.WriteInteger(ModeIds[m] + '.level' + IntToStr(i + 1), 'stars', BestStars[m, i]);
        end;
      end;
      ini.UpdateFile;
    finally
      ini.Free;
    end;
  except
    on E: Exception do Flash('progress not saved: ' + E.Message);
  end;
end;

{ ---------------------------------------------------------------- audio }

procedure BuildSounds;
var
  id: TSoundId;
  v: Integer;
begin
  for v := 0 to High(Voices) do Voices[v].Active := False;
  for id := Low(TSoundId) to High(TSoundId) do RenderSound(id, Snd[id]);
end;

procedure PlaySound(AId: TSoundId; AGain: Single = 1);
var
  i: Integer;
begin
  if Snd[AId].Frames = 0 then Exit;
  for i := 3 to High(Voices) do                { 0..2 = loops }
    if not Voices[i].Active then
    begin
      Voices[i].Active := True;
      Voices[i].Loop := False;
      Voices[i].Id := AId;
      Voices[i].Pos := 0;
      Voices[i].Gain := AGain;
      Inc(SoundCount);
      Exit;
    end;
end;

procedure SetLoop(AVoice: Integer; AId: TSoundId; AGain: Single);
begin
  if not Voices[AVoice].Active then
  begin
    Voices[AVoice].Active := True;
    Voices[AVoice].Loop := True;
    Voices[AVoice].Id := AId;
    Voices[AVoice].Pos := 0;
  end;
  Voices[AVoice].Gain := AGain;
end;

procedure PumpAudio(ADt: Double);
var
  need, n, i, v, f, idx: Integer;
  g, x: Single;
begin
  if Stream <> nil then need := Round(0.07 * SfxRate) - SDL_GetAudioStreamQueued(Stream) div 4
  else need := Round(ADt * SfxRate);
  while need > 0 do
  begin
    n := Min(need, 1024);
    if Length(MixF) < 2 * n then begin SetLength(MixF, 2 * n); SetLength(MixS, 2 * n); end;
    FillChar(MixF[0], 2 * n * SizeOf(Single), 0);
    for v := 0 to High(Voices) do
      with Voices[v] do
      begin
        if not Active then Continue;
        g := Gain;
        for f := 0 to n - 1 do
        begin
          if Pos >= Snd[Id].Frames then
          begin
            if Loop then Pos := 0
            else
            begin
              Active := False;
              Break;
            end;
          end;
          idx := 2 * Pos;
          MixF[2 * f] := MixF[2 * f] + Snd[Id].Data[idx] * g;
          MixF[2 * f + 1] := MixF[2 * f + 1] + Snd[Id].Data[idx + 1] * g;
          Inc(Pos);
        end;
      end;
    for i := 0 to 2 * n - 1 do
    begin
      x := MixF[i];
      if Muted then x := 0;
      if x > 1 then x := 1 else if x < -1 then x := -1;
      MixS[i] := Round(x * 32000);
    end;
    if Stream <> nil then SDL_PutAudioStreamData(Stream, @MixS[0], n * 4);
    Dec(need, n);
  end;
end;

{ ---------------------------------------------------------------- effects }

procedure AddFx(X, Y: Single; ACol: UInt32; const AText: string; ALife: Double = 0.9);
var
  i, oldest: Integer;
begin
  oldest := 0;
  for i := 0 to High(Fx) do
  begin
    if Fx[i].T >= Fx[i].Life then begin oldest := i; Break; end;
    if Fx[i].T > Fx[oldest].T then oldest := i;
  end;
  Fx[oldest].T := 0;
  Fx[oldest].Life := ALife * GFX[fxPopLife];
  Fx[oldest].X := X;
  Fx[oldest].Y := Y;
  Fx[oldest].Col := ACol;
  Fx[oldest].Text := AText;
end;

{ ---------------------------------------------------------------- camera / projection }

procedure CamPos(AAz, AEl, ADist: Double; out X, Y, Z: Double);
begin
  X := ADist * Cos(DegToRad(AEl)) * Cos(DegToRad(AAz));
  Y := ADist * Cos(DegToRad(AEl)) * Sin(DegToRad(AAz));
  Z := ADist * Sin(DegToRad(AEl));
end;

{ world point -> output pixels }
function Project(X, Y, Z: Double; out SXp, SYp: Single): Boolean;
var
  dx, dy, dz, zc, inv, k2: Double;
begin
  dx := X - Cam.Pos[0]; dy := Y - Cam.Pos[1]; dz := Z - Cam.Pos[2];
  zc := dx * Cam.Fwd[0] + dy * Cam.Fwd[1] + dz * Cam.Fwd[2];
  Result := zc > 0.05;
  if not Result then begin SXp := 0; SYp := 0; Exit; end;
  inv := Cam.Focal / zc;
  k2 := OutW / Max(1, TexW);
  SXp := (Cam.Cx + (dx * Cam.Right[0] + dy * Cam.Right[1] + dz * Cam.Right[2]) * inv) * k2;
  SYp := (Cam.Cy - (dx * Cam.Up[0] + dy * Cam.Up[1] + dz * Cam.Up[2]) * inv) * k2;
end;

{ pixels per a.u. at the origin }
function PixPerAU: Double;
var
  a, b, c, d: Single;
begin
  Project(0, 0, 0, a, b);
  Project(1, 0, 0, c, d);
  Result := Hypot(c - a, d - b);
end;

{ screen direction (dx right, dy up) -> plane direction }
procedure ScreenToPlane(DX, DY: Double; out PXd, PYd: Double);
var
  rx, ry, ux, uy, n, det, a, b: Double;
begin
  { plane vectors whose images are screen-right and screen-up }
  rx := Cam.Right[0]; ry := Cam.Right[1];
  ux := Cam.Up[0]; uy := Cam.Up[1];
  n := Hypot(rx, ry); if n > 0 then begin rx := rx / n; ry := ry / n; end;
  n := Hypot(ux, uy); if n > 0 then begin ux := ux / n; uy := uy / n; end;
  det := rx * uy - ry * ux;
  if Abs(det) < 1e-6 then begin PXd := DX; PYd := DY; Exit; end;
  a := DX; b := DY;
  PXd := a * rx + b * ux;
  PYd := a * ry + b * uy;
end;

{ ---------------------------------------------------------------- rendering }

procedure EnsureTextures;
var
  w, h, s: Integer;
begin
  SDL_GetCurrentRenderOutputSize(Ren, @OutW, @OutH);
  SDL_GetWindowSize(Win, @WinW, @WinH);
  w := Max(16, Round(OutW * RenderScale));
  h := Max(16, Round(OutH * RenderScale));
  if (Tex = nil) or (w <> TexW) or (h <> TexH) then
  begin
    if Tex <> nil then SDL_DestroyTexture(Tex);
    Tex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);
    SDL_SetTextureScaleMode(Tex, SDL_SCALEMODE_LINEAR);
    TexW := w;
    TexH := h;
    Raster.Resize(w, h);
  end;
  SetView;
  { wide: 70 % of the earlier inset (250 units at HUD 1.0), following [ / ] }
  { inset: 157.5 units (90 % of the compact 175) at the default HUD size, follows [ / ] }
  if IsWide then s := Max(48, Round(OutH / 900 * 250 * 0.7 * 0.9 * HudScale / 0.575))
  else s := Max(48, Round(LV(210)));
  if (InsetTex = nil) or (s <> InsetSz) then
  begin
    if InsetTex <> nil then SDL_DestroyTexture(InsetTex);
    InsetTex := SDL_CreateTexture(Ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, s, s);
    SDL_SetTextureBlendMode(InsetTex, SDL_BLENDMODE_BLEND);
    InsetSz := s;
    Inset.Resize(s);
  end;
end;

{ projected bounding box (texture pixels) of the circle of radius AR in z = 0 }
procedure CloudSpan(AR: Double; out X0, X1, Y0, Y1: Double);
var
  i: Integer;
  a, dx, dy, dz, zc, inv, sx, sy: Double;
begin
  X0 := 1e30; X1 := -1e30; Y0 := 1e30; Y1 := -1e30;
  for i := 0 to 71 do
  begin
    a := 2 * Pi * i / 72;
    dx := AR * Cos(a) - Cam.Pos[0]; dy := AR * Sin(a) - Cam.Pos[1]; dz := -Cam.Pos[2];
    zc := dx * Cam.Fwd[0] + dy * Cam.Fwd[1] + dz * Cam.Fwd[2];
    if zc < 0.05 then Continue;
    inv := Cam.Focal / zc;
    sx := Cam.Cx + (dx * Cam.Right[0] + dy * Cam.Right[1] + dz * Cam.Right[2]) * inv;
    sy := Cam.Cy - (dx * Cam.Up[0] + dy * Cam.Up[1] + dz * Cam.Up[2]) * inv;
    X0 := Min(X0, sx); X1 := Max(X1, sx); Y0 := Min(Y0, sy); Y1 := Max(Y1, sy);
  end;
end;

procedure RenderCloud;
var
  P: TFrameParams;
  x, y, z, d, pr, avail, availW, availH, f, sx0, sx1, sy0, sy1: Double;
  it: Integer;
  ic: TCamera;
  o: TOrbital;
  r: TSDL_FRect;
const
  ViewCut: array[0..2] of Integer = (5, 3, 0);
  ViewGain: array[0..2] of Double = (4.0, 1.5, 1.0);   { [0] = FX slice_gain }
begin
  o := G.Active;
  if o.Count = 0 then Exit;
  { camera distance so the cloud (radius 1.15 RView, fov 40) fills the free
    space: the full height minus margins, or the room between the side columns }
  { between the side blocks in a wide window; in a narrow window the cloud may
    pass under the (panel-less) corner blocks rather than shrink }
  availW := Max(100, Max(OutW - 2 * (LV(340) + 8), OutW * 0.9));
  availH := Max(100, OutH * 0.96);
  avail := Min(availW, availH);
  d := 2.3 * o.RView * (OutH / (2 * Tan(DegToRad(20)))) / avail;
  { the tilted camera makes the near (lower) side bigger: measure the projected
    outline of the cloud disc (radius 1.15 RView), fit it into availW x availH,
    then move the image centre so the outline is centred vertically }
  for it := 1 to 3 do
  begin
    CamPos(-90, 62, d, x, y, z);
    LookAtOrigin(Cam, x, y, z, 40, TexW, TexH);
    CloudSpan(o.RView * 1.15, sx0, sx1, sy0, sy1);
    f := Max((sx1 - sx0) / (availW * TexW / OutW), (sy1 - sy0) / (availH * TexH / OutH));
    if f > 0 then d := d * f;
  end;
  d := d / ZoomF;
  CamPos(-90, 62, d, x, y, z);
  LookAtOrigin(Cam, x, y, z, 40, TexW, TexH);
  CloudSpan(o.RView * 1.15, sx0, sx1, sy0, sy1);
  CamShift := (sy0 + sy1) / 2 - TexH / 2;
  Cam.Cy := Cam.Cy - CamShift;
  CamDist := d;
  AddLayer('cloud', 'world', sx0 * OutW / TexW, (sy0 - CamShift) * OutH / TexH, (sx1 - sx0) * OutW / TexW,
    (sy1 - sy0) * OutH / TexH);
  P.Cam := Cam;
  P.Time := G.SimTime;
  P.Cut := ViewCut[ViewMode];
  P.Slab := o.RView * 0.07;
  P.SizeWorld := o.RView * 0.0030 * GFX[fxCloudSize];
  pr := Cam.Focal * o.RView / d;
  if ViewMode = 0 then P.Energy := GFX[fxSliceGain] else P.Energy := ViewGain[ViewMode];
  P.Energy := 0.6 * P.Energy * GFX[fxCloudLight] * (300000 / o.Count) * Sqr(pr / 300);
  P.NucleusWorld := o.RView * 0.006 * GFX[fxNucleus];
  P.ThickPx := GFX[fxCloudThick];
  Raster.Render(o, P);
  SDL_UpdateTexture(Tex, nil, @Raster.Pix[0], TexW * 4);
  r.x := 0; r.y := 0; r.w := OutW; r.h := OutH;
  SDL_RenderTexture(Ren, Tex, nil, @r);
  { traditional orbital inset, phase as hue }
  CamPos(InsetAz, 22, o.RView * 4.2, x, y, z);
  LookAtOrigin(ic, x, y, z, 30, InsetSz, InsetSz);
  Inset.Render(o, ic, o.RView * 0.018);
  SDL_UpdateTexture(InsetTex, nil, @Inset.Pix[0], InsetSz * 4);
end;

procedure DrawInset;
var
  r: TSDL_FRect;
begin
  if IsWide and (Screen in [scPlaying, scPaused, scResult, scTitle, scLevels, scHelp, scBriefing]) and (YShift = 0) then
  begin
    GrpBegin('inset.label', 'inset');
    TextV(fkSmallBold, 'TRADITIONAL ORBITAL', CW - 24, 22, cText, alRight);
    TextV(fkTiny, 'hue: phase . 85 % probability', CW - 24, 44, cDim, alRight);
    GrpEnd;
    r.x := XV(CW - 24) - InsetSz; r.y := YV(66); r.w := InsetSz; r.h := InsetSz;
    SDL_RenderTexture(Ren, InsetTex, nil, @r);
    AddLayer('inset.orbital', 'inset', r.x, r.y, r.w, r.h);
    Exit;
  end;
  TextV(fkSmallBold, 'TRADITIONAL ORBITAL', 860, 40, cText, alRight);
  TextV(fkTiny, 'hue: phase . 85 % probability', 860, 64, cDim, alRight);
  r.x := XV(650); r.y := YV(86); r.w := InsetSz; r.h := InsetSz;
  SDL_RenderTexture(Ren, InsetTex, nil, @r);
end;

function FlowColor(AW, ASv: Double): UInt32;
begin
  if Abs(AW) * ASv < 0.06 * G.RView then Result := FxC(fxColSlow)
  else if AW > 0 then Result := FxC(fxColCCW)
  else Result := FxC(fxColCW);
end;

{ gravitational lensing: the cloud texture re-mapped on a radial mesh around
  the hole. A screen point at radius r shows the cloud from radius
  r - E^2/r (point-mass lens, E = Einstein radius), blended back to r at the
  edge of the lens so there is no seam. }
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
      v[k].tex_coord.x := EnsureRange((BX + rs * Cos(a)) / Max(1, OutW), 0, 1);
      v[k].tex_coord.y := EnsureRange((BY + rs * Sin(a)) / Max(1, OutH), 0, 1);
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

procedure DrawBlackHoles(APpa: Single);
var
  k, i: Integer;
  bxw, byw, rr, ang, w, sp: Double;
  bx, by, ax, ay, rh, rc, a: Single;
  col: UInt32;
begin
  for k := 0 to G.BHCount - 1 do
  begin
    G.BHPos(k, bxw, byw);
    if not Project(bxw, byw, 0, bx, by) then Continue;
    rh := Max(4, G.BH[k].Rh * APpa);
    rc := G.BH[k].Rc * APpa;
    AddLayer('blackhole.' + IntToStr(k), 'world', bx - rc, by - rc, 2 * rc, 2 * rc);
    DrawLens(bx, by, rc * GFX[fxLensRadius], rh * GFX[fxLensStrength]);
    { shadow + event horizon }
    Disc(bx, by, rh * GFX[fxShadowSize], $000000, GFX[fxShadowAlpha]);
    Disc(bx, by, rh * (1 + 0.42 * (GFX[fxShadowSize] - 1)), $000000, Min(1, GFX[fxShadowAlpha] * 1.8));
    Disc(bx, by, rh, $000000, 1);
    { accretion disc in the orbital plane (projected), Doppler-brightened on one side }
    for i := 0 to FxI(fxDiscCount) - 1 do
    begin
      rr := G.BH[k].Rh * (GFX[fxDiscInner] + GFX[fxDiscWidth] * Frac(i * 0.618034));
      w := 2.4 * Power(G.BH[k].Rh / rr, 1.5);
      ang := i * 2.399963 + NowS * w * GFX[fxDiscSpeed];
      if not Project(bxw + rr * Cos(ang), byw + rr * Sin(ang), 0, ax, ay) then Continue;
      a := Min(1, (0.35 + 0.5 * (0.5 + 0.5 * Sin(ang))) * GFX[fxDiscAlpha]);
      if rr < G.BH[k].Rh * (GFX[fxDiscInner] + 0.55) then col := FxC(fxColDiscHot) else col := FxC(fxColDisc);
      Disc(ax, ay, Max(1.2, LV(GFX[fxDiscDot])), col, a);
    end;
    { photon ring }
    if GFX[fxRingWidth] > 0 then Ring(bx, by, rh * 1.08, Max(1, LV(GFX[fxRingWidth])), FxC(fxColRing), GFX[fxRingAlpha]);
    Ring(bx, by, rh * 1.3, 1, $FFFFFF, GFX[fxHaloAlpha]);
    { capture radius: dashed ring = point of no return }
    for i := 0 to FxI(fxCaptureDots) - 1 do
    begin
      ang := 2 * Pi * i / FxI(fxCaptureDots) + NowS * GFX[fxCaptureSpin];
      if Project(bxw + G.BH[k].Rc * Cos(ang), byw + G.BH[k].Rc * Sin(ang), 0, ax, ay) then
        Disc(ax, ay, Max(1, LV(1.6)), FxC(fxColDanger), GFX[fxCaptureAlpha]);
    end;
    { it just ate a quantum }
    if G.BH[k].Meal < 0.8 then
    begin
      sp := G.BH[k].Meal / 0.8;
      Ring(bx, by, rh * (1.2 + GFX[fxMealRing] * sp), 3, FxC(fxColDisc), 0.8 * (1 - sp));
    end;
  end;
end;

procedure DrawWorld;
var
  k, i, n: Integer;
  sx, sy, px, py, s, ppa, a, rr: Single;
  q: TQuantum;
  o: TOrbital;
  col: UInt32;
begin
  o := G.Active;
  ppa := PixPerAU;
  DrawBlackHoles(ppa);
  { quanta }
  for k := 0 to MaxQuanta - 1 do
  begin
    q := G.Quanta[k];
    if not q.Alive then Continue;
    if not Project(q.S * Cos(q.Phi), q.S * Sin(q.Phi), 0, sx, sy) then Continue;
    rr := Max(4, G.PickRadius * ppa * 0.42);
    AddLayer(IfThen(q.Bonus, 'photon.', 'quantum.') + IntToStr(k), 'world', sx - rr * 2, sy - rr * 2, rr * 4, rr * 4);
    if q.Bonus then
    begin
      a := 0.6 + 0.4 * Sin(NowS * GFX[fxPhotonPulseSpeed]);
      Disc(sx, sy, rr * 2.2, FxC(fxColPhoton), GFX[fxPhotonGlowAlpha] * a);
      Star(sx, sy, rr * GFX[fxPhotonStar], FxC(fxColPhoton), 0.95);
      Ring(sx, sy, rr * 2.4, 2, FxC(fxColPhoton), 0.7 * (1 - q.Age / q.Life));
    end
    else
    begin
      col := FlowColor(o.W[q.Idx], q.S);
      a := 1 - GFX[fxQuantumPulse] + GFX[fxQuantumPulse] * Sin(NowS * GFX[fxQuantumPulseSpeed] + k);
      Disc(sx, sy, rr * GFX[fxQuantumGlow], col, GFX[fxQuantumGlowAlpha]);
      Disc(sx, sy, rr * GFX[fxQuantumCore], col, 0.9 * a);
      Disc(sx, sy, rr * GFX[fxQuantumCore] * 0.5, $FFFFFF, 0.95);
      Ring(sx, sy, rr * 1.6, 1.5, $FFFFFF, GFX[fxQuantumRingAlpha]);
    end;
  end;
  { trail }
  n := Min(TrailN, FxI(fxTrailLength));
  for i := 0 to n - 1 do
  begin
    k := (TrailPos - 1 - i + Length(TrailX)) mod Length(TrailX);
    if Project(TrailX[k], TrailY[k], 0, sx, sy) then
      Disc(sx, sy, Max(1.5, G.ProbeRadius * ppa * (1 - i / n) * GFX[fxTrailWidth]), FxC(fxColProbe),
        GFX[fxTrailAlpha] * (1 - i / n));
  end;
  { probe }
  if Project(G.PX, G.PY, 0, px, py) then
  begin
    rr := Max(5, G.ProbeRadius * ppa);
    AddLayer('probe', 'world', px - rr * 2.6, py - rr * 2.6, rr * 5.2, rr * 5.2);
    if G.ProbeProb < 0.035 then
    begin
      a := 0.5 + 0.5 * Sin(NowS * 18);
      Ring(px, py, rr * 2.4, 3, FxC(fxColDanger), 0.8 * a);
    end;
    Disc(px, py, rr * GFX[fxProbeGlow], FxC(fxColProbe), GFX[fxProbeGlowAlpha]);
    Disc(px, py, rr * 1.4, FxC(fxColProbe), GFX[fxProbeMidAlpha]);
    Disc(px, py, rr * 0.8, $FFFFFF, 1);
    Ring(px, py, rr * 1.9, 2, $FFFFFF, GFX[fxProbeRingAlpha]);
    { Hawking ejection: immune shield }
    if G.Immune > 0 then
      Ring(px, py, rr * (2.8 + 0.4 * Sin(NowS * 12)), 3, FxC(fxColPhoton), Min(1, G.Immune));
    { spin arrow }
    if G.Spin > 0 then s := -1 else s := 1;
    SDL_SetRenderDrawColor(Ren, 255, 255, 255, 230);
    a := GFX[fxSpinArrow];
    if a > 0.3 then
    begin
      SDL_RenderLine(Ren, px, py - s * rr * 0.3, px, py + s * rr * a);
      SDL_RenderLine(Ren, px - rr * 0.8, py + s * rr * (a - 0.9), px, py + s * rr * a);
      SDL_RenderLine(Ren, px + rr * 0.8, py + s * rr * (a - 0.9), px, py + s * rr * a);
    end;
  end;
  { effects }
  for i := 0 to High(Fx) do
    with Fx[i] do
      if T < Life then
      begin
        a := 1 - T / Life;
        if GFX[fxPopWidth] > 0 then Ring(X, Y, LV(20) + LV(GFX[fxPopRing]) * T / Life, GFX[fxPopWidth], Col, a);
        if Text <> '' then Hud.Text(fkBodyBold, Text, X, Y - LV(40) - LV(GFX[fxPopRise]) * T / Life, Col, alCenter, Round(255 * a));
      end;
end;

procedure DrawColumns;
begin
  { no panels: the HUD columns sit directly on the game (kept as a hook) }
end;

procedure DrawHeaderWide;
var
  o: TOrbital;
  t: string;
  col: UInt32;
begin
  o := G.Active;
  DrawColumns;
  GrpBegin('hud.orbital', 'hud');
  RectV(24, 22, 46, 4, cOrange);
  TextV(fkSmallBold, 'HYDROGEN / PAULI CURRENT', 24, 32, cText);
  TextV(fkTitle, o.Name, 20, 50, $FFFFFF);
  GrpEnd;
  GrpBegin('hud.quantum_numbers', 'hud');
  t := Format('n = %d    l = %d    m = %s', [o.N, o.L, IfThen(o.M > 0, '+', '') + IntToStr(o.M)]);
  TextV(fkBodyBold, t, 24, 132, $FFFFFF);
  GrpEnd;
  GrpBegin('hud.spin', 'hud');
  if G.Spin > 0 then t := 'SPIN UP   sigma = +1' else t := 'SPIN DOWN   sigma = -1';
  col := Pick(G.Spin > 0, cCyan, $FF7AD9);
  RectV(24, 172, 11, 11, col);
  TextV(fkSmallBold, t, 44, 166, col);
  GrpEnd;
  GrpBegin('hud.rule', 'hud');
  TextV(fkTiny, Format('LEVEL %d / %d  .  W%d', [G.Level + 1, LevelCount, G.Def.World + 1]) +
    IfThen(G.Def.Rule <> '', '  .  ' + G.Def.Rule, ''), 24, 190, cGold);
  GrpEnd;
  DrawInset;
end;

procedure DrawHeaderInfo;
var
  o: TOrbital;
  t: string;
  w: Single;
begin
  if IsWide then
  begin
    DrawHeaderWide;
    Exit;
  end;
  o := G.Active;
  RectV(40, 40, 46, 4, cOrange);
  TextV(fkSmallBold, 'HYDROGEN / PAULI CURRENT', 40, 52, cText);
  TextV(fkTitle, o.Name, 36, 74, $FFFFFF);
  t := Format('n = %d    l = %d    m = %s', [o.N, o.L, IfThen(o.M > 0, '+', '') + IntToStr(o.M)]);
  w := Hud.TextWidth(fkBodyBold, t) / K;
  TextV(fkBodyBold, t, 52, 186, $FFFFFF);
  if G.Spin > 0 then t := 'SPIN UP    sigma = +1' else t := 'SPIN DOWN    sigma = -1';
  RectV(36, 238, 12, 12, Pick(G.Spin > 0, cCyan, $FF7AD9));
  TextV(fkSmallBold, t, 58, 233, Pick(G.Spin > 0, cCyan, $FF7AD9));
  DrawInset;
end;

const
  BlockMaxPx = 140;              { coherence / black-hole blocks: max width in pixels }

procedure DrawGameHudWide;
var
  mult: Double;
  col: UInt32;
  x0, ly, by, lw, xl, bw, by2: Single;
  t1, t2: string;
begin
  DrawHeaderWide;
  { left column: score, coherence, black holes, probe }
  GrpBegin('hud.score', 'hud');
  TextV(fkTiny, 'SCORE', 24, 214, cDim);
  TextV(fkBodyBold, IntToStr(G.Score), 24, 230, $FFFFFF);
  TextV(fkTiny, 'QUANTA', 180, 214, cDim);
  TextV(fkBodyBold, Format('%d / %d', [G.Collected, G.Def.Target]), 180, 230, $FFFFFF);
  TextV(fkTiny, 'TIME', 24, 272, cDim);
  if G.TimeLeft < 10 then col := cRed else col := $FFFFFF;
  TextV(fkBodyBold, Format('%.0f s', [Max(0, G.TimeLeft)]), 24, 288, col);
  if (G.Combo > 0) and (G.ComboT > 0) then
  begin
    mult := Min(3, 1 + G.Combo * 0.25);
    TextV(fkTiny, 'COMBO', 180, 272, cDim);
    TextV(fkBodyBold, Format('x%.2f', [mult]), 180, 288, cGold);
  end;
  GrpEnd;
  { coherence + black-hole blocks: at most 140 px wide }
  bw := Min(292, BlockMaxPx / K);
  GrpBegin('hud.coherence', 'hud');
  TextV(fkTiny, 'COHERENCE', 24, 338, cDim);
  RectV(24, 356, bw, 16, $1A1E28);
  if G.Coherence < 0.3 then col := cRed else col := cCyan;
  RectV(24, 356, bw * EnsureRange(G.Coherence, 0, 1), 16, col);
  GrpEnd;
  GrpBegin('hud.blackholes', 'hud');
  if G.BHCount > 0 then
  begin
    { mode and count in the same font; the count moves under the mode if both do not fit }
    t1 := ModeNames[G.Mode];
    t2 := Format('%d BLACK HOLE%s', [G.BHCount, IfThen(G.BHCount > 1, 'S', '')]);
    by2 := 388;
    TextV(fkSmallBold, t1, 24, by2, cGold);
    if (Hud.TextWidth(fkSmallBold, t1) + Hud.TextWidth(fkSmallBold, t2)) / K + 10 <= bw then
      TextV(fkSmallBold, t2, 24 + bw, by2, cGold, alRight)
    else
    begin
      by2 := by2 + Hud.LineHeight(fkSmallBold) / K;
      TextV(fkSmallBold, t2, 24, by2, cGold);
    end;
    by2 := by2 + Hud.LineHeight(fkSmallBold) / K + 4;
    if G.Tidal > 0.12 then
    begin
      TextV(fkTiny, IfThen(G.Tidal >= 0.95, 'NO ESCAPE', 'TIDAL PULL'), 24, by2, Pick(G.Tidal >= 0.95, cRed, cGold));
      RectV(24, by2 + 18, bw, 10, $1A1E28);
      RectV(24, by2 + 18, bw * Min(1, G.Tidal), 10, Pick(G.Tidal >= 0.7, cRed, cGold));
    end;
  end;
  GrpEnd;
  GrpBegin('hud.probe', 'hud');
  col := Pick(G.ProbeProb < 0.035, cRed, cText);
  TextV(fkTiny, 'PROBE', 24, 470, cDim);
  TextV(fkSmallBold, Format('r = %.1f a0', [Hypot(G.PX, G.PY)]), 24, 488, col);
  TextV(fkSmallBold, Format('band %d of %d   .   %s', [G.ProbeRing + 1, Length(G.Active.RadialNodes) + 1, G.RingDirection]),
    24, 510, col);
  TextV(fkSmallBold, Format('P(r) %.2f', [G.ProbeProb]), 24, 532, col);
  GrpEnd;
  if G.ProbeProb < 0.035 then
  begin
    GrpBegin('hud.node_warning', 'hud');
    TextV(fkSmallBold, 'RADIAL NODE', 24, 566, cRed);
    TextV(fkSmall, '|psi|^2 = 0  -  decohering', 24, 588, cRed);
    GrpEnd;
  end;
  if BotOn then
  begin
    GrpBegin('hud.bot', 'hud');
    TextV(fkTiny, 'BOT', 24, CH - 30, cGold);
    GrpEnd;
  end;
  { right column: legend flush with the right edge (like the inset), buttons }
  lw := Max(Max(Hud.TextWidth(fkSmallBold, 'DIRECTION OF CIRCULATION'),
    Hud.TextWidth(fkTiny, 'VIEWED FROM +Z  .  ' + ViewNames[ViewMode])),
    LV(24) + Max(Hud.TextWidth(fkSmall, 'ORANGE / COUNTERCLOCKWISE'), Hud.TextWidth(fkSmall, 'BLUE / CLOCKWISE'))) / K;
  xl := CW - 24 - lw;
  x0 := CW - 316;
  ly := 66 + InsetSz / K + 36;
  GrpBegin('legend', 'hud');
  TextV(fkSmallBold, 'DIRECTION OF CIRCULATION', xl, ly, cText);
  TextV(fkTiny, 'VIEWED FROM +Z  .  ' + ViewNames[ViewMode], xl, ly + 22, cDim);
  Hud.Dot(XV(xl + 7), YV(ly + 62), LV(6), cOrange);
  TextV(fkSmall, 'ORANGE / COUNTERCLOCKWISE', xl + 24, ly + 52, cText);
  Hud.Dot(XV(xl + 7), YV(ly + 92), LV(6), cBlue);
  TextV(fkSmall, 'BLUE / CLOCKWISE', xl + 24, ly + 82, cText);
  Hud.Dot(XV(xl + 7), YV(ly + 122), LV(6), cWhite);
  TextV(fkSmall, 'WHITE / SLOW', xl + 24, ly + 112, cText);
  GrpEnd;
  GrpBegin('hud.zoom', 'hud');
  TextV(fkTiny, Format('zoom %.2f  (wheel, + / -)   .   HUD %.2f  ([ / ])', [ZoomF, HudScale]), CW - 24, ly + 160, cFaint, alRight);
  GrpEnd;
  by := CH - 24 - 60;
  if BtnV(IfThen(G.FlipCool > 0, 'SPIN ...', 'FLIP SPIN'), x0, by - 8 - 84, 292, 84, False, 'flip', 'SPACE') then FlipReq := True;
  if BtnV('PAUSE', x0, by, 142, 60, False, 'pause', 'P') then begin Screen := scPaused; PlaySound(snClick); end;
  if BtnV('VIEW', x0 + 150, by, 142, 60, False, 'view', 'V') then ViewMode := (ViewMode + 1) mod 3;
end;

{ ---------------------------------------------------------------- SUPER BOT DEMO state }

var
  DemoMode, DemoDone, DemoExit: Boolean;
  DemoT, DemoSpaceT, DemoEnterT, DemoRT, DemoClickT: Double;
  DemoClickX, DemoClickY: Single;
  DemoPrevScreen: TScreen;
  DemoSavedMode: TGameMode;
  DemoScores, DemoAttempts: array[0..LevelCount - 1] of Integer;
  DemoTimes: array[0..LevelCount - 1] of Double;
  DemoLog: array[0..5] of string;
  DemoLogT: array[0..5] of Double;
  DemoInputs, DemoMouseUses, DemoKeyUses: Integer;
  DemoMouseL, DemoUseKeys: Boolean;
  DemoLogFile: string;

procedure DemoAdd(const S: string);
var
  i: Integer;
begin
  for i := High(DemoLog) downto 1 do
  begin
    DemoLog[i] := DemoLog[i - 1];
    DemoLogT[i] := DemoLogT[i - 1];
  end;
  DemoLog[0] := S;
  DemoLogT[0] := NowS;
  Inc(DemoInputs);
end;

procedure DemoWrite(const S: string);
var
  f: TextFile;
begin
  if DemoLogFile = '' then Exit;
  try
    AssignFile(f, DemoLogFile);
    if FileExists(DemoLogFile) then Append(f) else Rewrite(f);
    WriteLn(f, FormatDateTime('hh:nn:ss', Now) + '  ' + S);
    CloseFile(f);
  except
  end;
end;

procedure StopDemo;
begin
  if not DemoMode then Exit;
  DemoMode := False;
  DemoDone := False;
  CurMode := DemoSavedMode;
  KeyL := False; KeyR := False; KeyU := False; KeyD := False;
  MouseDownL := False;
  DemoMouseL := False;
end;

procedure KeyCap(X, Y, W, H: Single; const ALabel: string; ALit: Boolean);
var
  th: Single;
begin
  if ALit then RectV(X, Y, W, H, cOrange, 235) else RectV(X, Y, W, H, $14161C, 200);
  RectV(X, Y, W, 1.5, Pick(ALit, $FFD9A0, $5E6570));
  RectV(X, Y + H - 1.5, W, 1.5, Pick(ALit, $FFD9A0, $5E6570));
  RectV(X, Y, 1.5, H, Pick(ALit, $FFD9A0, $5E6570));
  RectV(X + W - 1.5, Y, 1.5, H, Pick(ALit, $FFD9A0, $5E6570));
  th := Hud.LineHeight(fkSmallBold) / K;
  TextV(fkSmallBold, ALabel, X + W / 2, Y + (H - th) / 2, Pick(ALit, $111111, cText), alCenter);
end;

procedure DrawCursorArrow(X, Y, S: Single);
var
  v: array[0..6] of TSDL_Vertex;
  idx: array[0..8] of LongInt;
  i: Integer;
  c: TSDL_FColor;
const
  PX_: array[0..6] of Single = (0, 0, 0.27, 0.45, 0.6, 0.42, 0.72);
  PY_: array[0..6] of Single = (0, 1, 0.76, 1.08, 1.0, 0.68, 0.68);
begin
  for i := 0 to 6 do
  begin
    v[i].position.x := X + PX_[i] * S;
    v[i].position.y := Y + PY_[i] * S;
  end;
  { outline (slightly larger, dark) }
  c.r := 0; c.g := 0; c.b := 0; c.a := 1;
  idx[0] := 0; idx[1] := 1; idx[2] := 6;
  idx[3] := 2; idx[4] := 3; idx[5] := 4;
  idx[6] := 2; idx[7] := 4; idx[8] := 5;
  for i := 0 to 6 do v[i].color := c;
  SDL_RenderGeometry(Ren, nil, @v[0], 7, @idx[0], 9);
  for i := 0 to 6 do
  begin
    v[i].position.x := X + 1.5 + PX_[i] * (S - 4);
    v[i].position.y := Y + 2.5 + PY_[i] * (S - 4);
    c.r := 1; c.g := 1; c.b := 1; c.a := 1;
    v[i].color := c;
  end;
  SDL_RenderGeometry(Ren, nil, @v[0], 7, @idx[0], 9);
end;

procedure DrawDemoOverlay;
var
  ks, x0, y0, mx0, lx, a: Single;
  i, tot: Integer;
  sx, sy, px, py, d, st: Single;
begin
  tot := 0;
  for i := 0 to LevelCount - 1 do Inc(tot, DemoScores[i]);
  GrpBegin('demo.banner', 'hud');
  TextV(fkBodyBold, 'SUPER-HARD BOT', CW / 2, 14, cGold, alCenter);
  TextV(fkSmallBold, Format('SINGULARITY  .  LEVEL %d / %d  .  attempt %d  .  total %d', [G.Level + 1, LevelCount,
    Max(1, DemoAttempts[G.Level]), tot]), CW / 2, 44, cText, alCenter);
  TextV(fkTiny, 'the bot uses the keyboard and the mouse like a player   .   Esc pause, Q menu', CW / 2, 68, cDim, alCenter);
  GrpEnd;
  ks := 46;
  x0 := CW / 2 - 420;
  y0 := CH - 24 - 3 * ks - 8;
  GrpBegin('demo.keyboard', 'hud');
  TextV(fkTiny, 'KEYBOARD', x0, y0 - 22, cDim);
  KeyCap(x0 + ks + 4, y0, ks, ks, 'W', KeyU);
  KeyCap(x0, y0 + ks + 4, ks, ks, 'A', KeyL);
  KeyCap(x0 + ks + 4, y0 + ks + 4, ks, ks, 'S', KeyD);
  KeyCap(x0 + 2 * (ks + 4), y0 + ks + 4, ks, ks, 'D', KeyR);
  KeyCap(x0, y0 + 2 * (ks + 4), 3 * ks + 8, ks, 'SPACE', DemoSpaceT > 0);
  KeyCap(x0 + 3 * (ks + 4) + 10, y0 + ks + 4, 96, ks, 'ENTER', DemoEnterT > 0);
  KeyCap(x0 + 3 * (ks + 4) + 10, y0 + 2 * (ks + 4), 46, ks, 'R', DemoRT > 0);
  GrpEnd;
  mx0 := x0 + 3 * (ks + 4) + 130;
  GrpBegin('demo.mouse', 'hud');
  TextV(fkTiny, 'MOUSE', mx0, y0 - 22, cDim);
  RectV(mx0, y0, 74, 108, $14161C, 210);
  RectV(mx0 + 3, y0 + 3, 33, 44, Pick(MouseDownL, cOrange, $2A2F3A), Pick(MouseDownL, 235, 200));
  RectV(mx0 + 38, y0 + 3, 33, 44, $2A2F3A, 200);
  TextV(fkTiny, 'L', mx0 + 19, y0 + 16, Pick(MouseDownL, $111111, cDim), alCenter);
  TextV(fkTiny, 'R', mx0 + 55, y0 + 16, cDim, alCenter);
  TextV(fkSmallBold, IfThen(MouseDownL, 'LMB  HOLD', 'LMB  up'), mx0 + 88, y0 + 2, Pick(MouseDownL, cOrange, cDim));
  TextV(fkSmall, Format('x %d   y %d  px', [Round(MouseX), Round(MouseY)]), mx0 + 88, y0 + 30, cText);
  if MouseDownL then st := 1 else if KeyU or KeyD or KeyL or KeyR then st := 2 else st := 0;
  TextV(fkTiny, 'steering: ' + IfThen(st = 1, 'MOUSE', IfThen(st = 2, 'KEYBOARD', '-')), mx0 + 88, y0 + 58, cDim);
  TextV(fkTiny, Format('inputs %d   mouse %d   keys %d', [DemoInputs, DemoMouseUses, DemoKeyUses]), mx0 + 88, y0 + 80, cFaint);
  GrpEnd;
  lx := mx0 + 330;
  GrpBegin('demo.log', 'hud');
  TextV(fkTiny, 'BOT INPUT LOG', lx, y0 - 22, cDim);
  for i := 0 to High(DemoLog) do
    if DemoLog[i] <> '' then
    begin
      a := EnsureRange(1 - (NowS - DemoLogT[i]) / 12, 0.25, 1);
      TextV(fkSmall, Format('%5.1f s   %s', [NowS - DemoLogT[i], DemoLog[i]]), lx, y0 + i * 22, Pick(i = 0, cGold, cText),
        alLeft, Round(255 * a));
    end;
  GrpEnd;
  { the cursor where the bot holds the mouse, a dotted line to the probe }
  if (Screen = scPlaying) and MouseDownL then
  begin
    if Project(G.PX, G.PY, 0, px, py) then
    begin
      d := Hypot(MouseX - px, MouseY - py);
      i := 0;
      while i * 7 < d do
      begin
        sx := px + (MouseX - px) * i * 7 / Max(1, d);
        sy := py + (MouseY - py) * i * 7 / Max(1, d);
        Disc(sx, sy, 1.3, cOrange, 0.8);
        Inc(i);
      end;
    end;
    Ring(MouseX, MouseY, LV(14), 1.5, cOrange, 0.9);
    DrawCursorArrow(MouseX, MouseY, Max(14, LV(34)));
    AddLayer('demo.cursor', 'world', MouseX - LV(14), MouseY - LV(14), LV(48), LV(48));
  end;
  if DemoClickT < 0.6 then
    Ring(DemoClickX, DemoClickY, LV(10) + LV(60) * DemoClickT, 2, cOrange, 1 - DemoClickT / 0.6);
end;

procedure DrawGameHud;
var
  t: string;
  mult: Double;
  col: UInt32;
begin
  if IsWide then
  begin
    DrawGameHudWide;
    Exit;
  end;
  DrawHeaderInfo;
  { score row }
  TextV(fkTiny, 'SCORE', 50, 306, cDim);
  TextV(fkBodyBold, IntToStr(G.Score), 50, 326, $FFFFFF);
  TextV(fkTiny, 'QUANTA', 450, 306, cDim, alCenter);
  TextV(fkBodyBold, Format('%d / %d', [G.Collected, G.Def.Target]), 450, 326, $FFFFFF, alCenter);
  TextV(fkTiny, 'TIME', 850, 306, cDim, alRight);
  if G.TimeLeft < 10 then col := cRed else col := $FFFFFF;
  TextV(fkBodyBold, Format('%.0f s', [Max(0, G.TimeLeft)]), 850, 326, col, alRight);
  if (G.Combo > 0) and (G.ComboT > 0) then
  begin
    mult := Min(3, 1 + G.Combo * 0.25);
    TextV(fkSmallBold, Format('COMBO x%.2f', [mult]), 250, 330, cGold, alCenter);
  end;
  { coherence }
  TextV(fkTiny, 'COHERENCE', 30, 386, cDim);
  RectV(150, 390, 720, 14, $1A1E28);
  if G.Coherence < 0.3 then col := cRed else col := cCyan;
  RectV(150, 390, 720 * EnsureRange(G.Coherence, 0, 1), 14, col);
  { black holes }
  if G.BHCount > 0 then
  begin
    TextV(fkTiny, Format('%s  .  %d BLACK HOLE%s', [ModeNames[G.Mode], G.BHCount, IfThen(G.BHCount > 1, 'S', '')]), 30, 414, cGold);
    if G.Tidal > 0.12 then
    begin
      TextV(fkTiny, IfThen(G.Tidal >= 0.95, 'NO ESCAPE', 'TIDAL PULL'), 870, 414, Pick(G.Tidal >= 0.95, cRed, cGold), alRight);
      RectV(330, 420, 400, 8, $1A1E28);
      RectV(330, 420, 400 * Min(1, G.Tidal), 8, Pick(G.Tidal >= 0.7, cRed, cGold));
    end;
  end;
  { probe readout }
  t := Format('r = %.1f a0   .   band %d of %d   .   %s   .   P(r) %.2f',
    [Hypot(G.PX, G.PY), G.ProbeRing + 1, Length(G.Active.RadialNodes) + 1, G.RingDirection, G.ProbeProb]);
  TextV(fkSmallBold, t, 450, 1262, Pick(G.ProbeProb < 0.035, cRed, cText), alCenter);
  if G.ProbeProb < 0.035 then
    TextV(fkSmallBold, 'RADIAL NODE  |psi|^2 = 0  -  DECOHERING', 450, 1226, cRed, alCenter);
  { legend like the reference picture }
  TextV(fkSmallBold, 'DIRECTION OF CIRCULATION', 40, 1318, cText);
  TextV(fkTiny, 'VIEWED FROM +Z  .  ' + ViewNames[ViewMode], 40, 1342, cDim);
  Hud.Dot(XV(48), YV(1384), LV(6), cOrange);
  TextV(fkSmall, 'ORANGE / COUNTERCLOCKWISE', 66, 1374, cText);
  Hud.Dot(XV(48), YV(1416), LV(6), cBlue);
  TextV(fkSmall, 'BLUE / CLOCKWISE', 66, 1406, cText);
  Hud.Dot(XV(48), YV(1448), LV(6), cWhite);
  TextV(fkSmall, 'WHITE / SLOW', 66, 1438, cText);
  { touch / mouse buttons }
  if BtnV(IfThen(G.FlipCool > 0, 'SPIN ...', 'FLIP SPIN'), 470, 1372, 390, 80, False, 'flip', 'SPACE') then FlipReq := True;
  if BtnV('PAUSE', 470, 1466, 190, 56, False, 'pause', 'P') then begin Screen := scPaused; PlaySound(snClick); end;
  if BtnV('VIEW', 670, 1466, 190, 56, False, 'view', 'V') then ViewMode := (ViewMode + 1) mod 3;
  if BotOn then TextV(fkTiny, 'BOT', 860, 1540, cGold, alRight);
end;

procedure Dim(AAlpha: Byte);
begin
  Hud.Rect(0, 0, OutW, OutH, $000000, AAlpha);
end;

procedure DrawStars(CX, CY, R: Single; AN: Integer);
var
  i: Integer;
begin
  for i := 0 to 2 do
    if i < AN then Star(XV(CX + (i - 1) * R * 2.6), YV(CY), LV(R), cGold, 1)
    else Star(XV(CX + (i - 1) * R * 2.6), YV(CY), LV(R), $3A3F47, 1);
end;

procedure RequestLevel(ALevel: Integer);
begin
  PendingLevel := EnsureRange(ALevel, 0, LevelCount - 1);
  PendingScreen := scBriefing;
end;

procedure PlayPressed;
begin
  PlaySound(snClick);
  RequestLevel(Min(Unlocked[CurMode], LevelCount) - 1);
end;

procedure GoMenu;
begin
  if DemoMode then StopDemo;
  PlaySound(snClick);
  AttractMode := True;
  PendingLevel := AttractLevel;
  PendingScreen := scTitle;
end;

procedure StartFromBriefing;
begin
  PlaySound(snClick);
  if DemoMode then Inc(DemoAttempts[G.Level]);
  G.Mode := CurMode;
  G.StartLevel(G.Level, Points, 1000 + G.Level + 7919 * Ord(DemoMode) * DemoAttempts[G.Level]);
  TrailN := 0;
  Screen := scPlaying;
end;

procedure StartDemo;
var
  i: Integer;
begin
  if not DemoMode then DemoSavedMode := CurMode;
  DemoMode := True;
  DemoDone := False;
  CurMode := gmSingularity;
  BotOn := False;
  for i := 0 to LevelCount - 1 do
  begin
    DemoScores[i] := 0;
    DemoAttempts[i] := 0;
    DemoTimes[i] := 0;
  end;
  for i := 0 to High(DemoLog) do DemoLog[i] := '';
  DemoInputs := 0; DemoMouseUses := 0; DemoKeyUses := 0;
  DemoAdd('B  start the SUPER-HARD BOT (SINGULARITY)');
  DemoWrite('SUPER BOT DEMO start, mode SINGULARITY');
  PlaySound(snClick);
  RequestLevel(0);
end;

procedure DrawTitle;
const
  ModeDesc: array[TGameMode] of string = (
    'version 1: currents and radial nodes only',
    '1 - 3 black holes per orbital: pull, horizon, they eat quanta',
    '2 - 5 hungry black holes that grow with every quantum they eat');
var
  y: Single;
  m: TGameMode;
begin
  Dim(70);
  TextV(fkSmallBold, 'A GAME ON THE HYDROGEN ATOM', 450, 300, cOrange, alCenter);
  TextV(fkTitle, 'PAULI SURFER 2', 450, 326, $FFFFFF, alCenter);
  TextV(fkSmall, 'ride the probability current of the electron', 450, 430, cText, alCenter);
  TextV(fkSmallBold, 'VERSION 2  .  BLACK HOLES', 450, 470, cGold, alCenter);
  { mode }
  for m := Low(TGameMode) to High(TGameMode) do
    if BtnV(ModeNames[m], 60 + Ord(m) * 264, 920, 252, 56, CurMode = m, 'mode-' + ModeIds[m], IntToStr(Ord(m) + 1)) then
    begin
      CurMode := m;
      PlaySound(snClick);
      SaveProgress;
    end;
  TextV(fkTiny, ModeDesc[CurMode], 450, 990, cText, alCenter);
  y := 1040;
  if BtnV('PLAY', 250, y, 400, 66, True, 'play', 'ENTER') then PlayPressed;
  if BtnV('LEVELS', 250, y + 76, 400, 54, False, 'levels', 'L') then
  begin
    LevWorld := (Min(Unlocked[CurMode], LevelCount) - 1) div LevelsPerWorld;
    Screen := scLevels;
    PlaySound(snClick);
  end;
  if BtnV('HOW TO PLAY', 250, y + 140, 400, 54, False, 'help', 'H') then begin Screen := scHelp; PlaySound(snClick); end;
  if BtnV('SUPER BOT DEMO', 250, y + 204, 400, 54, False, 'demo', 'B') then StartDemo;
  if BtnV('QUIT', 250, y + 268, 400, 54, False, 'quit', 'Q') then Running := False;
  TextV(fkTiny, 'cloud: real |psi|^2 sample, coloured by the Pauli current (attract: the bot plays 6p with black holes)', 450, 1560,
    cFaint, alCenter);
end;

procedure DrawLevels;
var
  i, j, w, stars, won: Integer;
  y: Single;
  d: TLevelDef;
  t: string;
  locked: Boolean;
begin
  Dim(165);
  LevWorld := EnsureRange(LevWorld, 0, WorldCount - 1);
  TextV(fkSmallBold, 'SELECT ORBITAL  .  ' + ModeNames[CurMode] + '  .  <- -> world  .  1 - 6 level', 450, 286, cOrange, alCenter);
  for w := 0 to WorldCount - 1 do
    if BtnV(Format('WORLD %d', [w + 1]), 40 + w * 166, 318, 158, 44, LevWorld = w, 'world' + IntToStr(w + 1)) then
    begin
      LevWorld := w;
      PlaySound(snClick);
    end;
  stars := 0; won := 0;
  for j := 0 to LevelsPerWorld - 1 do
  begin
    Inc(stars, BestStars[CurMode, LevWorld * LevelsPerWorld + j]);
    if BestStars[CurMode, LevWorld * LevelsPerWorld + j] > 0 then Inc(won);
  end;
  TextV(fkBodyBold, Format('WORLD %d   %s', [LevWorld + 1, WorldNames[LevWorld]]), 450, 374, $FFFFFF, alCenter);
  TextV(fkTiny, Format('%d / %d cleared   .   %d / %d stars', [won, LevelsPerWorld, stars, 3 * LevelsPerWorld]), 450, 404, cDim,
    alCenter);
  for j := 0 to LevelsPerWorld - 1 do
  begin
    i := LevWorld * LevelsPerWorld + j;
    d := LevelDef(i);
    y := 430 + j * 124;
    locked := i + 1 > Unlocked[CurMode];
    t := Format('%d   %d%s   m = %s', [i + 1, d.N, OrbitalLetters[d.L + 1], IfThen(d.M > 0, '+', '') + IntToStr(d.M)]);
    if BtnV('', 60, y, 780, 112, False, 'lvl' + IntToStr(i + 1)) and not locked then
    begin
      PlaySound(snClick);
      RequestLevel(i);
    end;
    TextV(fkBodyBold, t, 86, y + 10, Pick(locked, cFaint, $FFFFFF));
    TextV(fkSmall, IfThen(locked, 'LOCKED', d.Title), 86, y + 52, Pick(locked, cFaint, cOrange));
    if d.Rule <> '' then TextV(fkTiny, d.Rule, 86, y + 80, Pick(locked, cFaint, cGold));
    if BlackHolesFor(CurMode, i) > 0 then
      TextV(fkTiny, Format('%d black hole%s', [BlackHolesFor(CurMode, i), IfThen(BlackHolesFor(CurMode, i) > 1, 's', '')]),
        440, y + 14, Pick(locked, cFaint, cGold));
    TextV(fkTiny, Format('%d quanta  .  %.0f s', [d.Target, d.TimeSec]), 440, y + 34, Pick(locked, cFaint, cDim));
    if not locked then
    begin
      DrawStars(720, y + 40, 16, BestStars[CurMode, i]);
      TextV(fkTiny, Format('best %d', [BestScore[CurMode, i]]), 820, y + 78, cDim, alRight);
    end;
  end;
  if BtnV('BACK', 300, 1196, 300, 60, False, 'back', 'ESC') then begin Screen := scTitle; PlaySound(snClick); end;
end;

procedure DrawHelp;
const
  Lines: array[0..20] of string = (
    'You are a probe inside a hydrogen atom.',
    'The cloud is |psi|^2: where the electron can be found.',
    'Its colour is the Pauli probability current around z:',
    '  orange = counterclockwise, blue = clockwise, white = slow.',
    'The current carries you and the quanta - use it.',
    '',
    'MOVE      WASD / arrows, or hold the mouse button',
    'FLIP SPIN SPACE / right click / button: sigma -> -sigma',
    '          changes the spin current, the bands move',
    'RADIAL NODES (dark rings, |psi|^2 = 0) drain coherence:',
    '          cross them fast',
    'GOLD STAR = Balmer photon, 500 points, 6 seconds',
    'COMBO: pick quanta within 4 s of each other (up to x3)',
    '30 LEVELS in 5 worlds: mirrored currents, spin lock, turbo, Rydberg ...',
    'P / Esc pause . V view . M mute . R restart . Q menu . Enter = default',
    'ZOOM mouse wheel or + / -  .  HUD SIZE [ / ] (wide window)',
    'SUPER BOT DEMO (B on the title): watch the bot play SINGULARITY 1 - 30',
    '',
    'BLACK HOLES (modes BLACK HOLE / SINGULARITY): the dashed red',
    '  ring is the point of no return; the horizon costs coherence',
    '  and throws you out (2 s immune). They drift with the current,'
    + ' eat quanta - and quanta taken at their edge score x2.');
var
  i: Integer;
begin
  Dim(185);
  TextV(fkSmallBold, 'HOW TO PLAY', 450, 300, cOrange, alCenter);
  for i := 0 to High(Lines) do TextV(fkSmall, Lines[i], 50, 360 + i * 44, cText);
  if BtnV('BACK', 300, 1180, 300, 64, False, 'back', 'ESC') then begin Screen := scTitle; PlaySound(snClick); end;
end;

procedure DrawBriefing;
var
  d: TLevelDef;
  o: TOrbital;
begin
  d := G.Def;
  o := G.Orb[0];
  Dim(170);
  TextV(fkSmallBold, Format('LEVEL %d OF %d   .   WORLD %d  %s', [G.Level + 1, LevelCount, d.World + 1, WorldNames[d.World]]), 450, 530,
    cOrange, alCenter);
  TextV(fkTitle, d.Title, 450, 560, $FFFFFF, alCenter);
  TextV(fkBodyBold, Format('%s     n = %d   l = %d   m = %s     %d radial node(s)',
    [o.Name, o.N, o.L, IfThen(o.M > 0, '+', '') + IntToStr(o.M), Length(o.RadialNodes)]), 450, 660, cText, alCenter);
  TextV(fkSmall, d.Tip, 450, 730, cText, alCenter);
  TextV(fkBodyBold, Format('collect %d quanta in %.0f s', [d.Target, d.TimeSec]), 450, 788, cGold, alCenter);
  if d.Rule <> '' then TextV(fkSmallBold, 'RULES:  ' + d.Rule, 450, 818, cOrange, alCenter);
  if G.BHCount > 0 then
    TextV(fkSmallBold, Format('%s:  %d black hole%s  -  stay out of the dashed ring', [ModeNames[G.Mode], G.BHCount,
      IfThen(G.BHCount > 1, 's', '')]), 450, 846, cRed, alCenter)
  else
    TextV(fkSmallBold, 'CLASSIC: no black holes', 450, 846, cDim, alCenter);
  TextV(fkTiny, 'WASD / mouse to move  .  SPACE flips the spin  .  dark rings drain coherence', 450, 884, cDim, alCenter);
  if BtnV('START', 280, 930, 340, 76, True, 'start', 'ENTER') then StartFromBriefing;
  if BtnV('BACK', 340, 1022, 220, 48, False, 'brief-back', 'ESC') then begin Screen := scLevels; PlaySound(snClick); end;
end;

procedure DrawPaused;
begin
  Dim(150);
  TextV(fkTitle, 'PAUSED', 450, 560, $FFFFFF, alCenter);
  if BtnV('RESUME', 280, 700, 340, 70, True, 'resume', 'P') then begin Screen := scPlaying; PlaySound(snClick); end;
  if BtnV('RESTART', 280, 790, 340, 60, False, 'restart', 'R') then begin PlaySound(snClick); RequestLevel(G.Level); end;
  if BtnV('MENU', 280, 870, 340, 60, False, 'menu', 'Q') then GoMenu;
end;

procedure DrawDemoEnd;
var
  i, w, tot, att, ws, wa: Integer;
  tt, wt: Double;
  y: Single;
begin
  Dim(195);
  TextV(fkSmallBold, 'SUPER-HARD BOT  .  SINGULARITY', 450, 410, cGold, alCenter);
  TextV(fkTitle, Format('ALL %d MAPPED', [LevelCount]), 450, 440, $FFFFFF, alCenter);
  tot := 0; att := 0; tt := 0;
  for w := 0 to WorldCount - 1 do
  begin
    ws := 0; wa := 0; wt := 0;
    for i := w * LevelsPerWorld to w * LevelsPerWorld + LevelsPerWorld - 1 do
    begin
      Inc(ws, DemoScores[i]);
      Inc(wa, DemoAttempts[i]);
      wt := wt + DemoTimes[i];
    end;
    y := 570 + w * 52;
    TextV(fkBodyBold, Format('WORLD %d', [w + 1]), 90, y, $FFFFFF);
    TextV(fkSmall, WorldNames[w], 230, y + 4, cOrange);
    TextV(fkSmall, Format('score %d   .   attempts %d   .   %.0f s', [ws, wa, wt]), 810, y + 4, cText, alRight);
    Inc(tot, ws);
    Inc(att, wa);
    tt := tt + wt;
  end;
  TextV(fkBodyBold, Format('total score %d   .   attempts %d / %d levels   .   %.0f s played', [tot, att, LevelCount, tt]), 450, 850,
    cGold, alCenter);
  TextV(fkTiny, Format('bot inputs %d   (mouse presses %d, key changes %d)', [DemoInputs, DemoMouseUses, DemoKeyUses]), 450, 894,
    cDim, alCenter);
  if BtnV('REPLAY', 120, 960, 300, 64, True, 'demo-replay', 'ENTER') then StartDemo;
  if BtnV('MENU', 480, 960, 300, 64, False, 'menu', 'Q') then GoMenu;
end;

procedure DrawResult;
var
  t: string;
  won: Boolean;
begin
  if DemoMode and DemoDone then
  begin
    DrawDemoEnd;
    Exit;
  end;
  won := G.State = gsWon;
  Dim(175);
  if won then t := 'ORBITAL MAPPED'
  else if G.LostToBH then t := 'SPAGHETTIFIED'
  else if G.Coherence <= 0 then t := 'DECOHERED'
  else t := 'TIME UP';
  TextV(fkSmallBold, Format('LEVEL %d  .  %s  %s', [G.Level + 1, G.Active.Name, G.Def.Title]), 450, 500, cOrange, alCenter);
  TextV(fkTitle, t, 450, 530, Pick(won, $FFFFFF, cRed), alCenter);
  DrawStars(450, 680, 34, G.Stars);
  TextV(fkTitle, IntToStr(G.Score), 450, 740, $FFFFFF, alCenter);
  if NewBest then TextV(fkSmallBold, 'NEW BEST', 450, 830, cGold, alCenter);
  TextV(fkSmall, Format('quanta %d / %d   .   photons %d   .   best combo %d', [G.Collected, G.Def.Target, G.Bonuses, G.BestCombo]),
    450, 870, cText, alCenter);
  TextV(fkSmall, Format('spin flips %d   .   node crossings %d   .   coherence %.0f %%   .   %.1f s',
    [G.Flips, G.NodeCrossings, G.Coherence * 100, G.Elapsed]), 450, 906, cText, alCenter);
  if G.BHCount > 0 then
    TextV(fkSmall, Format('%s  .  %d black holes  .  horizon %d  .  eaten %d  .  edge x2  %d',
      [ModeNames[G.Mode], G.BHCount, G.HorizonHits, G.Swallowed, G.EdgeBonuses]), 450, 940, cGold, alCenter);
  TextV(fkTiny, Format('2 stars: %d   .   3 stars: %d', [G.StarScore(2), G.StarScore(3)]), 450, 970, cDim, alCenter);
  if won and (G.Level < LevelCount - 1) then
    if BtnV('NEXT LEVEL', 280, 1000, 340, 70, True, 'next', 'ENTER') then begin PlaySound(snClick); RequestLevel(G.Level + 1); end;
  if BtnV('RETRY', 120, 1086, 300, 60, not won, 'retry', 'R') then begin PlaySound(snClick); RequestLevel(G.Level); end;
  if BtnV('MENU', 480, 1086, 300, 60, False, 'menu', 'Q') then GoMenu;
  if DemoMode then
    TextV(fkSmallBold, Format('SUPER BOT:  %s in %.0f s', [IfThen(won, IfThen(G.Level < LevelCount - 1, 'next level', 'final summary'),
      'retry'), Max(0, 3.2 - DemoT)]), 450, 1170, cGold, alCenter);
end;

const
  MenuName: array[TScreen] of string = ('title', 'levels', 'help', 'briefing', 'playing', 'paused', 'result');

procedure DrawLoading;
begin
  SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
  SDL_RenderClear(Ren);
  SetView;
  UseOverlay;
  TextV(fkSmallBold, 'SAMPLING |psi|^2 ...', 450, 760, cOrange, alCenter);
  TextV(fkTiny, Format('%dk particles x 2 spins', [Points div 1000]), 450, 800, cDim, alCenter);
end;

{ ---------------------------------------------------------------- game step }

procedure HandleGameEvents;
var
  e: TGameEvent;
  sx, sy: Single;
  i: Integer;
begin
  Project(G.PX, G.PY, 0, sx, sy);
  repeat
    e := G.PopEvent;
    case e of
      geStart: PlaySound(snStart);
      gePickup:
        begin
          i := Min(4, G.Combo);
          PlaySound(TSoundId(Ord(snPick0) + i));
          AddFx(sx, sy, FxC(fxColSlow), '+' + IntToStr(Round(100 * Min(3, 1 + G.Combo * 0.25))));
        end;
      geBonus:
        begin
          PlaySound(snBonus);
          AddFx(sx, sy, cGold, 'PHOTON +' + IntToStr(Round(500 * Min(3, 1 + G.Combo * 0.25))), 1.3);
        end;
      geFlip:
        begin
          PlaySound(snFlip);
          FlipFlash := 1;
          AddFx(sx, sy, Pick(G.Spin > 0, cCyan, $FF7AD9), IfThen(G.Spin > 0, 'SPIN UP', 'SPIN DOWN'), 1.0);
        end;
      geFlipDenied: PlaySound(snDenied, 0.6);
      geNodeEnter: PlaySound(snNode, 0.7);
      geLowCoherence: PlaySound(snLow);
      geTimeWarn: PlaySound(snTime);
      geWin: PlaySound(snWin);
      geFail: PlaySound(snFail);
      geSwallow: PlaySound(snSwallow, 0.8);
      geHorizon:
        begin
          PlaySound(snHorizon);
          HorizonFlash := 1;
          if G.LostToBH then AddFx(sx, sy, cRed, 'SPAGHETTIFIED', 1.6)
          else
          begin
            Project(G.PX, G.PY, 0, sx, sy);
            AddFx(sx, sy, cGold, 'HAWKING EJECTION', 1.6);
          end;
        end;
      geEdgeBonus:
        begin
          PlaySound(snEdge, 0.8);
          AddFx(sx, sy + LV(40), cGold, 'EDGE x2', 1.1);
        end;
      geTidal: PlaySound(snTidal, 0.7);
    end;
  until e = geNone;
end;

procedure FinishLevel;
var
  lv: Integer;
begin
  lv := G.Level;
  NewBest := False;
  if DemoMode then
  begin
    DemoTimes[lv] := DemoTimes[lv] + G.Elapsed;
    if G.State = gsWon then DemoScores[lv] := G.Score;
    DemoAdd(Format('level %d %s  score %d', [lv + 1, IfThen(G.State = gsWon, 'WON', 'LOST'), G.Score]));
    DemoWrite(Format('level %d %s %s  attempt %d  score %d  %.1f s  flips %d  horizon %d  eaten %d',
      [lv + 1, G.Active.Name, IfThen(G.State = gsWon, 'WON ', 'LOST'), DemoAttempts[lv], G.Score, G.Elapsed, G.Flips,
      G.HorizonHits, G.Swallowed]));
  end;
  if not AttractMode and not DemoMode and not PreviewMode then
  begin
    if G.Score > BestScore[G.Mode, lv] then
    begin
      BestScore[G.Mode, lv] := G.Score;
      NewBest := G.State = gsWon;
    end;
    if G.State = gsWon then
    begin
      BestStars[G.Mode, lv] := Max(BestStars[G.Mode, lv], G.Stars);
      Unlocked[G.Mode] := Max(Unlocked[G.Mode], Min(LevelCount, lv + 2));
    end;
    SaveProgress;
  end;
  Screen := scResult;
end;

{ the demo bot sends input like a person: the left mouse held at a screen point
  (the probe steers towards the cursor) or W A S D when its wanted direction
  lines up with a key direction (8 directions, hysteresis 8 / 18 deg), SPACE to
  flip the spin }
procedure DemoInput;
var
  ax, ay, rx, ry, ux, uy, n, a, b, ang, err, lim: Double;
  fl, mouse, kw, ka, ks, kd: Boolean;
  k: Integer;
  sx, sy: Single;
  desc: string;
begin
  G.BotInput(ax, ay, fl);
  if fl then
  begin
    FlipReq := True;
    DemoSpaceT := 0.35;
    DemoAdd('SPACE  flip spin -> ' + IfThen(G.Spin > 0, 'DOWN', 'UP'));
  end;
  { plane direction -> screen right / up components (inverse of ScreenToPlane) }
  rx := Cam.Right[0]; ry := Cam.Right[1]; ux := Cam.Up[0]; uy := Cam.Up[1];
  n := Hypot(rx, ry); if n > 0 then begin rx := rx / n; ry := ry / n; end;
  n := Hypot(ux, uy); if n > 0 then begin ux := ux / n; uy := uy / n; end;
  a := ax * rx + ay * ry;
  b := ax * ux + ay * uy;
  n := Hypot(a, b);
  kw := False; ka := False; ks := False; kd := False; mouse := False;
  if n > 0.1 then
  begin
    ang := ArcTan2(b, a);
    k := Round(ang / (Pi / 4));
    err := Abs(ang - k * Pi / 4);
    if DemoUseKeys then lim := DegToRad(18) else lim := DegToRad(8);
    DemoUseKeys := err < lim;
    if DemoUseKeys then
    begin
      kd := Round(Cos(k * Pi / 4)) > 0;
      ka := Round(Cos(k * Pi / 4)) < 0;
      kw := Round(Sin(k * Pi / 4)) > 0;
      ks := Round(Sin(k * Pi / 4)) < 0;
    end
    else if Project(G.PX, G.PY, 0, sx, sy) then
    begin
      mouse := True;
      MouseX := EnsureRange(sx + a / n * LV(150), 2, OutW - 2);
      MouseY := EnsureRange(sy - b / n * LV(150), 2, OutH - 2);
    end;
  end;
  if mouse and not DemoMouseL then
  begin
    DemoClickT := 0;
    DemoClickX := MouseX;
    DemoClickY := MouseY;
    Inc(DemoMouseUses);
    DemoAdd(Format('LMB press at (%d, %d)', [Round(MouseX), Round(MouseY)]));
  end
  else if not mouse and DemoMouseL then
    DemoAdd('LMB release');
  DemoMouseL := mouse;
  MouseDownL := mouse;
  if (kw <> KeyU) or (ka <> KeyL) or (ks <> KeyD) or (kd <> KeyR) then
  begin
    desc := '';
    if kw then desc := desc + 'W ';
    if ka then desc := desc + 'A ';
    if ks then desc := desc + 'S ';
    if kd then desc := desc + 'D ';
    if desc <> '' then
    begin
      Inc(DemoKeyUses);
      DemoAdd(Trim(desc) + '  (keyboard)');
    end;
  end;
  KeyU := kw; KeyL := ka; KeyD := ks; KeyR := kd;
end;

{ demo flow: briefing -> play -> result -> next level / retry -> ... -> done }
procedure DemoTick(ADt: Double);
var
  i, tot: Integer;
  tt: Double;
begin
  if Screen <> DemoPrevScreen then
  begin
    DemoT := 0;
    DemoPrevScreen := Screen;
  end;
  DemoT := DemoT + ADt;
  DemoSpaceT := DemoSpaceT - ADt;
  DemoEnterT := DemoEnterT - ADt;
  DemoRT := DemoRT - ADt;
  DemoClickT := DemoClickT + ADt;
  if PendingLevel >= 0 then Exit;
  case Screen of
    scBriefing:
      if DemoT > 1.8 then
      begin
        DemoEnterT := 0.35;
        DemoAdd(Format('ENTER  start level %d', [G.Level + 1]));
        StartFromBriefing;
      end;
    scResult:
      if not DemoDone and (DemoT > 3.2) then
        if G.State = gsWon then
        begin
          if G.Level < LevelCount - 1 then
          begin
            DemoEnterT := 0.35;
            DemoAdd('ENTER  next level');
            RequestLevel(G.Level + 1);
          end
          else
          begin
            DemoDone := True;
            DemoAdd(Format('ALL %d ORBITALS MAPPED', [LevelCount]));
            tot := 0; tt := 0;
            for i := 0 to LevelCount - 1 do
            begin
              Inc(tot, DemoScores[i]);
              tt := tt + DemoTimes[i];
            end;
            DemoWrite(Format('DONE  total score %d  total time %.1f s', [tot, tt]));
            if DemoExit then Running := False;
          end;
        end
        else
        begin
          DemoRT := 0.35;
          DemoAdd(Format('R  retry level %d', [G.Level + 1]));
          RequestLevel(G.Level);
        end;
  end;
end;

procedure StepGame(ADt: Double);
var
  ax, ay, dx, dy, n: Double;
  sx, sy: Single;
  fl, bf: Boolean;
begin
  if DemoMode and (Screen = scPlaying) then DemoInput;
  ax := 0; ay := 0;
  fl := FlipReq;
  FlipReq := False;
  if BotOn or AttractMode then
  begin
    G.BotInput(ax, ay, bf);
    fl := fl or bf;
  end
  else
  begin
    dx := Ord(KeyR) - Ord(KeyL);
    dy := Ord(KeyU) - Ord(KeyD);
    if MouseDownL and Project(G.PX, G.PY, 0, sx, sy) then
    begin
      dx := MouseX - sx;
      dy := -(MouseY - sy);
      n := Hypot(dx, dy);
      if n < LV(12) then begin dx := 0; dy := 0; end
      else begin dx := dx / n; dy := dy / n; end;
    end;
    ScreenToPlane(dx, dy, ax, ay);
  end;
  G.Update(ADt, ax, ay, fl);
  TrailX[TrailPos] := G.PX;
  TrailY[TrailPos] := G.PY;
  TrailPos := (TrailPos + 1) mod Length(TrailX);
  TrailN := Min(Length(TrailX), TrailN + 1);
  if AttractMode then
  begin
    while G.PopEvent <> geNone do ;
    if G.State <> gsPlaying then
    begin
      G.Mode := gmBlackHole;
      G.StartLevel(G.Level, Points, 4242, Random(100000) + 1);
      TrailN := 0;
    end;
  end
  else
  begin
    HandleGameEvents;
    if G.State <> gsPlaying then FinishLevel;
  end;
end;

{ ---------------------------------------------------------------- PNG }

function SavePNG(const AFile: string): Boolean;
var
  surf, conv: PSDL_Surface;
begin
  Result := False;
  surf := SDL_RenderReadPixels(Ren, nil);
  if surf = nil then Exit;
  if surf^.format <> SDL_PIXELFORMAT_ARGB8888 then
  begin
    conv := SDL_ConvertSurface(surf, SDL_PIXELFORMAT_ARGB8888);
    SDL_DestroySurface(surf);
    surf := conv;
  end;
  ForceDirectories(ExtractFileDir(ExpandFileName(AFile)));
  Result := IMG_SavePNG(surf, PAnsiChar(AnsiString(AFile)));
  SDL_DestroySurface(surf);
end;

{ ---------------------------------------------------------------- input }

{ ---------------------------------------------------------------- layer outlines (F3) }

procedure DashRect(X, Y, W, H, T: Single; ACol: UInt32; AAlpha: Byte);
var
  p, seg, gap: Single;
begin
  seg := 4; gap := 4;
  p := 0;
  while p < W do
  begin
    Hud.Rect(X + p, Y, Min(seg, W - p), T, ACol, AAlpha);
    Hud.Rect(X + p, Y + H - T, Min(seg, W - p), T, ACol, AAlpha);
    p := p + seg + gap;
  end;
  p := 0;
  while p < H do
  begin
    Hud.Rect(X, Y + p, T, Min(seg, H - p), ACol, AAlpha);
    Hud.Rect(X + W - T, Y + p, T, Min(seg, H - p), ACol, AAlpha);
    p := p + seg + gap;
  end;
end;

function KindColor(const AKind: string): UInt32;
begin
  if AKind = 'button' then Result := cOrange
  else if AKind = 'inset' then Result := $FF7AD9
  else if AKind = 'world' then Result := $7CFF7C
  else if AKind = 'menu' then Result := cGold
  else Result := cCyan;
end;

procedure DrawLayerOutlines;
var
  i: Integer;
  col: UInt32;
  hi: Boolean;
  lh, t: Single;
  keep: THud;
begin
  if not ShowOutlines and (HoverLayer = '') and (PinnedLayer = '') then Exit;
  keep := Hud;
  Hud := HudLbl;
  HudLbl.SetScale(Max(0.5, OutH / 1100));
  lh := HudLbl.LineHeight(fkTiny);
  for i := 0 to LayerN - 1 do
    with Layers[i] do
    begin
      if R.w < 0 then Continue;
      hi := (Name = HoverLayer) or (Name = PinnedLayer);
      if not ShowOutlines and not hi then Continue;
      col := KindColor(Kind);
      { hair-line dashes (1 px) for every layer, also the selected one }
      t := 1;
      if hi then Hud.Rect(R.x, R.y, R.w, R.h, col, 28);
      DashRect(R.x, R.y, R.w, R.h, t, col, Pick(hi, 255, 150));
      if ShowLabels or hi then
      begin
        if R.y >= lh + 2 then
          HudLbl.Text(fkTiny, Name, R.x + 2, R.y - lh - 1, col)
        else
          HudLbl.Text(fkTiny, Name, R.x + 3, R.y + 2, col);
      end;
    end;
  Hud := keep;
end;

{ ---------------------------------------------------------------- developer window (F2) }

const
  DevWinW = 700;                 { developer window width (window units) }

var
  DevWin: PSDL_Window;
  DevRen: PSDL_Renderer;
  DevHud: THud;
  DevUI: TUI;
  DevScroll, DevRedrawT, DevContentH, DevU: Single;
  DevOutW, DevOutH: Integer;
  DevShotFile, LayoutFile: string;
  DevTab: Integer;               { 0 PHYSICS, 1 PARAMETERS, 2 LAYERS, 3 STATE }
  DevRightPress: Boolean;        { right button pressed in the developer window (this frame) }
  DevRightX, DevRightY: Single;
  PopupRow: Integer = -1;        { layer index of the open right-click menu, -1 = closed }
  PopupX, PopupY: Single;
  RowRectsName: array of string; { LAYERS rows on screen (for --ui-test) }
  RowRectsY: array of Single;
  ClipText: string;              { last text copied to the clipboard }
  DevPlotCount: Integer;         { plots drawn in the last PHYSICS frame (ui-test) }

const
  DevTabNames: array[0..3] of string = ('PHYSICS', 'PARAMETERS', 'LAYERS', 'STATE');

function DevId: TSDL_WindowID;
begin
  if DevWin = nil then Result := 0 else Result := SDL_GetWindowID(DevWin);
end;

procedure DevOpen;
var
  x, y, w, h: Integer;
  rc: TSDL_Rect;
begin
  if DevWin <> nil then Exit;
  if SDL_GetWindowSize(Win, @w, @h) then h := Max(400, h) else h := 900;
  DevWin := SDL_CreateWindow('PAULI SURFER 2 - Developer  (F2 close, F3 outlines, F4 labels)', DevWinW, h,
    SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if DevWin = nil then
  begin
    Flash('developer window: ' + SDLErr);
    Exit;
  end;
  SDL_SetWindowMinimumSize(DevWin, 480, 400);
  if SDL_GetWindowPosition(Win, @x, @y) and SDL_GetWindowSize(Win, @w, @h) then
  begin
    if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @rc) then begin rc.x := 0; rc.w := 1920; end;
    if x + w + 12 + DevWinW <= rc.x + rc.w then SDL_SetWindowPosition(DevWin, x + w + 12, y)
    else SDL_SetWindowPosition(DevWin, Max(rc.x, rc.x + rc.w - DevWinW - 12), y + 40);
  end;
  DevRen := SDL_CreateRenderer(DevWin, nil);
  SDL_SetRenderVSync(DevRen, 0);
  SDL_SetRenderDrawBlendMode(DevRen, SDL_BLENDMODE_BLEND);
  DevHud := THud.Create(DevRen);
  DevUI := TUI.Create(DevHud);
  DevRedrawT := 0;
  DevScroll := 0;
  SDL_RaiseWindow(Win);
end;

procedure DevClose;
begin
  if DevWin = nil then Exit;
  DevUI.Free;
  DevHud.Free;
  SDL_DestroyRenderer(DevRen);
  SDL_DestroyWindow(DevWin);
  DevWin := nil; DevRen := nil; DevUI := nil; DevHud := nil;
  HoverLayer := '';
  PinnedLayer := '';
end;

function F1(X: Double): string;
begin
  Result := FloatToStrF(X, ffFixed, 8, 1, SfxFS);
end;

function F3(X: Double): string;
begin
  Result := FloatToStrF(X, ffFixed, 8, 3, SfxFS);
end;

procedure ExportLayout;
var
  t: TStringList;
  i: Integer;
  base: string;
const
  ScreenNames: array[TScreen] of string = ('title', 'levels', 'help', 'briefing', 'playing', 'paused', 'result');
begin
  base := ExeDir + 'exports' + PathDelim + 'layout';
  ForceDirectories(ExeDir + 'exports');
  t := TStringList.Create;
  try
    t.Add('{');
    t.Add(Format('  "window": [%d, %d], "screen": "%s", "hud_size": %s, "zoom": %s, "canvas": [%s, %s],',
      [OutW, OutH, ScreenNames[Screen], F3(HudScale), F3(ZoomF), F1(CW), F1(CH)]));
    t.Add('  "layers": [');
    for i := 0 to LayerN - 1 do
      with Layers[i] do
        t.Add(Format('    {"name": "%s", "kind": "%s", "x": %s, "y": %s, "w": %s, "h": %s, "rel": [%s, %s, %s, %s]}%s',
          [Name, Kind, F1(R.x), F1(R.y), F1(R.w), F1(R.h), F3(R.x / OutW), F3(R.y / OutH), F3(R.w / OutW), F3(R.h / OutH),
          IfThen(i < LayerN - 1, ',', '')]));
    t.Add('  ]');
    t.Add('}');
    t.SaveToFile(base + '.json');
    t.Clear;
    t.Add(Format('# PAULI SURFER 2 layout  %d x %d px  (%s)', [OutW, OutH, ScreenNames[Screen]]));
    t.Add('');
    t.Add('| # | layer | kind | x | y | w | h | x % | y % | w % | h % |');
    t.Add('|---|---|---|---|---|---|---|---|---|---|---|');
    for i := 0 to LayerN - 1 do
      with Layers[i] do
        t.Add(Format('| %d | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |', [i, Name, Kind, F1(R.x), F1(R.y), F1(R.w), F1(R.h),
          F1(100 * R.x / OutW), F1(100 * R.y / OutH), F1(100 * R.w / OutW), F1(100 * R.h / OutH)]));
    t.SaveToFile(base + '.md');
    LayoutFile := base + '.json';
    Flash('layout exported: ' + base + '.json / .md');
  finally
    t.Free;
  end;
end;

{ one layer as a line of text: easy to paste into a message }
function LayerLine(I: Integer): string;
begin
  with Layers[I] do
    Result := Format('%s  %s  x=%s y=%s w=%s h=%s px  (x %s%% y %s%% w %s%% h %s%%)  window %dx%d',
      [Name, Kind, F1(R.x), F1(R.y), F1(R.w), F1(R.h), F1(100 * R.x / OutW), F1(100 * R.y / OutH), F1(100 * R.w / OutW),
      F1(100 * R.h / OutH), OutW, OutH]);
end;

procedure CopyText(const S: string; const AWhat: string);
begin
  ClipText := S;
  SDL_SetClipboardText(PAnsiChar(AnsiString(S)));
  Flash('copied ' + AWhat);
end;

procedure CopyAllLayers;
var
  i: Integer;
  t: string;
begin
  t := Format('PAULI SURFER 2 layers, window %dx%d', [OutW, OutH]);
  for i := 0 to LayerN - 1 do
    if Layers[i].R.w >= 0 then t := t + LineEnding + LayerLine(i);
  CopyText(t, IntToStr(LayerN) + ' layers');
end;

procedure DevDraw(ADt: Double);
var
  u, y, top, rowH: Single;
  i, bi: Integer;
  clip: TSDL_Rect;
  surf, conv: PSDL_Surface;
  bx, by: Double;
  nm: string;
  hovered: Boolean;
  clip_f: TSDL_FRect;
  t: Integer;
  px0, py0, pw, ph, pxmax, pymin, pymax: Single;
  xs, ys: array of Double;
  o: TOrbital;
  dp: TGameParams;

  procedure Section(const ATitle: string);
  begin
    y := y + 10 * u;
    DevHud.Text(fkSmallBold, ATitle, 14 * u, y, cOrange);
    DevHud.Rect(14 * u, y + 20 * u, DevOutW - 28 * u, 1, $FFFFFF, 40);
    y := y + 26 * u;
  end;

  procedure Row(const AKey, AValue: string; ACol: UInt32 = cText);
  begin
    if (y > top - 24 * u) and (y < DevOutH) then
    begin
      DevHud.Text(fkSmall, AKey, 14 * u, y, cDim);
      DevHud.Text(fkSmall, AValue, 260 * u, y, ACol);
    end;
    y := y + rowH;
  end;

  { ---- plots (dev pixel coordinates) }
  function PlotBegin(const ATitle: string; AXMax, AYMin, AYMax, AH: Single): Boolean;
  begin
    if (y > top - 24 * u) and (y < DevOutH) then DevHud.Text(fkTiny, ATitle, 30 * u, y, cDim);
    y := y + 16 * u;
    px0 := 30 * u; pw := DevOutW - 60 * u; py0 := y; ph := AH * u;
    pxmax := Max(1e-9, AXMax); pymin := AYMin; pymax := AYMax;
    Result := (py0 + ph > top) and (py0 < DevOutH);
    if Result then DevHud.Rect(px0, py0, pw, ph, $0F1117);
    Inc(DevPlotCount);
  end;

  function PXm(X: Double): Single;
  begin
    Result := px0 + pw * EnsureRange(X / pxmax, 0, 1);
  end;

  function PYm(Y: Double): Single;
  begin
    Result := py0 + ph * (1 - EnsureRange((Y - pymin) / Max(1e-9, pymax - pymin), 0, 1));
  end;

  procedure PLine(AN: Integer; ACol: UInt32);
  var
    pts: array of TSDL_FPoint;
    i: Integer;
  begin
    if AN < 2 then Exit;
    SetLength(pts, AN);
    for i := 0 to AN - 1 do
    begin
      pts[i].x := PXm(xs[i]);
      pts[i].y := PYm(ys[i]);
    end;
    SDL_SetRenderDrawColor(DevRen, (ACol shr 16) and $FF, (ACol shr 8) and $FF, ACol and $FF, 255);
    SDL_RenderLines(DevRen, @pts[0], AN);
  end;

  procedure PVLine(X: Double; ACol: UInt32; AAlpha: Byte = 220);
  begin
    DevHud.Rect(PXm(X), py0, Max(1, u), ph, ACol, AAlpha);
  end;

  procedure PHLine(Y: Double; ACol: UInt32; AAlpha: Byte = 90);
  begin
    DevHud.Rect(px0, PYm(Y), pw, 1, ACol, AAlpha);
  end;

  procedure PlotEnd(const AL, AM, AR: string);
  begin
    y := py0 + ph + 3 * u;
    if (y > top - 24 * u) and (y < DevOutH) then
    begin
      DevHud.Text(fkTiny, AL, px0, y, cDim);
      DevHud.Text(fkTiny, AM, px0 + pw / 2, y, cDim, alCenter);
      DevHud.Text(fkTiny, AR, px0 + pw, y, cDim, alRight);
    end;
    y := y + 20 * u;
  end;

  function JoinNodes(const A: array of Double; AUnit: string): string;
  var
    i: Integer;
  begin
    Result := '';
    for i := 0 to High(A) do
    begin
      if i > 0 then Result := Result + ', ';
      Result := Result + FloatToStrF(A[i], ffFixed, 8, 2, SfxFS);
    end;
    if Result = '' then Result := '-' else Result := Result + AUnit;
  end;

  procedure PhysicsTab;
  var
    i, n, step, k, sp: Integer;
    rmax, sv, w, rho, raw: Double;
  begin
    o := G.Active;
    Section('QUANTUM STATE');
    Row('orbital', Format('%s   n = %d   l = %d   m = %d', [o.Name, o.N, o.L, o.M]));
    Row('current model', ModelName(G.Spin) + Format('   (sigma_z = %d,  SPACE flips)', [G.Spin]));
    Row('energy  -1/(2n^2)', FloatToStrF(o.EnergyHa, ffGeneral, 6, 0, SfxFS) + ' Ha   =   ' +
      FloatToStrF(o.EnergyHa * 27.211386, ffGeneral, 6, 0, SfxFS) + ' eV');
    Row('degeneracy (n^2, no spin)', IntToStr(o.N * o.N));
    Row('Pauli current  omega(s, z)', 'm/s^2  -  (sigma / 2s) d ln rho / ds     (s = r sin theta)');

    Section('ORBITAL GEOMETRY');
    Row('radial nodes  n-l-1', IntToStr(o.N - o.L - 1) + '   at r = ' + JoinNodes(o.RadialNodes, ' a0'));
    Row('angular nodes  l-|m|', IntToStr(o.L - Abs(o.M)) + '   at theta = ' + JoinNodes(o.AngularNodesDeg, ' deg'));
    Row('<r> = (3n^2 - l(l+1))/2', F1((3 * o.N * o.N - o.L * (o.L + 1)) / 2) + ' a0');
    Row('r50 / r95 / r99.9', F3(o.R50) + ' / ' + F3(o.RView) + ' / ' + F3(o.RMax) + ' a0');
    Row('rho_c (85 % iso, unnorm.)', FloatToStrF(o.RhoC, ffGeneral, 5, 0, SfxFS));
    Row('circulation CCW / CW', F1(o.CCWFrac * 100) + ' %  /  ' + F1((1 - o.CCWFrac) * 100) + ' %');
    Row('game bands (radial nodes + 1)', Format('%d   probe in band %d', [Length(o.RadialNodes) + 1, G.ProbeRing + 1]));

    { radial probability with nodes, probe and black holes }
    rmax := o.RMax;
    if PlotBegin('radial probability r^2 R^2 (peak 1)   blue = radial nodes   cyan = probe   red = black holes', rmax, 0, 1.08, 120) then
    begin
      n := Length(o.RTabR);
      step := Max(1, n div 700);
      SetLength(xs, 0); SetLength(ys, 0);
      i := 0;
      while (i < n) and (o.RTabR[i] <= rmax) do
      begin
        SetLength(xs, Length(xs) + 1); SetLength(ys, Length(ys) + 1);
        xs[High(xs)] := o.RTabR[i]; ys[High(ys)] := o.RTabP[i];
        Inc(i, step);
      end;
      for i := 0 to High(o.RadialNodes) do PVLine(o.RadialNodes[i], cBlue);
      for k := 0 to G.BHCount - 1 do PVLine(G.BH[k].S, cRed, 200);
      PVLine(Hypot(G.PX, G.PY), cCyan, 255);
      PLine(Length(xs), cOrange);
    end;
    PlotEnd('0 a0', F1(rmax / 2) + ' a0', F1(rmax) + ' a0');

    if PlotBegin('polar probability sin(theta) P^2 (peak 1)   blue = angular nodes   cyan = game plane z = 0 (90 deg)', Pi, 0, 1.08, 90) then
    begin
      n := Length(o.ATabT);
      step := Max(1, n div 700);
      SetLength(xs, 0); SetLength(ys, 0);
      i := 0;
      while i < n do
      begin
        SetLength(xs, Length(xs) + 1); SetLength(ys, Length(ys) + 1);
        xs[High(xs)] := o.ATabT[i]; ys[High(ys)] := o.ATabP[i];
        Inc(i, step);
      end;
      for i := 0 to High(o.AngularNodesDeg) do PVLine(DegToRad(o.AngularNodesDeg[i]), cBlue);
      PVLine(Pi / 2, cCyan, 255);
      PLine(Length(xs), cOrange);
    end;
    PlotEnd('0 deg', '90 deg', '180 deg');

    Section('CURRENT IN THE GAME PLANE  z = 0');
    sv := Max(1e-6, Hypot(G.PX, G.PY));
    raw := o.FieldAt(sv, 0, G.Spin, rho);
    Row('at the probe: omega raw / display', FloatToStrF(raw, ffGeneral, 5, 0, SfxFS) + ' a.u.   /   ' + F3(G.ProbeOmega) +
      ' rad/s  (' + G.RingDirection + ')');
    Row('tangential speed / probe top speed', F3(Abs(G.ProbeOmega) * sv / G.RView) + '  /  ' + F3(GP.MaxSelfSpeed) + ' RView/s');
    Row('rho at probe (unnorm.)', FloatToStrF(rho, ffGeneral, 5, 0, SfxFS));
    Row('game flow = display x FlowScale', F3(GP.FlowScale) + '   cap ' + F3(GP.MaxFlowSpeed) + ' RView/s');
    if PlotBegin('tangential current v = omega s (RView/s) vs s   orange = spin up   blue = spin down   (current spin brighter)   dashes = +- top speed',
      1.15 * G.RView, -1, 1, 130) then
    begin
      PHLine(0, $FFFFFF, 70);
      PHLine(GP.MaxSelfSpeed, $FFFFFF, 40);
      PHLine(-GP.MaxSelfSpeed, $FFFFFF, 40);
      for i := 0 to High(o.RadialNodes) do PVLine(o.RadialNodes[i], cBlue, 120);
      for k := 0 to G.BHCount - 1 do PVLine(G.BH[k].S, cRed, 160);
      PVLine(sv, cCyan, 255);
      for sp := 0 to 1 do
      begin
        SetLength(xs, 300); SetLength(ys, 300);
        for i := 0 to 299 do
        begin
          xs[i] := 1.15 * G.RView * (i + 1) / 300;
          w := G.OmegaAt(xs[i], 1 - 2 * sp);
          ys[i] := w * xs[i] / G.RView;
        end;
        if (1 - 2 * sp) = G.Spin then PLine(300, Pick(sp = 0, cOrange, cBlue))
        else PLine(300, Pick(sp = 0, $7A4A1A, $27346B));
      end;
    end;
    PlotEnd('0', F1(0.575 * G.RView) + ' a0', F1(1.15 * G.RView) + ' a0');

    Section('SAMPLING  |psi|^2');
    Row('particles / inset points', Format('%d x 2 spins  /  %d', [o.Count, o.InsetCount]));
    Row('sampling time', F1(o.SampleMs) + ' ms  (inverse CDF, radial + polar tables)');
    Row('median |omega|  (a.u.)', FloatToStrF(o.OmegaMedian, ffGeneral, 6, 0, SfxFS));
    Row('p97 clamp |omega|  (a.u.)', FloatToStrF(o.OmegaCap, ffGeneral, 6, 0, SfxFS));
    Row('median speed |omega| s', FloatToStrF(o.SpeedMedian, ffGeneral, 6, 0, SfxFS));
    Row('display time scale', FloatToStrF(o.TimeScale, ffGeneral, 6, 0, SfxFS) + '   (median turn = 10 s at 1x, ' +
      F1(10 / Max(1e-6, GP.FlowScale)) + ' s in the game)');
  end;

  { ---- live parameters }
  function PS(AId: Integer; const ACap, AUnit: string; var V: Double; ADef, AMin, AMax: Double; ADig: Integer = 2): Boolean;
  var
    v2: Double;
    cm: Boolean;
    txt: string;
  begin
    Result := False;
    if (y > top - 40 * u) and (y < DevOutH) then
    begin
      v2 := V;
      txt := FloatToStrF(V, ffFixed, 8, ADig, SfxFS);
      if Abs(V - ADef) > 1e-9 then txt := txt + '   (default ' + FloatToStrF(ADef, ffFixed, 8, ADig, SfxFS) + ')';
      if DevUI.Slider(AId, ACap + '    ' + AUnit, txt, 14 * u, y, DevOutW - 28 * u, v2, AMin, AMax, cm) then
      begin
        V := v2;
        Result := True;
      end;
    end;
    y := y + 38 * u;
  end;

  procedure ApplyBHSize;
  var
    k: Integer;
  begin
    for k := 0 to G.BHCount - 1 do
    begin
      G.BH[k].Rc := GP.BHRc[G.Mode] * G.RView;
      G.BH[k].Rh := G.BH[k].Rc * GP.BHHorizon;
    end;
  end;

  procedure ParamsTab;
  begin
    dp := DefaultGameParams;
    Section('GAME PARAMETERS  (live: the running game uses them at once)');
    if (y > top - 40 * u) and (y < DevOutH) then
      if DevUI.Button('RESET DEFAULTS', 14 * u, y, 170 * u, 30 * u, False, 'dev-reset') then
      begin
        GP := DefaultGameParams;
        ApplyBHSize;
      end;
    y := y + 42 * u;
    Section('FLOW / PROBE');
    PS(901, 'FlowScale', 'x HydrogenFlow display speed', GP.FlowScale, dp.FlowScale, 0.1, 1.5);
    PS(902, 'MaxFlowSpeed', 'RView/s, cap of the current at the probe', GP.MaxFlowSpeed, dp.MaxFlowSpeed, 0.2, 2);
    PS(903, 'MaxQuantumSpeed', 'RView/s, quanta spawn only slower', GP.MaxQuantumSpeed, dp.MaxQuantumSpeed, 0.1, 1.5);
    PS(904, 'MaxSelfSpeed', 'RView/s, probe top speed', GP.MaxSelfSpeed, dp.MaxSelfSpeed, 0.1, 0.8, 3);
    PS(905, 'Accel', 'RView/s^2, thrust', GP.Accel, dp.Accel, 0.4, 4);
    PS(906, 'Drag', '1/s', GP.Drag, dp.Drag, 0.5, 6);
    Section('RADIAL NODES / COHERENCE');
    PS(907, 'NodeProb', 'r^2R^2 / band peak = node', GP.NodeProb, dp.NodeProb, 0.005, 0.15, 3);
    PS(908, 'DrainNode', 'coherence/s inside a node', GP.DrainNode, dp.DrainNode, 0, 1);
    PS(909, 'Recover', 'coherence/s in dense regions', GP.Recover, dp.Recover, 0, 0.3, 3);
    Section('SCORING / TIMING');
    PS(910, 'ComboWindow', 's', GP.ComboWindow, dp.ComboWindow, 1, 10, 1);
    PS(911, 'FlipCooldown', 's', GP.FlipCooldown, dp.FlipCooldown, 0, 3);
    PS(912, 'BonusEvery', 's between Balmer photons', GP.BonusEvery, dp.BonusEvery, 3, 30, 1);
    PS(913, 'BonusLife', 's a photon lives', GP.BonusLife, dp.BonusLife, 2, 15, 1);
    Section('BLACK HOLES  (mode ' + ModeNames[G.Mode] + IfThen(G.Mode = gmClassic, ': none in this mode', '') + ')');
    if PS(914, 'BHRc', 'capture radius (no escape), RView', GP.BHRc[G.Mode], dp.BHRc[G.Mode], 0.02, 0.2, 3) then ApplyBHSize;
    if PS(915, 'BHHorizon', 'Rh / Rc', GP.BHHorizon, dp.BHHorizon, 0.2, 0.9) then ApplyBHSize;
    PS(916, 'BHDrift', 'x local current', GP.BHDrift[G.Mode], dp.BHDrift[G.Mode], 0, 1.5);
    PS(917, 'BHHit', 'coherence lost at the horizon', GP.BHHit[G.Mode], dp.BHHit[G.Mode], 0, 1);
    PS(918, 'BHGrow', 'Rc x per quantum (SINGULARITY)', GP.BHGrow, dp.BHGrow, 1, 1.3, 3);
    PS(919, 'BHRcMax', 'RView, growth limit', GP.BHRcMax, dp.BHRcMax, 0.05, 0.3, 3);
    PS(920, 'BHMaxSink', 'RView/s, cap of the pull', GP.BHMaxSink, dp.BHMaxSink, 0.3, 3);
    PS(921, 'ImmuneTime', 's after a Hawking ejection', GP.ImmuneTime, dp.ImmuneTime, 0, 5, 1);
    PS(922, 'EdgeFactor', 'EDGE x2 radius, x Rc', GP.EdgeFactor, dp.EdgeFactor, 1.2, 5);
    Section('LEVEL  (read only)');
    Row('level', Format('%d / %d  %s  %s', [G.Level + 1, LevelCount, G.Active.Name, G.Def.Title]));
    Row('world', Format('%d  %s', [G.Def.World + 1, WorldNames[G.Def.World]]));
    Row('rules', IfThen(G.Def.Rule = '', 'standard', G.Def.Rule) + Format('   (flow x%.2f, photons x%.2f, node drain x%.2f, spin %s)',
      [G.Def.FlowMul, G.Def.PhotonMul, G.Def.DrainMul, IfThen(G.Def.NoFlip, IfThen(G.Def.StartSpin > 0, 'locked UP', 'locked DOWN'), 'free')]));
    Row('target / time / quanta on screen', Format('%d  /  %s s  /  %d', [G.Def.Target, F1(G.Def.TimeSec), G.Def.Quanta]));
    Row('black holes', IntToStr(BlackHolesFor(G.Mode, G.Level)));
    Section('VIEW');
    PS(923, 'zoom', 'wheel, + / -', ZoomF, 1, 0.7, 1.5, 3);
    PS(924, 'HUD size', '[ / ]', HudScale, 0.575, 0.3, 1.5, 3);
    Row('render scale / particles', F3(RenderScale) + Format('  /  %dk x 2 spins', [Points div 1000]));
    Row('view', ViewNames[ViewMode] + '   (V)');
  end;

begin
  if DevWin = nil then Exit;
  DevRedrawT := DevRedrawT - ADt;
  if (DevRedrawT > 0) and (DevShotFile = '') then Exit;
  DevRedrawT := 1 / 12;
  SDL_GetCurrentRenderOutputSize(DevRen, @DevOutW, @DevOutH);
  DevU := Max(0.75, SDL_GetWindowPixelDensity(DevWin));
  u := DevU;
  DevHud.SetScale(u * 1.05);
  rowH := 19 * u;
  top := 100 * u;
  DevPlotCount := 0;
  SDL_SetRenderDrawColor(DevRen, 9, 10, 14, 255);
  SDL_RenderClear(DevRen);

  DevScroll := EnsureRange(DevScroll, 0, Max(0, DevContentH - (DevOutH - top)));
  clip.x := 0; clip.y := Round(top); clip.w := DevOutW; clip.h := DevOutH - clip.y;
  SDL_SetRenderClipRect(DevRen, @clip);
  y := top + 4 * u - DevScroll;
  HoverLayer := '';
  if DevTab = 0 then PhysicsTab;
  if DevTab = 1 then ParamsTab;
  SetLength(RowRectsName, 0);
  SetLength(RowRectsY, 0);
  if DevTab <> 2 then PopupRow := -1;
  if DevTab = 2 then
  begin
  Section(Format('LAYERS  (%d parts  .  hover = highlight  .  click = pin  .  right click = copy)', [LayerN]));
  if (y > top - 24 * u) and (y < DevOutH) then
  begin
    DevHud.Text(fkTiny, 'NAME', 14 * u, y, cFaint);
    DevHud.Text(fkTiny, 'KIND', 230 * u, y, cFaint);
    DevHud.Text(fkTiny, 'X  Y  W  H  (px)', 300 * u, y, cFaint);
    DevHud.Text(fkTiny, 'x%  y%  w%  h%  of the window', 540 * u, y, cFaint);
  end;
  y := y + rowH;
  for i := 0 to LayerN - 1 do
    with Layers[i] do
    begin
      if R.w < 0 then Continue;
      hovered := (y >= top) and (PopupRow < 0) and DevUI.Inside(0, y - 2 * u, DevOutW, rowH);
      SetLength(RowRectsName, Length(RowRectsName) + 1);
      SetLength(RowRectsY, Length(RowRectsY) + 1);
      RowRectsName[High(RowRectsName)] := Name;
      RowRectsY[High(RowRectsY)] := y - 2 * u + rowH / 2;
      if (y >= top) and DevRightPress and (DevRightY >= y - 2 * u) and (DevRightY < y - 2 * u + rowH) then
      begin
        PopupRow := i;
        PopupX := DevRightX;
        PopupY := DevRightY;
        hovered := True;
      end;
      if hovered or (PopupRow = i) then
      begin
        HoverLayer := Name;
        DevHud.Rect(0, y - 2 * u, DevOutW, rowH, $FFFFFF, 22);
        if hovered and (PopupRow < 0) and DevUI.Pressed then
          if PinnedLayer = Name then PinnedLayer := '' else PinnedLayer := Name;
      end;
      if Name = PinnedLayer then DevHud.Rect(0, y - 2 * u, DevOutW, rowH, KindColor(Kind), 40);
      if (y > top - 24 * u) and (y < DevOutH) then
      begin
        DevHud.Rect(14 * u, y + 5 * u, 8 * u, 8 * u, KindColor(Kind));
        DevHud.Text(fkSmall, Name, 28 * u, y, cText);
        DevHud.Text(fkSmall, Kind, 230 * u, y, KindColor(Kind));
        DevHud.Text(fkSmall, Format('%s  %s  %s  %s', [F1(R.x), F1(R.y), F1(R.w), F1(R.h)]), 300 * u, y, cText);
        DevHud.Text(fkSmall, Format('%s  %s  %s  %s', [F1(100 * R.x / OutW), F1(100 * R.y / OutH), F1(100 * R.w / OutW),
          F1(100 * R.h / OutH)]), 540 * u, y, cDim);
      end;
      y := y + rowH;
    end;
  end;

  if DevTab = 3 then
  begin
  Section('WINDOW / LAYOUT');
  Row('game window', Format('%d x %d  (render %d x %d px)', [WinW, WinH, OutW, OutH]));
  Row('layout', 'corner-anchored HUD, sized by the window height');
  Row('HUD size  /  canvas K', F3(HudScale) + '  /  ' + F3(K) + ' px per unit');
  Row('canvas', F1(CW) + ' x ' + F1(CH) + ' units');
  Row('inset', IntToStr(InsetSz) + ' px');
  Row('render scale / texture', F3(RenderScale) + Format('  /  %d x %d', [TexW, TexH]));
  Row('outlines / labels', BoolToStr(ShowOutlines, 'on', 'off') + '  /  ' + BoolToStr(ShowLabels, 'on', 'off'));

  Section('CAMERA / CLOUD');
  Row('azimuth / elevation / fov', '-90 / 62 / 40 deg');
  Row('distance', F1(CamDist) + ' a0  =  ' + F3(CamDist / Max(1e-9, G.RView)) + ' RView');
  Row('zoom', F3(ZoomF));
  Row('vertical centring shift', F1(CamShift) + ' texture px');
  if FindLayer('cloud', clip_f) then
    Row('cloud box', Format('%s %s %s %s px   centre y %s  (window centre %s)', [F1(clip_f.x), F1(clip_f.y), F1(clip_f.w),
      F1(clip_f.h), F1(clip_f.y + clip_f.h / 2), F1(OutH / 2)]));
  Row('view', ViewNames[ViewMode]);

  Section('GAME');
  Row('mode / level', ModeNames[G.Mode] + Format('  /  %d  %s  %s', [G.Level + 1, G.Active.Name, G.Def.Title]));
  Row('state', IfThen(G.State = gsPlaying, 'playing', IfThen(G.State = gsWon, 'won', 'lost')) +
    IfThen(AttractMode, '  (attract)', '') + IfThen(BotOn, '  (bot)', ''));
  Row('time left / elapsed', F1(G.TimeLeft) + ' / ' + F1(G.Elapsed) + ' s');
  Row('score / quanta', Format('%d  /  %d of %d', [G.Score, G.Collected, G.Def.Target]));
  Row('combo / best', Format('%d / %d', [G.Combo, G.BestCombo]));
  Row('coherence', F3(G.Coherence), Pick(G.Coherence < 0.3, cRed, cText));
  Row('spin / flips / cooldown', Format('%d / %d / ', [G.Spin, G.Flips]) + F1(G.FlipCool) + ' s');
  Row('node crossings / photons', Format('%d / %d', [G.NodeCrossings, G.Bonuses]));

  Section('PROBE');
  Row('position', F1(G.PX) + ', ' + F1(G.PY) + ' a0   r = ' + F1(Hypot(G.PX, G.PY)));
  Row('own velocity', F3(G.VX / G.RView) + ', ' + F3(G.VY / G.RView) + ' RView/s');
  Row('current at probe', F3(G.FlowVX / G.RView) + ', ' + F3(G.FlowVY / G.RView) + ' RView/s   omega ' + F3(G.ProbeOmega));
  Row('P(r) / band', F3(G.ProbeProb) + Format('  /  %d of %d', [G.ProbeRing + 1, Length(G.Active.RadialNodes) + 1]));
  Row('tidal / immune', F3(G.Tidal) + ' / ' + F1(G.Immune) + ' s', Pick(G.Tidal >= 0.95, cRed, cText));

  Section(Format('BLACK HOLES  (%d)', [G.BHCount]));
  for bi := 0 to G.BHCount - 1 do
  begin
    G.BHPos(bi, bx, by);
    Row('blackhole.' + IntToStr(bi), Format('s %s  phi %s deg  Rc %s  Rh %s a0  eaten %d', [F1(G.BH[bi].S),
      F1(RadToDeg(G.BH[bi].Phi) - 360 * Floor(RadToDeg(G.BH[bi].Phi) / 360)), F1(G.BH[bi].Rc), F1(G.BH[bi].Rh), G.BH[bi].Eaten]));
  end;
  Row('horizon hits / swallowed / edge x2', Format('%d / %d / %d', [G.HorizonHits, G.Swallowed, G.EdgeBonuses]));

  Section('QUANTA');
  for bi := 0 to MaxQuanta - 1 do
    with G.Quanta[bi] do
      if Alive then
      begin
        nm := IfThen(Bonus, 'photon.', 'quantum.') + IntToStr(bi);
        Row(nm, Format('s %s a0  phi %s deg  particle %d%s', [F1(S), F1(RadToDeg(Phi) - 360 * Floor(RadToDeg(Phi) / 360)), Idx,
          IfThen(Bonus, Format('  life %s s', [F1(Life - Age)]), '')]));
      end;

  Section('PERFORMANCE');
  Row('fps (avg)', F1(FpsAvg));
  Row('cloud render', F1(Raster.ProjectMs) + ' ms project  +  ' + F1(Raster.DrawMs) + ' ms splat');
  Row('particles / threads', Format('%dk x 2 spins  /  %d', [Points div 1000, Raster.Threads]));
  Row('sounds played', IntToStr(SoundCount) + IfThen(Muted, '  (muted)', ''));

  Section('DATA FILES (editors, hot reload)');
  Row('levels', IfThen(LevelsFile <> '', 'data\' + LevelsFileName, 'built-in (no data\' + LevelsFileName + ')'));
  Row('sounds', IfThen(SoundsLoaded <> '', 'data\' + SoundsFileName, 'built-in (no data\' + SoundsFileName + ')'));
  Row('effects', IfThen(FxLoaded <> '', 'data\' + FxFileName, 'built-in (no data\' + FxFileName + ')'));
  Row('last reload', IfThen(ReloadMsg <> '', ReloadMsg, '-'));

  end;
  DevContentH := y + DevScroll - top;
  SDL_SetRenderClipRect(DevRen, nil);

  { right-click menu of a LAYERS row }
  if (PopupRow >= 0) and (PopupRow < LayerN) then
  begin
    pw := 200 * u; ph := 4 * 30 * u + 30 * u;
    PopupX := EnsureRange(PopupX, 4 * u, DevOutW - pw - 4 * u);
    PopupY := EnsureRange(PopupY, top, DevOutH - ph - 4 * u);
    DevHud.Rect(PopupX + 4 * u, PopupY + 4 * u, pw, ph, $000000, 120);
    DevHud.Rect(PopupX, PopupY, pw, ph, $1B1E26);
    DevHud.Rect(PopupX, PopupY, pw, 1, cOrange);
    DevHud.Text(fkTiny, Layers[PopupRow].Name, PopupX + 10 * u, PopupY + 8 * u, cOrange);
    if DevUI.Button('Copy row', PopupX + 6 * u, PopupY + 30 * u, pw - 12 * u, 28 * u, False, 'pop-copyrow') then
    begin
      CopyText(LayerLine(PopupRow), Layers[PopupRow].Name);
      PopupRow := -1;
    end
    else if DevUI.Button('Copy name', PopupX + 6 * u, PopupY + 60 * u, pw - 12 * u, 28 * u, False, 'pop-copyname') then
    begin
      CopyText(Layers[PopupRow].Name, 'name ' + Layers[PopupRow].Name);
      PopupRow := -1;
    end
    else if DevUI.Button('Copy all layers', PopupX + 6 * u, PopupY + 90 * u, pw - 12 * u, 28 * u, False, 'pop-copyall') then
    begin
      CopyAllLayers;
      PopupRow := -1;
    end
    else if DevUI.Button('Close', PopupX + 6 * u, PopupY + 120 * u, pw - 12 * u, 28 * u, False, 'pop-close') then
      PopupRow := -1
    else if DevUI.Pressed and not DevUI.Inside(PopupX, PopupY, pw, ph) then
      PopupRow := -1;
  end;
  DevRightPress := False;

  { toolbar }
  DevHud.Rect(0, 0, DevOutW, top, $14161C);
  DevHud.Rect(0, top - 1, DevOutW, 1, $FFFFFF, 40);
  if DevUI.Button(IfThen(ShowOutlines, 'OUTLINES ON  F3', 'OUTLINES  F3'), 10 * u, 10 * u, 150 * u, 36 * u, ShowOutlines, 'dev-outlines') then
    ShowOutlines := not ShowOutlines;
  if DevUI.Button(IfThen(ShowLabels, 'LABELS ON  F4', 'LABELS  F4'), 166 * u, 10 * u, 130 * u, 36 * u, ShowLabels, 'dev-labels') then
    ShowLabels := not ShowLabels;
  if DevUI.Button('EXPORT LAYOUT', 302 * u, 10 * u, 140 * u, 36 * u, False, 'dev-export') then ExportLayout;
  if DevUI.Button('PNG GAME', 448 * u, 10 * u, 100 * u, 36 * u, False, 'dev-pnggame') then
    ShotFile := ExeDir + 'screenshots' + PathDelim + 'game_' + FormatDateTime('hhnnss', Now) + '.png';
  for t := 0 to High(DevTabNames) do
    if DevUI.Button(DevTabNames[t], 10 * u + t * 132 * u, 56 * u, 126 * u, 34 * u, DevTab = t, 'dev-tab-' + LowerCase(DevTabNames[t])) then
    begin
      DevTab := t;
      DevScroll := 0;
      DevRedrawT := 0;
    end;
  if DevUI.Button('PNG DEV', 554 * u, 10 * u, 100 * u, 36 * u, False, 'dev-pngdev') then
    DevShotFile := ExeDir + 'screenshots' + PathDelim + 'dev_' + FormatDateTime('hhnnss', Now) + '.png';
  DevUI.EndFrame;

  if DevShotFile <> '' then
  begin
    surf := SDL_RenderReadPixels(DevRen, nil);
    if surf <> nil then
    begin
      if surf^.format <> SDL_PIXELFORMAT_ARGB8888 then
      begin
        conv := SDL_ConvertSurface(surf, SDL_PIXELFORMAT_ARGB8888);
        SDL_DestroySurface(surf);
        surf := conv;
      end;
      ForceDirectories(ExtractFileDir(ExpandFileName(DevShotFile)));
      if IMG_SavePNG(surf, PAnsiChar(AnsiString(DevShotFile))) then Flash('saved ' + DevShotFile);
      SDL_DestroySurface(surf);
    end;
    DevShotFile := '';
  end;
  SDL_RenderPresent(DevRen);
end;

procedure HandleKey(AKey: TSDL_Keycode; ADown: Boolean);
begin
  if not DemoMode then             { in the demo the bot owns the movement keys }
    case AKey of
      SDLK_A, SDLK_LEFT: KeyL := ADown;
      SDLK_D, SDLK_RIGHT: KeyR := ADown;
      SDLK_W, SDLK_UP: KeyU := ADown;
      SDLK_S, SDLK_DOWN: KeyD := ADown;
    end;
  if not ADown then Exit;
  case AKey of
    SDLK_SPACE: if (Screen = scPlaying) and not DemoMode then FlipReq := True;
    SDLK_P:
      if Screen = scPlaying then Screen := scPaused
      else if Screen = scPaused then Screen := scPlaying;
    SDLK_ESCAPE:
      case Screen of
        scPlaying: Screen := scPaused;
        scPaused: Screen := scPlaying;
        scLevels, scHelp: Screen := scTitle;
        scBriefing: if DemoMode then GoMenu else Screen := scLevels;
        scResult: GoMenu;
      end;
    SDLK_L:
      if Screen = scTitle then
      begin
        LevWorld := (Min(Unlocked[CurMode], LevelCount) - 1) div LevelsPerWorld;
        Screen := scLevels;
      end;
    SDLK_LEFT, SDLK_RIGHT, SDLK_PAGEUP, SDLK_PAGEDOWN:
      if Screen = scLevels then
      begin
        if (AKey = SDLK_LEFT) or (AKey = SDLK_PAGEUP) then LevWorld := Max(0, LevWorld - 1)
        else LevWorld := Min(WorldCount - 1, LevWorld + 1);
        PlaySound(snClick);
      end;
    SDLK_H: if Screen = scTitle then Screen := scHelp;
    SDLK_Q:
      case Screen of
        scTitle: Running := False;
        scPaused, scResult: GoMenu;
        scBriefing, scPlaying: if DemoMode then GoMenu;
      end;
    SDLK_R: if (Screen in [scPaused, scResult]) and not DemoMode then begin PlaySound(snClick); RequestLevel(G.Level); end;
    SDLK_1, SDLK_2, SDLK_3, SDLK_4, SDLK_5, SDLK_6:
      if (Screen = scLevels) and (LevWorld * LevelsPerWorld + Integer(AKey - SDLK_1) < Unlocked[CurMode]) then
      begin
        PlaySound(snClick);
        RequestLevel(LevWorld * LevelsPerWorld + Integer(AKey - SDLK_1));
      end
      else if (Screen = scTitle) and (AKey <= SDLK_3) then
      begin
        CurMode := TGameMode(AKey - SDLK_1);
        PlaySound(snClick);
        SaveProgress;
      end;
    SDLK_V: ViewMode := (ViewMode + 1) mod 3;
    SDLK_EQUALS, SDLK_KP_PLUS: ZoomF := Min(1.5, ZoomF * 1.08);
    SDLK_MINUS, SDLK_KP_MINUS: ZoomF := Max(0.7, ZoomF / 1.08);
    SDLK_RIGHTBRACKET: HudScale := Min(1.5, HudScale + 0.1);
    SDLK_LEFTBRACKET: HudScale := Max(0.3, HudScale - 0.1);
    SDLK_M: Muted := not Muted;
    SDLK_B:
      if Screen = scTitle then StartDemo
      else if not DemoMode then BotOn := not BotOn;
    SDLK_F2: if DevWin = nil then DevOpen else DevClose;
    SDLK_F3: ShowOutlines := not ShowOutlines;
    SDLK_F4: ShowLabels := not ShowLabels;
    SDLK_F12: ShotFile := ExeDir + 'screenshots' + PathDelim + 'pauli_' + FormatDateTime('hhnnss', Now) + '.png';
    SDLK_RETURN, SDLK_KP_ENTER:
      case Screen of
        scTitle: PlayPressed;
        scBriefing: StartFromBriefing;
        scResult:
          if DemoMode and DemoDone then StartDemo
          else if not DemoMode then
          begin
            PlaySound(snClick);
            if (G.State = gsWon) and (G.Level < LevelCount - 1) then RequestLevel(G.Level + 1) else RequestLevel(G.Level);
          end;
      end;
  end;
end;

{ steering with the mouse only in the cloud area, not on the HUD }
function InPlayArea(X, Y: Single): Boolean;
const
  Keys: array[0..2] of string = ('flip', 'pause', 'view');
var
  r: TSDL_FRect;
  i: Integer;
begin
  { steer anywhere except on the buttons }
  Result := True;
  for i := 0 to High(Keys) do
    if FindBtn(Keys[i], r) and (X >= r.x) and (X < r.x + r.w) and (Y >= r.y) and (Y < r.y + r.h) then Exit(False);
end;

procedure PollEvents;
var
  ev: TSDL_Event;
  k2, dk: Single;
  did: TSDL_WindowID;
  ww, wh, ow, oh: Integer;
begin
  k2 := OutW / Max(1, WinW);
  while SDL_PollEvent(@ev) do
  begin
    did := DevId;
    case ev._type of
      SDL_EVENT_QUIT: Running := False;
      SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        if (did <> 0) and (ev.window.windowID = did) then DevClose else Running := False;
      SDL_EVENT_KEY_DOWN:
        if (did <> 0) and (ev.key.windowID = did) and (ev.key.key = SDLK_ESCAPE) and (PopupRow >= 0) then
        begin
          PopupRow := -1;
          DevRedrawT := 0;
        end
        else if (did <> 0) and (ev.key.windowID = did) and (ev.key.key = SDLK_ESCAPE) then DevClose
        else if not ev.key._repeat then HandleKey(ev.key.key, True);
      SDL_EVENT_KEY_UP: HandleKey(ev.key.key, False);
      SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP, SDL_EVENT_MOUSE_WHEEL:
        if (did <> 0) and (ev.motion.windowID = did) then
        begin
          SDL_GetWindowSize(DevWin, @ww, @wh);
          SDL_GetCurrentRenderOutputSize(DevRen, @ow, @oh);
          dk := ow / Max(1, ww);
          case ev._type of
            SDL_EVENT_MOUSE_MOTION: DevUI.MouseMove(ev.motion.x * dk, ev.motion.y * dk);
            SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP:
              if ev.button.button = SDL_BUTTON_LEFT then
                DevUI.MouseButton(ev.button.x * dk, ev.button.y * dk, ev._type = SDL_EVENT_MOUSE_BUTTON_DOWN)
              else if (ev.button.button = SDL_BUTTON_RIGHT) and (ev._type = SDL_EVENT_MOUSE_BUTTON_DOWN) then
              begin
                DevRightPress := True;
                DevRightX := ev.button.x * dk;
                DevRightY := ev.button.y * dk;
                DevUI.MouseMove(DevRightX, DevRightY);
              end;
            SDL_EVENT_MOUSE_WHEEL: DevScroll := DevScroll - ev.wheel.y * 60 * DevU;
          end;
          DevRedrawT := 0;
        end
        else
          case ev._type of
            SDL_EVENT_MOUSE_WHEEL:
              if Screen in [scPlaying, scPaused] then
                ZoomF := EnsureRange(ZoomF * Power(1.08, ev.wheel.y), 0.7, 1.5);
            SDL_EVENT_MOUSE_MOTION:
              begin
                { in the demo the bot owns the steering cursor; the real mouse still works the buttons }
                if not DemoMode then begin MouseX := ev.motion.x * k2; MouseY := ev.motion.y * k2; end;
                UI.MouseMove(ev.motion.x * k2, ev.motion.y * k2);
              end;
            SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP:
              begin
                if not DemoMode then begin MouseX := ev.button.x * k2; MouseY := ev.button.y * k2; end;
                if ev.button.button = SDL_BUTTON_LEFT then
                begin
                  UI.MouseButton(ev.button.x * k2, ev.button.y * k2, ev._type = SDL_EVENT_MOUSE_BUTTON_DOWN);
                  { steering only when the press is not on a button }
                  if not DemoMode then
                    if ev._type = SDL_EVENT_MOUSE_BUTTON_DOWN then
                      MouseDownL := (Screen = scPlaying) and InPlayArea(MouseX, MouseY)
                    else
                      MouseDownL := False;
                end
                else if (ev.button.button = SDL_BUTTON_RIGHT) and (ev._type = SDL_EVENT_MOUSE_BUTTON_DOWN) and (Screen = scPlaying) and
                  not DemoMode then
                  FlipReq := True;
              end;
          end;
    end;
  end;
end;

{ ---------------------------------------------------------------- --ui-test }

type
  TUITest = record
    Step, Wait: Integer;
    Log: TStringList;
    PX, PY: Single;
    Pending, PendDev: Boolean;
    Fails: Integer;
    T0: Double;
    Saved: Integer;
    SavedF: Double;
    Msg: string;
  end;

var
  UT: TUITest;
  UTR, UTR2: TSDL_FRect;
  UTI: Integer;

procedure UTLog(const S: string);
begin
  UT.Log.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S);
end;

procedure UTCheck(ACond: Boolean; const AWhat: string);
begin
  if ACond then UTLog('ok    ' + AWhat)
  else
  begin
    UTLog('FAIL  ' + AWhat);
    Inc(UT.Fails);
  end;
end;

procedure UTClick(const AKey: string);
var
  r: TSDL_FRect;
begin
  if not FindBtn(AKey, r) then
  begin
    UTCheck(False, 'widget not found: ' + AKey);
    Exit;
  end;
  UTLog('click ' + AKey);
  UT.PX := r.x + r.w / 2; UT.PY := r.y + r.h / 2;
  UI.MouseMove(UT.PX, UT.PY);
  UI.MouseButton(UT.PX, UT.PY, True);
  UT.Pending := True;
end;

procedure UTClickDev(const AKey: string);
var
  r: TSDL_FRect;
begin
  if (DevUI = nil) or not DevUI.FindRect(AKey, r) then
  begin
    UTCheck(False, 'developer button not found: ' + AKey);
    Exit;
  end;
  UTLog('click dev ' + AKey);
  UT.PX := r.x + r.w / 2; UT.PY := r.y + r.h / 2;
  DevUI.MouseMove(UT.PX, UT.PY);
  DevUI.MouseButton(UT.PX, UT.PY, True);
  UT.Pending := True;
  UT.PendDev := True;
  DevRedrawT := 0;
end;

function UTLayersOk(out AMsg: string): Boolean;
const
  Need: array[0..13] of string = ('cloud', 'probe', 'hud.orbital', 'hud.quantum_numbers', 'hud.spin', 'hud.score',
    'hud.coherence', 'hud.blackholes', 'hud.probe', 'inset.label', 'inset.orbital', 'legend', 'hud.zoom', 'btn.flip');
var
  i: Integer;
  r: TSDL_FRect;
begin
  AMsg := '';
  for i := 0 to High(Need) do
    if not FindLayer(Need[i], r) then AMsg := AMsg + ' ' + Need[i];
  Result := AMsg = '';
end;

procedure UTShot(const AName: string);
begin
  if UIShotDir <> '' then
    if SavePNG(IncludeTrailingPathDelimiter(UIShotDir) + AName + '.png') then UTLog('shot ' + AName);
end;

function UITestStep: Boolean;
var
  ini: TMemIniFile;
  sp: Integer;
  sid: TSoundId;
begin
  Result := True;
  if UT.Pending then
  begin
    if UT.PendDev and (DevUI <> nil) then DevUI.MouseButton(UT.PX, UT.PY, False)
    else UI.MouseButton(UT.PX, UT.PY, False);
    UT.Pending := False;
    UT.PendDev := False;
    UT.Wait := 3;
    Exit;
  end;
  if UT.Wait > 0 then
  begin
    Dec(UT.Wait);
    Exit;
  end;
  case UT.Step of
    0:
      begin
        UTCheck((Screen = scTitle) and AttractMode and (G.Active.Name = '6p') and (G.BHCount = 3) and (CurMode = gmBlackHole),
          'title screen, attract mode plays 6p with 3 black holes, mode BLACK HOLE');
        sp := 0;
        for sid := Low(TSoundId) to High(TSoundId) do
          if Snd[sid].Frames > 0 then Inc(sp);
        UTCheck(sp = Ord(High(TSoundId)) + 1, Format('%d sound effects rendered by the SFX engine', [sp]));
      end;
    1: begin UT.Wait := 90; end;
    2: begin UTCheck(G.Elapsed > 0.5, Format('attract bot is playing (%.1f s, %d quanta)', [G.Elapsed, G.Collected])); UTShot('01_title'); end;
    3: UTClick('help');
    4: begin UTCheck(Screen = scHelp, 'how to play'); UTShot('02_help'); end;
    5: UTClick('back');
    6: UTClick('levels');
    7: UTCheck((Screen = scLevels) and (Unlocked[CurMode] = 1), 'level select, only level 1 unlocked');
    8: UTClick('lvl3');
    9: UTCheck(Screen = scLevels, 'locked level 3 does nothing');
    10: UTClick('lvl1');
    11: begin UT.Wait := 4; end;
    12: begin UTCheck((Screen = scBriefing) and (G.Level = 0) and (G.Active.Name = '2p'), 'briefing level 1 (2p)'); UTShot('03_briefing'); end;
    13: UTClick('start');
    14: UTCheck((Screen = scPlaying) and (G.State = gsPlaying) and not AttractMode and (G.Mode = gmBlackHole) and (G.BHCount = 1),
          'level 1 started in BLACK HOLE mode with 1 black hole');
    15: begin BotOn := True; UT.T0 := NowS; UT.Saved := SoundCount; FrameCount := 0; FrameTime := 0; UTLog('bot takes over level 1'); end;
    16:
      begin
        if (Screen = scPlaying) and (NowS - UT.T0 < 90) then
        begin
          if (NowS - UT.T0 > 4) and not FileExists(IncludeTrailingPathDelimiter(UIShotDir) + '04_play_2p.png') then UTShot('04_play_2p');
          Exit;                                   { stay on this step }
        end;
        UTCheck((Screen = scResult) and (G.State = gsWon), Format('bot won level 1: score %d, %d stars, %.1f s', [G.Score, G.Stars, G.Elapsed]));
        UTCheck(SoundCount - UT.Saved >= G.Collected, Format('sound effects played during the level: %d (pickups %d)', [SoundCount - UT.Saved, G.Collected]));
        UTLog(Format('info  %d frames in %.1f s = %.0f fps (%dk particles, render scale %.2f, %dx%d)',
          [FrameCount, FrameTime, FrameCount / Max(0.001, FrameTime), Points div 1000, RenderScale, OutW, OutH]));
      end;
    17:
      begin
        UTShot('05_result');
        ini := TMemIniFile.Create(ProgressPath);
        try
          UTCheck((ini.ReadInteger('blackhole', 'unlocked', 0) = 2) and (ini.ReadInteger('blackhole.level1', 'best', 0) = G.Score) and
            (ini.ReadInteger('blackhole.level1', 'stars', 0) = G.Stars) and (ini.ReadInteger('singularity', 'unlocked', 0) = 1),
            'progress per mode: BLACK HOLE level 2 unlocked, best + stars saved, SINGULARITY still locked');
        finally
          ini.Free;
        end;
      end;
    18: begin BotOn := False; UTClick('next'); end;
    19: begin UT.Wait := 4; end;
    20: UTCheck((Screen = scBriefing) and (G.Level = 1) and (Length(G.Orb[0].RadialNodes) = 1), 'NEXT -> level 2 (3p, one radial node)');
    21: UTClick('start');
    22: begin UT.Saved := G.Spin; UTClick('flip'); end;
    23: UTCheck((G.Spin = -UT.Saved) and (G.Flips = 1), 'FLIP SPIN button flips sigma');
    24: begin KeyR := True; UT.Wait := 30; end;
    25: begin KeyR := False; UTCheck(Hypot(G.VX, G.VY) > 0.05 * G.RView, Format('keyboard thrust moves the probe (%.2f RView/s)', [Hypot(G.VX, G.VY) / G.RView])); end;
    26: UTClick('view');
    27: begin UTCheck(ViewMode = 1, 'VIEW -> half cloud'); UTShot('06_view_half'); end;
    28: UTClick('view');
    29: UTClick('view');
    30: UTCheck(ViewMode = 0, 'VIEW cycles back to slice');
    31: UTClick('pause');
    32: begin UT.Saved := Round(G.Elapsed * 1000); UT.Wait := 20; end;
    33: begin UTCheck((Screen = scPaused) and (Round(G.Elapsed * 1000) = UT.Saved), 'pause freezes the game'); UTShot('07_paused'); end;
    34: UTClick('resume');
    35: UTCheck(Screen = scPlaying, 'resume');
    36: begin sp := 0; G.PX := G.Orb[0].RadialNodes[0]; G.PY := sp; UT.Wait := 30; end;
    37: UTCheck(G.Coherence < 1, Format('probe on the radial node loses coherence (%.2f)', [G.Coherence]));
    38: UTClick('pause');
    39: UTClick('menu');
    40: begin UT.Wait := 6; end;
    41: UTCheck((Screen = scTitle) and AttractMode, 'MENU -> title (attract)');
    42: UTClick('mode-singularity');
    43: UTCheck(CurMode = gmSingularity, 'mode SINGULARITY selected');
    44: UTClick('levels');
    45: begin UTCheck((Screen = scLevels) and (Unlocked[gmSingularity] = 1), 'SINGULARITY has its own progress (level 1 only)'); UTShot('08_levels_singularity'); end;
    46: UTClick('lvl1');
    47: begin UT.Wait := 4; end;
    48: begin UTCheck((Screen = scBriefing) and (G.Mode = gmSingularity) and (G.BHCount = 2), 'briefing: SINGULARITY level 1 has 2 black holes'); UTShot('09_briefing_singularity'); end;
    49: UTClick('start');
    50: begin UT.Saved := SoundCount; G.BHPos(0, G.PX, G.PY); UT.Wait := 2; end;
    51:
      begin
        UTCheck((G.HorizonHits = 1) and (G.Immune > 1.5) and (Abs(G.Coherence - 0.5) < 0.02) and (G.State = gsPlaying),
          Format('probe dropped on a horizon: -50 %% coherence (%.2f), Hawking ejection, immune', [G.Coherence]));
        UTCheck(SoundCount > UT.Saved, 'horizon sound played');
        UTShot('10_hawking_ejection');
      end;
    52: begin G.Immune := 0; G.Coherence := 0.3; G.BHPos(1, G.PX, G.PY); UT.Wait := 2; end;
    53: begin UT.Wait := 8; end;
    54: UTCheck((Screen = scResult) and G.LostToBH, 'second horizon with 30 % coherence -> SPAGHETTIFIED, result screen');
    55: UTShot('11_spaghettified');
    56: UTClick('menu');
    57: begin UT.Wait := 6; end;
    58: UTClick('mode-blackhole');
    59: UTCheck((Screen = scTitle) and (CurMode = gmBlackHole), 'back to BLACK HOLE mode');
    60:
      begin
        SetView;
        if not FindBtn('flip', UTR) then FillChar(UTR, SizeOf(UTR), 0);
        UTCheck(IsWide and (UTR.x + UTR.w > OutW * 0.85) and (UTR.y + UTR.h > OutH * 0.85),
          Format('corner layout at %d x %d: buttons bottom-right (%.0f, %.0f)', [OutW, OutH, UTR.x + UTR.w, UTR.y + UTR.h]));
      end;
    61: begin UT.Saved := Round(ZoomF * 1000); HandleKey(SDLK_EQUALS, True); HandleKey(SDLK_EQUALS, True); end;
    62: UTCheck(Round(ZoomF * 1000) > UT.Saved + 100, Format('+ zooms the cloud: %.3f', [ZoomF]));
    63: begin HandleKey(SDLK_MINUS, True); HandleKey(SDLK_MINUS, True); end;
    64: UTCheck(Abs(Round(ZoomF * 1000) - UT.Saved) <= 2, Format('- zooms back: %.3f', [ZoomF]));
    65: begin UT.Saved := Round(HudScale * 10); HandleKey(SDLK_RIGHTBRACKET, True); end;
    66: begin UTCheck(Round(HudScale * 10) = UT.Saved + 1, Format('] HUD size +0.1 -> %.1f', [HudScale])); HandleKey(SDLK_LEFTBRACKET, True); end;
    67: UTCheck((Round(HudScale * 10) = UT.Saved) and (Abs(HudScale - 0.575) < 0.01) and
          (Abs(InsetSz - OutH / 900 * 157.5) <= 1),
          Format('[ HUD size back to default %.3f, inset %d px (= 157.5 units)', [HudScale, InsetSz]));
    { keyboard shortcuts shown on the buttons }
    68: HandleKey(SDLK_H, True);
    69: begin UTCheck(Screen = scHelp, 'key H -> how to play'); HandleKey(SDLK_ESCAPE, True); end;
    70: begin UTCheck(Screen = scTitle, 'Esc -> title'); HandleKey(SDLK_2, True); end;
    71: begin UTCheck(CurMode = gmBlackHole, 'key 2 on the title -> BLACK HOLE'); HandleKey(SDLK_L, True); end;
    72: begin UTCheck(Screen = scLevels, 'key L -> levels'); HandleKey(SDLK_1, True); end;
    73: begin UT.Wait := 4; end;
    74: begin UTCheck((Screen = scBriefing) and (G.Level = 0), 'key 1 -> briefing level 1'); UTShot('17_briefing_keys'); HandleKey(SDLK_RETURN, True); end;
    75: begin UTCheck(Screen = scPlaying, 'Enter -> start'); UT.Wait := 30; end;
    76: begin UTShot('18_play_keys'); HandleKey(SDLK_P, True); end;
    77: begin UTCheck(Screen = scPaused, 'key P -> pause'); UTShot('19_paused_keys'); HandleKey(SDLK_R, True); end;
    78: begin UT.Wait := 4; end;
    79: begin UTCheck((Screen = scBriefing) and (G.Level = 0), 'key R -> restart (briefing)'); HandleKey(SDLK_RETURN, True); end;
    80: HandleKey(SDLK_ESCAPE, True);
    81: begin UTCheck(Screen = scPaused, 'Esc -> pause'); HandleKey(SDLK_Q, True); end;
    82: begin UT.Wait := 6; end;
    83: UTCheck((Screen = scTitle) and AttractMode, 'key Q -> menu');
    { developer window, named layers, layout fixes }
    84: HandleKey(SDLK_RETURN, True);
    85: begin UT.Wait := 6; end;
    86: HandleKey(SDLK_RETURN, True);
    87: begin UT.Wait := 30; end;
    88: begin UTCheck(Screen = scPlaying, 'playing (for the layer checks)'); HandleKey(SDLK_F2, True); UT.Wait := 8; end;
    89:
      begin
        UTCheck((DevWin <> nil) and (LayerN >= 20), Format('F2 opens the developer window, %d named layers', [LayerN]));
        UTCheck(UTLayersOk(UT.Msg), 'all HUD / world parts have names' + IfThen(UT.Msg <> '', ', missing:' + UT.Msg, ''));
        if FindLayer('legend', UTR) and FindLayer('inset.orbital', UTR2) then
          UTCheck(Abs((UTR.x + UTR.w) - (UTR2.x + UTR2.w)) <= 3,
            Format('legend flush with the right edge: right %.0f = inset right %.0f', [UTR.x + UTR.w, UTR2.x + UTR2.w]))
        else
          UTCheck(False, 'legend / inset layers');
        if FindLayer('cloud', UTR) then
          UTCheck((Abs(UTR.y + UTR.h / 2 - OutH / 2) <= 3) and (UTR.y >= -2) and (UTR.y + UTR.h <= OutH + 2),
            Format('cloud centred vertically: top %.0f, bottom %.0f, centre %.0f (window %d)', [UTR.y, UTR.y + UTR.h,
            UTR.y + UTR.h / 2, OutH]))
        else
          UTCheck(False, 'cloud layer');
      end;
    90: UTClickDev('dev-outlines');
    91: begin UT.Wait := 4; end;
    92:
      begin
        UTCheck(ShowOutlines, 'OUTLINES button -> dashed layer outlines on');
        UTShot('27_layer_outlines');
        if UIShotDir <> '' then DevShotFile := IncludeTrailingPathDelimiter(UIShotDir) + '28_dev_window.png';
        DevRedrawT := 0;
      end;
    93: begin UT.Wait := 3; end;
    94:
      begin
        if UIShotDir <> '' then UTCheck(FileExists(IncludeTrailingPathDelimiter(UIShotDir) + '28_dev_window.png'), 'developer window PNG');
        UTClickDev('dev-export');
      end;
    95:
      begin
        UTCheck(FileExists(ExeDir + 'exports' + PathDelim + 'layout.json') and FileExists(ExeDir + 'exports' + PathDelim + 'layout.md'),
          'EXPORT LAYOUT -> exports/layout.json + layout.md');
        UTClickDev('dev-outlines');
      end;
    { 140 px blocks, right-click copy in LAYERS }
    96:
      begin
        if not FindLayer('hud.coherence', UTR) then UTR.w := 9999;
        UTCheck(UTR.w <= 140.5, Format('hud.coherence w = %.1f px (max 140)', [UTR.w]));
      end;
    97:
      begin
        if not FindLayer('hud.blackholes', UTR) then UTR.w := 9999;
        UTCheck(UTR.w <= 140.5, Format('hud.blackholes w = %.1f px (max 140)', [UTR.w]));
      end;
    98: UTClickDev('dev-tab-layers');
    99: begin DevRedrawT := 0; UT.Wait := 3; end;
    100:
      begin
        UT.Saved := -1;
        for UTI := 0 to High(RowRectsName) do
          if RowRectsName[UTI] = 'hud.coherence' then UT.Saved := UTI;
        if UT.Saved >= 0 then
        begin
          DevRightPress := True;
          DevRightX := 120 * DevU;
          DevRightY := RowRectsY[UT.Saved];
          DevUI.MouseMove(DevRightX, DevRightY);
          DevRedrawT := 0;
          UTLog('right click dev row hud.coherence');
        end
        else
          UTCheck(False, 'row hud.coherence not on screen');
      end;
    101: begin UT.Wait := 3; end;
    102:
      begin
        UTCheck((PopupRow >= 0) and (Layers[PopupRow].Name = 'hud.coherence'), 'right click -> popup menu for hud.coherence');
        if UIShotDir <> '' then DevShotFile := IncludeTrailingPathDelimiter(UIShotDir) + '34_dev_popup.png';
        DevRedrawT := 0;
      end;
    103: begin UT.Wait := 3; end;
    104: UTClickDev('pop-copyrow');
    105:
      begin
        UT.Msg := StrPas(SDL_GetClipboardText);
        UTCheck((Pos('hud.coherence', UT.Msg) = 1) and (Pos(' w=', UT.Msg) > 0) and (PopupRow < 0),
          'Copy row -> clipboard: ' + UT.Msg);
      end;
    106: UTClickDev('dev-tab-physics');
    107: begin DevRedrawT := 0; UT.Wait := 3; end;
    108:
      begin
        UTCheck((DevTab = 0) and (DevPlotCount >= 3), Format('PHYSICS tab: quantum state, geometry, sampling + %d plots', [DevPlotCount]));
        if UIShotDir <> '' then DevShotFile := IncludeTrailingPathDelimiter(UIShotDir) + '28_dev_physics.png';
        DevRedrawT := 0;
      end;
    109: begin UT.Wait := 3; end;
    110:
      begin
        if UIShotDir <> '' then UTCheck(FileExists(IncludeTrailingPathDelimiter(UIShotDir) + '28_dev_physics.png'), 'PHYSICS tab PNG');
        UTClickDev('dev-tab-parameters');
      end;
    111: begin DevRedrawT := 0; UT.Wait := 3; end;
    112: begin UT.SavedF := GP.FlowScale; UTClickDev('slider901'); end;
    113: begin UT.Wait := 3; end;
    114:
      begin
        UTCheck((DevTab = 1) and (Abs(GP.FlowScale - 0.8) < 0.02) and (Abs(UT.SavedF - 0.5) < 1e-9),
          Format('PARAMETERS tab: FlowScale slider 0.50 -> %.2f, used by the game at once (probe omega %.3f)', [GP.FlowScale, G.ProbeOmega]));
        if UIShotDir <> '' then DevShotFile := IncludeTrailingPathDelimiter(UIShotDir) + '31_dev_parameters.png';
        DevRedrawT := 0;
      end;
    115: begin UT.Wait := 3; end;
    116: UTClickDev('dev-reset');
    117: begin UT.Wait := 3; end;
    118: UTCheck(Abs(GP.FlowScale - 0.5) < 1e-9, 'RESET DEFAULTS -> FlowScale 0.50');
    119: UTClickDev('dev-tab-state');
    120:
      begin
        UTCheck(DevTab = 3, 'STATE tab');
        if UIShotDir <> '' then DevShotFile := IncludeTrailingPathDelimiter(UIShotDir) + '33_dev_state.png';
        DevRedrawT := 0;
      end;
    121: UTClickDev('dev-tab-layers');
    122:
      begin
        UTCheck(DevTab = 2, 'LAYERS tab');
        if UIShotDir <> '' then DevShotFile := IncludeTrailingPathDelimiter(UIShotDir) + '32_dev_layers.png';
        DevRedrawT := 0;
      end;
    123: begin UT.Wait := 3; end;
    124: HandleKey(SDLK_F2, True);
    125: UTCheck((DevWin = nil) and not ShowOutlines, 'outlines off, F2 closes the developer window');
    126: HandleKey(SDLK_P, True);
    127: HandleKey(SDLK_Q, True);
    128: begin UT.Wait := 6; end;
    129: UTCheck(Screen = scTitle, 'back to the title');
    { SUPER BOT DEMO }
    130: begin UT.Saved := Unlocked[gmSingularity]; UTClick('demo'); end;
    131: begin UT.Wait := 6; end;
    132: UTCheck(DemoMode and (CurMode = gmSingularity) and (Screen = scBriefing) and (G.Level = 0) and (G.Mode = gmSingularity),
           'SUPER BOT DEMO button -> SINGULARITY level 1 briefing');
    133: begin UT.T0 := NowS; end;
    134: if (Screen <> scPlaying) and (NowS - UT.T0 < 6) then Exit
         else UTCheck(Screen = scPlaying, Format('briefing advances by itself (ENTER) after %.1f s', [NowS - UT.T0]));
    135: begin UT.Wait := 240; end;
    136:
      begin
        UTCheck((DemoInputs >= 3) and ((DemoMouseUses > 0) or (DemoKeyUses > 0)) and not BotOn,
          Format('the bot plays through the input path: %d inputs, %d mouse presses, %d key changes', [DemoInputs, DemoMouseUses,
          DemoKeyUses]));
        UTShot('36_demo_play');
        UT.T0 := NowS;
      end;
    137: if (Screen <> scResult) and (NowS - UT.T0 < 120) then Exit
         else
         begin
           UTCheck(Screen = scResult, Format('level 1 finished: %s, score %d', [IfThen(G.State = gsWon, 'won', 'lost'), G.Score]));
           UT.Wait := 30;
         end;
    138: begin UTShot('37_demo_result'); UT.T0 := NowS; end;
    139: if (Screen <> scBriefing) and (NowS - UT.T0 < 10) then Exit
         else UTCheck((Screen = scBriefing) and ((G.Level = 1) or (DemoAttempts[0] >= 1)),
           Format('result advances by itself to level %d (no player input)', [G.Level + 1]));
    140: begin UT.Wait := 20; end;
    141: HandleKey(SDLK_ESCAPE, True);            { Esc stops the demo on any demo screen }
    142: begin UT.Wait := 3; end;
    143: begin UT.Wait := 6; end;
    144:
      begin
        UTCheck(not DemoMode and (Screen = scTitle) and (CurMode = gmBlackHole), 'Esc stops the demo, the player mode is restored');
        UTCheck(Unlocked[gmSingularity] = UT.Saved, 'demo results do not change the player progress');
      end;
    { 30 levels in 5 worlds }
    145: UTClick('levels');
    146: begin UTCheck((Screen = scLevels) and (LevWorld = 0) and (LevelCount = 30), 'level select opens on world 1 of 5 (30 levels)'); HandleKey(SDLK_RIGHT, True); end;
    147: begin UT.Wait := 3; end;
    148: UTCheck((LevWorld = 1) and FindBtn('lvl7', UTR), 'Right -> world 2 MIRROR CURRENTS, level 7 shown');
    149: UTClick('lvl7');
    150: begin UT.Wait := 4; end;
    151: begin UTCheck(Screen = scLevels, 'level 7 is locked until level 6 is won'); UTClick('world4'); end;
    152: begin UT.Wait := 3; end;
    153: begin UTCheck(LevWorld = 3, 'WORLD 4 tab -> RYDBERG'); UTShot('38_levels_world4'); HandleKey(SDLK_LEFT, True); end;
    154: UTCheck(LevWorld = 2, 'Left -> world 3');
    155: HandleKey(SDLK_ESCAPE, True);
    156: UTCheck(Screen = scTitle, 'Esc -> title');
  else
    UTLog(Format('done: %d failure(s)', [UT.Fails]));
    Exit(False);
  end;
  Inc(UT.Step);
  if UT.Wait = 0 then UT.Wait := 3;
end;

{ ---------------------------------------------------------------- main }

{ hot reload: the editors save into data\, the running game picks it up }
procedure CheckDataFiles(AForce: Boolean);
var
  st: Int64;
  what: string;
begin
  what := '';
  st := FileStamp(DataPath(LevelsFileName));
  if AForce or (st <> StampLevels) then
  begin
    StampLevels := st;
    LoadLevels(DataPath(LevelsFileName));
    if not AForce then
    begin
      what := what + ' levels';
      { the next StartLevel uses the new table; a level on screen keeps running }
      if PendingLevel < 0 then
        if Screen = scTitle then
        begin
          PendingLevel := G.Level;
          PendingScreen := scTitle;
        end
        else if Screen = scBriefing then RequestLevel(G.Level);
    end;
  end;
  st := FileStamp(DataPath(SoundsFileName));
  if AForce or (st <> StampSounds) then
  begin
    StampSounds := st;
    LoadSounds(DataPath(SoundsFileName));
    if not AForce then
    begin
      BuildSounds;
      what := what + ' sounds';
    end;
  end;
  st := FileStamp(DataPath(FxFileName));
  if AForce or (st <> StampFx) then
  begin
    StampFx := st;
    LoadFx(DataPath(FxFileName));
    ApplyCloudColours;
    if not AForce then
    begin
      G.Orb[0].Recolour;
      G.Orb[1].Recolour;
      what := what + ' effects';
    end;
  end;
  if what <> '' then
  begin
    ReloadMsg := FormatDateTime('hh:nn:ss', Now) + ' reloaded' + what;
    Flash('data reloaded:' + what);
  end;
end;

procedure ParseArgs(out AW, AH: Integer);
var
  i: Integer;
  a, k, v: string;
  parts: TStringArray;
begin
  AW := 0; AH := 0;
  for i := 1 to ParamCount do
  begin
    a := ParamStr(i);
    if Pos('--', a) <> 1 then Continue;
    k := Copy(a, 3, Pos('=', a + '=') - 3);
    v := Copy(a, Pos('=', a + '=') + 1, MaxInt);
    if k = 'level' then CliLevel := EnsureRange(StrToIntDef(v, 1), 1, LevelCount)
    else if k = 'mode' then CliMode := v
    else if k = 'demo' then CliDemo := True
    else if k = 'demo-exit' then begin CliDemo := True; DemoExit := True; end
    else if k = 'demo-log' then DemoLogFile := v
    else if k = 'dev' then begin DevAuto := v <> '0'; DevArg := True; end
    else if k = 'bot' then BotOn := True
    else if k = 'preview' then begin PreviewMode := True; BotOn := True; end
    else if k = 'data' then DataDirOverride := v
    else if k = 'mute' then Muted := True
    else if k = 'points' then Points := EnsureRange(StrToIntDef(v, 300000), 10000, 2000000)
    else if k = 'scale' then RenderScale := EnsureRange(StrToFloatDef(v, 0.75, SfxFS), 0.25, 1)
    else if k = 'progress' then ProgressPath := ExpandFileName(v)
    else if k = 'size' then
    begin
      parts := v.Split(['x', 'X']);
      if Length(parts) = 2 then begin AW := StrToIntDef(parts[0], 0); AH := StrToIntDef(parts[1], 0); end;
    end
    else if k = 'shot' then ShotFile := v
    else if k = 'shot-delay' then ShotDelay := StrToFloatDef(v, 0, SfxFS)
    else if k = 'ui-test' then UITestLog := v
    else if k = 'ui-shots' then UIShotDir := v;
  end;
end;

var
  rect: TSDL_Rect;
  ww, wh: Integer;
  spec: TSDL_AudioSpec;
  lastS, startS, dt: Double;
  quitAfterShot, autoSize: Boolean;
  o: TOrbital;
  mm: TGameMode;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  Randomize;
  Points := 300000;
  RenderScale := 0.75;
  ParseArgs(ww, wh);
  if ProgressPath = '' then ProgressPath := ExeDir + 'progress_v2.ini';
  LoadProgress;
  for mm := Low(TGameMode) to High(TGameMode) do
    if SameText(CliMode, ModeIds[mm]) or SameText(CliMode, ModeNames[mm]) then CurMode := mm;
  quitAfterShot := ShotFile <> '';
  CheckDataFiles(True);
  if PreviewMode and (CliLevel = 0) then CliLevel := AttractLevel + 1;

  if not SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO) then Halt(1);
  { automated runs (screenshots, ui-test) keep their exact setup unless --dev is given }
  if not DevArg and ((ShotFile <> '') or (UITestLog <> '') or PreviewMode) then DevAuto := False;
  autoSize := ww <= 0;
  if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @rect) then
  begin
    rect.x := 0; rect.y := 0; rect.w := 1920; rect.h := 1080;
  end;
  if autoSize then
  begin
    wh := Round(rect.h * 0.9);
    if DevAuto then
      { game + developer window side by side }
      ww := Max(640, rect.w - DevWinW - 36)
    else
      { wide window, 90 % of the usable screen: the WIDE layout (bigger text and cloud) }
      ww := Round(rect.w * 0.9);
  end;
  Win := SDL_CreateWindow('PAULI SURFER 2 - black holes in the hydrogen probability current', ww, wh, SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if autoSize and DevAuto then SDL_SetWindowPosition(Win, rect.x + 12, rect.y + 32);
  SDL_SetWindowMinimumSize(Win, 360, 640);
  Ren := SDL_CreateRenderer(Win, nil);
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  HudMain := THud.Create(Ren);
  HudMenu := THud.Create(Ren);
  HudLbl := THud.Create(Ren);
  Hud := HudMain;
  UI := TUI.Create(HudMain);
  Raster := TCloudRaster.Create;
  Inset := TInsetRaster.Create;
  G := TPauliGame.Create;
  spec.format := SDL_AUDIO_S16;
  spec.channels := 2;
  spec.freq := SfxRate;
  Stream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, nil, nil);
  if Stream = nil then AudioError := 'no audio: ' + SDLErr else SDL_ResumeAudioStreamDevice(Stream);
  if UITestLog <> '' then Muted := True;

  EnsureTextures;
  DrawLoading;
  SDL_RenderPresent(Ren);
  BuildSounds;
  if CliLevel > 0 then
  begin
    AttractMode := False;
    G.Mode := CurMode;
    G.StartLevel(CliLevel - 1, Points, 1000 + CliLevel - 1);
    Screen := scBriefing;
    if BotOn or quitAfterShot or PreviewMode then Screen := scPlaying;
  end
  else
  begin
    AttractMode := True;
    G.Mode := gmBlackHole;
    G.StartLevel(AttractLevel, Points, 4242);
    Screen := scTitle;
  end;
  PendingLevel := -1;
  if DevAuto then DevOpen;
  if CliDemo then StartDemo;
  if UITestLog <> '' then
  begin
    UT.Log := TStringList.Create;
    UTLog('PauliSurfer --ui-test  progress ' + ProgressPath);
    UT.Wait := 10;
  end;

  Running := True;
  lastS := SDL_GetTicksNS / 1e9;
  startS := lastS;
  while Running do
  begin
    PollEvents;
    if (UITestLog <> '') and not UITestStep then Running := False;
    NowS := SDL_GetTicksNS / 1e9;
    dt := Min(0.05, NowS - lastS);
    lastS := NowS;
    if StatusT > 0 then StatusT := StatusT - dt;
    ReloadT := ReloadT + dt;
    if ReloadT > 0.5 then
    begin
      ReloadT := 0;
      CheckDataFiles(False);
    end;
    { editor preview: the bot replays the level }
    if PreviewMode and (Screen = scResult) then
    begin
      PreviewT := PreviewT + dt;
      if PreviewT > 2.5 then
      begin
        PreviewT := 0;
        RequestLevel(G.Level);
        PendingScreen := scPlaying;
      end;
    end;
    { level change: show the loading frame, then sample the orbital }
    if PendingLevel >= 0 then
    begin
      EnsureTextures;
      DrawLoading;
      SDL_RenderPresent(Ren);
      AttractMode := PendingScreen = scTitle;
      if AttractMode then
      begin
        G.Mode := gmBlackHole;
        G.StartLevel(PendingLevel, Points, 4242, Random(100000) + 1);
      end
      else
      begin
        G.Mode := CurMode;
        G.StartLevel(PendingLevel, Points, 1000 + PendingLevel);
      end;
      Screen := PendingScreen;
      PendingLevel := -1;
      TrailN := 0;
      lastS := SDL_GetTicksNS / 1e9;
      Continue;
    end;
    if DemoMode then DemoTick(dt);
    if (Screen = scPlaying) or (AttractMode and (Screen in [scTitle, scLevels, scHelp])) then StepGame(dt);
    if Screen = scPlaying then begin Inc(FrameCount); FrameTime := FrameTime + dt; end;
    FlipFlash := Max(0, FlipFlash - dt * GFX[fxFlipDecay]);
    InsetAz := InsetAz + dt * 12;
    for ww := 0 to High(Fx) do Fx[ww].T := Fx[ww].T + dt;
    { sound loops: orbital ambience, decoherence hiss on a node }
    if Screen = scPlaying then NodeGlow := NodeGlow + ((Ord(G.ProbeProb < 0.035)) - NodeGlow) * Min(1, dt * 8)
    else NodeGlow := NodeGlow * 0.9;
    SetLoop(0, snAmbient, 1);
    SetLoop(1, snNodeLoop, NodeGlow * 0.9);
    if Screen = scPlaying then BHGlow := BHGlow + (Min(1.2, G.Tidal) - BHGlow) * Min(1, dt * 6)
    else BHGlow := BHGlow * 0.9;
    SetLoop(2, snBHLoop, BHGlow);
    HorizonFlash := Max(0, HorizonFlash - dt * GFX[fxHorizonDecay]);

    EnsureTextures;
    LayersReset;
    SDL_SetRenderDrawColor(Ren, 0, 0, 0, 255);
    SDL_RenderClear(Ren);
    RenderCloud;
    o := G.Active;
    if Screen in [scPlaying, scPaused, scResult] then
    begin
      DrawWorld;
      if NodeGlow > 0.02 then Hud.Rect(0, 0, OutW, OutH, FxC(fxColDanger), Round(GFX[fxNodeTint] * NodeGlow));
      if FlipFlash > 0 then Hud.Rect(0, 0, OutW, OutH, $FFFFFF, Round(GFX[fxFlipFlash] * FlipFlash));
      if HorizonFlash > 0 then Hud.Rect(0, 0, OutW, OutH, FxC(fxColHorizonFlash), Round(GFX[fxHorizonFlash] * HorizonFlash));
      DrawGameHud;
      if DemoMode then DrawDemoOverlay;
    end
    else if Screen = scBriefing then
    begin
      DrawHeaderInfo;
      if DemoMode then DrawDemoOverlay;
    end
    else
    begin
      DrawWorld;
      DrawHeaderInfo;
    end;
    if Screen <> scPlaying then UseOverlay;
    if Screen <> scPlaying then GrpBegin('menu.' + MenuName[Screen], 'menu');
    case Screen of
      scTitle: DrawTitle;
      scLevels: DrawLevels;
      scHelp: DrawHelp;
      scBriefing: DrawBriefing;
      scPaused: DrawPaused;
      scResult: DrawResult;
    end;
    GrpEnd;
    SetView;
    if IsWide then
    begin
      if StatusT > 0 then TextV(fkTiny, StatusMsg, CW / 2, CH - 20, cText, alCenter);
      if AudioError <> '' then TextV(fkTiny, AudioError, CW / 2, CH - 36, cFaint, alCenter);
    end
    else
    begin
      if StatusT > 0 then TextV(fkTiny, StatusMsg, 450, 1580, cText, alCenter);
      if AudioError <> '' then TextV(fkTiny, AudioError, 450, 1590, cFaint, alCenter);
    end;
    DrawLayerOutlines;
    UI.EndFrame;
    PumpAudio(dt);
    if dt > 0 then FpsAvg := FpsAvg * 0.95 + 0.05 / dt;
    if (ShotFile <> '') and (NowS - startS >= ShotDelay) then
    begin
      if FileExists(ShotFile) then DeleteFile(ShotFile);
      if SavePNG(ShotFile) then Flash('saved ' + ShotFile);
      ShotFile := '';
      if quitAfterShot then Running := False;
    end;
    SDL_RenderPresent(Ren);
    DevDraw(dt);
  end;
  DevClose;
  StopDemo;                                 { restores the player's mode before saving }
  if UITestLog = '' then SaveProgress;      { keeps zoom / HUD size }
  if UT.Log <> nil then
  begin
    UT.Log.SaveToFile(UITestLog);
    UT.Log.Free;
  end;
  G.Free;
  Raster.Free;
  Inset.Free;
  UI.Free;
  HudMain.Free;
  HudMenu.Free;
  HudLbl.Free;
  if Tex <> nil then SDL_DestroyTexture(Tex);
  if InsetTex <> nil then SDL_DestroyTexture(InsetTex);
  if Stream <> nil then SDL_DestroyAudioStream(Stream);
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
  if UT.Fails > 0 then Halt(2);
end.
