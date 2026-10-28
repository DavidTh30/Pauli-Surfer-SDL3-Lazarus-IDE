program SoundEditor;

{ PAULI SURFER 2 - SOUND EDITOR

  Edits the 22 sounds of the game (data\pauli_sounds.ini, uPauliData):
    RECIPE   an SFX Studio preset (15 categories x 5) + seed, length, pitch,
             volume - the way the game has always built its sounds
    DESIGN   EDIT LAYERS turns the sound into a custom design: the full
             uSfxEngine synthesis (6 layers: source, glide, FM, filter sweep,
             envelope, ...; echo, reverb) - BACK TO PRESET drops it again
    LISTEN   PLAY (SPACE) the edited sound, PLAY SAVED = the version in the
             file (A / B), COMBO RUN = the 5 pickup sounds as in a combo,
             AMBIENT / NODE / HOLE = the 3 game loops at their game volume
  SAVE (Ctrl+S) writes the file; a running game reloads it within 0.5 s.
  PLAY GAME starts PauliSurfer2.exe. Developer window: F2 (LAYERS + STATE).

  --data=DIR uses another data folder, --ui-test=LOG --ui-shots=DIR test. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils, Math, StrUtils, SDL3, uHud, uUI, uSfxEngine, uSfxGen, uPauliData, uEdKit;

type
  TVoice = record
    Active, Loop: Boolean;
    Data: array of Single;
    Frames, Pos: Integer;
    Gain: Single;
  end;

  TQueued = record
    At: Double;
    Id: TSoundId;
  end;

var
  Sel: TSoundId = snFlip;
  Bufs, SavedBufs: array[TSoundId] of TSoundBuf;
  Saved: array[TSoundId] of string;          { recipe text as in the file -> modified marker }
  Dirty: array[TSoundId] of Boolean;         { needs a new render }
  RenderMs, Peak, Rms: Double;
  LastRender: Double;
  SoundsPath: string;
  SavedAt: string;
  CurLayer: Integer;
  Stream: PSDL_AudioStream;
  AudioError: string;
  Voices: array[0..15] of TVoice;
  MixF: array of Single;
  MixS: array of SmallInt;
  PreviewLoop, LoopAmb, LoopNode, LoopHole: Boolean;
  Queue: array of TQueued;
  ListScroll: Double;
  WaveMin, WaveMax: array of Single;
  PlayVoice: Integer = -1;

{ ---------------------------------------------------------------- recipe text / state }

function SpecText(AId: TSoundId): string;
begin
  with Sounds[AId] do
  begin
    Result := Format('%s|%d|%s|%s|%s', [Preset, Seed, DotF(Dur), DotF(Pitch), DotF(Gain)]);
    if Custom <> nil then Result := Result + '|' + Custom.ToText;
  end;
end;

function Modified(AId: TSoundId): Boolean;
begin
  Result := SpecText(AId) <> Saved[AId];
end;

function ModifiedCount: Integer;
var
  id: TSoundId;
begin
  Result := 0;
  for id := Low(TSoundId) to High(TSoundId) do if Modified(id) then Inc(Result);
end;

procedure MarkAllDirty;
var
  id: TSoundId;
begin
  for id := Low(TSoundId) to High(TSoundId) do Dirty[id] := True;
end;

procedure RememberSaved;
var
  id: TSoundId;
begin
  for id := Low(TSoundId) to High(TSoundId) do
  begin
    Saved[id] := SpecText(id);
    RenderSound(id, SavedBufs[id]);
  end;
end;

procedure DoLoad;
begin
  LoadSounds(SoundsPath);
  RememberSaved;
  MarkAllDirty;
end;

procedure DoSave;
begin
  try
    SaveSounds(SoundsPath);
    RememberSaved;
    SavedAt := FormatDateTime('hh:nn:ss', Now);
    Status('saved ' + SoundsPath + '  (a running game reloads it)');
  except
    on E: Exception do Status('save failed: ' + E.Message);
  end;
end;

{ ---------------------------------------------------------------- audio }

procedure OpenAudio;
var
  spec: TSDL_AudioSpec;
begin
  spec.format := SDL_AUDIO_S16;
  spec.channels := 2;
  spec.freq := SfxRate;
  Stream := SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, @spec, nil, nil);
  if Stream = nil then AudioError := 'no audio device: ' + string(SDL_GetError)
  else SDL_ResumeAudioStreamDevice(Stream);
end;

function StartVoice(const ABuf: TSoundBuf; AGain: Single; ALoop: Boolean; AFirst: Integer = 4): Integer;
var
  i: Integer;
begin
  Result := -1;
  if ABuf.Frames = 0 then Exit;
  for i := AFirst to High(Voices) do
    if not Voices[i].Active then
    begin
      Voices[i].Active := True;
      Voices[i].Loop := ALoop;
      Voices[i].Data := ABuf.Data;
      Voices[i].Frames := ABuf.Frames;
      Voices[i].Pos := 0;
      Voices[i].Gain := AGain;
      Exit(i);
    end;
end;

procedure StopAll;
var
  i: Integer;
