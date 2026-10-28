unit uPauliGame;

{ PAULI SURFER - game logic (no rendering, no SDL calls: testable headless).

  The probe moves in the equatorial plane z = 0 of a hydrogen eigenstate.
  Its velocity = the Pauli probability current of the orbital (same omega as
  the particles of the cloud, uOrbital.FieldAt) + the player's own thrust:
    omega = m/s^2 - (sigma/2s) d ln rho/ds      (orange > 0 CCW, blue < 0 CW)
  Quanta ride the current with their cloud particle (sampled from |psi|^2).
  Radial nodes (r^2 R^2 ~ 0) drain coherence; flipping the spin (sigma -> -sigma)
  changes the magnetisation current, so the bands of the flow change.
  Collect Target quanta before the time runs out.

  VERSION 2 - black holes (mode BLACK HOLE / SINGULARITY):
    pull      a 2D sink velocity v = vmax Rc/d exp(-((d-Rc)/3Rc)^2) towards the
              hole; at the capture radius Rc it equals the probe's top speed,
              so inside Rc there is no escape
    horizon   d < Rh: coherence -35 % (-50 %), the probe is ejected to the far
              side of the orbital ("Hawking ejection", 2 s immune); coherence 0
              = SPAGHETTIFIED
    drift     the holes orbit with the local current (35 % / 60 %), so a spin
              flip turns them round as well
    food      a hole swallows quanta that come near; SINGULARITY holes grow
    edge      a quantum collected within 2.5 Rc of a hole scores x2 }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, StrUtils, IniFiles, uOrbital;

const
  LevelCount = 30;                  { 5 worlds x 6 levels }
  WorldCount = 5;
  LevelsPerWorld = 6;
  AttractLevel = 5;                 { the title screen shows level 6 (6p, the reference picture) }
  WorldNames: array[0..WorldCount - 1] of string = ('GROUND RULES', 'MIRROR CURRENTS', 'SPIN LOCK', 'RYDBERG',
    'SINGULARITY TRIALS');
  MaxQuanta = 8;
  MaxBlackHoles = 6;

