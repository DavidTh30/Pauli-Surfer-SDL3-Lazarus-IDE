unit uPauliData;

{ PAULI SURFER 2 - the editable data of the game, shared by the game and the
  three editors (Sound Editor, Level Editor, Effect Editor):

    data\pauli_sounds.ini   the 22 game sounds: SFX Studio preset + seed,
                            length, pitch, volume, or a full custom design
                            (the TSfxDef layers of uSfxEngine)
    data\pauli_levels.ini   the 30 levels (uPauliGame: LoadLevels / SaveLevels)
    data\pauli_fx.ini       the graphic effects: colours, cloud, black holes,
                            quanta, probe, trail, screen flashes

  A missing file or key = the built-in value. The game checks the time stamps
  twice a second and reloads a changed file while it runs (hot reload), so an
  editor's SAVE shows up in a running game at once. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, IniFiles, uSfxEngine, uSfxGen, uOrbital;

const
  SoundsFileName = 'pauli_sounds.ini';
  LevelsFileName = 'pauli_levels.ini';
  FxFileName = 'pauli_fx.ini';

type
  TSoundId = (snPick0, snPick1, snPick2, snPick3, snPick4, snBonus, snFlip, snDenied, snNode, snLow, snTime, snWin,
    snFail, snStart, snClick, snAmbient, snNodeLoop, snSwallow, snHorizon, snEdge, snTidal, snBHLoop);

  TSoundBuf = record
    Data: array of Single;      { interleaved L R }
    Frames: Integer;
  end;

  TSoundSpec = record
    Preset: string;             { SFX Studio 'category:preset' }
    Seed: Integer;
    Dur: Double;                { s, 0 = the preset's own length }
    Pitch: Double;              { x all layer frequencies }
    Gain: Double;               { volume in the game mix }
    Custom: TSfxDef;            { nil = generated from the preset; else the full edited design }
  end;

const
  SoundKeys: array[TSoundId] of string = ('pick0', 'pick1', 'pick2', 'pick3', 'pick4', 'bonus', 'flip', 'denied',
    'node', 'low', 'time', 'win', 'fail', 'start', 'click', 'ambient', 'node_loop', 'swallow', 'horizon', 'edge',
    'tidal', 'bh_loop');
  SoundInfo: array[TSoundId] of string = (
    'quantum collected (no combo)', 'quantum collected, combo 1', 'quantum collected, combo 2',
    'quantum collected, combo 3', 'quantum collected, combo 4+', 'Balmer photon collected',
    'spin flip (SPACE)', 'spin flip refused (spin locked)', 'probe enters a radial node',
    'coherence low warning', '10 s left warning', 'level won', 'level lost', 'level start',
    'menu click', 'LOOP: orbital ambience (always)', 'LOOP: decoherence hiss inside a node',
    'a black hole swallows a quantum', 'event horizon hit (Hawking ejection)', 'EDGE x2 pickup near a hole',
    'tidal warning (pull > top speed)', 'LOOP: black hole rumble (by the pull)');
  SoundLoops = [snAmbient, snNodeLoop, snBHLoop];

var
  Sounds: array[TSoundId] of TSoundSpec;
  SoundsLoaded: string;          { file the sounds came from, '' = built-in }

procedure DefaultSounds;
procedure SetSoundCustom(AId: TSoundId; ADef: TSfxDef);   { takes ownership; nil = back to the preset }
{ the design that is rendered for a sound (a new object: free it) }
function SoundDesign(AId: TSoundId): TSfxDef;
{ renders a sound for the game mixer: design x pitch, x gain, interleaved }
procedure RenderSound(AId: TSoundId; out ABuf: TSoundBuf);
function LoadSounds(const AFile: string): Boolean;
procedure SaveSounds(const AFile: string);

type
  TFxKind = (fkFloat, fkInt, fkColor);
  TFxKey = (
    { colours }
    fxCloudCCW, fxCloudCW, fxCloudSlow,
    fxColCCW, fxColCW, fxColSlow, fxColProbe, fxColPhoton, fxColDanger, fxColDiscHot, fxColDisc, fxColRing,
    fxColHorizonFlash,
    { cloud }
    fxCloudLight, fxCloudSize, fxCloudThick, fxSliceGain, fxNucleus,
    { black hole }
    fxLensRadius, fxLensStrength, fxShadowSize, fxShadowAlpha, fxDiscCount, fxDiscInner, fxDiscWidth, fxDiscSpeed,
    fxDiscDot, fxDiscAlpha, fxRingWidth, fxRingAlpha, fxHaloAlpha, fxCaptureDots, fxCaptureAlpha, fxCaptureSpin,
    fxMealRing,
    { quanta + photons }
    fxQuantumGlow, fxQuantumGlowAlpha, fxQuantumCore, fxQuantumPulse, fxQuantumPulseSpeed, fxQuantumRingAlpha,
    fxPhotonStar, fxPhotonGlowAlpha, fxPhotonPulseSpeed,
    { probe + trail }
    fxProbeGlow, fxProbeGlowAlpha, fxProbeMidAlpha, fxProbeRingAlpha, fxSpinArrow, fxTrailLength, fxTrailAlpha,
    fxTrailWidth,
    { screen flashes + pop-ups }
    fxNodeTint, fxFlipFlash, fxFlipDecay, fxHorizonFlash, fxHorizonDecay, fxPopRing, fxPopWidth, fxPopRise, fxPopLife);

  TFxInfo = record
    Key, Caption, Group: string;
    Kind: TFxKind;
    Def, Lo, Hi: Double;
    Hint: string;
  end;

const
  FxGroups: array[0..5] of string = ('COLOURS', 'CLOUD', 'BLACK HOLE', 'QUANTA', 'PROBE', 'FLASHES');
  MaxTrail = 160;
  FxInfo: array[TFxKey] of TFxInfo = (
    (Key: 'cloud_ccw'; Caption: 'cloud: current CCW'; Group: 'COLOURS'; Kind: fkColor; Def: $FF8C1A; Lo: 0; Hi: $FFFFFF; Hint: 'cloud particles turning counterclockwise'),
    (Key: 'cloud_cw'; Caption: 'cloud: current CW'; Group: 'COLOURS'; Kind: fkColor; Def: $1A40FF; Lo: 0; Hi: $FFFFFF; Hint: 'cloud particles turning clockwise'),
    (Key: 'cloud_slow'; Caption: 'cloud: slow current'; Group: 'COLOURS'; Kind: fkColor; Def: $EBF0FF; Lo: 0; Hi: $FFFFFF; Hint: 'cloud particles where the flow is slow'),
    (Key: 'col_ccw'; Caption: 'quanta: current CCW'; Group: 'COLOURS'; Kind: fkColor; Def: $FF8C1A; Lo: 0; Hi: $FFFFFF; Hint: 'quanta riding a counterclockwise current'),
    (Key: 'col_cw'; Caption: 'quanta: current CW'; Group: 'COLOURS'; Kind: fkColor; Def: $3A6BFF; Lo: 0; Hi: $FFFFFF; Hint: 'quanta riding a clockwise current'),
    (Key: 'col_slow'; Caption: 'quanta: slow current'; Group: 'COLOURS'; Kind: fkColor; Def: $EEF0F6; Lo: 0; Hi: $FFFFFF; Hint: 'quanta where the current is slow, +score pop-ups'),
    (Key: 'col_probe'; Caption: 'probe + trail'; Group: 'COLOURS'; Kind: fkColor; Def: $6FE6FF; Lo: 0; Hi: $FFFFFF; Hint: 'the probe glow and its trail'),
    (Key: 'col_photon'; Caption: 'Balmer photon / gold'; Group: 'COLOURS'; Kind: fkColor; Def: $FFD24A; Lo: 0; Hi: $FFFFFF; Hint: 'bonus photon star, shield, EDGE x2'),
    (Key: 'col_danger'; Caption: 'danger (red)'; Group: 'COLOURS'; Kind: fkColor; Def: $FF3B3B; Lo: 0; Hi: $FFFFFF; Hint: 'capture ring dots, node warning, node tint'),
    (Key: 'col_disc_hot'; Caption: 'accretion disc inner'; Group: 'COLOURS'; Kind: fkColor; Def: $FFE9C2; Lo: 0; Hi: $FFFFFF; Hint: 'hot inner part of the disc'),
    (Key: 'col_disc'; Caption: 'accretion disc outer'; Group: 'COLOURS'; Kind: fkColor; Def: $FF8C1A; Lo: 0; Hi: $FFFFFF; Hint: 'outer part of the disc, meal ring'),
    (Key: 'col_ring'; Caption: 'photon ring'; Group: 'COLOURS'; Kind: fkColor; Def: $FFC870; Lo: 0; Hi: $FFFFFF; Hint: 'bright ring just outside the horizon'),
    (Key: 'col_horizon_flash'; Caption: 'horizon flash'; Group: 'COLOURS'; Kind: fkColor; Def: $FFB060; Lo: 0; Hi: $FFFFFF; Hint: 'full screen flash at the event horizon'),

    (Key: 'cloud_light'; Caption: 'cloud brightness x'; Group: 'CLOUD'; Kind: fkFloat; Def: 1; Lo: 0.1; Hi: 4; Hint: 'light carried by one particle'),
    (Key: 'cloud_size'; Caption: 'particle size x'; Group: 'CLOUD'; Kind: fkFloat; Def: 1; Lo: 0.3; Hi: 4; Hint: 'splat radius of a particle'),
    (Key: 'cloud_thick'; Caption: 'point thickness px'; Group: 'CLOUD'; Kind: fkFloat; Def: 0; Lo: 0; Hi: 4; Hint: 'solid round dots (HydrogenFlow thickness)'),
    (Key: 'slice_gain'; Caption: 'slice view gain'; Group: 'CLOUD'; Kind: fkFloat; Def: 4; Lo: 0.5; Hi: 10; Hint: 'brightness of the z = 0 slice view'),
    (Key: 'nucleus'; Caption: 'nucleus glow x'; Group: 'CLOUD'; Kind: fkFloat; Def: 1; Lo: 0; Hi: 5; Hint: 'red nucleus at the centre'),

    (Key: 'lens_radius'; Caption: 'lens radius (x Rc)'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 3.6; Lo: 1; Hi: 8; Hint: 'how far the lensing distortion reaches'),
    (Key: 'lens_strength'; Caption: 'Einstein radius (x Rh)'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 2.4; Lo: 0; Hi: 6; Hint: 'strength of the light bending'),
    (Key: 'shadow_size'; Caption: 'shadow size (x Rh)'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 1.6; Lo: 1; Hi: 4; Hint: 'soft shadow around the horizon'),
    (Key: 'shadow_alpha'; Caption: 'shadow opacity'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 0.45; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'disc_count'; Caption: 'disc particles'; Group: 'BLACK HOLE'; Kind: fkInt; Def: 60; Lo: 0; Hi: 300; Hint: 'dots of the accretion disc'),
    (Key: 'disc_inner'; Caption: 'disc inner (x Rh)'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 1.35; Lo: 1; Hi: 3; Hint: ''),
    (Key: 'disc_width'; Caption: 'disc width (x Rh)'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 1.4; Lo: 0.1; Hi: 5; Hint: ''),
    (Key: 'disc_speed'; Caption: 'disc spin speed'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 3; Lo: 0; Hi: 12; Hint: 'Kepler: inner dots faster'),
    (Key: 'disc_dot'; Caption: 'disc dot size'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 2.2; Lo: 0.5; Hi: 8; Hint: ''),
    (Key: 'disc_alpha'; Caption: 'disc brightness'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 1; Lo: 0; Hi: 2; Hint: 'Doppler-bright side x this'),
    (Key: 'ring_width'; Caption: 'photon ring width'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 2.5; Lo: 0; Hi: 10; Hint: ''),
    (Key: 'ring_alpha'; Caption: 'photon ring opacity'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 0.95; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'halo_alpha'; Caption: 'outer halo opacity'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 0.25; Lo: 0; Hi: 1; Hint: 'thin white ring at 1.3 Rh'),
    (Key: 'capture_dots'; Caption: 'capture ring dots'; Group: 'BLACK HOLE'; Kind: fkInt; Def: 36; Lo: 0; Hi: 120; Hint: 'dashed ring = point of no return'),
    (Key: 'capture_alpha'; Caption: 'capture ring opacity'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 0.45; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'capture_spin'; Caption: 'capture ring spin'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 0.3; Lo: -3; Hi: 3; Hint: 'rad/s'),
    (Key: 'meal_ring'; Caption: 'meal ring growth (x Rh)'; Group: 'BLACK HOLE'; Kind: fkFloat; Def: 2.5; Lo: 0; Hi: 8; Hint: 'ring when a hole eats a quantum'),

    (Key: 'quantum_glow'; Caption: 'quantum glow size'; Group: 'QUANTA'; Kind: fkFloat; Def: 2; Lo: 0; Hi: 5; Hint: 'x pick radius'),
    (Key: 'quantum_glow_alpha'; Caption: 'quantum glow opacity'; Group: 'QUANTA'; Kind: fkFloat; Def: 0.16; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'quantum_core'; Caption: 'quantum core size'; Group: 'QUANTA'; Kind: fkFloat; Def: 0.9; Lo: 0.2; Hi: 3; Hint: ''),
    (Key: 'quantum_pulse'; Caption: 'quantum pulse depth'; Group: 'QUANTA'; Kind: fkFloat; Def: 0.25; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'quantum_pulse_speed'; Caption: 'quantum pulse speed'; Group: 'QUANTA'; Kind: fkFloat; Def: 5; Lo: 0; Hi: 20; Hint: 'rad/s'),
    (Key: 'quantum_ring_alpha'; Caption: 'quantum ring opacity'; Group: 'QUANTA'; Kind: fkFloat; Def: 0.35; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'photon_star'; Caption: 'photon star size'; Group: 'QUANTA'; Kind: fkFloat; Def: 1.5; Lo: 0.5; Hi: 4; Hint: 'Balmer photon'),
    (Key: 'photon_glow_alpha'; Caption: 'photon glow opacity'; Group: 'QUANTA'; Kind: fkFloat; Def: 0.18; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'photon_pulse_speed'; Caption: 'photon pulse speed'; Group: 'QUANTA'; Kind: fkFloat; Def: 9; Lo: 0; Hi: 30; Hint: 'rad/s'),

    (Key: 'probe_glow'; Caption: 'probe glow size'; Group: 'PROBE'; Kind: fkFloat; Def: 2.6; Lo: 1; Hi: 6; Hint: 'x probe radius'),
    (Key: 'probe_glow_alpha'; Caption: 'probe glow opacity'; Group: 'PROBE'; Kind: fkFloat; Def: 0.12; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'probe_mid_alpha'; Caption: 'probe body opacity'; Group: 'PROBE'; Kind: fkFloat; Def: 0.35; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'probe_ring_alpha'; Caption: 'probe ring opacity'; Group: 'PROBE'; Kind: fkFloat; Def: 0.8; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'spin_arrow'; Caption: 'spin arrow length'; Group: 'PROBE'; Kind: fkFloat; Def: 3.4; Lo: 0; Hi: 8; Hint: 'x probe radius'),
    (Key: 'trail_length'; Caption: 'trail length (frames)'; Group: 'PROBE'; Kind: fkInt; Def: 48; Lo: 0; Hi: MaxTrail; Hint: ''),
    (Key: 'trail_alpha'; Caption: 'trail opacity'; Group: 'PROBE'; Kind: fkFloat; Def: 0.25; Lo: 0; Hi: 1; Hint: ''),
    (Key: 'trail_width'; Caption: 'trail width'; Group: 'PROBE'; Kind: fkFloat; Def: 0.7; Lo: 0.1; Hi: 3; Hint: 'x probe radius'),

    (Key: 'node_tint'; Caption: 'node red tint'; Group: 'FLASHES'; Kind: fkFloat; Def: 40; Lo: 0; Hi: 200; Hint: 'screen tint inside a radial node (alpha)'),
    (Key: 'flip_flash'; Caption: 'spin flip flash'; Group: 'FLASHES'; Kind: fkFloat; Def: 90; Lo: 0; Hi: 255; Hint: 'white flash (alpha)'),
    (Key: 'flip_decay'; Caption: 'flip flash decay /s'; Group: 'FLASHES'; Kind: fkFloat; Def: 2.5; Lo: 0.3; Hi: 10; Hint: ''),
    (Key: 'horizon_flash'; Caption: 'horizon flash'; Group: 'FLASHES'; Kind: fkFloat; Def: 150; Lo: 0; Hi: 255; Hint: 'flash at the event horizon (alpha)'),
    (Key: 'horizon_decay'; Caption: 'horizon flash decay /s'; Group: 'FLASHES'; Kind: fkFloat; Def: 1.5; Lo: 0.3; Hi: 10; Hint: ''),
    (Key: 'pop_ring'; Caption: 'pop-up ring growth'; Group: 'FLASHES'; Kind: fkFloat; Def: 90; Lo: 0; Hi: 300; Hint: 'ring around +score / SPIN UP'),
    (Key: 'pop_width'; Caption: 'pop-up ring width'; Group: 'FLASHES'; Kind: fkFloat; Def: 3; Lo: 0; Hi: 12; Hint: ''),
    (Key: 'pop_rise'; Caption: 'pop-up text rise'; Group: 'FLASHES'; Kind: fkFloat; Def: 50; Lo: 0; Hi: 200; Hint: ''),
    (Key: 'pop_life'; Caption: 'pop-up life x'; Group: 'FLASHES'; Kind: fkFloat; Def: 1; Lo: 0.3; Hi: 4; Hint: ''));

var
  GFX: array[TFxKey] of Double;
  FxLoaded: string;

function FxC(AKey: TFxKey): UInt32; inline;
function FxI(AKey: TFxKey): Integer; inline;
procedure DefaultFx;
function LoadFx(const AFile: string): Boolean;
procedure SaveFx(const AFile: string);
function FindFxKey(const AKey: string; out K: TFxKey): Boolean;
{ cloud colours -> uOrbital.FlowCCW / FlowCW / FlowSlow (then TOrbital.Recolour) }
procedure ApplyCloudColours;
function FxValueText(AKey: TFxKey): string;

{ files }
var
  DataDirOverride: string;               { --data=DIR (tests, other sets) }

function PauliDataDir: string;           { <exe folder>\data\ or DataDirOverride }
function DataPath(const AName: string): string;
function FileStamp(const AFile: string): Int64;   { -1 = missing }
function DotF(X: Double; ADigits: Integer = 4): string;
function DotR(const S: string; ADef: Double): Double;

implementation

var
  DotFS: TFormatSettings;

function DotF(X: Double; ADigits: Integer): string;
begin
  Result := FloatToStrF(X, ffGeneral, ADigits + 2, 0, DotFS);
end;

function DotR(const S: string; ADef: Double): Double;
begin
  Result := StrToFloatDef(Trim(S), ADef, DotFS);
end;

function PauliDataDir: string;
begin
  if DataDirOverride <> '' then Exit(IncludeTrailingPathDelimiter(ExpandFileName(DataDirOverride)));
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)) + 'data');
end;