begin
  for i := 0 to High(Voices) do Voices[i].Active := False;
  PlayVoice := -1;
  SetLength(Queue, 0);
  LoopAmb := False; LoopNode := False; LoopHole := False;
  if Stream <> nil then SDL_ClearAudioStream(Stream);
end;

procedure PlaySel;
begin
  if (PlayVoice >= 0) then Voices[PlayVoice].Active := False;
  PlayVoice := StartVoice(Bufs[Sel], 1, PreviewLoop or (Sel in SoundLoops));
end;

{ the 3 game loops: voices 1..3 }
procedure SetLoopVoice(AVoice: Integer; AId: TSoundId; AOn: Boolean; AGain: Single);
begin
  if not AOn then
  begin
    Voices[AVoice].Active := False;
    Exit;
  end;
  if not Voices[AVoice].Active or (Pointer(Voices[AVoice].Data) <> Pointer(Bufs[AId].Data)) then
  begin
    Voices[AVoice].Active := Bufs[AId].Frames > 0;
    Voices[AVoice].Loop := True;
    Voices[AVoice].Data := Bufs[AId].Data;
    Voices[AVoice].Frames := Bufs[AId].Frames;
    Voices[AVoice].Pos := 0;
  end;
  Voices[AVoice].Gain := AGain;
end;

procedure PumpAudio;
var
  need, n, i, v, f, idx: Integer;
  x: Single;
begin
  if Stream = nil then Exit;
  need := Round(0.07 * SfxRate) - SDL_GetAudioStreamQueued(Stream) div 4;
  while need > 0 do
  begin
    n := Min(need, 1024);
    if Length(MixF) < 2 * n then begin SetLength(MixF, 2 * n); SetLength(MixS, 2 * n); end;
    FillChar(MixF[0], 2 * n * SizeOf(Single), 0);
    for v := 0 to High(Voices) do
    begin
      if not Voices[v].Active then Continue;
      for f := 0 to n - 1 do
      begin
        if Voices[v].Pos >= Voices[v].Frames then
        begin
          if Voices[v].Loop then Voices[v].Pos := 0
          else
          begin
            Voices[v].Active := False;
            Break;
          end;
        end;
        idx := 2 * Voices[v].Pos;
        MixF[2 * f] := MixF[2 * f] + Voices[v].Data[idx] * Voices[v].Gain;
        MixF[2 * f + 1] := MixF[2 * f + 1] + Voices[v].Data[idx + 1] * Voices[v].Gain;
        Inc(Voices[v].Pos);
      end;
    end;
    for i := 0 to 2 * n - 1 do
    begin
      x := EnsureRange(MixF[i], -1, 1);
      MixS[i] := Round(x * 32000);
    end;
    if UTLines <> nil then FillChar(MixS[0], 2 * n * SizeOf(SmallInt), 0);   { tests are silent }
    SDL_PutAudioStreamData(Stream, @MixS[0], n * 4);
    Dec(need, n);
  end;
end;

{ ---------------------------------------------------------------- render }

procedure RenderSel;
var
  t0: QWord;
  i, c, cols, a, b: Integer;
  mn, mx, s2, v: Double;
begin
  t0 := SDL_GetTicksNS;
  RenderSound(Sel, Bufs[Sel]);
  RenderMs := (SDL_GetTicksNS - t0) / 1e6;
  Dirty[Sel] := False;
  LastRender := NowS;
  { waveform columns + peak / rms }
  cols := 600;
  SetLength(WaveMin, cols);
  SetLength(WaveMax, cols);
  Peak := 0; s2 := 0;
  for c := 0 to cols - 1 do
  begin
    a := Int64(c) * Bufs[Sel].Frames div cols;
    b := Max(a + 1, Int64(c + 1) * Bufs[Sel].Frames div cols);
    mn := 0; mx := 0;
    for i := a to Min(b, Bufs[Sel].Frames) - 1 do
    begin
      v := 0.5 * (Bufs[Sel].Data[2 * i] + Bufs[Sel].Data[2 * i + 1]);
      if v < mn then mn := v;
      if v > mx then mx := v;
    end;
    WaveMin[c] := mn;
    WaveMax[c] := mx;
  end;
  for i := 0 to Bufs[Sel].Frames - 1 do
  begin
    v := 0.5 * (Bufs[Sel].Data[2 * i] + Bufs[Sel].Data[2 * i + 1]);
    Peak := Max(Peak, Abs(v));
    s2 := s2 + v * v;
  end;
  if Bufs[Sel].Frames > 0 then Rms := Sqrt(s2 / Bufs[Sel].Frames) else Rms := 0;
end;

procedure Changed;
begin
  Dirty[Sel] := True;
end;

{ ---------------------------------------------------------------- widgets on fields }

function LinSl(AId: Integer; const AKey, ACap: string; X, Y, W: Single; var AField: Double; AMin, AMax: Double;
  ADigits: Integer = 2; const AUnit: string = ''): Boolean;
var
  v: Double;
begin
  v := AField;
  Result := SliderU(AId, AKey, ACap, FloatToStrF(AField, ffFixed, 8, ADigits) + AUnit, X, Y, W, v, AMin, AMax);
  if Result then
  begin
    AField := v;
    Changed;
  end;