type
  TGameEvent = (geNone, geStart, gePickup, geBonus, geFlip, geFlipDenied, geNodeEnter, geLowCoherence,
    geWin, geFail, geTimeWarn, geSwallow, geHorizon, geEdgeBonus, geTidal);

  TGameMode = (gmClassic, gmBlackHole, gmSingularity);

  TBlackHole = record
    S, Phi: Double;        { plane position (polar) }
    Rc, Rh: Double;        { capture radius (no escape) and event horizon, a.u. }
    Eaten: Integer;
    Meal: Double;          { seconds since the last swallowed quantum (glow) }
  end;

  TGameState = (gsPlaying, gsWon, gsLost);

  TLevelDef = record
    N, L, M: Integer;
    Title, Tip: string;
    Target, Quanta: Integer;
    TimeSec: Double;
    World: Integer;                 { 0 .. WorldCount - 1 }
    BH: Integer;                    { black holes in BLACK HOLE mode (SINGULARITY: more) }
    { rules }
    FlowMul: Double;                { current speed x (calm < 1 < turbo) }
    PhotonMul: Double;              { time between Balmer photons x (< 1 = photon rush) }
    DrainMul: Double;               { node drain x (> 1 = node storm) }
    NoFlip: Boolean;                { spin locked }
    StartSpin: Integer;             { +1 / -1 }
    Rule: string;                   { short text of the rules, '' = standard (MakeRuleText) }
    Badge: string;                  { own label in front of the rules (TIME ATTACK, MARATHON ...) }
  end;

  TQuantum = record
    Alive, Bonus: Boolean;
    Idx: Integer;          { cloud particle it rides with }
    S, Phi: Double;        { plane position (polar) }
    Life, Age: Double;
  end;

  { every tunable number of the game in one place (developer window: live sliders) }
  TGameParams = record
    FlowScale: Double;        { game flow = x HydrogenFlow display speed }
    MaxFlowSpeed: Double;     { RView/s: cap of the current for the probe (jets at nodes) }
    MaxQuantumSpeed: Double;  { RView/s: quanta are not spawned faster than this }
    MaxSelfSpeed: Double;     { RView/s: probe top speed }
    Accel: Double;            { RView/s^2: thrust }
    Drag: Double;             { 1/s }
    NodeProb: Double;         { r^2 R^2 / band peak below this = radial node }
    DrainNode: Double;        { coherence/s inside a node }
    Recover: Double;          { coherence/s in dense regions }
    ComboWindow: Double;      { s }
    FlipCooldown: Double;     { s }
    BonusEvery: Double;       { s between Balmer photons }
    BonusLife: Double;        { s a photon lives }
    BHRc: array[TGameMode] of Double;     { capture radius, RView }
    BHRcMax: Double;          { RView: SINGULARITY growth limit }
    BHGrow: Double;           { Rc factor per swallowed quantum (SINGULARITY) }
    BHHorizon: Double;        { Rh / Rc }
    BHDrift: array[TGameMode] of Double;  { hole drift / local current }
    BHHit: array[TGameMode] of Double;    { coherence lost at the horizon }
    BHMaxSink: Double;        { RView/s: cap of the pull }
    ImmuneTime: Double;       { s after a Hawking ejection }
    EdgeFactor: Double;       { EDGE x2 radius in Rc }
  end;

  TPauliGame = class
  private
    FEvents: array[0..63] of TGameEvent;
    FHead, FTail: Integer;
    FRng: UInt32;
    FInNode, FLowWarned, FTimeWarned: Boolean;
    FBotFlipT: Double;
    FBuiltLevel, FBuiltPoints: Integer;
    FBuiltSeed: Cardinal;
    FBuiltKey: string;              { n l m the cloud was sampled for (levels can change at run time) }
    FTidalWarned: Boolean;
    procedure Emit(E: TGameEvent);
    function Rnd: Double;
    function FlowK: Double;         { GP.FlowScale x the level's FlowMul }
    procedure SpawnQuantum(ABonus: Boolean);
    procedure PlaceBlackHoles;
    procedure Eject(AFrom: Integer);
  public
    RingPeak: array of Double;        { max of r^2 R^2 inside each band between radial nodes }
    Level: Integer;
    Def: TLevelDef;
    Orb: array[0..1] of TOrbital;     { [0] spin up sigma = +1, [1] spin down sigma = -1 }
    Spin: Integer;                    { +1 / -1 }
    SimTime: Double;                  { flow time: the cloud is drawn at Phi0 + W * SimTime }
    PX, PY, VX, VY: Double;           { probe, a.u., plane z = 0 }
    FlowVX, FlowVY: Double;           { current at the probe (a.u./s) }
    Coherence: Double;                { 0..1 }
    Score, Collected, Combo, BestCombo, Flips, Bonuses, NodeCrossings: Integer;
    ComboT, TimeLeft, Elapsed, FlipCool, BonusT: Double;
    ProbeProb, ProbeOmega: Double;    { r^2 R^2 (1 = max), display omega }
    ProbeRing: Integer;               { radial nodes inside the probe radius }
    Quanta: array[0..MaxQuanta - 1] of TQuantum;
    State: TGameState;
    Points: Integer;                  { particles per orbital }
    RView: Double;
    { version 2: black holes }
    Mode: TGameMode;
    BH: array[0..MaxBlackHoles - 1] of TBlackHole;
    BHCount: Integer;
    Immune: Double;                   { seconds left after a Hawking ejection }
    Tidal: Double;                    { pull at the probe / top speed (>= 1: no escape) }
    Swallowed, HorizonHits, EdgeBonuses: Integer;
    LostToBH: Boolean;
    { sink velocity of all holes at (X, Y), a.u./s }
    procedure SinkAt(X, Y: Double; out SX_, SY_: Double);
    { game-plane current at radius ASv for spin ASpin: display omega x FlowScale, capped (rad/s) }
    function OmegaAt(ASv: Double; ASpin: Integer): Double;
    function BHPos(K: Integer; out X, Y: Double): Boolean;
    function NearBH(X, Y, AFactor: Double): Boolean;
    constructor Create;
    destructor Destroy; override;
    function Active: TOrbital;
    { ASeed samples the cloud (cached: same level + points + seed = no rebuild),
      ARunSeed (0 = ASeed) drives the quanta }
    procedure StartLevel(ALevel, APoints: Integer; ASeed: Cardinal; ARunSeed: Cardinal = 0);
    { AX, AY = thrust direction in the plane (|a| <= 1); AFlip = spin flip request }
    procedure Update(ADt, AX, AY: Double; AFlip: Boolean);
    function PopEvent: TGameEvent;
    function Stars: Integer;
    function StarScore(AStars: Integer): Integer;
    function RingDirection: string;
    { robot player for tests / attract mode: thrust + flip decision }
    procedure BotInput(out AX, AY: Double; out AFlip: Boolean);
    { constants in RView units }
    function ProbeRadius: Double;
    function PickRadius: Double;
    { band index (radial nodes inside s) and r^2 R^2 relative to the peak of that band }
    function RingAt(ASv: Double): Integer;
    function LocalProb(ASv: Double): Double;
  end;

{ the level table: LevelTable (built-in levels, or pauli_levels.ini when loaded) }
function LevelDef(ALevel: Integer): TLevelDef;
{ the levels as shipped with the game (the code) }
function BuiltinLevel(ALevel: Integer): TLevelDef;
procedure ResetLevels;
{ pauli_levels.ini: [level1] .. [level30]; missing keys keep the built-in value }
function LoadLevels(const AFile: string): Boolean;
procedure SaveLevels(const AFile: string);
procedure WriteLevel(AIni: TCustomIniFile; ALevel: Integer; const D: TLevelDef);
function ReadLevel(AIni: TCustomIniFile; ALevel: Integer; const ADefault: TLevelDef): TLevelDef;
{ Rule := Badge + the rule words of the flags (SPIN LOCKED, TURBO, ...) }
procedure MakeRuleText(var D: TLevelDef);
{ '' = playable; else why not (quantum numbers, ranges, no density in z = 0) }
function CheckLevel(const D: TLevelDef): string;
function OrbitalName(N, L: Integer): string;
function BlackHolesFor(AMode: TGameMode; ALevel: Integer): Integer;
function DefaultGameParams: TGameParams;

var
  GP: TGameParams;                  { the live parameters (= DefaultGameParams at start) }
  LevelTable: array[0..LevelCount - 1] of TLevelDef;
  LevelsFile: string;               { file the table was loaded from, '' = built-in }

const
  ModeNames: array[TGameMode] of string = ('CLASSIC', 'BLACK HOLE', 'SINGULARITY');
  ModeIds: array[TGameMode] of string = ('classic', 'blackhole', 'singularity');

implementation

function DefaultGameParams: TGameParams;
begin
  with Result do
  begin
    FlowScale := 0.5;
    MaxFlowSpeed := 0.8;
    MaxQuantumSpeed := 0.45;
    MaxSelfSpeed := 0.34;
    Accel := 1.6;
    Drag := 2.2;
    NodeProb := 0.035;
    DrainNode := 0.30;
    Recover := 0.05;
    ComboWindow := 4.0;
    FlipCooldown := 1.0;
    BonusEvery := 12.0;
    BonusLife := 6.0;
    BHRc[gmClassic] := 0; BHRc[gmBlackHole] := 0.075; BHRc[gmSingularity] := 0.09;
    BHRcMax := 0.14;
    BHGrow := 1.08;
    BHHorizon := 0.45;
    BHDrift[gmClassic] := 0; BHDrift[gmBlackHole] := 0.35; BHDrift[gmSingularity] := 0.6;
    BHHit[gmClassic] := 0; BHHit[gmBlackHole] := 0.35; BHHit[gmSingularity] := 0.5;
    BHMaxSink := 1.2;
    ImmuneTime := 2.0;
    EdgeFactor := 2.5;
  end;
end;

function BlackHolesFor(AMode: TGameMode; ALevel: Integer): Integer;
var
  b: Integer;
begin
  b := LevelDef(ALevel).BH;
  case AMode of
    gmClassic: Result := 0;
    gmBlackHole: Result := b;
  else
    Result := Min(MaxBlackHoles, b + 1 + b div 3);
  end;
end;

function BuiltinLevel(ALevel: Integer): TLevelDef;

  procedure Lv(AN, AL, AM, ATarget: Integer; ATime: Double; ABH: Integer; const ATitle, ATip: string);
  begin
    Result.N := AN; Result.L := AL; Result.M := AM;
    Result.Target := ATarget; Result.TimeSec := ATime; Result.BH := ABH;
    Result.Title := ATitle; Result.Tip := ATip;
  end;

  procedure Turbo(AMul: Double); begin Result.FlowMul := AMul; end;
  procedure Rush; begin Result.PhotonMul := 0.35; end;
  procedure Storm; begin Result.DrainMul := 1.8; end;
  procedure Lock(ASpin: Integer); begin Result.NoFlip := True; Result.StartSpin := ASpin; end;

begin
  Result.N := 2; Result.L := 1; Result.M := 1;
  Result.Target := 10; Result.TimeSec := 80; Result.Quanta := 6; Result.BH := 1;
  Result.FlowMul := 1; Result.PhotonMul := 1; Result.DrainMul := 1; Result.NoFlip := False; Result.StartSpin := 1;
  Result.Title := ''; Result.Tip := ''; Result.Rule := ''; Result.Badge := '';
  ALevel := EnsureRange(ALevel, 0, LevelCount - 1);
  Result.World := ALevel div LevelsPerWorld;
  case ALevel of
    { WORLD 1  GROUND RULES (version 2.0 levels) }
    0: Lv(2, 1, 1, 10, 80, 1, 'FIRST CURRENT', 'm = +1: the probability current circulates around z. Ride it, or thrust against it.');
    1: Lv(3, 1, 1, 12, 80, 1, 'ONE RADIAL NODE', '|psi|^2 = 0 on the node ring: cross it fast, coherence drains there.');
    2: Lv(3, 2, 2, 14, 80, 2, 'DOUBLE TWIST', 'm = +2 doubles the orbital current m/s^2: the inner region spins fast.');
    3: Lv(4, 3, 3, 14, 80, 2, 'F-RING', 'l = m = 3: one wide ring. Flip the spin to change where the flow is slow (white).');
    4: Lv(5, 0, 0, 16, 80, 3, 'SPIN ONLY', 'm = 0: no orbital current at all - only the spin current. A spin flip reverses everything.');
    5: begin
         Lv(6, 1, 1, 20, 95, 3, 'PAULI CURRENT 6p', 'n = 6, l = 1, m = +1: four radial nodes, five bands. Orange CCW, blue CW, white slow.');
         Result.Quanta := 7;
       end;
    { WORLD 2  MIRROR CURRENTS }
    6: Lv(2, 1, -1, 10, 80, 1, 'MIRROR', 'm = -1: the same cloud, the current turns the other way (clockwise).');
    7: Lv(3, 2, -2, 12, 80, 2, 'COUNTER TWIST', 'm = -2: a fast clockwise core. Your reflexes from world 1 are now wrong.');
    8: Lv(3, 2, 0, 12, 80, 1, 'STILL WATER', 'm = 0, l = 2: angular nodes above and below the plane, only the spin current flows.');
    9: begin
         Lv(4, 2, -2, 14, 80, 2, 'TURBO 4d', '4d m = -2 with the current at 1.6 x: plan the path, the flow does most of the work.');
         Turbo(1.6);
       end;
    10: begin
          Lv(4, 3, -1, 14, 70, 2, 'CALM 4f', '4f m = -1 at 0.6 x speed: the current barely helps - you have to fly.');
          Turbo(0.6);
        end;
    11: begin
          Lv(5, 2, 2, 18, 85, 3, 'PHOTON RUSH', '5d m = +2: Balmer photons every 4 s. Gold is worth 500.');
          Rush;
        end;
    { WORLD 3  SPIN LOCK }
    12: begin
          Lv(3, 1, 1, 12, 80, 1, 'LOCKED UP', 'The spin is locked UP: no flips. Learn the bands you are given.');
          Lock(1);
        end;
    13: begin
          Lv(4, 1, 1, 12, 85, 2, 'LOCKED DOWN', '4p with the spin locked DOWN: the magnetisation current fights the orbital one.');
          Lock(-1);
        end;
    14: begin
          Lv(5, 3, -3, 14, 85, 2, 'F-LOCK', '5f m = -3, spin locked UP: one direction everywhere - use the slow (white) edges.');
          Lock(1);
        end;
    15: begin
          Lv(5, 0, 0, 14, 85, 2, 'FROZEN SPIN', '5s, spin locked DOWN: the spin-only current never reverses this time.');
          Lock(-1);
        end;
    16: begin
          Lv(6, 2, -2, 16, 90, 2, 'NODE STORM', '6d, spin locked UP, nodes drain coherence 1.8 x faster.');
          Lock(1); Storm;
        end;
    17: begin
          Lv(6, 3, 1, 18, 95, 3, 'LOCK 6f', '6f m = +1, spin locked UP: two radial nodes, angular nodes off the plane.');
          Lock(1);
        end;
    { WORLD 4  RYDBERG }
    18: Lv(7, 0, 0, 16, 95, 2, 'RYDBERG 7s', '7s: six radial nodes, seven thin bands, spin current only.');
    19: Lv(7, 1, -1, 18, 100, 2, 'RYDBERG 7p', '7p m = -1: five nodes, clockwise bands.');
    20: begin
          Lv(7, 2, 2, 14, 60, 3, 'TIME ATTACK', '7d m = +2 in 60 seconds.');
          Result.Badge := 'TIME ATTACK';
        end;
    21: Lv(8, 1, 1, 18, 105, 3, '8p', '8p m = +1: six radial nodes. The outer band is huge and slow.');
    22: begin
          Lv(8, 4, -4, 18, 100, 3, 'TURBO 8g', '8g m = -4 at 1.4 x: a wide fast clockwise ring.');
          Turbo(1.4);
        end;
    23: begin
          Lv(9, 1, 1, 26, 140, 3, 'MARATHON 9p', '9p: seven radial nodes, 26 quanta. Keep your coherence for the long run.');
          Result.Quanta := 7;
          Result.Badge := 'MARATHON';
        end;
    { WORLD 5  SINGULARITY TRIALS }
    24: begin
          Lv(4, 3, 3, 16, 80, 3, 'STORM RUSH', '4f m = +3: node storm and photon rush together.');
          Storm; Rush;
        end;
    25: begin
          Lv(5, 4, -4, 16, 80, 3, 'LOCKED TURBO', '5g m = -4, spin locked UP, current 1.4 x.');
          Lock(1); Turbo(1.4);
        end;
    26: begin
          Lv(6, 1, -1, 24, 120, 3, 'MIRROR MARATHON', '6p m = -1: the reference orbital mirrored, 24 quanta.');
          Result.Quanta := 7;
          Result.Badge := 'MARATHON';
        end;
    27: begin
          Lv(7, 3, 3, 14, 65, 4, 'FAST F', '7f m = +3 in 65 seconds.');
          Result.Badge := 'TIME ATTACK';
        end;
    28: begin
          Lv(8, 2, 0, 16, 100, 3, 'DEEP FREEZE', '8d m = 0, spin locked DOWN, node storm: only the spin current, and it never turns.');
          Lock(-1); Storm;
        end;
  else
    begin
      Lv(9, 4, 4, 24, 140, 4, 'PAULI STORM 9g', 'The finale: 9g m = +4, turbo current, photon rush, four black holes.');
      Turbo(1.3); Rush;
      Result.Quanta := 7;
    end;
  end;
  MakeRuleText(Result);
end;

procedure MakeRuleText(var D: TLevelDef);
begin
  D.Rule := D.Badge;
  if D.NoFlip then
    D.Rule := Trim(D.Rule + IfThen(D.StartSpin > 0, '  SPIN LOCKED UP', '  SPIN LOCKED DOWN'));
  if D.FlowMul > 1.01 then D.Rule := Trim(D.Rule + Format('  TURBO x%.1f', [D.FlowMul]))
  else if D.FlowMul < 0.99 then D.Rule := Trim(D.Rule + Format('  CALM x%.1f', [D.FlowMul]));
  if D.PhotonMul < 0.99 then D.Rule := Trim(D.Rule + '  PHOTON RUSH');
  if D.DrainMul > 1.01 then D.Rule := Trim(D.Rule + '  NODE STORM');
  if D.M < 0 then D.Rule := Trim(D.Rule + '  MIRRORED');
end;

function OrbitalName(N, L: Integer): string;
const
  Letters = 'spdfghiklm';
begin
  if (L >= 0) and (L < Length(Letters)) then Result := IntToStr(N) + Letters[L + 1]
  else Result := IntToStr(N) + '?';
end;

function CheckLevel(const D: TLevelDef): string;
begin
  Result := '';
  if (D.N < 1) or (D.N > 9) then Exit('n must be 1 .. 9');
  if (D.L < 0) or (D.L >= D.N) then Exit('l must be 0 .. n - 1');
  if Abs(D.M) > D.L then Exit('|m| must be <= l');
  { Y_lm(theta = 90 deg) = 0 when l - |m| is odd: no density in the game plane }
  if Odd(D.L - Abs(D.M)) then Exit('l - |m| odd: the orbital is empty in the plane z = 0');
  if (D.Target < 1) or (D.Target > 99) then Exit('target must be 1 .. 99');
  if (D.Quanta < 1) or (D.Quanta > MaxQuanta) then Exit(Format('quanta on screen must be 1 .. %d', [MaxQuanta]));
  if (D.TimeSec < 10) or (D.TimeSec > 600) then Exit('time must be 10 .. 600 s');
  if (D.BH < 0) or (D.BH > MaxBlackHoles) then Exit(Format('black holes must be 0 .. %d', [MaxBlackHoles]));
  if (D.FlowMul < 0.2) or (D.FlowMul > 3) then Exit('current x must be 0.2 .. 3');
end;

function LevelDef(ALevel: Integer): TLevelDef;
begin
  Result := LevelTable[EnsureRange(ALevel, 0, LevelCount - 1)];
end;

procedure ResetLevels;
var
  i: Integer;
begin
  for i := 0 to LevelCount - 1 do LevelTable[i] := BuiltinLevel(i);
  LevelsFile := '';
end;

function LvF(X: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(X, ffGeneral, 6, 0, fs);
end;

function LvR(AIni: TCustomIniFile; const ASec, AKey: string; ADef: Double): Double;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := StrToFloatDef(AIni.ReadString(ASec, AKey, ''), ADef, fs);
end;

procedure WriteLevel(AIni: TCustomIniFile; ALevel: Integer; const D: TLevelDef);
var
  sec: string;
begin
  sec := 'level' + IntToStr(ALevel + 1);
  AIni.WriteString(sec, 'orbital', OrbitalName(D.N, D.L));
  AIni.WriteInteger(sec, 'n', D.N);
  AIni.WriteInteger(sec, 'l', D.L);
  AIni.WriteInteger(sec, 'm', D.M);
  AIni.WriteString(sec, 'title', D.Title);
  AIni.WriteString(sec, 'tip', D.Tip);
  AIni.WriteString(sec, 'badge', D.Badge);
  AIni.WriteInteger(sec, 'target', D.Target);
  AIni.WriteInteger(sec, 'quanta', D.Quanta);
  AIni.WriteString(sec, 'time', LvF(D.TimeSec));
  AIni.WriteInteger(sec, 'black_holes', D.BH);
  AIni.WriteString(sec, 'current_x', LvF(D.FlowMul));
  AIni.WriteString(sec, 'photon_every_x', LvF(D.PhotonMul));
  AIni.WriteString(sec, 'node_drain_x', LvF(D.DrainMul));
  AIni.WriteBool(sec, 'spin_locked', D.NoFlip);
  AIni.WriteInteger(sec, 'start_spin', D.StartSpin);
end;

function ReadLevel(AIni: TCustomIniFile; ALevel: Integer; const ADefault: TLevelDef): TLevelDef;
var
  sec: string;
begin
  Result := ADefault;
  sec := 'level' + IntToStr(ALevel + 1);
  if not AIni.SectionExists(sec) then Exit;
  Result.N := AIni.ReadInteger(sec, 'n', Result.N);
  Result.L := AIni.ReadInteger(sec, 'l', Result.L);
  Result.M := AIni.ReadInteger(sec, 'm', Result.M);
  Result.Title := AIni.ReadString(sec, 'title', Result.Title);
  Result.Tip := AIni.ReadString(sec, 'tip', Result.Tip);
  Result.Badge := AIni.ReadString(sec, 'badge', Result.Badge);
  Result.Target := AIni.ReadInteger(sec, 'target', Result.Target);
  Result.Quanta := AIni.ReadInteger(sec, 'quanta', Result.Quanta);
  Result.TimeSec := LvR(AIni, sec, 'time', Result.TimeSec);
  Result.BH := AIni.ReadInteger(sec, 'black_holes', Result.BH);
  Result.FlowMul := LvR(AIni, sec, 'current_x', Result.FlowMul);
  Result.PhotonMul := LvR(AIni, sec, 'photon_every_x', Result.PhotonMul);
  Result.DrainMul := LvR(AIni, sec, 'node_drain_x', Result.DrainMul);
  Result.NoFlip := AIni.ReadBool(sec, 'spin_locked', Result.NoFlip);
  Result.StartSpin := AIni.ReadInteger(sec, 'start_spin', Result.StartSpin);
  if Result.StartSpin >= 0 then Result.StartSpin := 1 else Result.StartSpin := -1;
  Result.World := ALevel div LevelsPerWorld;
  MakeRuleText(Result);
  { an unplayable level falls back to the built-in one }
  if CheckLevel(Result) <> '' then Result := ADefault;
end;

function LoadLevels(const AFile: string): Boolean;
var
  ini: TMemIniFile;
  i: Integer;
begin
  Result := False;
  ResetLevels;
  if not FileExists(AFile) then Exit;
  try
    ini := TMemIniFile.Create(AFile);
    try
      for i := 0 to LevelCount - 1 do LevelTable[i] := ReadLevel(ini, i, BuiltinLevel(i));
      LevelsFile := AFile;
      Result := True;
    finally
      ini.Free;
    end;
  except
    ResetLevels;
  end;
end;

procedure SaveLevels(const AFile: string);
var
  ini: TMemIniFile;
  i: Integer;
begin
  ForceDirectories(ExtractFilePath(AFile));
  if FileExists(AFile) then DeleteFile(AFile);
  ini := TMemIniFile.Create(AFile);
  try
    ini.WriteString('info', 'about', 'PAULI SURFER 2 levels (Level Editor). Orbital n l m, rules, black holes.');
    ini.WriteInteger('info', 'levels', LevelCount);
    for i := 0 to LevelCount - 1 do WriteLevel(ini, i, LevelTable[i]);
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

constructor TPauliGame.Create;
begin
  Orb[0] := TOrbital.Create;
  Orb[1] := TOrbital.Create;
  Spin := 1;
  Mode := gmBlackHole;
end;

destructor TPauliGame.Destroy;
begin
  Orb[0].Free;
  Orb[1].Free;
  inherited Destroy;
end;

function TPauliGame.RingAt(ASv: Double): Integer;
var
  i: Integer;
  o: TOrbital;
begin
  o := Orb[0];
  Result := 0;
  for i := 0 to High(o.RadialNodes) do
    if o.RadialNodes[i] < ASv then Inc(Result);
end;

function TPauliGame.LocalProb(ASv: Double): Double;
var
  k: Integer;
begin
  k := RingAt(ASv);
  if k > High(RingPeak) then Exit(0);
  Result := Orb[0].RadialProb(ASv) / RingPeak[k];
end;

function TPauliGame.FlowK: Double;
begin
  Result := GP.FlowScale * Def.FlowMul;
end;

function TPauliGame.Active: TOrbital;
begin
  if Spin > 0 then Result := Orb[0] else Result := Orb[1];
end;

function TPauliGame.ProbeRadius: Double;
begin
  Result := 0.03 * RView;
end;

function TPauliGame.PickRadius: Double;
begin
  Result := 0.065 * RView;
end;

procedure TPauliGame.Emit(E: TGameEvent);
var
  n: Integer;
begin
  n := (FTail + 1) mod Length(FEvents);
  if n = FHead then Exit;
  FEvents[FTail] := E;
  FTail := n;
end;

function TPauliGame.PopEvent: TGameEvent;
begin
  if FHead = FTail then Exit(geNone);
  Result := FEvents[FHead];
  FHead := (FHead + 1) mod Length(FEvents);
end;

function TPauliGame.Rnd: Double;
begin
  FRng := FRng xor (FRng shl 13);
  FRng := FRng xor (FRng shr 17);
  FRng := FRng xor (FRng shl 5);
  Result := FRng / 4294967296.0;
end;

function TPauliGame.OmegaAt(ASv: Double; ASpin: Integer): Double;
var
  o: TOrbital;
  rho: Double;
begin
  if ASpin > 0 then o := Orb[0] else o := Orb[1];
  Result := o.DisplayOmega(o.FieldAt(ASv, 0, ASpin, rho)) * FlowK;
  if Abs(Result) * ASv > GP.MaxFlowSpeed * RView then Result := Sign(Result) * GP.MaxFlowSpeed * RView / Max(1e-9, ASv);
end;

procedure TPauliGame.StartLevel(ALevel, APoints: Integer; ASeed: Cardinal; ARunSeed: Cardinal);
var
  i, best: Integer;
  r, p, bp: Double;
  o: TOrbital;
begin
  Level := EnsureRange(ALevel, 0, LevelCount - 1);
  Def := LevelDef(Level);
  Points := APoints;
  { same seed for both spins -> identical particle positions, only omega differs }
  if (FBuiltLevel <> Level + 1) or (FBuiltPoints <> APoints) or (FBuiltSeed <> ASeed) or
    (FBuiltKey <> Format('%d %d %d', [Def.N, Def.L, Def.M])) then
  begin
    RandSeed := ASeed;
    Orb[0].Build(Def.N, Def.L, Def.M, APoints, 1);
    RandSeed := ASeed;
    Orb[1].Build(Def.N, Def.L, Def.M, APoints, -1);
    FBuiltLevel := Level + 1;
    FBuiltPoints := APoints;
    FBuiltSeed := ASeed;
    FBuiltKey := Format('%d %d %d', [Def.N, Def.L, Def.M]);
  end;
  RView := Orb[0].RView;
  if ARunSeed = 0 then ARunSeed := ASeed;
  FRng := ARunSeed * 2654435761 + 1;
  if FRng = 0 then FRng := 7;
  Spin := Def.StartSpin;
  SimTime := 0;
  { start on the outermost maximum of r^2 R^2 }
  o := Orb[0];
  best := 0; bp := 0;
  for i := 0 to High(o.RTabR) do
  begin
    r := o.RTabR[i];
    if r > RView * 1.05 then Break;
    p := o.RTabP[i];
    if (p > 0.5) and (r > o.RTabR[best]) and (i > 0) and (i < High(o.RTabR)) and
      (o.RTabP[i] >= o.RTabP[i - 1]) and (o.RTabP[i] >= o.RTabP[i + 1]) then best := i;
    if p > bp then bp := p;
  end;
  if best = 0 then
    for i := 0 to High(o.RTabR) do
      if o.RTabP[i] = 1 then best := i;
  PX := o.RTabR[best]; PY := 0;
  SetLength(RingPeak, Length(o.RadialNodes) + 1);
  for i := 0 to High(RingPeak) do RingPeak[i] := 1e-12;
  for i := 0 to High(o.RTabR) do
    RingPeak[RingAt(o.RTabR[i])] := Max(RingPeak[RingAt(o.RTabR[i])], o.RTabP[i]);
  VX := 0; VY := 0;
  Coherence := 1;
  Score := 0; Collected := 0; Combo := 0; BestCombo := 0; Flips := 0; Bonuses := 0; NodeCrossings := 0;
  ComboT := 0; Elapsed := 0; FlipCool := 0; BonusT := GP.BonusEvery * Def.PhotonMul;
  TimeLeft := Def.TimeSec;
  FInNode := False; FLowWarned := False; FTimeWarned := False;
  FBotFlipT := -10;
  State := gsPlaying;
  FHead := 0; FTail := 0;
  Immune := 0; Tidal := 0;
  Swallowed := 0; HorizonHits := 0; EdgeBonuses := 0;
  LostToBH := False; FTidalWarned := False;
  PlaceBlackHoles;
  for i := 0 to MaxQuanta - 1 do Quanta[i].Alive := False;
  for i := 0 to Def.Quanta - 1 do SpawnQuantum(False);
  Emit(geStart);
end;

function TPauliGame.BHPos(K: Integer; out X, Y: Double): Boolean;
begin
  Result := (K >= 0) and (K < BHCount);
  if not Result then begin X := 0; Y := 0; Exit; end;
  X := BH[K].S * Cos(BH[K].Phi);
  Y := BH[K].S * Sin(BH[K].Phi);
end;

function TPauliGame.NearBH(X, Y, AFactor: Double): Boolean;
var
  k: Integer;
  bx, by: Double;
begin
  for k := 0 to BHCount - 1 do
  begin
    BHPos(k, bx, by);
    if Hypot(X - bx, Y - by) < AFactor * BH[k].Rc then Exit(True);
  end;
  Result := False;
end;

procedure TPauliGame.PlaceBlackHoles;
var
  k, j, tries: Integer;
  sv, ph, x, y, bx, by, rc: Double;
  ok: Boolean;
begin
  BHCount := BlackHolesFor(Mode, Level);
  rc := GP.BHRc[Mode] * RView;
  for k := 0 to BHCount - 1 do
  begin
    sv := 0.6 * RView; ph := 0;
    for tries := 0 to 300 do
    begin
      { inside the cloud, away from the jets at the centre and from the probe start }
      sv := (0.3 + 0.7 * Rnd) * RView;
      ph := Rnd * 2 * Pi;
      x := sv * Cos(ph); y := sv * Sin(ph);
      ok := (Hypot(x - PX, y - PY) > 0.45 * RView) and (LocalProb(sv) > 0.2);
      for j := 0 to k - 1 do
      begin
        bx := BH[j].S * Cos(BH[j].Phi); by := BH[j].S * Sin(BH[j].Phi);
        if Hypot(x - bx, y - by) < 5 * rc then ok := False;
      end;
      if ok then Break;
    end;
    BH[k].S := sv;
    BH[k].Phi := ph;
    BH[k].Rc := rc;
    BH[k].Rh := rc * GP.BHHorizon;
    BH[k].Eaten := 0;
    BH[k].Meal := 99;
  end;
end;

procedure TPauliGame.SinkAt(X, Y: Double; out SX_, SY_: Double);
var
  k: Integer;
  bx, by, dx, dy, d, v, vmax: Double;
begin
  SX_ := 0; SY_ := 0;
  vmax := GP.MaxSelfSpeed * RView;
  for k := 0 to BHCount - 1 do
  begin
    BHPos(k, bx, by);
    dx := bx - X; dy := by - Y;
    d := Max(1e-6, Hypot(dx, dy));
    v := vmax * BH[k].Rc / d * Exp(-Sqr(Max(0, d - BH[k].Rc) / (3 * BH[k].Rc)));
    v := Min(v, GP.BHMaxSink * RView);
    SX_ := SX_ + dx / d * v;
    SY_ := SY_ + dy / d * v;
  end;
end;

procedure TPauliGame.Eject(AFrom: Integer);
var
  o: TOrbital;
  i, best: Integer;
  ph: Double;
begin
  { Hawking ejection: back on the outermost band, opposite the hole }
  o := Orb[0];
  best := 0;
  for i := 0 to High(o.RTabR) do
  begin
    if o.RTabR[i] > RView * 1.05 then Break;
    if (i > 0) and (i < High(o.RTabR)) and (o.RTabP[i] > 0.5) and (o.RTabP[i] >= o.RTabP[i - 1]) and
      (o.RTabP[i] >= o.RTabP[i + 1]) then best := i;
  end;
  if best = 0 then best := High(o.RTabR) div 4;
  ph := BH[AFrom].Phi + Pi;
  PX := o.RTabR[best] * Cos(ph);
  PY := o.RTabR[best] * Sin(ph);
  VX := 0; VY := 0;
  Immune := GP.ImmuneTime;
end;

procedure TPauliGame.SpawnQuantum(ABonus: Boolean);
var
  i, k, tries: Integer;
  o: TOrbital;
  x, y, d: Double;
begin
  o := Active;
  for k := 0 to MaxQuanta - 1 do
    if not Quanta[k].Alive then
    begin
      { a sample of |psi|^2 near the plane, not right on top of the probe }
      for tries := 0 to 400 do
      begin
        i := Trunc(Rnd * o.Count);
        if (Abs(o.Z[i]) > 0.12 * RView) or (o.S[i] < 0.12 * RView) or (o.S[i] > 1.1 * RView) then Continue;
        if Abs(o.W[i]) * FlowK * o.S[i] > GP.MaxQuantumSpeed * RView then Continue;
        x := o.S[i] * Cos(o.Phi0[i] + o.W[i] * SimTime);
        y := o.S[i] * Sin(o.Phi0[i] + o.W[i] * SimTime);
        d := Hypot(x - PX, y - PY);
        if (d > 0.25 * RView) and not NearBH(x, y, 2.0) then Break;
      end;
      Quanta[k].Alive := True;
      Quanta[k].Bonus := ABonus;
      Quanta[k].Idx := i;
      Quanta[k].S := o.S[i];
      Quanta[k].Phi := o.Phi0[i] + o.W[i] * SimTime;
      Quanta[k].Age := 0;
      if ABonus then Quanta[k].Life := GP.BonusLife else Quanta[k].Life := 1e9;
      Exit;
    end;
end;

procedure TPauliGame.Update(ADt, AX, AY: Double; AFlip: Boolean);
var
  k, i, j: Integer;
  s, w, a, sp, maxv, r, x, y, mult: Double;
  o: TOrbital;
  inNode: Boolean;
begin
  if State <> gsPlaying then Exit;
  ADt := Min(ADt, 0.05);
  SimTime := SimTime + ADt * FlowK;
  Elapsed := Elapsed + ADt;
  TimeLeft := TimeLeft - ADt;
  FlipCool := Max(0, FlipCool - ADt);
  if ComboT > 0 then
  begin
    ComboT := ComboT - ADt;
    if ComboT <= 0 then Combo := 0;
  end;

  if AFlip and Def.NoFlip then
    Emit(geFlipDenied)
  else if AFlip then
    if FlipCool <= 0 then
    begin
      Spin := -Spin;
      FlipCool := GP.FlipCooldown;
      Inc(Flips);
      Emit(geFlip);
    end
    else
      Emit(geFlipDenied);
  o := Active;

  { flow at the probe: v = omega x r (tangential, CCW for omega > 0) }
  s := Max(1e-6, Hypot(PX, PY));
  w := OmegaAt(s, Spin);
  ProbeOmega := w;
  FlowVX := -w * PY;
  FlowVY := w * PX;

  { own velocity: thrust + drag, limited }
  a := Hypot(AX, AY);
  if a > 1 then begin AX := AX / a; AY := AY / a; end;
  VX := VX + (AX * GP.Accel * RView - VX * GP.Drag) * ADt;
  VY := VY + (AY * GP.Accel * RView - VY * GP.Drag) * ADt;
  sp := Hypot(VX, VY);
  maxv := GP.MaxSelfSpeed * RView;
  if sp > maxv then begin VX := VX * maxv / sp; VY := VY * maxv / sp; end;

  { integrate: the flow is a rotation, so rotate exactly (no outward drift) }
  r := s;
  a := ArcTan2(PY, PX) + w * ADt;
  PX := r * Cos(a) + VX * ADt;
  PY := r * Sin(a) + VY * ADt;
  { black holes: drift with the current, pull the probe, horizon }
  Immune := Max(0, Immune - ADt);
  Tidal := 0;
  for k := 0 to BHCount - 1 do
    with BH[k] do
    begin
      Phi := Phi + GP.BHDrift[Mode] * OmegaAt(S, Spin) * ADt;
      Meal := Meal + ADt;
    end;
  if (BHCount > 0) and (Immune <= 0) then
  begin
    SinkAt(PX, PY, x, y);
    Tidal := Hypot(x, y) / (GP.MaxSelfSpeed * RView);
    PX := PX + x * ADt;
    PY := PY + y * ADt;
    if (Tidal > 0.5) and not FTidalWarned then
    begin
      FTidalWarned := True;
      Emit(geTidal);
    end;
    if Tidal < 0.25 then FTidalWarned := False;
    for k := 0 to BHCount - 1 do
    begin
      BHPos(k, x, y);
      if Hypot(PX - x, PY - y) < BH[k].Rh + 0.5 * ProbeRadius then
      begin
        Inc(HorizonHits);
        Coherence := Coherence - GP.BHHit[Mode];
        Emit(geHorizon);
        if Coherence <= 0 then
          LostToBH := True
        else
          Eject(k);
        Break;
      end;
    end;
  end;

  { the cloud ends: soft wall at 1.15 RView }
  s := Hypot(PX, PY);
  if s > 1.15 * RView then
  begin
    PX := PX * 1.15 * RView / s;
    PY := PY * 1.15 * RView / s;
    VX := VX * 0.5; VY := VY * 0.5;
  end;
  s := Max(1e-6, Hypot(PX, PY));

  { probability at this radius and ring index }
  ProbeProb := LocalProb(s);
  ProbeRing := RingAt(s);
  inNode := ProbeProb < GP.NodeProb;
  if inNode then
  begin
    Coherence := Coherence - GP.DrainNode * Def.DrainMul * ADt;
    if not FInNode then
    begin
      Inc(NodeCrossings);
      Emit(geNodeEnter);
    end;
  end
  else if ProbeProb > 0.15 then
    Coherence := Min(1, Coherence + GP.Recover * ADt);
  FInNode := inNode;
  if (Coherence < 0.3) and not FLowWarned then
  begin
    FLowWarned := True;
    Emit(geLowCoherence);
  end;
  if Coherence > 0.45 then FLowWarned := False;

  { quanta ride the current of their particle }
  for k := 0 to MaxQuanta - 1 do
    with Quanta[k] do
    begin
      if not Alive then Continue;
      Phi := Phi + o.W[Idx] * ADt * FlowK;
      Age := Age + ADt;
      if Age > Life then
      begin
        Alive := False;
        Continue;
      end;
      x := S * Cos(Phi);
      y := S * Sin(Phi);
      { swallowed by a black hole? }
      j := -1;
      for i := 0 to BHCount - 1 do
        if Hypot(x - BH[i].S * Cos(BH[i].Phi), y - BH[i].S * Sin(BH[i].Phi)) < BH[i].Rh * 1.3 then j := i;
      if j >= 0 then
      begin
        Alive := False;
        Inc(Swallowed);
        Inc(BH[j].Eaten);
        BH[j].Meal := 0;
        if Mode = gmSingularity then
        begin
          BH[j].Rc := Min(GP.BHRcMax * RView, BH[j].Rc * GP.BHGrow);
          BH[j].Rh := BH[j].Rc * GP.BHHorizon;
        end;
        Emit(geSwallow);
        if not Bonus then SpawnQuantum(False);
        Continue;
      end;
      if Hypot(x - PX, y - PY) < PickRadius then
      begin
        Alive := False;
        if ComboT > 0 then Inc(Combo) else Combo := 0;
        ComboT := GP.ComboWindow;
        BestCombo := Max(BestCombo, Combo);
        mult := Min(3, 1 + Combo * 0.25);
        if (BHCount > 0) and NearBH(PX, PY, GP.EdgeFactor) then
        begin
          mult := mult * 2;
          Inc(EdgeBonuses);
          Emit(geEdgeBonus);
        end;
        if Bonus then
        begin
          Inc(Bonuses);
          Inc(Score, Round(500 * mult));
          Emit(geBonus);
        end
        else
        begin
          Inc(Collected);
          Inc(Score, Round(100 * mult));
          Emit(gePickup);
          SpawnQuantum(False);
        end;
      end;
    end;

  BonusT := BonusT - ADt;
  if BonusT <= 0 then
  begin
    BonusT := GP.BonusEvery * Def.PhotonMul;
    SpawnQuantum(True);
  end;

  if (TimeLeft < 10) and not FTimeWarned then
  begin
    FTimeWarned := True;
    Emit(geTimeWarn);
  end;
  if Collected >= Def.Target then
  begin
    State := gsWon;
    Inc(Score, Round(Max(0, TimeLeft)) * 10 + Round(Coherence * 500));
    Emit(geWin);
  end
  else if (Coherence <= 0) or (TimeLeft <= 0) or LostToBH then
  begin
    Coherence := Max(0, Coherence);
    TimeLeft := Max(0, TimeLeft);
    State := gsLost;
    Emit(geFail);
  end;
end;

function TPauliGame.StarScore(AStars: Integer): Integer;
begin
  { calibrated with the bot: 2 stars ~ bot level, 3 stars needs combos }
  case AStars of
    2: Result := Def.Target * 130 + 400;
    3: Result := Def.Target * 175 + 700;
  else
    Result := 0;
  end;
end;

function TPauliGame.Stars: Integer;
begin
  if State <> gsWon then Exit(0);
  Result := 1;
  if Score >= StarScore(2) then Result := 2;
  if Score >= StarScore(3) then Result := 3;
end;

function TPauliGame.RingDirection: string;
begin
  if Abs(ProbeOmega) < 0.12 then Result := 'SLOW'
  else if ProbeOmega > 0 then Result := 'CCW'
  else Result := 'CW';
end;

procedure TPauliGame.BotInput(out AX, AY: Double; out AFlip: Boolean);
var
  k, best, nn, j: Integer;
  d, bd, x, y, tx, ty, wq, bw, vx_, vy_, s, tang, flowT, otherT, w, sp0, tg, lo, hi: Double;
  o: TOrbital;
begin
  AX := 0; AY := 0; AFlip := False;
  o := Active;
  best := -1; bd := 1e30; tx := 0; ty := 0; bw := 0;
  sp0 := Max(1e-6, Hypot(PX, PY));
  for k := 0 to MaxQuanta - 1 do
    if Quanta[k].Alive then
    begin
      x := Quanta[k].S * Cos(Quanta[k].Phi);
      y := Quanta[k].S * Sin(Quanta[k].Phi);
      d := Hypot(x - PX, y - PY);
      if Quanta[k].Bonus then d := d * 0.6;
      if NearBH(x, y, 2.2) then d := d * 4;          { next to a hole: only if nothing else }
      { every radial node on the way costs coherence: more when coherence is low }
      nn := Abs(RingAt(Quanta[k].S) - ProbeRing);
      if nn > 0 then d := d * (1 + nn * (0.2 + 2 * Max(0, 0.6 - Coherence)));
      { spin locked (or cooling down): a target against a strong current is far away }
      if Def.NoFlip or (FlipCool > 0) then
      begin
        tg := (-PY * (x - PX) + PX * (y - PY)) / sp0;
        if (tg * ProbeOmega < 0) and (Abs(ProbeOmega) * sp0 > 0.5 * GP.MaxSelfSpeed * RView) then d := d * 2.5;
      end;
      if d < bd then
      begin
        bd := d; best := k; tx := x; ty := y; bw := o.W[Quanta[k].Idx] * FlowK;
      end;
    end;
  if best < 0 then Exit;
  { wanted own velocity: close the gap + cancel the shear between target and
    probe (limited, so the radial part survives next to the jets at a node) }
  wq := bw;
  x := -wq * ty - FlowVX;
  y := wq * tx - FlowVY;
  d := Hypot(x, y);
  if d > 0.25 * RView then begin x := x * 0.25 * RView / d; y := y * 0.25 * RView / d; end;
  vx_ := 1.8 * (tx - PX) + x - VX;
  vy_ := 1.8 * (ty - PY) + y - VY;
  { inside a node band: go straight across, radially }
  s := Max(1e-6, Hypot(PX, PY));
  if (ProbeProb < 0.12) and (Abs(Hypot(tx, ty) - s) > 0.02 * RView) then
  begin
    w := Sign(Hypot(tx, ty) - s);
    { low coherence: leave the node by the nearest side instead }
    if Coherence < 0.45 then
    begin
      lo := 0; hi := 1e30;
      for j := 0 to High(Orb[0].RadialNodes) do
        if Abs(Orb[0].RadialNodes[j] - s) < Abs(hi - s) then hi := Orb[0].RadialNodes[j];
      if hi < 1e29 then
        if s >= hi then w := 1 else w := -1;
    end;
    vx_ := PX / s * w;
    vy_ := PY / s * w;
  end;
  { black holes: cancel the pull and steer around the capture zone }
  if (BHCount > 0) and (Immune <= 0) then
  begin
    SinkAt(PX, PY, x, y);
    vx_ := vx_ - 1.5 * x;
    vy_ := vy_ - 1.5 * y;
    for k := 0 to BHCount - 1 do
    begin
      BHPos(k, x, y);
      d := Max(1e-6, Hypot(PX - x, PY - y));
      if d < 4.0 * BH[k].Rc then
      begin
        w := (4.0 * BH[k].Rc - d) / BH[k].Rc;
        vx_ := vx_ + (PX - x) / d * w * RView;
        vy_ := vy_ + (PY - y) / d * w * RView;
      end;
    end;
  end;
  d := Max(1e-9, Hypot(vx_, vy_));
  AX := vx_ / d; AY := vy_ / d;
  { flip when the current fights the way we want to go and the other spin helps }
  s := Max(1e-6, Hypot(PX, PY));
  tang := (-PY * (tx - PX) + PX * (ty - PY)) / s;
  w := OmegaAt(s, Spin);
  flowT := w * s;
  otherT := OmegaAt(s, -Spin) * s;
  if not Def.NoFlip and (FlipCool <= 0) and (Elapsed - FBotFlipT > 2.5) and (tang * flowT < 0) and (Abs(flowT) > 0.25 * RView) and
    (tang * otherT >= 0) then
  begin
    AFlip := True;
    FBotFlipT := Elapsed;
  end;
end;

initialization
  GP := DefaultGameParams;
  ResetLevels;
end.