function DataPath(const AName: string): string;
begin
  Result := PauliDataDir + AName;
end;

function FileStamp(const AFile: string): Int64;
var
  sr: TSearchRec;
begin
  Result := -1;
  if FindFirst(AFile, faAnyFile, sr) = 0 then
  begin
    Result := Int64(sr.Time) * 1000003 + sr.Size;
    FindClose(sr);
  end;
end;

{ ---------------------------------------------------------------- sounds }

procedure Spec(AId: TSoundId; const APreset: string; ASeed: Integer; ADur, APitch, AGain: Double);
begin
  Sounds[AId].Preset := APreset;
  Sounds[AId].Seed := ASeed;
  Sounds[AId].Dur := ADur;
  Sounds[AId].Pitch := APitch;
  Sounds[AId].Gain := AGain;
  FreeAndNil(Sounds[AId].Custom);
end;

procedure DefaultSounds;
begin
  Spec(snPick0, 'flick:coin_flip', 3, 0.35, 1.0, 0.55);
  Spec(snPick1, 'flick:coin_flip', 3, 0.35, 1.12, 0.55);
  Spec(snPick2, 'flick:coin_flip', 3, 0.35, 1.26, 0.55);
  Spec(snPick3, 'flick:coin_flip', 3, 0.35, 1.41, 0.55);
  Spec(snPick4, 'flick:coin_flip', 3, 0.35, 1.59, 0.55);
  Spec(snBonus, 'scifi:power_up', 2, 0.6, 1.0, 0.5);
  Spec(snFlip, 'scifi:teleport', 4, 0.55, 1.0, 0.5);
  Spec(snDenied, 'warning:error_buzz', 1, 0.35, 1.0, 0.3);
  Spec(snNode, 'atom:geiger', 5, 0.35, 1.0, 0.6);
  Spec(snLow, 'warning:low_battery', 1, 0, 1.0, 0.45);
  Spec(snTime, 'warning:warn_beep', 1, 0, 1.0, 0.35);
  Spec(snWin, 'orbital:balmer_series', 1, 2.4, 1.0, 0.6);
  Spec(snFail, 'robot:shutdown', 1, 1.6, 1.0, 0.55);
  Spec(snStart, 'orbital:quantum_jump', 1, 0, 1.0, 0.5);
  Spec(snClick, 'click:ui_tick', 1, 0, 1.0, 0.35);
  Spec(snAmbient, 'orbital:orbital_6p', 1, 0, 1.0, 0.18);
  Spec(snNodeLoop, 'atom:electron_cloud', 2, 0, 1.0, 0.5);
  Spec(snSwallow, 'scifi:laser', 3, 0.5, 0.35, 0.55);
  Spec(snHorizon, 'breakdown:power_down', 2, 1.3, 1.0, 0.7);
  Spec(snEdge, 'scifi:power_up', 5, 0.45, 1.4, 0.45);
  Spec(snTidal, 'alarm:nuclear_alert', 1, 0.7, 0.8, 0.35);
  Spec(snBHLoop, 'atom:nucleus', 3, 0, 0.6, 0.9);
  SoundsLoaded := '';