end;

function LogSl(AId: Integer; const AKey, ACap: string; X, Y, W: Single; var AField: Double; AMin, AMax: Double;
  ADigits: Integer = 1; const AUnit: string = ''): Boolean;
var
  v: Double;
begin
  v := EnsureRange(Ln(Max(AMin, AField) / AMin) / Ln(AMax / AMin), 0, 1);
  Result := SliderU(AId, AKey, ACap, FloatToStrF(AField, ffFixed, 8, ADigits) + AUnit, X, Y, W, v, 0, 1);
  if Result then
  begin
    AField := AMin * Power(AMax / AMin, v);
    Changed;
  end;
end;

{ ---------------------------------------------------------------- drawing }

procedure SelectSound(AId: TSoundId);
begin
  if AId = Sel then Exit;
  Sel := AId;
  CurLayer := 0;
  RenderSel;
end;

{ the 5 pickup sounds one after the other, like a combo in the game }
procedure ComboRun;
var
  i: Integer;
begin
  SetLength(Queue, 5);
  for i := 0 to 4 do
  begin
    Queue[i].At := NowS + i * 0.32;
    Queue[i].Id := TSoundId(Ord(snPick0) + i);
  end;
end;

procedure DrawHeader;
var
  x: Single;
  n: Integer;
begin
  GrpBegin('header', 'panel');
  Txt(fkBodyBold, 'PAULI SURFER 2  .  SOUND EDITOR', 20, 12, cOrange);
  n := ModifiedCount;
  Txt(fkTiny, SoundsPath + IfThen(FileExists(SoundsPath), '', '   (new file)') +
    IfThen(n > 0, Format('   .   %d sound(s) modified', [n]), '   .   saved') +
    IfThen(SavedAt <> '', '   .   last save ' + SavedAt, ''), 20, 36, IfThen(n > 0, cGold, cDim));
  GrpEnd;
  x := CWu - 16;
  x := x - 130; if Btn('PLAY GAME', x, 12, 126, 32, False, 'play_game', 'G') then LaunchGame(['--data=' + PauliDataDir]);
  x := x - 120; if Btn('DEFAULTS', x, 12, 116, 32, False, 'defaults') then
  begin
    DefaultSounds;
    MarkAllDirty;
    Status('all sounds back to the built-in recipes (not saved yet)');
  end;
  x := x - 110; if Btn('RELOAD', x, 12, 106, 32, False, 'reload') then
  begin
    DoLoad;
    Status('reloaded ' + SoundsPath);
  end;
  x := x - 120; if Btn('SAVE', x, 12, 116, 32, ModifiedCount > 0, 'save', 'Ctrl+S') then DoSave;
end;

procedure DrawList;
var
  id: TSoundId;
  y, h, rh: Single;
  i: Integer;
begin
  h := CHu - 64 - 40;
  PanelU('sounds', 16, 64, 320, h, 'GAME SOUNDS  (22)');
  GrpBegin('list.sounds', 'list');
  rh := Min(34, (h - 40) / 22);
  y := 92;
  i := 0;
  for id := Low(TSoundId) to High(TSoundId) do
  begin
    if id = Sel then Box(20, y, 312, rh - 2, cOrange, 60)
    else if UI.Inside(U(20), U(y), U(312), U(rh - 2)) then Box(20, y, 312, rh - 2, $FFFFFF, 14);
    AddLayer('row.' + SoundKeys[id], 'row', U(20), U(y), U(312), U(rh - 2));
    Txt(fkSmallBold, SoundKeys[id], 28, y + 2, IfThen(id = Sel, cText, $C8CCD2));
    Txt(fkTiny, SoundInfo[id], 28, y + rh * 0.48, cFaint);
    if id in SoundLoops then Txt(fkTiny, 'LOOP', 326, y + 3, cCyan, alRight);
    if Sounds[id].Custom <> nil then Txt(fkTiny, 'CUSTOM', 326 - IfThen(id in SoundLoops, 34, 0), y + 3, cGold, alRight);
    if Modified(id) then Txt(fkSmallBold, '*', 326, y + rh * 0.45, cGold, alRight);
    if RowHit(20, y, 312, rh - 2) then SelectSound(id);
    y := y + rh;
    Inc(i);
  end;
  GrpEnd;
end;

procedure DrawRecipe;
var
  c, p, i, cat, pre: Integer;
  x0, y: Single;
  hasPreset: Boolean;
