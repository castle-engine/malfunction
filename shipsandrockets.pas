{
  Copyright 2003-2022 Michalis Kamburelis.

  This file is part of "malfunction".

  "malfunction" is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  "malfunction" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with "malfunction"; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA

  ----------------------------------------------------------------------------
}

unit ShipsAndRockets;

{ Ten modul gromadzi stan mobilnych rzeczy w przestrzeni (ale nie statku gracza)
  czyli wrogich statkow i rakiet.

  W implementacji ten modul zarzadza tez ladowaniem i uzywaniem VRMLi modeli.
  Konwencje VRMLi modeli :
    Caly model musi byc zbudowany rownomiernie wokolo punktu 0, 0, 0.
    Cos co jest uwazane za "przod" modelu (tam gdzie ma wskazywac Direction)
    musi byc skierowane w strone +Z.
    Cos co jest uwazane za "up" modelu musi byc skierowane w strone +X.
}

interface

uses SysUtils, Classes, Generics.Collections,
  CastleWindow, CastleGLUtils, CastleVectors, CastleUtils,
  CastleClassUtils, CastleTimeUtils, CastleScene, CastleTransform;

type
  TEnemyShipKind = (skHedgehog, skTieFighter, skDestroyer);
  TRocket = class;
  TEnemyShip = class;

  TRocketList = specialize TObjectList<TRocket>;

  TSpaceShip = class(TCastleTransform)
  private
    {rakiety tego statku jakie kraza w przestrzeni.
     Zeby nie przeciazac programu kazdy statek moze miec ich maksymalnie
      maxFiredRocketsCount (nie bedzie mogl wystrzelic nowej rakiety jezeli
      spowodowaloby to przekroczenie tej liczby). Ponadto, musimy przechowywac
      sobie wskazniki na wszystkie utworzone rakiety zeby jezeli statek
      zostanie zniszczony to ustawic im wskazniki motherShip na nil
      (zeby torpedy wiedzialy ze kiedy one zostane zniszczone to nie musza
      o tym powiadamiac zadnego statku). }
    firedRockets: TRocketList;
    FMaxShipLife, FShipLife: Single;
  protected
    { mozesz zwiekszyc wartosc tego pola dla jakiejs bardzo istotnej podklasy
      TSpaceShip (np. dla TPlayerShip) }
    MaxFiredRocketsCount: integer; { =10 }
  public
    Speed: Single;

    { ShipLife MAxShipLife = pelna sprawnosc, 0 lub mniej => statek zniszczony.
      Player Ship ma MaxShipLife = 100 zeby byl jakis punkt odniesienia. }
    property ShipLife: Single read FShipLife write FShipLife; { =MaxShipLife }
    property MaxShipLife: Single read FMaxShipLife;

    { zostanie zignorowane jezeli za duzo rakiet wystrzelonych przez ten
      statek juz jest w przestrzeni. Dlugosc rocketDir nie ma wplywu
      na szybkosc rakiety podobnie jak w TRocket.Create. }
    procedure FireRocket(const rocketDir: TVector3; rocketSpeed: Single);

    {kolizje statek/rakieta - level sa robione przy pomocy drzewa osemkowego ale
     kolizje statek - statek i statek - rakieta sa robione "recznie" tzn.
     kazdy z kazdym i to uzywajac najprostrzego modelu : statek to sfera
     o promieniu shipRadius wokol Translation. }
    function shipRadius: Single; virtual; abstract;

    {w tej klasie HitByRocket powoduje tylko ze shipLife spada.
     NIE wywoluje Destroy. Mozesz pokryc ta metode w podklasach
     (tylko pamietaj wywolac na poczatku inherited) wlasnie aby dodac destroy
     i/lub wyswietlic jakies Notification lub zrobic FadeOut graczowi.}
    procedure HitByRocket; virtual;

    {sprawdza czy gdybysmy stali na pozycji pos to kolidowalibysmy z jakims
     statkiem na liscie enemyShips (ale nie z samymi soba, naturalnie).
     Jezeli nie ma kolizji to zwraca nil. }
    function CollisionWithOtherEnemyShip(const pos: TVector3): TEnemyShip;

    constructor Create(const AMaxShipLife: Single); reintroduce;
    destructor Destroy; override;
  end;

  TEnemyShip = class(TSpaceShip)
  private
    FKind: TEnemyShipKind;
  public
    property Kind: TEnemyShipKind read FKind;
    function ShipName: string;

    constructor Create(const AKind: TEnemyShipKind; const AShipPos: TVector3);
    destructor Destroy; override;

    procedure HitByRocket; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function ShipRadius: Single; override;

    { sprawdz czy nowa pozycja jest dobra (a wiec takze czy droga z Translation
      na NewTranslation jest dobra), jesli true - zmien Translation na NewTranslation.
      Nie przeprowadza tak dokladnego testu na kolizje jaki trzeba robic
      dla playerShip, ale dla enemyShips jest dobre. }
    function TryShipMove(const NewTranslation: TVector3): boolean;
  end;

  TEnemyShipList = specialize TObjectList<TEnemyShip>;

  {statki tej klasy wywoluja w Update FireRocket co jakis czas, zalezny od
   FireDelay dla tego shipKind. Pamietaj wywolac inherited w Update; }
  TFiringRocketsEnemyShip = class(TEnemyShip)
  private
    LastFiredRocketTime: TTimerResult;
    NextFireRocketDelay: TFloatTime;
    RocketFiringInited: boolean;
  protected
    {uzywaj tego w podklasach aby sterowac tym kiedy statek strzela
     rakietami (bo ZAWSZE powinienes wywolywac Update.inherited !).
     Domyslnie jest true.}
    FiringRocketsAllowed: boolean;
  public
    constructor Create(const AKind: TEnemyShipKind; const AShipPos: TVector3);
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  end;

  TNotMovingEnemyShip = class(TFiringRocketsEnemyShip)
  end;

  TCircleMovingEnemyShip = class(TFiringRocketsEnemyShip)
  private
    AngleRad: Single; { aktualny kat na kole (w radianach) }
    AngleRadChange: Single; { zmiana kata co Update (moze byc ujemna) }
    FCircleCenter: TVector3;
    FCircleRadius: Single;
    FUniqueCircleMovingSpeed: Single;
    procedure SetUniqueCircleMovingSpeed(const value: Single);
  public
    { wlasciwa dla statku szybkosc poruszania sie po kole. 1 = jakis default. }
    property UniqueCircleMovingSpeed: Single read FUniqueCircleMovingSpeed
      write SetUniqueCircleMovingSpeed;
    { promien i srodek kola po ktorym sie porusza w plaszczyznie XY statek }
    property CircleCenter: TVector3 read FCircleCenter;
    property CircleRadius: Single read FCircleRadius;

    { zwroc uwage ze jako drugi parametr podajesz nie Translation ale circleCenter.
      Poczatkowe Translation bedzie wyliczone (jako pozycja na zadanym kole
      dla AngleRad = 0 a wiec w [ CircleCenter[0]+CircleRadius,
       CircleCenter[1], CircleCenter[2] ] }
    constructor Create(const AKind: TEnemyShipKind; const ACircleCenter: TVector3;
      const ACircleRadius, AUniqueCircleMovingSpeed: Single);

    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  end;

  THuntingEnemyShip = class(TFiringRocketsEnemyShip)
  private
    { Random* - uzywane do modyfikowania Direction.
        Sa losowane w Randomize uzywanym z Create i zapamietywane w tych polach
        obiektu zeby zawsze uzywac tego samego wektora losowego i kata dla
        jednego statku (zeby statki nie poruszaly sie w takiej "trzesawce"
        na skutek ciaglego losowania nowego RandomVectora).
      Moga byc relosowane tylko raz na jakis czas - zeby nie spowodowac
        tego "trzesacego sie ruchu".}
    RandomVector: TVector3;
    RandomAngleDeg: Single;
    procedure Randomize;
  private
    FHuntingAttack: boolean;
    procedure SetHuntingAttack(value: boolean);
    property HuntingAttack: boolean read FHuntingAttack write SetHuntingAttack;
  public
    constructor Create(const AKind: TEnemyShipKind; const AShipPos: TVector3);
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  end;

  TRocket = class(TCastleTransform)
  private
    FMotherShip: TSpaceShip;
    FSpeed: Single;
  public
    { MotherShip = statek ktory wystrzelil ta rakiete. Gdy rakieta
      zostanie zniszczona (bo zderzyla sie z czyms lub wyleciala za level)
      powiadomi o tym swoj MotherShip usuwajac sie z jego listy firedRockets.
      Z drugiej strony, jezeli to motherShip zostanie zniszczony pierwszy
      to musi on powiadomic o tym wszystkie swoje rakiety ustawiajac im
      motherShip na nil. }
    property MotherShip: TSpaceShip read FMotherShip;
    constructor Create(const ArocPos, ArocDir: TVector3;
      const speed: Single; AmotherShip: TSpaceShip); reintroduce;
    destructor Destroy; override;

    class function rocRadius: Single;

    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  end;

var
  { Wszystkie rakiety i statki wroga jakie istnieja w przestrzeni.

    These lists do not own children (it would be too easy to free rockets/ships too early then),
    rockets and ships are owned by SceneManager.
    This way they are freed at the end of game (unless freed earlier).

    These lists are synchronized with SceneManager contents,
    when we add new rocket/enemy, and when it is destroyed. }
  rockets: TRocketList;
  enemyShips: TEnemyShipList;

procedure ShipsAndRocketsUpdate;

{ inne funkcje }

function NameShcutToEnemyShipKind(const ANameShcut: string): TEnemyShipKind;

implementation

uses
  CastleBoxes, GameGeneral, X3DNodes, LevelUnit, Math, PlayerShipUnit,
  CastleUIControls, CastleFilesUtils, CastleApplicationProperties,
  ModeGameUnit;

type
  TEnemyShipKindInfo = record
    MaxLife: integer;

    { Skrotowa nazwa do uzytku wewnetrznego (w tej chwili w
      node'ach "DEF Enemy Info" w VRML'ach levelu), 1 wyraz bez bialych
      spacji pisany malymi literami. }
    NameShcut: string;

    { Ladna nazwa dla usera, pisana z duzych liter i byc moze
      wielowyrazowa. }
    Name: string;

    { Nazwa pliku z ktorego zaladowac VRML statku. }
    VrmlFName: string;

    { Determinuje jak czesto statek bedzie strzelal rakiety,
      istotne tylko jesli statek jest TFiringRocketsEnemyShip. }
    FireDelay: TFloatTime;

    { Okreslaja jaka jest szybkosc statku przy danym stanie
      HuntingAttack, w skali gdzie wartosc 1.0 oznacza pewna domyslna
      sensowna szybkosc. }
    HuntingSpeed: array[boolean]of Single;

    { Jaka jest szybkosc poruszania sie po kole. 1.0 oznacza domyslna szybkosc. }
    CircleMovingSpeed: Single;
  end;

const
  EnemyShipKindsInfos : array[TEnemyShipKind]of TEnemyShipKindInfo =
  (( MaxLife: 30; NameShcut: 'hedgehog'; Name: 'Black Hedgehog';
     VrmlFname:'black_hedgehog.wrl'; FireDelay: 8.000;
     HuntingSpeed: (0.5, 0.5); CircleMovingSpeed: 1.0),
   ( MaxLife: 15; NameShcut: 'tieftr'; Name: 'Tie Fighter';
     VrmlFname: 'tie_fighter.wrl'; FireDelay: 8.000;
     HuntingSpeed: (1, 1); CircleMovingSpeed: 1.0),
   ( MaxLife: 50; NameShcut:'destroyer'; Name: 'Destroyer';
     VrmlFname: 'destroyer.wrl'; FireDelay: 4.000;
     HuntingSpeed: (1, 1); CircleMovingSpeed: 0.5)
  );

var
  { Shared models.  }
  RocketScene: TCastleScene;
  EnemyShipScenes: array [TEnemyShipKind] of TCastleScene;

{ TSpaceShip ----------------------------------------------------------------- }

constructor TSpaceShip.Create(const AMaxShipLife: Single);
begin
 inherited Create(SceneManager);
 MaxFiredRocketsCount := 10;
 FMaxShipLife := AMaxShipLife;
 FShipLife := MaxShipLife;
 firedRockets := TRocketList.Create(false);
end;

destructor TSpaceShip.Destroy;
var i: integer;
begin
 if firedRockets <> nil then
 begin
  for i := 0 to firedRockets.Count-1 do firedRockets[i].FMotherShip := nil;
  FreeAndNil(firedRockets);
 end;
 inherited;
end;

procedure TSpaceShip.FireRocket(const rocketDir: TVector3; rocketSpeed: Single);
var rocket: TRocket;
begin
 if firedRockets.Count < maxFiredRocketsCount then
 begin
  rocket := TRocket.Create(Translation, rocketDir, rocketSpeed, Self);
  rockets.Add(rocket);
  SceneManager.ITems.Add(rocket);
  firedRockets.Add(rocket);
 end;
end;

procedure TSpaceShip.HitByRocket;
begin
 fshipLife := fshipLife - (Random(15)+5);
end;

function TSpaceShip.CollisionWithOtherEnemyShip(const pos: TVector3): TEnemyShip;
var i: integer;
begin
 {jak widac, sprawdzamy powyzej czy enemyShips[i] <> Self zeby gdy wywolamy
  ta procedure z klasy TEnemySpaceShip nie otrzymac kolizji z samym
  soba.}
 for i := 0 to enemyShips.Count-1 do
  if (enemyShips[i] <> nil) and
    IsSpheresCollision(pos, shipRadius,
                       enemyShips[i].Translation, enemyShips[i].shipRadius) and
    (enemyShips[i] <> Self) then
   exit(enemyShips[i]);
 result := nil;
end;

{ TEnemyShip ---------------------------------------------------------------- }

constructor TEnemyShip.Create(const AKind: TEnemyShipKind; const AShipPos: TVector3);
begin
 inherited Create(EnemyShipKindsInfos[AKind].MaxLife);
 Add(EnemyShipScenes[AKind]);
 FKind := AKind;
 Translation := AShipPos;
 Up := Vector3(0, 0, 1);
 Direction := Vector3(1, 0, 0);
end;

destructor TEnemyShip.Destroy;
var
  Index: Integer;
begin
  if enemyShips <> nil then
  begin
    Index := enemyShips.IndexOf(Self);
    if Index <> -1 then
      enemyShips[Index] := nil;
  end;
  inherited;
end;

function TEnemyShip.ShipName: string;
begin
 result := EnemyShipKindsInfos[Kind].Name;
end;

procedure TEnemyShip.HitByRocket;
begin
 inherited;
 Notifications.Show('"'+ShipName+'" was hit by the rocket.');
 if ShipLife <= 0 then
 begin
  Notifications.Show('"'+ShipName+'" was destroyed.');
 end;
end;

procedure TEnemyShip.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if ShipLife <= 0 then
  begin
    RemoveMe := rtRemoveAndFree;
    enemyShips.Remove(Self);
  end;
end;

function TEnemyShip.ShipRadius: Single;
begin
 result := EnemyShipScenes[Kind].BoundingBox.AverageSize * Sqrt2/2;
end;

function TEnemyShip.TryShipMove(const NewTranslation: TVector3): boolean;
begin
 {jezeli mozna sie przesunac, to rusz sie; uwaga - nie uwzgledniamy tu
  ze statek moze tu przeleciec przez torpede lub przez statek gracza.
  Wszystko to dla prostoty i szybkosci.}

 result :=
   (not levelScene.InternalOctreeCollisions.IsSegmentCollision(Translation, NewTranslation,
     nil, false, nil)) and
   (CollisionWithOtherEnemyShip(NewTranslation) = nil) and
   MoveLimit.Contains(NewTranslation);
 if result then Translation := NewTranslation;
end;

{ TFiringRocketsEnemyShip ------------------------------------------------- }

constructor TFiringRocketsEnemyShip.Create(const AKind: TEnemyShipKind; const AShipPos: TVector3);
begin
 inherited;
 RocketFiringInited := false;
 FiringRocketsAllowed := true;
end;

procedure TFiringRocketsEnemyShip.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
 inherited;
 if RocketFiringInited then
 begin
  if TimerSeconds(Timer, LastFiredRocketTime) >= NextFireRocketDelay then
  begin
   if FiringRocketsAllowed then
    FireRocket(playerShip.Translation - Translation, 1);
   {w ten sposob statki beda strzelaly w dosc zroznicowanych odstepach czasu}
   LastFiredRocketTime := Timer;
   with EnemyShipKindsInfos[Kind] do
    NextFireRocketDelay := (FireDelay / 2) + Random * (FireDelay / 2);
  end;
 end else
 begin
  {ustalamy czas wystrzelenia pierwszej rakiety dopiero tutaj, naszym Update,
   zamiast w naszym konstruktorze bo po skonstruowaniu obiektu enemyShip
   w LoadLevel moze minac duzo czasu do poczatku gry - np. czas na ten MessageOK
   w ModeGameUnit.modeGameEnter; }
  LastFiredRocketTime := Timer;
  with EnemyShipKindsInfos[Kind] do
   NextFireRocketDelay := (FireDelay / 2) + Random * (FireDelay / 2);
  RocketFiringInited := true;
 end;
end;

{ TCircleMovingEnemyShip ------------------------------------------------------ }

procedure TCircleMovingEnemyShip.SetUniqueCircleMovingSpeed(const value: Single);
begin
 FUniqueCircleMovingSpeed := value;
 AngleRadChange:=
   10 {standardowa zmiana kata} *
   (1/CircleRadius) {obwod kola rosnie liniowo razem z promieniem;
      wiec jezeli np. zwiekszymy promien 2 razy to zwiekszymy tez
      obwod dwa razy a wiec statek musi sie poruszac 2 razy wolniej
      zeby miec taka sama szubkosc.} *
   EnemyShipKindsInfos[Kind].CircleMovingSpeed {zmodyfikuj szybkosc w
      zaleznosci od Kind} *
   UniqueCircleMovingSpeed {zmodyfikuj szybkosc w sposob szczegolny dla
      tego wlasnie statku};
end;

constructor TCircleMovingEnemyShip.Create(const AKind: TEnemyShipKind;
  const ACircleCenter: TVector3;
  const ACircleRadius, AUniqueCircleMovingSpeed: Single);
begin
 inherited Create(AKind, Vector3(ACircleCenter[0]+ACircleRadius,
   ACircleCenter[1], ACircleCenter[2]));

 FCircleRadius := ACircleRadius;
 FCircleCenter := ACircleCenter;
 AngleRad := 0;

 {ustawianie UniqueCircleMovingSpeed zainicjuje AngleRadChange od razu}
 UniqueCircleMovingSpeed := AUniqueCircleMovingSpeed;
end;

procedure TCircleMovingEnemyShip.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
var newAngleRad: Double;
    NewTranslation, NewDirection: TVector3;
begin
 inherited;

 newAngleRad := AngleRad + AngleRadChange * Window.Fps.SecondsPassed * 50;
 NewTranslation.X := cos(newAngleRad)*CircleRadius + CircleCenter.X;
 NewTranslation.Y := sin(newAngleRad)*CircleRadius + CircleCenter.Y;
 NewTranslation.Z := CircleCenter.Z;

 NewDirection := NewTranslation - Translation;

 if TryShipMove(NewTranslation) then
 begin
  Direction := NewDirection;
  AngleRad := newAngleRad;
 end else
  AngleRadChange := -AngleRadChange;
end;

{ THuntingEnemyShip ---------------------------------------------------------- }

procedure THuntingEnemyShip.SetHuntingAttack(value: boolean);
begin
 FHuntingAttack := value;
 { bylo tu FiringRocketsAllowed := value; ale niech jednak ZAWSZE strzela,
   nawet gdy ucieka - inaczej gracz bedzie mogl "przyprzec statek dpo muru"
   i spokojnie strzelac w nieruchomy statek. }
end;

procedure THuntingEnemyShip.Randomize;
begin
 RandomVector := Vector3(Random, Random, Random);
 RandomAngleDeg := 15+Random(15);
end;

constructor THuntingEnemyShip.Create(const AKind: TEnemyShipKind; const AShipPos: TVector3);
begin
 inherited;
 HuntingAttack := Boolean(Random(2));
 Randomize;
end;

procedure THuntingEnemyShip.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
 inherited;

 if ( HuntingAttack and
      ( PointsDistanceSqr(Translation, PlayerShip.Translation)<=
        Sqr((ShipRadius+PlayerShip.ShipRadius)*10) )
    ) or
    ( (not HuntingAttack) and
      (PointsDistanceSqr(Translation, PlayerShip.Translation) > Sqr(10000.0))
    ) then
  HuntingAttack := not HuntingAttack;

 {ustal Direction: dla HuntingAttack, shipDir kieruje sie w strone gracza,
  potem jest nieznacznie zmodyfikowany o maly obrot wokol losowej osi
   (zeby statek nie lecial DOKLADNIE na/od gracza, bo wtedy latwo
   go trafic ! Statek ma leciec tylko tak mniej-wiecej po torze w poblizu
   kolizyjnego !)
  ma dlugosc wzieta z PlayerDirectionLength o naszego HuntingSpeed,
  dla not HuntingAttack jest skierowany po prostu w druga strone.}
 Direction := PlayerShip.Translation - Translation;
 Direction := RotatePointAroundAxisDeg(RandomAngleDeg, Direction, RandomVector);
 Speed := 20 * EnemyShipKindsInfos[Kind].HuntingSpeed[HuntingAttack];
 if not HuntingAttack then
  Direction := -Direction;

 if not TryShipMove(Translation +
   Direction * Speed * Window.Fps.SecondsPassed * 50) then
 begin
  Randomize;
  HuntingAttack := not HuntingAttack
 end;
end;

{ TRocket ---------------------------------------------------------------- }

constructor TRocket.Create(const ArocPos, ArocDir: TVector3;
  const speed: Single; AmotherShip: TSpaceShip);
begin
  inherited Create(SceneManager);
  Translation := ArocPos;
  Direction := ArocDir;
  FSpeed := Speed * 50 * 50;
  FMotherShip := AMotherShip;
  Add(RocketScene);
end;

destructor TRocket.Destroy;
var
  Index: Integer;
begin
  if MotherShip <> nil then MotherShip.firedRockets.Remove(Self);
  if rockets <> nil then
  begin
    Index := rockets.IndexOf(Self);
    if Index <> -1 then
      rockets[Index] := nil;
  end;
  inherited;
end;

procedure TRocket.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
var NewTranslation: TVector3;

  function CollidesWith(ship: TSpaceShip): boolean;
  begin
   result := IsTunnelSphereCollision(Translation, NewTranslation, rocRadius,
     ship.Translation, ship.shipRadius);
  end;

var i: integer;
begin
 inherited;
 NewTranslation := Translation + Direction * FSpeed * Window.Fps.SecondsPassed;
 if (levelScene.InternalOctreeCollisions.IsSegmentCollision(Translation,
       NewTranslation, nil, false, nil)) or
    (not MoveLimit.Contains(Translation)) then
 begin
  {rakieta zderzyla sie z czescia levelu lub wyleciala poza MoveLimit}
  RemoveMe := rtRemoveAndFree;
  rockets.Remove(Self);
 end else
 begin
  {sprawdzamy czy rakieta zderzyla sie z jakims statkiem, naszym lub wroga.
   Uzywamy testowania kolizji na kulach. Jak widac rakieta nie moze
   uderzyc w swoj wlasny MotherShip - to dlatego ze na poczatku, gdy
   statek strzela, rakieta wylatuje zawsze ze statku i zawsze bylaby
   kolizja. Moglibysmy wysunac rakiete duzo do przodu i dac jej taka
   szybkosc zeby statek nie mogl jej dogonic ale to byloby skomplikowane.}
  for i := 0 to enemyShips.Count-1 do
   if (enemyShips[i] <> nil) and
     CollidesWith(enemyShips[i]) and (enemyShips[i] <> motherShip) then
   begin
    enemyShips[i].HitByRocket;
    RemoveMe := rtRemoveAndFree;
    rockets.Remove(Self);
    exit;
   end;

  if CollidesWith(playerShip) and (playerShip <> motherShip) then
  begin
   playerShip.HitByRocket;
   RemoveMe := rtRemoveAndFree;
   rockets.Remove(Self);
   exit
  end;

  {nie bylo zderzenia ? to lec dalej.}
  Translation := NewTranslation;
 end;
end;

class function TRocket.rocRadius: Single;
begin
 result := RocketScene.BoundingBox.AverageSize / 2;
end;

{ global funcs ----------------------------------------------------------- }

procedure ShipsAndRocketsUpdate;
begin
  if enemyShips.Count = 0 then
    Notifications.Show('ALL ENEMY SHIPS DESTROYED.');
end;

function NameShcutToEnemyShipKind(const ANameShcut: string): TEnemyShipKind;
begin
 for result := Low(result) to High(result) do
  if EnemyShipKindsInfos[result].NameShcut = ANameShcut then exit;
 raise Exception.Create('NameShcut ' +ANameShcut+
   ' doesn''t specify any EnemyShipKind');
end;

{ glw callbacks ------------------------------------------------------------- }

procedure ContextOpen;
var sk: TEnemyShipKind;
begin
 RocketScene := TCastleScene.Create(nil);
 RocketScene.Load('castle-data:/vrmls/rocket.wrl');
 RocketScene.Rotation := Vector4(0, 1, 0, -Pi / 2);
 RocketScene.Attributes.Lighting := false;

 for sk := Low(sk) to High(sk) do
 begin
  EnemyShipScenes[sk] := TCastleScene.Create(nil);
  EnemyShipScenes[sk].Rotation := Vector4(0, 1, 0, -Pi / 2);
  EnemyShipScenes[sk].Load('castle-data:/vrmls/' + EnemyShipKindsInfos[sk].VrmlFname);
 end;
end;

procedure ContextClose;
var sk: TEnemyShipKind;
begin
 FreeAndNil(RocketScene);
 for sk := Low(sk) to High(sk) do FreeAndNil(EnemyShipScenes[sk]);
end;

initialization
 TCastleTransform.DefaultOrientation := otUpZDirectionX;
 ApplicationProperties.OnGLContextOpen.Add(@ContextOpen);
 ApplicationProperties.OnGLContextClose.Add(@ContextClose);
end.