end;

procedure SetSoundCustom(AId: TSoundId; ADef: TSfxDef);
begin
  if Sounds[AId].Custom = ADef then Exit;
  FreeAndNil(Sounds[AId].Custom);
  Sounds[AId].Custom := ADef;
end;

function SoundDesign(AId: TSoundId): TSfxDef;
var
  c, p: Integer;
begin
  with Sounds[AId] do
  begin
    if Custom <> nil then Exit(Custom.Clone);
    if not FindPreset(Preset, c, p) then begin c := 0; p := 0; end;
    Result := GenerateSfx(c, p, Seed);
    if Dur > 0 then
    begin
      Result.Duration := Dur;
      Result.FadeOut := Min(0.08, Dur * 0.3);
    end;
    if Result.Loop then Result.FadeOut := 0.02;
  end;
end;

procedure RenderSound(AId: TSoundId; out ABuf: TSoundBuf);
var
  d: TSfxDef;
  L, R: TSingleArray;
  inf: TRenderInfo;
  i, k: Integer;
  g: Single;
begin
  ABuf.Frames := 0;
  ABuf.Data := nil;
  d := SoundDesign(AId);
  try
    for k := 0 to SfxLayers - 1 do
    begin
      d.Layers[k].Freq := d.Layers[k].Freq * Sounds[AId].Pitch;
      d.Layers[k].FreqEnd := d.Layers[k].FreqEnd * Sounds[AId].Pitch;
    end;
    inf := RenderSfx(d, L, R);
    g := Sounds[AId].Gain;
    ABuf.Frames := inf.Frames;
    SetLength(ABuf.Data, inf.Frames * 2);
    for i := 0 to inf.Frames - 1 do
    begin
      ABuf.Data[2 * i] := L[i] * g;
      ABuf.Data[2 * i + 1] := R[i] * g;
    end;
  finally
    d.Free;
  end;