begin
  x0 := 348;
  PanelU('recipe', x0, 64, 500, CHu - 104, 'RECIPE');
  GrpBegin('recipe.title', 'text');
  Txt(fkBodyBold, UpperCase(SoundKeys[Sel]), x0 + 14, 30 + 64, cText);
  Txt(fkTiny, SoundInfo[Sel] + IfThen(Sel in SoundLoops, '   (loops in the game)', ''), x0 + 14, 54 + 64, cDim);
  GrpEnd;
  hasPreset := FindPreset(Sounds[Sel].Preset, cat, pre);
  if not hasPreset then begin cat := 0; pre := 0; end;
  { categories }
  Txt(fkTiny, 'CATEGORY  (SFX Studio)', x0 + 14, 146, cFaint);
  GrpBegin('recipe.categories', 'group');
  for c := 0 to SfxCats - 1 do
    if Btn(CatLabels[c], x0 + 10 + (c mod 5) * 97, 162 + (c div 5) * 30, 93, 26, c = cat, 'cat.' + CatIds[c]) then
    begin
      Sounds[Sel].Preset := CatIds[c] + ':' + PresetIds[c, 0];
      Changed;
    end;
  GrpEnd;
  { presets }
  Txt(fkTiny, 'PRESET', x0 + 14, 256, cFaint);
  GrpBegin('recipe.presets', 'group');
  for p := 0 to SfxPresets - 1 do
    if Btn(PresetIds[cat, p] + '  -  ' + PresetDesc[cat, p], x0 + 10, 272 + p * 29, 480, 26, p = pre, 'preset.' + IntToStr(p)) then
    begin
      Sounds[Sel].Preset := CatIds[cat] + ':' + PresetIds[cat, p];
      Changed;
    end;
  GrpEnd;
  { seed }
  i := StepperU('seed', 'SEED  (variation of the preset)', IntToStr(Sounds[Sel].Seed), x0 + 14, 444, 220, 30);
  if i <> 0 then
  begin
    Sounds[Sel].Seed := Max(1, Sounds[Sel].Seed + i);
    Changed;
  end;
  if Btn('RANDOM SEED', x0 + 250, 444, 150, 30, False, 'random_seed', 'R') then
  begin
    Sounds[Sel].Seed := Random(9999) + 1;
    Changed;
  end;
  { length / pitch / volume }
  if Sounds[Sel].Custom <> nil then
    Txt(fkTiny, 'length: set Duration in the design (custom)', x0 + 14, 492, cFaint)
  else
    LinSl(1, 'length', 'LENGTH  (0 = the preset''s own length)', x0 + 14, 488, 470, Sounds[Sel].Dur, 0, 6, 2, ' s');
  LogSl(2, 'pitch', 'PITCH  (x all frequencies)', x0 + 14, 532, 470, Sounds[Sel].Pitch, 0.25, 4, 2, ' x');
  LinSl(3, 'volume', 'VOLUME  in the game mix', x0 + 14, 576, 470, Sounds[Sel].Gain, 0, 1.5, 2);
  { listen }
  y := 630;
  if Btn('PLAY', x0 + 14, y, 150, 34, False, 'play', 'SPACE') then PlaySel;
  if Btn('STOP', x0 + 172, y, 110, 34, False, 'stop', 'Esc') then StopAll;
  Toggle('loop_preview', 'LOOP', x0 + 290, y, 100, 34, PreviewLoop);
  if Btn('PLAY SAVED', x0 + 14, y + 40, 150, 30, False, 'play_saved', 'B') then
  begin
    if PlayVoice >= 0 then Voices[PlayVoice].Active := False;
    PlayVoice := StartVoice(SavedBufs[Sel], 1, False);
  end;
  if Btn('UNDO CHANGES', x0 + 172, y + 40, 150, 30, False, 'undo_sound') then
  begin
    LoadSounds(SoundsPath);
    Status('all unsaved changes dropped');
    MarkAllDirty;
  end;
  { custom design }
  Txt(fkTiny, 'DESIGN', x0 + 14, 718, cFaint);
  if Sounds[Sel].Custom = nil then
  begin
    if Btn('EDIT LAYERS  (make it a custom design)', x0 + 10, 734, 480, 30, False, 'edit_layers', 'E') then
    begin
      SetSoundCustom(Sel, SoundDesign(Sel));
      Changed;
    end;
  end
  else if Btn('BACK TO PRESET  (drop the custom design)', x0 + 10, 734, 480, 30, False, 'back_to_preset') then
  begin
    SetSoundCustom(Sel, nil);
    Changed;
  end;
  { game mix }
  Txt(fkTiny, 'GAME MIX  (game volumes)', x0 + 14, 778, cFaint);
  if Btn('COMBO RUN', x0 + 10, 794, 120, 30, False, 'combo_run', 'C') then ComboRun;
  Toggle('loop_ambient', 'AMBIENT', x0 + 136, 794, 112, 30, LoopAmb);
  Toggle('loop_node', 'NODE', x0 + 254, 794, 100, 30, LoopNode);
  Toggle('loop_hole', 'HOLE', x0 + 360, 794, 100, 30, LoopHole);
end;

procedure DrawWave(X, Y, W, H: Single);
var
  i, n: Integer;
  cx, ym, a, b: Single;
  sec: Double;
