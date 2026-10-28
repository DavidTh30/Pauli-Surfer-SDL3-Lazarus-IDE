unit uEdKit;

{ Shared frame of the three PAULI SURFER 2 editors (Sound / Level / Effect).

  - one SDL3 window, render-output pixels, a design canvas of 1440 x 900 units
    scaled by SK = min(OutW / 1440, OutH / 900): the layout keeps its place at
    any window size, extra room goes to the right / bottom
  - widgets in units (uUI underneath): buttons with key chips, sliders,
    steppers, toggles, text fields (SDL text input), panels
  - every part is a named layer (GrpBegin / GrpEnd, widgets add themselves):
    F3 = 1 px dashed outlines, F4 = names, like the game
  - DEVELOPER window (separate SDL window, opens at start, F2): LAYERS (name,
    kind, x y w h; hover = highlight in the editor; right click = copy row /
    name / all) and STATE (rows the editor supplies: data, file, audio ...)
  - --ui-test=LOG [--ui-shots=DIR]: the editor's scripted test steps, clicks
    go through the same widgets as the mouse; --size=WxH, --dev=0|1 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, SDL3, SDL3_image, uHud, uUI;

const
  DesignW = 1440;
  DesignH = 900;
  cOrange = $FF8C1A;
  cBlue = $3A6BFF;
  cGold = $FFD24A;
  cCyan = $6FE6FF;
  cRed = $FF3B3B;
  cGreen = $5FD68A;
  cText = $E8E8E8;
  cDim = $9AA0A8;
  cFaint = $5E6570;
  cBg = $07090D;
  cPanel = $0E1016;
  DevWinW = 560;

type
  TEdLayer = record
    Name, Kind: string;
    R: TSDL_FRect;
  end;

  TKeyProc = procedure(AKey: TSDL_Keycode; AMod: TSDL_Keymod);
  TStateProc = procedure(L: TStrings);
  TStepFunc = function(AStep: Integer): Boolean;
  TDrawProc = procedure;

var
  Win: PSDL_Window;
  Ren: PSDL_Renderer;
  Hud: THud;
  UI: TUI;
  OutW, OutH, WinW, WinH: Integer;
  SK: Single = 1;                    { pixels per design unit }
  CWu, CHu: Single;                  { canvas size in units }
  Running: Boolean = True;
  NowS, Dt: Double;
  ShowOutlines, ShowLabels: Boolean;
  Layers: array of TEdLayer;
  LayerN: Integer;
  OnKey: TKeyProc;
  OnDevState: TStateProc;
  OnTestStep: TStepFunc;
  OnQuit: TDrawProc;                 { before the windows close (stop audio, ask nothing) }
  AppTitle: string;
  StatusMsg: string;
  StatusT: Double;
  FocusKey: string;                  { text field being edited }
  HoverLayer: string;                { from the developer window }
  { command line }
  DevAuto: Boolean = True;
  DevArg: Boolean;
  UTLogFile, UTShotDir: string;
  UTStep, UTWait, UTFails, UTChecks: Integer;
  UTLines: TStringList;

function ExeDir: string;
function ArgValue(const AName, ADefault: string): string;
function HasArg(const AName: string): Boolean;

procedure EdInit(const ATitle: string);
procedure EdRun(ADraw: TDrawProc);
procedure EdDone;
procedure Status(const S: string);

{ units <-> pixels }
function U(X: Single): Single; inline;
function PX(X: Single): Single; inline;    { unit x -> pixel x }
function PY(Y: Single): Single; inline;

{ layers (pixel rectangles) }
procedure GrpBegin(const AName, AKind: string);
procedure GrpEnd;
procedure AddLayer(const AName, AKind: string; X, Y, W, H: Single);
function FindLayer(const AName: string; out R: TSDL_FRect): Boolean;

{ drawing in units }
function Txt(AKind: TFontKind; const S: string; X, Y: Single; ACol: UInt32; AAlign: TAlign = alLeft;
  AAlpha: Byte = 255): Single;
function TxtW(AKind: TFontKind; const S: string): Single;
procedure Box(X, Y, W, H: Single; ACol: UInt32; AAlpha: Byte = 255);
procedure Frame(X, Y, W, H: Single; ACol: UInt32; AAlpha: Byte = 255);
procedure PanelU(const AName: string; X, Y, W, H: Single; const ATitle: string = '');
procedure DashRect(X, Y, W, H, T: Single; ACol: UInt32; AAlpha: Byte);

{ widgets in units; AKey names the layer (btn.<key>, slider.<key> ...) }
function Btn(const ACap: string; X, Y, W, H: Single; ASel: Boolean = False; const AKey: string = '';
  const AChip: string = ''): Boolean;
function SliderU(AId: Integer; const AKey, ACap, AVal: string; X, Y, W: Single; var V: Double;
  AMin, AMax: Double): Boolean;
function StepperU(const AKey, ACap, AVal: string; X, Y, W, H: Single): Integer;
function Toggle(const AKey, ACap: string; X, Y, W, H: Single; var B: Boolean): Boolean;
function TextField(const AKey: string; X, Y, W, H: Single; var AText: string; AMaxLen: Integer = 160): Boolean;
function RowHit(X, Y, W, H: Single): Boolean;      { a list row clicked }

{ developer window }
procedure DevOpen;
procedure DevClose;

{ test + files }
procedure UTLog(const S: string);
procedure UTCheck(ACond: Boolean; const AWhat: string);
function UTClick(const AKey: string): Boolean;
procedure UTShot(const AName: string);
function SavePNG(const AFile: string): Boolean;
{ starts PauliSurfer2.exe (next to the editor) with the arguments }
function LaunchGame(const AArgs: array of string): Boolean;

implementation

uses
  Process;

var
  Groups: array[0..15] of Integer;
  GroupDepth: Integer;
  ClickRelease: Boolean;
  PendingShot: string;
  EdBuf, EdOrig: string;
  EdUnfocus: Boolean;
  { developer window }
  DevWin: PSDL_Window;
  DevRen: PSDL_Renderer;
  DevHud: THud;
  DevUI: TUI;
  DevTab: Integer;
  DevScroll, DevContentH, DevRedrawT: Double;
  DevRows: TStringList;
  PopupRow: Integer = -1;
  PopupX, PopupY: Single;

function ExeDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function ArgValue(const AName, ADefault: string): string;
var
  i: Integer;
  a: string;
begin
  Result := ADefault;
  for i := 1 to ParamCount do
  begin
    a := ParamStr(i);
    if SameText(a, '--' + AName) then Exit('1');
    if AnsiStartsText('--' + AName + '=', a) then Exit(Copy(a, Length(AName) + 4, MaxInt));
  end;
end;

function HasArg(const AName: string): Boolean;
begin
  Result := ArgValue(AName, #0) <> #0;
end;

procedure Status(const S: string);
begin
  StatusMsg := S;
  StatusT := 4;
  if UTLines <> nil then UTLog('status: ' + S);
end;

function U(X: Single): Single;
begin
  Result := X * SK;
end;

function PX(X: Single): Single;
begin
  Result := X * SK;
end;

function PY(Y: Single): Single;
begin
  Result := Y * SK;
end;

{ ---------------------------------------------------------------- layers }

procedure Extend(AIdx: Integer; AX, AY, AW, AH: Single);
var
  p: ^TSDL_FRect;
  x1, y1: Single;
begin
  p := @Layers[AIdx].R;
  if p^.w < 0 then
  begin
    p^.x := AX; p^.y := AY; p^.w := AW; p^.h := AH;
    Exit;
  end;
  x1 := Max(p^.x + p^.w, AX + AW);
  y1 := Max(p^.y + p^.h, AY + AH);
  p^.x := Min(p^.x, AX);
  p^.y := Min(p^.y, AY);
  p^.w := x1 - p^.x;
  p^.h := y1 - p^.y;
end;

procedure ExtendGroups(AX, AY, AW, AH: Single);
var
  i: Integer;
begin
  for i := 0 to GroupDepth - 1 do Extend(Groups[i], AX, AY, AW, AH);
end;

function NewLayer(const AName, AKind: string): Integer;
begin
  if LayerN >= Length(Layers) then SetLength(Layers, LayerN * 2 + 64);
  Layers[LayerN].Name := AName;
  Layers[LayerN].Kind := AKind;
  Layers[LayerN].R.x := 0; Layers[LayerN].R.y := 0; Layers[LayerN].R.w := -1; Layers[LayerN].R.h := -1;
  Result := LayerN;
  Inc(LayerN);
end;

procedure GrpBegin(const AName, AKind: string);
begin
  if GroupDepth > High(Groups) then Exit;
  Groups[GroupDepth] := NewLayer(AName, AKind);
  Inc(GroupDepth);
end;

procedure GrpEnd;
begin
  if GroupDepth > 0 then Dec(GroupDepth);
end;

procedure AddLayer(const AName, AKind: string; X, Y, W, H: Single);
var
  i: Integer;
begin
  i := NewLayer(AName, AKind);
  Extend(i, X, Y, W, H);
  ExtendGroups(X, Y, W, H);
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

{ ---------------------------------------------------------------- drawing }

function Txt(AKind: TFontKind; const S: string; X, Y: Single; ACol: UInt32; AAlign: TAlign; AAlpha: Byte): Single;
var
  w, x0: Single;
begin
  w := Hud.Text(AKind, S, U(X), U(Y), ACol, AAlign, AAlpha);
  case AAlign of
    alRight: x0 := U(X) - w;
    alCenter: x0 := U(X) - w / 2;
  else
    x0 := U(X);
  end;
  if S <> '' then ExtendGroups(x0, U(Y), w, Hud.LineHeight(AKind));
  Result := w / SK;
end;

function TxtW(AKind: TFontKind; const S: string): Single;
begin
  Result := Hud.TextWidth(AKind, S) / SK;
end;

procedure Box(X, Y, W, H: Single; ACol: UInt32; AAlpha: Byte);
begin
  Hud.Rect(U(X), U(Y), U(W), U(H), ACol, AAlpha);
end;

procedure Frame(X, Y, W, H: Single; ACol: UInt32; AAlpha: Byte);
begin
  Hud.Rect(U(X), U(Y), U(W), 1, ACol, AAlpha);
  Hud.Rect(U(X), U(Y + H) - 1, U(W), 1, ACol, AAlpha);
  Hud.Rect(U(X), U(Y), 1, U(H), ACol, AAlpha);
  Hud.Rect(U(X + W) - 1, U(Y), 1, U(H), ACol, AAlpha);
end;

procedure PanelU(const AName: string; X, Y, W, H: Single; const ATitle: string);
begin
  Box(X, Y, W, H, cPanel, 235);
  Frame(X, Y, W, H, $FFFFFF, 28);
  AddLayer('panel.' + AName, 'panel', U(X), U(Y), U(W), U(H));
  if ATitle <> '' then Txt(fkSmallBold, ATitle, X + 14, Y + 10, cDim);
end;

procedure DashRect(X, Y, W, H, T: Single; ACol: UInt32; AAlpha: Byte);
var
  p: Single;
const
  Seg = 4;
  Gap = 4;
begin
  p := 0;
  while p < W do
  begin
    Hud.Rect(X + p, Y, Min(Seg, W - p), T, ACol, AAlpha);
    Hud.Rect(X + p, Y + H - T, Min(Seg, W - p), T, ACol, AAlpha);
    p := p + Seg + Gap;
  end;
  p := 0;
  while p < H do
  begin
    Hud.Rect(X, Y + p, T, Min(Seg, H - p), ACol, AAlpha);
    Hud.Rect(X + W - T, Y + p, T, Min(Seg, H - p), ACol, AAlpha);
    p := p + Seg + Gap;
  end;
end;

{ ---------------------------------------------------------------- widgets }

function KeyOf(const ACap, AKey: string): string;
begin
  if AKey <> '' then Result := AKey else Result := LowerCase(ReplaceStr(Trim(ACap), ' ', '_'));
end;

function Btn(const ACap: string; X, Y, W, H: Single; ASel: Boolean; const AKey, AChip: string): Boolean;
var
  k: string;
  cw, th: Single;
begin
  k := KeyOf(ACap, AKey);
  if AChip = '' then
    Result := UI.Button(ACap, U(X), U(Y), U(W), U(H), ASel, k)
  else
  begin
    { caption centred in the room left of the key chip }
    Result := UI.Button('', U(X), U(Y), U(W), U(H), ASel, k);
    cw := TxtW(fkTiny, AChip) + 8;
    th := Hud.LineHeight(fkSmall);
    Hud.Text(fkSmall, ACap, U(X + (W - cw - 6) / 2), U(Y) + (U(H) - th) / 2 + th * 0.05, IfThen(ASel, $111111, cText), alCenter);
    Box(X + W - cw - 5, Y + (H - 15) / 2, cw, 15, $000000, IfThen(ASel, 60, 120));
    Frame(X + W - cw - 5, Y + (H - 15) / 2, cw, 15, IfThen(ASel, $000000, $FFFFFF), 70);
    Hud.Text(fkTiny, AChip, U(X + W - cw / 2 - 5), U(Y + (H - 15) / 2 + 1), IfThen(ASel, $111111, cGold), alCenter);
  end;
  AddLayer('btn.' + k, 'button', U(X), U(Y), U(W), U(H));
end;

function SliderU(AId: Integer; const AKey, ACap, AVal: string; X, Y, W: Single; var V: Double; AMin, AMax: Double): Boolean;
var
  commit: Boolean;
begin
  Result := UI.Slider(AId, ACap, AVal, U(X), U(Y), U(W), V, AMin, AMax, commit);
  AddLayer('slider.' + AKey, 'slider', U(X), U(Y), U(W), 16 * Hud.Scale + 16 * Hud.Scale);
end;

function StepperU(const AKey, ACap, AVal: string; X, Y, W, H: Single): Integer;
begin
  { [-] value [+]; the buttons are btn.<key>- and btn.<key>+ }
  Result := 0;
  GrpBegin('stepper.' + AKey, 'stepper');
  Txt(fkTiny, ACap, X, Y - 15, cDim);
  if Btn('-', X, Y, H, H, False, AKey + '-') then Result := -1;
  Box(X + H, Y, W - 2 * H, H, $05070A);
  Txt(fkBodyBold, AVal, X + W / 2, Y + (H - Hud.LineHeight(fkBodyBold) / SK) / 2 + 1, cText, alCenter);
  if Btn('+', X + W - H, Y, H, H, False, AKey + '+') then Result := 1;
  GrpEnd;
end;

function Toggle(const AKey, ACap: string; X, Y, W, H: Single; var B: Boolean): Boolean;
begin
  Result := Btn(IfThen(B, '[x] ', '[ ] ') + ACap, X, Y, W, H, B, AKey);
  if Result then B := not B;
end;

function RowHit(X, Y, W, H: Single): Boolean;
begin
  Result := (UI.Active = 0) and UI.Pressed and UI.Inside(U(X), U(Y), U(W), U(H));
end;

function TextField(const AKey: string; X, Y, W, H: Single; var AText: string; AMaxLen: Integer): Boolean;
var
  focused, hot: Boolean;
  shown: string;
  tw, maxw: Single;
begin
  Result := False;
  AddLayer('field.' + AKey, 'field', U(X), U(Y), U(W), U(H));
  hot := UI.Inside(U(X), U(Y), U(W), U(H));
  if UI.Pressed and (UI.Active = 0) then
  begin
    if hot and (FocusKey <> AKey) then
    begin
      FocusKey := AKey;
      EdBuf := AText;
      EdOrig := AText;
      SDL_StartTextInput(Win);
    end
    else if not hot and (FocusKey = AKey) then
    begin
      FocusKey := '';
      SDL_StopTextInput(Win);
    end;
  end;
  focused := FocusKey = AKey;
  if focused then
  begin
    if Length(EdBuf) > AMaxLen then SetLength(EdBuf, AMaxLen);
    if AText <> EdBuf then
    begin
      AText := EdBuf;
      Result := True;
    end;
    if EdUnfocus then
    begin
      EdUnfocus := False;
      FocusKey := '';
      SDL_StopTextInput(Win);
      focused := False;
    end;
  end;
  Box(X, Y, W, H, $05070A);
  if focused then Frame(X, Y, W, H, cOrange, 255)
  else if hot then Frame(X, Y, W, H, $FFFFFF, 90)
  else Frame(X, Y, W, H, $FFFFFF, 40);
  shown := AText;
  maxw := U(W - 14);
  tw := Hud.TextWidth(fkSmall, shown);
  while (tw > maxw) and (Length(shown) > 1) do
  begin
    Delete(shown, 1, 1);
    tw := Hud.TextWidth(fkSmall, '...' + shown);
  end;
  if shown <> AText then shown := '...' + shown;
  Hud.Text(fkSmall, shown, U(X + 7), U(Y) + (U(H) - Hud.LineHeight(fkSmall)) / 2, cText);
  if focused and (Frac(NowS * 1.6) < 0.6) then
    Hud.Rect(U(X + 7) + Hud.TextWidth(fkSmall, shown) + 1, U(Y + 4), Max(1, U(1.5)), U(H - 8), cOrange);
end;

{ ---------------------------------------------------------------- PNG / launch }

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

function LaunchGame(const AArgs: array of string): Boolean;
var
  p: TProcess;
  i: Integer;
  exe: string;
begin
  Result := False;
  exe := ExeDir + 'PauliSurfer2.exe';
  if not FileExists(exe) then
  begin
    Status('PauliSurfer2.exe not found next to the editor');
    Exit;
  end;
  p := TProcess.Create(nil);
  try
    p.Executable := exe;
    p.CurrentDirectory := ExeDir;
    for i := 0 to High(AArgs) do p.Parameters.Add(AArgs[i]);
    p.Options := [];
    try
      p.Execute;
      Result := True;
    except
      on E: Exception do Status('could not start the game: ' + E.Message);
    end;
  finally
    p.Free;     { the game keeps running on its own }
  end;
end;

{ ---------------------------------------------------------------- ui-test }

procedure UTLog(const S: string);
begin
  if UTLines = nil then Exit;
  UTLines.Add(FormatDateTime('hh:nn:ss.zzz', Now) + '  ' + S);
end;

procedure UTCheck(ACond: Boolean; const AWhat: string);
begin
  Inc(UTChecks);
  if ACond then UTLog('ok    ' + AWhat)
  else
  begin
    Inc(UTFails);
    UTLog('FAIL  ' + AWhat);
  end;
end;

function UTClick(const AKey: string): Boolean;
var
  r: TSDL_FRect;
begin
  Result := UI.FindRect(AKey, r) or FindLayer(AKey, r) or FindLayer('btn.' + AKey, r) or FindLayer('field.' + AKey, r);
  if not Result then
  begin
    UTCheck(False, 'click target not found: ' + AKey);
    Exit;
  end;
  UI.MouseMove(r.x + r.w / 2, r.y + r.h / 2);
  UI.MouseButton(r.x + r.w / 2, r.y + r.h / 2, True);
  ClickRelease := True;
  UTLog('click ' + AKey);
end;

procedure UTShot(const AName: string);
begin
  if UTShotDir <> '' then PendingShot := IncludeTrailingPathDelimiter(UTShotDir) + AName + '.png';
end;

{ ---------------------------------------------------------------- developer window }

procedure DevOpen;
var
  x, y, w, h: Integer;
  rect: TSDL_Rect;
begin
  if DevWin <> nil then Exit;
  SDL_GetWindowPosition(Win, @x, @y);
  SDL_GetWindowSize(Win, @w, @h);
  if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @rect) then
  begin
    rect.x := 0; rect.y := 0; rect.w := 1920; rect.h := 1080;
  end;
  DevWin := SDL_CreateWindow(PAnsiChar(AnsiString(AppTitle + ' - DEVELOPER')), DevWinW, Min(h, rect.h - 60),
    SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if DevWin = nil then Exit;
  SDL_SetWindowPosition(DevWin, Min(x + w + 8, rect.x + rect.w - DevWinW), y);
  DevRen := SDL_CreateRenderer(DevWin, nil);
  SDL_SetRenderDrawBlendMode(DevRen, SDL_BLENDMODE_BLEND);
  SDL_SetRenderVSync(DevRen, 0);
  DevHud := THud.Create(DevRen);
  DevUI := TUI.Create(DevHud);
  if DevRows = nil then DevRows := TStringList.Create;
  DevRedrawT := 0;
  SDL_RaiseWindow(Win);
end;

procedure DevClose;
begin
  if DevWin = nil then Exit;
  FreeAndNil(DevUI);
  FreeAndNil(DevHud);
  SDL_DestroyRenderer(DevRen);
  SDL_DestroyWindow(DevWin);
  DevWin := nil;
  DevRen := nil;
  HoverLayer := '';
  PopupRow := -1;
end;

function DevId: TSDL_WindowID;
begin
  if DevWin = nil then Result := 0 else Result := SDL_GetWindowID(DevWin);
end;

function LayerLine(I: Integer): string;
begin
  with Layers[I] do
    Result := Format('%s'#9'%s'#9'x %d  y %d  w %d  h %d', [Name, Kind, Round(R.x), Round(R.y), Round(R.w), Round(R.h)]);
end;

procedure CopyText(const S, AWhat: string);
begin
  SDL_SetClipboardText(PAnsiChar(AnsiString(S)));
  Status('copied ' + AWhat);
end;

procedure DevDraw;
var
  ow, oh, i, n: Integer;
  y, top, rh, u2, x2: Single;
  sec, nm, val, t: string;
  p: Integer;
  hot: Boolean;
begin
  if DevWin = nil then Exit;
  DevRedrawT := DevRedrawT - Dt;
  if (DevRedrawT > 0) and not DevUI.Pressed and (DevUI.WheelY = 0) then Exit;
  DevRedrawT := 1 / 15;
  SDL_GetCurrentRenderOutputSize(DevRen, @ow, @oh);
  u2 := Max(1, oh / 900);
  DevHud.SetScale(u2 * 1.1);
  SDL_SetRenderDrawColor(DevRen, 8, 10, 14, 255);
  SDL_RenderClear(DevRen);
  DevHud.Text(fkBodyBold, 'DEVELOPER', 14 * u2, 10 * u2, cOrange);
  DevHud.Text(fkTiny, AppTitle + '   F2 window  F3 outlines  F4 names  F12 PNG', 14 * u2, 32 * u2, cDim);
  if DevUI.Button('LAYERS', 14 * u2, 52 * u2, 120 * u2, 26 * u2, DevTab = 0, 'tab.layers') then begin DevTab := 0; DevScroll := 0; end;
  if DevUI.Button('STATE', 140 * u2, 52 * u2, 120 * u2, 26 * u2, DevTab = 1, 'tab.state') then begin DevTab := 1; DevScroll := 0; end;
  if DevUI.Button(IfThen(ShowOutlines, 'OUTLINES ON', 'OUTLINES OFF'), 266 * u2, 52 * u2, 130 * u2, 26 * u2, ShowOutlines, 'outlines') then
    ShowOutlines := not ShowOutlines;
  if DevUI.Button('COPY ALL', 402 * u2, 52 * u2, 110 * u2, 26 * u2, False, 'copyall') then
  begin
    t := '';
    for i := 0 to LayerN - 1 do if Layers[i].R.w >= 0 then t := t + LayerLine(i) + LineEnding;
    CopyText(t, 'all layers');
  end;
  top := 88 * u2;
  rh := DevHud.LineHeight(fkTiny) + 3 * u2;
  if DevUI.Inside(0, top, ow, oh - top) then DevScroll := DevScroll - DevUI.WheelY * rh * 3;
  DevScroll := EnsureRange(DevScroll, 0, Max(0, DevContentH - (oh - top)));
  y := top - DevScroll;
  if PopupRow < 0 then HoverLayer := '';
  if DevTab = 0 then
  begin
    n := 0;
    DevHud.Text(fkTiny, Format('%d named layers (drawn this frame)', [LayerN]), 14 * u2, y, cFaint);
    y := y + rh * 1.3;
    for i := 0 to LayerN - 1 do
    begin
      if Layers[i].R.w < 0 then Continue;
      Inc(n);
      if (y > top - rh) and (y < oh) then
      begin
        hot := DevUI.Inside(0, y, ow, rh) and (DevUI.MY >= top);
        if hot and (PopupRow < 0) then
        begin
          DevHud.Rect(0, y, ow, rh, $FFFFFF, 18);
          HoverLayer := Layers[i].Name;
        end;
        if (PopupRow = i) then DevHud.Rect(0, y, ow, rh, cOrange, 40);
        DevHud.Text(fkTiny, Layers[i].Name, 14 * u2, y, cText);
        DevHud.Text(fkTiny, Layers[i].Kind, 250 * u2, y, cDim);
        DevHud.Text(fkTiny, Format('%d %d %d %d', [Round(Layers[i].R.x), Round(Layers[i].R.y), Round(Layers[i].R.w),
          Round(Layers[i].R.h)]), ow - 12 * u2, y, cDim, alRight);
      end;
      y := y + rh;
    end;
  end
  else
  begin
    DevRows.Clear;
    if Assigned(OnDevState) then OnDevState(DevRows);
    DevRows.Add('#WINDOW');
    DevRows.Add(Format('output'#9'%d x %d px  (window %d x %d)', [OutW, OutH, WinW, WinH]));
    DevRows.Add(Format('design scale SK'#9'%.3f px / unit  (canvas %.0f x %.0f units)', [SK, CWu, CHu]));
    DevRows.Add(Format('frame'#9'%.1f ms', [Dt * 1000]));
    DevRows.Add('focus field'#9 + IfThen(FocusKey <> '', FocusKey, '-'));
    for i := 0 to DevRows.Count - 1 do
    begin
      t := DevRows[i];
      if (t <> '') and (t[1] = '#') then
      begin
        y := y + rh * 0.4;
        DevHud.Text(fkSmallBold, Copy(t, 2, MaxInt), 14 * u2, y, cOrange);
        y := y + rh * 1.2;
        Continue;
      end;
      p := Pos(#9, t);
      if p > 0 then begin nm := Copy(t, 1, p - 1); val := Copy(t, p + 1, MaxInt); end
      else begin nm := t; val := ''; end;
      DevHud.Text(fkTiny, nm, 14 * u2, y, cDim);
      x2 := 200 * u2;
      DevHud.Text(fkTiny, val, x2, y, cText);
      y := y + rh;
    end;
  end;
  DevContentH := y + DevScroll - top + rh;
  sec := '';
  { right-click menu on a layer row }
  if (DevTab = 0) and (PopupRow >= 0) and (PopupRow < LayerN) then
  begin
    DevHud.Rect(PopupX, PopupY, 190 * u2, 4 * 28 * u2 + 8 * u2, $1A1E28, 250);
    if DevUI.Button('Copy row', PopupX + 4 * u2, PopupY + 4 * u2, 182 * u2, 26 * u2, False, 'pop-copyrow') then sec := 'row';
    if DevUI.Button('Copy name', PopupX + 4 * u2, PopupY + 32 * u2, 182 * u2, 26 * u2, False, 'pop-copyname') then sec := 'name';
    if DevUI.Button('Copy all layers', PopupX + 4 * u2, PopupY + 60 * u2, 182 * u2, 26 * u2, False, 'pop-copyall') then sec := 'all';
    if DevUI.Button('Close', PopupX + 4 * u2, PopupY + 88 * u2, 182 * u2, 26 * u2, False, 'pop-close') then sec := 'close';
    if (sec = '') and DevUI.Pressed and not DevUI.Inside(PopupX, PopupY, 190 * u2, 120 * u2) then sec := 'close';
  end;
  if sec = 'row' then CopyText(LayerLine(PopupRow), Layers[PopupRow].Name)
  else if sec = 'name' then CopyText(Layers[PopupRow].Name, 'name ' + Layers[PopupRow].Name)
  else if sec = 'all' then
  begin
    t := '';
    for i := 0 to LayerN - 1 do if Layers[i].R.w >= 0 then t := t + LayerLine(i) + LineEnding;
    CopyText(t, 'all layers');
  end;
  if sec <> '' then PopupRow := -1;
  DevUI.EndFrame;
  SDL_RenderPresent(DevRen);
end;

{ which layer row is under a dev-window point }
function DevRowAt(AY: Single): Integer;
var
  ow, oh, i: Integer;
  y, top, rh, u2: Single;
begin
  Result := -1;
  SDL_GetCurrentRenderOutputSize(DevRen, @ow, @oh);
  u2 := Max(1, oh / 900);
  top := 88 * u2;
  rh := DevHud.LineHeight(fkTiny) + 3 * u2;
  y := top - DevScroll + rh * 1.3;
  for i := 0 to LayerN - 1 do
  begin
    if Layers[i].R.w < 0 then Continue;
    if (AY >= y) and (AY < y + rh) then Exit(i);
    y := y + rh;
  end;
end;

{ ---------------------------------------------------------------- outlines }

function KindColor(const AKind: string): UInt32;
begin
  if AKind = 'panel' then Result := $FFD24A
  else if AKind = 'button' then Result := $6FE6FF
  else if AKind = 'slider' then Result := $FF8C1A
  else if AKind = 'field' then Result := $5FD68A
  else if AKind = 'list' then Result := $B57EDC
  else if AKind = 'view' then Result := $FF3B3B
  else Result := $FFFFFF;
end;

procedure DrawOutlines;
var
  i: Integer;
begin
  for i := 0 to LayerN - 1 do
    with Layers[i] do
    begin
      if R.w < 0 then Continue;
      if ShowOutlines then
      begin
        DashRect(R.x, R.y, R.w, R.h, 1, KindColor(Kind), 170);
        if ShowLabels then Hud.Text(fkTiny, Name, R.x + 2, R.y + 1, KindColor(Kind), alLeft, 200);
      end;
      if (HoverLayer <> '') and (Name = HoverLayer) then
      begin
        Hud.Rect(R.x, R.y, R.w, R.h, $FFFFFF, 30);
        DashRect(R.x, R.y, R.w, R.h, 1, $FFFFFF, 255);
        Hud.Text(fkTiny, Name + Format('  %d x %d', [Round(R.w), Round(R.h)]), R.x + 2, R.y - Hud.LineHeight(fkTiny), $FFFFFF);
      end;
    end;
end;

{ ---------------------------------------------------------------- events + loop }

procedure HandleKeyDown(const AEv: TSDL_KeyboardEvent);
var
  k: TSDL_Keycode;
begin
  k := AEv.key;
  if FocusKey <> '' then
  begin
    if k = SDLK_BACKSPACE then
    begin
      if EdBuf <> '' then
      begin
        { drop one UTF-8 character }
        SetLength(EdBuf, Length(EdBuf) - 1);
        while (EdBuf <> '') and ((Ord(EdBuf[Length(EdBuf)]) and $C0) = $80) do SetLength(EdBuf, Length(EdBuf) - 1);
        if (EdBuf <> '') and (Ord(EdBuf[Length(EdBuf)]) >= $C0) then SetLength(EdBuf, Length(EdBuf) - 1);
      end;
    end
    else if (k = SDLK_RETURN) or (k = SDLK_KP_ENTER) or (k = SDLK_TAB) then
    begin
      FocusKey := '';
      SDL_StopTextInput(Win);
    end
    else if k = SDLK_ESCAPE then
    begin
      { the field takes the original text back, then lets go of the focus }
      EdBuf := EdOrig;
      EdUnfocus := True;
    end;
    Exit;
  end;
  case k of
    SDLK_F2: if DevWin = nil then DevOpen else DevClose;
    SDLK_F3: ShowOutlines := not ShowOutlines;
    SDLK_F4: ShowLabels := not ShowLabels;
    SDLK_F12: PendingShot := ExeDir + 'exports\' + LowerCase(ReplaceStr(AppTitle, ' ', '_')) + '_' +
      FormatDateTime('yyyymmdd_hhnnss', Now) + '.png';
  else
    if Assigned(OnKey) then OnKey(k, AEv.mod_);
  end;
end;

procedure PollEvents;
var
  ev: TSDL_Event;
  did: TSDL_WindowID;
  k2, dk: Single;
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
      SDL_EVENT_TEXT_INPUT:
        if FocusKey <> '' then EdBuf := EdBuf + string(ev.Text.Text);
      SDL_EVENT_KEY_DOWN:
        if (did <> 0) and (ev.key.windowID = did) then
        begin
          if ev.key.key = SDLK_ESCAPE then
            if PopupRow >= 0 then PopupRow := -1 else DevClose;
        end
        else HandleKeyDown(ev.key);
      SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP, SDL_EVENT_MOUSE_WHEEL:
        if (did <> 0) and (ev.motion.windowID = did) then
        begin
          SDL_GetWindowSize(DevWin, @ww, @wh);
          SDL_GetCurrentRenderOutputSize(DevRen, @ow, @oh);
          dk := ow / Max(1, ww);
          DevRedrawT := 0;
          case ev._type of
            SDL_EVENT_MOUSE_MOTION: DevUI.MouseMove(ev.motion.x * dk, ev.motion.y * dk);
            SDL_EVENT_MOUSE_BUTTON_DOWN:
              if ev.button.button = SDL_BUTTON_RIGHT then
              begin
                if DevTab = 0 then
                begin
                  PopupRow := DevRowAt(ev.button.y * dk);
                  PopupX := Min(ev.button.x * dk, ow - 200);
                  PopupY := Min(ev.button.y * dk, oh - 130);
                end;
              end
              else DevUI.MouseButton(ev.button.x * dk, ev.button.y * dk, True);
            SDL_EVENT_MOUSE_BUTTON_UP:
              if ev.button.button = SDL_BUTTON_LEFT then DevUI.MouseButton(ev.button.x * dk, ev.button.y * dk, False);
            SDL_EVENT_MOUSE_WHEEL: DevUI.Wheel(ev.wheel.y);
          end;
        end
        else
          case ev._type of
            SDL_EVENT_MOUSE_MOTION: UI.MouseMove(ev.motion.x * k2, ev.motion.y * k2);
            SDL_EVENT_MOUSE_BUTTON_DOWN:
              if ev.button.button = SDL_BUTTON_LEFT then UI.MouseButton(ev.button.x * k2, ev.button.y * k2, True);
            SDL_EVENT_MOUSE_BUTTON_UP:
              if ev.button.button = SDL_BUTTON_LEFT then UI.MouseButton(ev.button.x * k2, ev.button.y * k2, False);
            SDL_EVENT_MOUSE_WHEEL: UI.Wheel(ev.wheel.y);
          end;
    end;
  end;
end;

procedure EdInit(const ATitle: string);
var
  rect: TSDL_Rect;
  ww, wh: Integer;
  parts: TStringArray;
  v: string;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  AppTitle := ATitle;
  UTLogFile := ArgValue('ui-test', '');
  UTShotDir := ArgValue('ui-shots', '');
  v := ArgValue('dev', '');
  if v <> '' then begin DevAuto := v <> '0'; DevArg := True; end;
  if (UTLogFile <> '') and not DevArg then DevAuto := False;
  if not SDL_Init(SDL_INIT_VIDEO or SDL_INIT_AUDIO) then Halt(1);
  if not SDL_GetDisplayUsableBounds(SDL_GetPrimaryDisplay, @rect) then
  begin
    rect.x := 0; rect.y := 0; rect.w := 1920; rect.h := 1080;
  end;
  ww := 0; wh := 0;
  v := ArgValue('size', '');
  if v <> '' then
  begin
    parts := v.Split(['x', 'X']);
    if Length(parts) = 2 then begin ww := StrToIntDef(parts[0], 0); wh := StrToIntDef(parts[1], 0); end;
  end;
  if ww <= 0 then
  begin
    wh := Round(rect.h * 0.9);
    if DevAuto then ww := Max(900, rect.w - DevWinW - 36) else ww := Round(rect.w * 0.9);
    ww := Min(ww, Round(wh * 1.75));
  end;
  Win := SDL_CreateWindow(PAnsiChar(AnsiString(ATitle)), ww, wh, SDL_WINDOW_RESIZABLE or SDL_WINDOW_HIGH_PIXEL_DENSITY);
  if v = '' then SDL_SetWindowPosition(Win, rect.x + 12, rect.y + 32);
  SDL_SetWindowMinimumSize(Win, 800, 500);
  Ren := SDL_CreateRenderer(Win, nil);
  SDL_SetRenderVSync(Ren, 1);
  SDL_SetRenderDrawBlendMode(Ren, SDL_BLENDMODE_BLEND);
  Hud := THud.Create(Ren);
  UI := TUI.Create(Hud);
  if UTLogFile <> '' then
  begin
    UTLines := TStringList.Create;
    UTLog(ATitle + ' --ui-test');
    UTWait := 15;
  end;
  if DevAuto then DevOpen;
end;

procedure EdRunLoop(ADraw: TDrawProc); forward;

{ runs the frame loop; an exception ends it with the message in crash.txt (and the test log) }
procedure EdRun(ADraw: TDrawProc);
var
  t: TStringList;
  i: Integer;
  fr: PPointer;
begin
  try
    EdRunLoop(ADraw);
  except
    on E: Exception do
    begin
      t := TStringList.Create;
      try
        t.Add(AppTitle + ': ' + E.ClassName + ': ' + E.Message);
        t.Add(BackTraceStrFunc(ExceptAddr));
        fr := ExceptFrames;
        for i := 0 to ExceptFrameCount - 1 do
        begin
          t.Add(BackTraceStrFunc(fr^));
          Inc(fr);
        end;
        t.SaveToFile(ExeDir + 'crash.txt');
        UTLog('CRASH ' + t.Text);
        Inc(UTFails);
      finally
        t.Free;
      end;
    end;
  end;
end;

procedure EdRunLoop(ADraw: TDrawProc);
var
  lastS: Double;
begin
  lastS := SDL_GetTicksNS / 1e9;
  while Running do
  begin
    if ClickRelease then
    begin
      UI.MouseButton(UI.MX, UI.MY, False);
      ClickRelease := False;
    end;
    PollEvents;
    NowS := SDL_GetTicksNS / 1e9;
    Dt := Min(0.1, NowS - lastS);
    lastS := NowS;
    if StatusT > 0 then StatusT := StatusT - Dt;
    if UTLines <> nil then
    begin
      if UTWait > 0 then Dec(UTWait)
      else if not Assigned(OnTestStep) or not OnTestStep(UTStep) then Running := False
      else Inc(UTStep);
    end;
    SDL_GetCurrentRenderOutputSize(Ren, @OutW, @OutH);
    SDL_GetWindowSize(Win, @WinW, @WinH);
    SK := Max(0.4, Min(OutW / DesignW, OutH / DesignH));
    CWu := OutW / SK;
    CHu := OutH / SK;
    Hud.SetScale(SK * 1.2);
    LayerN := 0;
    GroupDepth := 0;
    SDL_SetRenderDrawColor(Ren, 7, 9, 13, 255);
    SDL_RenderClear(Ren);
    ADraw;
    GroupDepth := 0;
    if EdUnfocus then
    begin
      EdUnfocus := False;
      FocusKey := '';
      SDL_StopTextInput(Win);
    end;
    if StatusT > 0 then
    begin
      Box(0, CHu - 26, CWu, 26, $000000, 200);
      Txt(fkSmall, StatusMsg, CWu / 2, CHu - 22, cText, alCenter);
    end;
    DrawOutlines;
    UI.EndFrame;
    if PendingShot <> '' then
    begin
      if SavePNG(PendingShot) then UTLog('png ' + PendingShot)
      else UTLog('png FAILED ' + PendingShot);
      PendingShot := '';
    end;
    SDL_RenderPresent(Ren);
    DevDraw;
  end;
end;

procedure EdDone;
begin
  if Assigned(OnQuit) then OnQuit;
  DevClose;
  if UTLines <> nil then
  begin
    UTLog(Format('done: %d checks, %d failure(s)', [UTChecks, UTFails]));
    UTLines.SaveToFile(UTLogFile);
    FreeAndNil(UTLines);
  end;
  UI.Free;
  Hud.Free;
  SDL_DestroyRenderer(Ren);
  SDL_DestroyWindow(Win);
  SDL_Quit;
  DevRows.Free;
  if UTFails > 0 then Halt(2);
end;

end.