end;

function LoadSounds(const AFile: string): Boolean;
var
  ini: TMemIniFile;
  id: TSoundId;
  sec: string;
  d: TSfxDef;
begin
  Result := False;
  DefaultSounds;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      for id := Low(TSoundId) to High(TSoundId) do
      begin
        sec := 'sound.' + SoundKeys[id];
        if not ini.SectionExists(sec) then Continue;
        with Sounds[id] do
        begin
          Preset := ini.ReadString(sec, 'preset', Preset);
          Seed := ini.ReadInteger(sec, 'seed', Seed);
          Dur := EnsureRange(DotR(ini.ReadString(sec, 'length', ''), Dur), 0, 30);
          Pitch := EnsureRange(DotR(ini.ReadString(sec, 'pitch', ''), Pitch), 0.1, 8);
          Gain := EnsureRange(DotR(ini.ReadString(sec, 'volume', ''), Gain), 0, 2);
        end;
        if ini.ReadBool(sec, 'custom', False) and ini.SectionExists(sec + '.design') then
        begin
          d := TSfxDef.Create;
          d.LoadFrom(ini, sec + '.design');
          SetSoundCustom(id, d);
        end;
      end;
      SoundsLoaded := AFile;
      Result := True;
    finally
      ini.Free;
    end;
  except
    DefaultSounds;
  end;