begin
  PanelU('wave', X, Y, W, H, 'WAVEFORM');
  AddLayer('view.waveform', 'view', U(X + 14), U(Y + 34), U(W - 28), U(H - 76));
  Box(X + 14, Y + 34, W - 28, H - 76, $000000, 200);
  ym := Y + 34 + (H - 76) / 2;
  Box(X + 14, ym, W - 28, 0.6, $FFFFFF, 40);
  n := Length(WaveMin);
  for i := 0 to n - 1 do
  begin
    cx := X + 14 + (W - 28) * i / Max(1, n);
    a := ym - WaveMax[i] * (H - 76) / 2;
    b := ym - WaveMin[i] * (H - 76) / 2;
    Box(cx, a, Max(0.6, (W - 28) / Max(1, n)), Max(0.6, b - a), cOrange, 200);
  end;
  if (PlayVoice >= 0) and Voices[PlayVoice].Active and (Pointer(Voices[PlayVoice].Data) = Pointer(Bufs[Sel].Data)) then
    Box(X + 14 + (W - 28) * Voices[PlayVoice].Pos / Max(1, Voices[PlayVoice].Frames), Y + 34, 1.2, H - 76, $FFFFFF, 220);
  sec := Bufs[Sel].Frames / SfxRate;
  GrpBegin('wave.info', 'text');
  Txt(fkTiny, Format('%.2f s   .   %d frames   .   peak %.2f   .   rms %.3f   .   render %.1f ms%s',
    [sec, Bufs[Sel].Frames, Peak, Rms, RenderMs, IfThen(Peak * 1 > 0.99, '   .   CLIPS', '')]), X + 14, Y + H - 34,
    IfThen(Peak > 0.99, cRed, cDim));
  GrpEnd;
end;

procedure DrawDesign(X, Y, W: Single);
var
  d: TSfxDef;
  L: PSfxLayer;
  i, k: Integer;
  c1, c2, cw, yy, h: Single;
  t: string;
  gen: TSfxDef;