end;

procedure SaveSounds(const AFile: string);
var
  ini: TMemIniFile;
  id: TSoundId;
  sec: string;
begin
  ForceDirectories(ExtractFilePath(AFile));
  if FileExists(AFile) then DeleteFile(AFile);
  ini := TMemIniFile.Create(AFile);
  try
    ini.WriteString('info', 'about', 'PAULI SURFER 2 sounds (Sound Editor). preset = SFX Studio category:preset.');
    for id := Low(TSoundId) to High(TSoundId) do
      with Sounds[id] do
      begin
        sec := 'sound.' + SoundKeys[id];
        ini.WriteString(sec, 'when', SoundInfo[id]);
        ini.WriteString(sec, 'preset', Preset);
        ini.WriteInteger(sec, 'seed', Seed);
        ini.WriteString(sec, 'length', DotF(Dur));
        ini.WriteString(sec, 'pitch', DotF(Pitch));
        ini.WriteString(sec, 'volume', DotF(Gain));
        ini.WriteBool(sec, 'custom', Custom <> nil);
        if Custom <> nil then Custom.SaveTo(ini, sec + '.design');
      end;
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

{ ---------------------------------------------------------------- effects }

function FxC(AKey: TFxKey): UInt32;
begin
  Result := UInt32(Round(GFX[AKey])) and $FFFFFF;