begin
  h := CHu - 40 - Y;
  PanelU('design', X, Y, W, h, IfThen(Sounds[Sel].Custom <> nil, 'DESIGN  (custom: the full synthesis)', 'DESIGN  (generated by the preset)'));
  d := Sounds[Sel].Custom;
  if d = nil then
  begin
    gen := SoundDesign(Sel);
    try
      GrpBegin('design.summary', 'text');
      yy := Y + 38;
      Txt(fkSmall, Format('%s   %.2f s   gain %.2f   echo %.2f   reverb %.2f', [gen.Name, gen.Duration, gen.Gain,
        gen.EchoMix, gen.ReverbMix]), X + 14, yy, cText);
      yy := yy + 26;
      for k := 0 to SfxLayers - 1 do
        with gen.Layers[k] do
          if Enabled then
          begin
            t := Format('layer %d   %s   %.0f -> %.0f Hz   %s %.0f -> %.0f Hz   A %.3f  H %.2f  D %.2f   gain %.2f',
              [k + 1, SourceNames[Source], Freq * Sounds[Sel].Pitch, FreqEnd * Sounds[Sel].Pitch, FiltNames[Filter],
              Cutoff, CutoffEnd, Attack, Hold, Decay, Gain]);
            Txt(fkTiny, t, X + 14, yy, cDim);
            yy := yy + 20;
          end;
      Txt(fkTiny, 'EDIT LAYERS (E) copies this design so every layer can be changed.', X + 14, yy + 14, cFaint);
      GrpEnd;
    finally
      gen.Free;
    end;
    Exit;
  end;
  cw := (W - 42) / 3;
  { global }
  yy := Y + 36;
  LinSl(10, 'duration', 'Duration', X + 14, yy, cw, d.Duration, 0.02, 8, 2, ' s');
  LinSl(11, 'fade_in', 'Fade in', X + 14 + cw + 7, yy, cw, d.FadeIn, 0, 2, 3, ' s');
  LinSl(12, 'fade_out', 'Fade out', X + 14 + 2 * (cw + 7), yy, cw, d.FadeOut, 0, 3, 3, ' s');
  yy := yy + 42;
  LinSl(13, 'echo_time', 'Echo time', X + 14, yy, cw, d.EchoTime, 0.01, 1, 3, ' s');
  LinSl(14, 'echo_mix', 'Echo mix', X + 14 + cw + 7, yy, cw, d.EchoMix, 0, 1);
  LinSl(15, 'reverb_mix', 'Reverb mix', X + 14 + 2 * (cw + 7), yy, cw, d.ReverbMix, 0, 1);
  { layer tabs }
  yy := yy + 48;
  GrpBegin('design.layers', 'group');
  for k := 0 to SfxLayers - 1 do
    if Btn(IfThen(d.Layers[k].Enabled, 'LAYER ', 'off ') + IntToStr(k + 1), X + 14 + k * ((W - 28) / 6), yy,
      (W - 28) / 6 - 4, 26, k = CurLayer, 'layer.' + IntToStr(k + 1)) then CurLayer := k;
  GrpEnd;
  L := @d.Layers[CurLayer];
  yy := yy + 50;
  cw := (W - 28 - 3 * 8) / 4;
  if Btn(IfThen(L^.Enabled, 'ON', 'OFF'), X + 14, yy, cw, 28, L^.Enabled, 'layer_on') then
  begin
    L^.Enabled := not L^.Enabled;
    Changed;
  end;
  i := StepperU('source', 'Source', SourceNames[L^.Source], X + 14 + (cw + 8), yy, cw, 28);
  if i <> 0 then begin L^.Source := TSource((Ord(L^.Source) + i + Ord(High(TSource)) + 1) mod (Ord(High(TSource)) + 1)); Changed; end;
  i := StepperU('filter', 'Filter', FiltNames[L^.Filter], X + 14 + 2 * (cw + 8), yy, cw, 28);
  if i <> 0 then begin L^.Filter := TFilt((Ord(L^.Filter) + i + Ord(High(TFilt)) + 1) mod (Ord(High(TFilt)) + 1)); Changed; end;
  i := StepperU('spread', 'Partials', Format('%d %s', [L^.Partials, Copy(SpreadNames[L^.Spread], 1, 4)]), X + 14 + 3 * (cw + 8), yy, cw, 28);
  if i <> 0 then
  begin
    L^.Partials := EnsureRange(L^.Partials + i, 1, MaxPartials);
    Changed;
  end;
  { sliders, 2 columns }
  yy := yy + 40;
  cw := (W - 42) / 2;
  c1 := X + 14;
  c2 := X + 28 + cw;
  LogSl(101, 'l_freq', 'Frequency', c1, yy, cw, L^.Freq, 0.5, 16000, 1, ' Hz');
  LogSl(201, 'l_cutoff', 'Cutoff (start)', c2, yy, cw, L^.Cutoff, 20, 20000, 0, ' Hz');
  yy := yy + 40;
  LogSl(102, 'l_freq_end', 'Frequency at end (glide)', c1, yy, cw, L^.FreqEnd, 0.5, 16000, 1, ' Hz');
  LogSl(202, 'l_cutoff_end', 'Cutoff (end, sweep)', c2, yy, cw, L^.CutoffEnd, 20, 20000, 0, ' Hz');
  yy := yy + 40;
  LogSl(103, 'l_curve', 'Glide curve', c1, yy, cw, L^.PitchCurve, 0.1, 10, 2);
  LogSl(203, 'l_q', 'Q / resonance', c2, yy, cw, L^.Q, 0.1, 30, 2);
  yy := yy + 40;
  LinSl(104, 'l_vib_rate', 'Vibrato rate', c1, yy, cw, L^.VibRate, 0, 30, 2, ' Hz');
  LinSl(204, 'l_attack', 'Attack', c2, yy, cw, L^.Attack, 0.0005, 2, 3, ' s');
  yy := yy + 40;
  LinSl(105, 'l_vib_depth', 'Vibrato depth', c1, yy, cw, L^.VibDepth, 0, 0.5, 3);
  LinSl(205, 'l_hold', 'Hold', c2, yy, cw, L^.Hold, 0, 6, 3, ' s');
  yy := yy + 40;
  LogSl(108, 'l_fm_ratio', 'FM ratio', c1, yy, cw, L^.FmRatio, 0.1, 12, 3);
  LinSl(206, 'l_decay', 'Decay (0 = sustain)', c2, yy, cw, L^.Decay, 0, 6, 3, ' s');
  yy := yy + 40;
  LinSl(109, 'l_fm_index', 'FM index (start)', c1, yy, cw, L^.FmIndex, 0, 30, 2);
  LinSl(217, 'l_gain', 'Layer gain', c2, yy, cw, L^.Gain, 0, 1.5);
  yy := yy + 40;
  LinSl(110, 'l_fm_index_end', 'FM index (end)', c1, yy, cw, L^.FmIndexEnd, 0, 30, 2);
  LinSl(218, 'l_pan', 'Pan (-1 L .. +1 R)', c2, yy, cw, L^.Pan, -1, 1);
  yy := yy + 40;
  if yy + 40 < Y + h then
  begin
    LinSl(214, 'l_drive', 'Drive (tanh)', c1, yy, cw, L^.Drive, 0, 1);
    LinSl(207, 'l_delay', 'Start delay', c2, yy, cw, L^.Delay, 0, 6, 3, ' s');
  end;
end;

procedure DrawAll;
var
  x2, w2: Single;
  i: Integer;
begin
  { queued pickups (COMBO RUN) }
  for i := High(Queue) downto 0 do
    if NowS >= Queue[i].At then
    begin
      StartVoice(Bufs[Queue[i].Id], 1, False);
      Delete(Queue, i, 1);
    end;
  { re-render the edited sound (8 per second while dragging) }
  if Dirty[Sel] and (NowS - LastRender > 0.12) then
  begin
    RenderSel;
    if (PlayVoice >= 0) and Voices[PlayVoice].Active and Voices[PlayVoice].Loop then PlaySel;
  end;
  if (LoopAmb or LoopNode or LoopHole) then
  begin
    if Dirty[snAmbient] then RenderSound(snAmbient, Bufs[snAmbient]);
    if Dirty[snNodeLoop] then RenderSound(snNodeLoop, Bufs[snNodeLoop]);
    if Dirty[snBHLoop] then RenderSound(snBHLoop, Bufs[snBHLoop]);
    Dirty[snAmbient] := Dirty[snAmbient] and (Sel = snAmbient);
    Dirty[snNodeLoop] := Dirty[snNodeLoop] and (Sel = snNodeLoop);
    Dirty[snBHLoop] := Dirty[snBHLoop] and (Sel = snBHLoop);
  end;
  for i := 0 to 4 do
    if Dirty[TSoundId(Ord(snPick0) + i)] and (TSoundId(Ord(snPick0) + i) <> Sel) then
    begin
      RenderSound(TSoundId(Ord(snPick0) + i), Bufs[TSoundId(Ord(snPick0) + i)]);
      Dirty[TSoundId(Ord(snPick0) + i)] := False;
    end;
  SetLoopVoice(1, snAmbient, LoopAmb, 1);
  SetLoopVoice(2, snNodeLoop, LoopNode, 0.9);
  SetLoopVoice(3, snBHLoop, LoopHole, 1);

  DrawHeader;
  DrawList;
  DrawRecipe;
  x2 := 860;
  w2 := CWu - x2 - 16;
  DrawWave(x2, 64, w2, 220);
  DrawDesign(x2, 296, w2);
  if AudioError <> '' then Txt(fkTiny, AudioError, CWu - 16, CHu - 30, cRed, alRight);
  PumpAudio;
end;

{ ---------------------------------------------------------------- keys / state / test }

procedure KeyDown(AKey: TSDL_Keycode; AMod: TSDL_Keymod);
var
  id: Integer;
begin
  id := Ord(Sel);
  case AKey of
    SDLK_SPACE: PlaySel;
    SDLK_ESCAPE: StopAll;
    SDLK_UP: SelectSound(TSoundId(Max(0, id - 1)));
    SDLK_DOWN: SelectSound(TSoundId(Min(Ord(High(TSoundId)), id + 1)));
    SDLK_S: if (AMod and SDL_KMOD_CTRL) <> 0 then DoSave;
    SDLK_R: begin Sounds[Sel].Seed := Random(9999) + 1; Changed; end;
    SDLK_B: PlayVoice := StartVoice(SavedBufs[Sel], 1, False);
    SDLK_C: ComboRun;
    SDLK_E: if Sounds[Sel].Custom = nil then begin SetSoundCustom(Sel, SoundDesign(Sel)); Changed; end;
    SDLK_G: LaunchGame(['--data=' + PauliDataDir]);
  end;
end;

procedure DevState(L: TStrings);
var
  i, n: Integer;
begin
  L.Add('#FILE');
  L.Add('sounds file'#9 + SoundsPath);
  L.Add('exists'#9 + BoolToStr(FileExists(SoundsPath), 'yes', 'no (built-in recipes until SAVE)'));
  L.Add('modified sounds'#9 + IntToStr(ModifiedCount));
  L.Add('last save'#9 + IfThen(SavedAt <> '', SavedAt, '-'));
  L.Add('#SOUND  ' + SoundKeys[Sel]);
  L.Add('when'#9 + SoundInfo[Sel]);
  L.Add('preset'#9 + Sounds[Sel].Preset);
  L.Add('seed'#9 + IntToStr(Sounds[Sel].Seed));
  L.Add('length'#9 + IfThen(Sounds[Sel].Dur > 0, DotF(Sounds[Sel].Dur) + ' s', 'preset length'));
  L.Add('pitch / volume'#9 + DotF(Sounds[Sel].Pitch) + ' x  /  ' + DotF(Sounds[Sel].Gain));
  L.Add('custom design'#9 + BoolToStr(Sounds[Sel].Custom <> nil, 'yes (layer ' + IntToStr(CurLayer + 1) + ')', 'no'));
  L.Add('rendered'#9 + Format('%d frames  %.3f s  peak %.3f  rms %.4f  %.1f ms', [Bufs[Sel].Frames,
    Bufs[Sel].Frames / SfxRate, Peak, Rms, RenderMs]));
  L.Add('modified'#9 + BoolToStr(Modified(Sel), 'yes', 'no'));
  L.Add('#AUDIO');
  L.Add('device'#9 + IfThen(Stream <> nil, Format('S16 stereo %d Hz', [SfxRate]), AudioError));
  n := 0;
  for i := 0 to High(Voices) do if Voices[i].Active then Inc(n);
  L.Add('voices playing'#9 + IntToStr(n) + ' / ' + IntToStr(Length(Voices)));
  if Stream <> nil then L.Add('queued'#9 + Format('%.0f ms', [SDL_GetAudioStreamQueued(Stream) / 4 / SfxRate * 1000]));
  L.Add('game loops'#9 + Format('ambient %s  node %s  hole %s', [BoolToStr(LoopAmb, 'on', 'off'), BoolToStr(LoopNode, 'on', 'off'),
    BoolToStr(LoopHole, 'on', 'off')]));
end;

function TestStep(AStep: Integer): Boolean;
var
  r: TSDL_FRect;
  n, i: Integer;
  id: TSoundId;
  f: string;
begin
  Result := True;
  UTWait := 2;
  case AStep of
    0: begin
         n := 0;
         for id := Low(TSoundId) to High(TSoundId) do if FindLayer('row.' + SoundKeys[id], r) then Inc(n);
         UTCheck(n = 22, Format('22 sound rows drawn (%d)', [n]));
         UTCheck(FindLayer('panel.recipe', r) and FindLayer('panel.wave', r) and FindLayer('panel.design', r),
           'panels recipe / wave / design');
         UTCheck(FindLayer('btn.save', r) and (r.x + r.w <= OutW + 0.5), 'SAVE button inside the window');
         UTShot('01_sound_editor');
       end;
    1: UTClick('row.flip');
    2: begin
         UTCheck(Sel = snFlip, 'click on the row selects "flip"');
         UTCheck(Sounds[snFlip].Preset = 'scifi:teleport', 'flip = scifi:teleport (built-in recipe)');
         UTClick('preset.1');
       end;
    3: begin
         UTCheck(Sounds[snFlip].Preset = 'scifi:phaser', 'preset button -> scifi:phaser (' + Sounds[snFlip].Preset + ')');
         UTCheck(Modified(snFlip) and (ModifiedCount = 1), 'flip marked modified (1 sound)');
         UTClick('slider2');
       end;
    4: begin
         UTCheck(Abs(Sounds[snFlip].Pitch - 1) < 0.08, Format('pitch slider centre = 1.0 x (log scale): %.3f', [Sounds[snFlip].Pitch]));
         UTClick('play');
         UTWait := 8;
       end;
    5: begin
         UTCheck((PlayVoice >= 0) and (Bufs[snFlip].Frames > 1000), Format('PLAY starts the rendered sound (%d frames)', [Bufs[snFlip].Frames]));
         UTClick('edit_layers');
       end;
    6: begin
         UTCheck(Sounds[snFlip].Custom <> nil, 'EDIT LAYERS makes a custom design');
         UTShot('02_custom_design');
         UTClick('layer.2');
       end;
    7: begin
         UTCheck(CurLayer = 1, 'layer tab 2');
         UTClick('slider101');
       end;
    8: begin
         UTCheck(Abs(Sounds[snFlip].Custom.Layers[1].Freq - Sqrt(0.5 * 16000)) < 3,
           Format('layer 2 frequency = log centre %.1f Hz', [Sounds[snFlip].Custom.Layers[1].Freq]));
         UTWait := 12;
       end;
    9: begin
         UTCheck(not Dirty[snFlip] and (Bufs[snFlip].Frames > 1000), 'custom design re-rendered');
         UTClick('save');
       end;
    10: begin
         f := SoundsPath;
         UTCheck(FileExists(f) and (ModifiedCount = 0), 'SAVE writes ' + f + ', nothing modified');
         DefaultSounds;
         LoadSounds(f);
         UTCheck((Sounds[snFlip].Custom <> nil) and (Abs(Sounds[snFlip].Custom.Layers[1].Freq - Sqrt(0.5 * 16000)) < 3) and
           (Sounds[snFlip].Preset = 'scifi:phaser'), 'file loads back: custom flip with layer 2 at the new frequency');
         RememberSaved;
         UTClick('back_to_preset');
       end;
    11: begin
         UTCheck(Sounds[snFlip].Custom = nil, 'BACK TO PRESET drops the design');
         UTClick('combo_run');
       end;
    12: begin
         UTCheck(Length(Queue) >= 4, Format('COMBO RUN queues the pickups (%d left)', [Length(Queue)]));
         UTClick('loop_ambient');
         UTWait := 20;
       end;
    13: begin
         UTCheck(LoopAmb and Voices[1].Active, 'AMBIENT loop plays');
         n := 0;
         for i := 0 to High(Voices) do if Voices[i].Active then Inc(n);
         UTCheck(n >= 2, Format('%d voices mixed', [n]));
         UTClick('row.bh_loop');
       end;
    14: begin
         UTCheck(Sel = snBHLoop, 'select bh_loop');
         UTShot('03_loops');
         UTClick('stop');
       end;
    15: begin
         n := 0;
         for i := 0 to High(Voices) do if Voices[i].Active then Inc(n);
         UTCheck((n = 0) and not LoopAmb, 'STOP silences everything');
         SDL_SetWindowSize(Win, 1000, 640);
         UTWait := 10;
       end;
    16: begin
         UTCheck(FindLayer('btn.save', r) and (r.x + r.w <= OutW + 0.5) and FindLayer('panel.design', r) and
           (r.x + r.w <= OutW + 0.5), Format('small window %d x %d: everything inside', [OutW, OutH]));
         UTShot('04_small_window');
       end;
  else
    Result := False;
  end;
end;

procedure Quit;
begin
  if Stream <> nil then
  begin
    SDL_ClearAudioStream(Stream);
    SDL_DestroyAudioStream(Stream);
    Stream := nil;
  end;
end;

var
  d: string;
begin
  Randomize;
  d := ArgValue('data', '');
  if d <> '' then DataDirOverride := d;
  SoundsPath := DataPath(SoundsFileName);
  EdInit('PAULI SURFER 2 - SOUND EDITOR');
  OnKey := @KeyDown;
  OnDevState := @DevState;
  OnTestStep := @TestStep;
  OnQuit := @Quit;
  OpenAudio;
  DoLoad;
  RenderSel;
  EdRun(@DrawAll);
  EdDone;
end.