end;

function FxI(AKey: TFxKey): Integer;
begin
  Result := Round(GFX[AKey]);
end;

procedure DefaultFx;
var
  k: TFxKey;
begin
  for k := Low(TFxKey) to High(TFxKey) do GFX[k] := FxInfo[k].Def;
  FxLoaded := '';
end;

procedure ApplyCloudColours;

  function RGB(AKey: TFxKey; const AExact: TRGB): TRGB;
  var
    c: UInt32;
  begin
    { the default keeps the exact floats of uOrbital }
    if FxC(AKey) = UInt32(Round(FxInfo[AKey].Def)) then Exit(AExact);
    c := FxC(AKey);
    Result.R := ((c shr 16) and $FF) / 255;
    Result.G := ((c shr 8) and $FF) / 255;
    Result.B := (c and $FF) / 255;
  end;

const
  ExactCCW: TRGB = (R: 1.0; G: 0.55; B: 0.10);
  ExactCW: TRGB = (R: 0.10; G: 0.25; B: 1.0);
  ExactSlow: TRGB = (R: 0.92; G: 0.94; B: 1.0);
begin
  FlowCCW := RGB(fxCloudCCW, ExactCCW);
  FlowCW := RGB(fxCloudCW, ExactCW);
  FlowSlow := RGB(fxCloudSlow, ExactSlow);
end;

function FindFxKey(const AKey: string; out K: TFxKey): Boolean;
var
  i: TFxKey;
begin
  for i := Low(TFxKey) to High(TFxKey) do
    if SameText(FxInfo[i].Key, AKey) then
    begin
      K := i;
      Exit(True);
    end;
  K := Low(TFxKey);
  Result := False;
end;

function FxValueText(AKey: TFxKey): string;
begin
  case FxInfo[AKey].Kind of
    fkColor: Result := '#' + IntToHex(FxC(AKey), 6);
    fkInt: Result := IntToStr(FxI(AKey));
  else
    Result := FloatToStrF(GFX[AKey], ffFixed, 8, 2, DotFS);
  end;
end;

function LoadFx(const AFile: string): Boolean;
var
  ini: TMemIniFile;
  k: TFxKey;
  s: string;
  v: Int64;
begin
  Result := False;
  DefaultFx;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      for k := Low(TFxKey) to High(TFxKey) do
      begin
        s := Trim(ini.ReadString(FxInfo[k].Group, FxInfo[k].Key, ''));
        if s = '' then Continue;
        if FxInfo[k].Kind = fkColor then
        begin
          if s[1] = '#' then Delete(s, 1, 1);
          if TryStrToInt64('$' + s, v) then GFX[k] := v and $FFFFFF;
        end
        else
          GFX[k] := EnsureRange(DotR(s, GFX[k]), FxInfo[k].Lo, FxInfo[k].Hi);
        if FxInfo[k].Kind = fkInt then GFX[k] := Round(GFX[k]);
      end;
      FxLoaded := AFile;
      Result := True;
    finally
      ini.Free;
    end;
  except
    DefaultFx;
  end;
end;

procedure SaveFx(const AFile: string);
var
  ini: TMemIniFile;
  k: TFxKey;
begin
  ForceDirectories(ExtractFilePath(AFile));
  if FileExists(AFile) then DeleteFile(AFile);
  ini := TMemIniFile.Create(AFile);
  try
    ini.WriteString('info', 'about', 'PAULI SURFER 2 graphic effects (Effect Editor). Colours #RRGGBB.');
    for k := Low(TFxKey) to High(TFxKey) do
      if FxInfo[k].Kind = fkFloat then ini.WriteString(FxInfo[k].Group, FxInfo[k].Key, DotF(GFX[k]))
      else ini.WriteString(FxInfo[k].Group, FxInfo[k].Key, FxValueText(k));
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

initialization
  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  DefaultSounds;
  DefaultFx;

finalization
  DefaultSounds;   { frees the custom designs }
end.
