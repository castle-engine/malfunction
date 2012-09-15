{
  Copyright 2003-2012 Michalis Kamburelis.

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
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

  ----------------------------------------------------------------------------
}

unit LevelUnit;

(* this unit keeps track of the whole state of current level :
   it's 3D scene, sky images and so on.

   Notka o wspolrzednych : ziemia to dla nas XY, pion to os Z.
   Ja tak lubie, tak napisalem SkyCube, kompas tez zwraca kierunek
   w plaszczyznie XY i wreszcie nawet Blender domyslnie uznaje Z
   jako pion.

   Specjalne rzeczy jakie odczytujemy z VRMLa:

   - Dokladnie jeden taki node MUSI byc obecny na kazdym levelu :
     MalfunctionLevelInfo {
       SFString sky  ""           # nazwa nieba istniejacego w skiesDir
       SFString type "planet"
         # Dopuszczalne wartosci : "planet" i "space".
         # Patrz typ TLevelType w tym module.
     }

   - Dowolnie wiele node'ow definiujacych enemy ships :
     MalfunctionNotMoving {
       SFString kind "hedgehog"
         # mozliwe wartosci EnemyShipKindsInfos[].NameShcut w LevelUnit
       SFVec3f position 0 0 0
     }
     MalfunctionCircleMoving {
       SFString kind "hedgehog"
         # mozliwe wartosci EnemyShipKindsInfos[].NameShcut w LevelUnit
       SFVec3f circleCenter 0 0 0
       SFFloat circleRadius 1
       SFFloat uniqueCircleMovingSpeed 1
     }
     MalfunctionHunting {
       SFString kind "hedgehog"
         # mozliwe wartosci EnemyShipKindsInfos[].NameShcut w LevelUnit
       SFVec3f position 0 0 0
     }

   - DEF CasMoveLimit <dowolny-node-o-niepustym-BoundingBox> { ... }
     taki node jest dozwolony (chociaz nie wymagany).
     Jezeli go znajdziemy to wymiary MoveLimit'a beda wziete z wymiarow
     BoundingBox'a tego node'a (a sam node bedzie usuniety ze sceny,
     zeby nie byl nigdy renderowany i nie bylo z nim kolizji...).
     Jezeli nie bedzie takiego node'a na scenie to zostanie obliczony pewien
     domyslny zazwyczaj sensowny MoveLimit (bedzie roznie liczony w zaleznosci
     od LevelType)

   - To nie jest specjalne (kiedys bylo specjalne, kiedys byly zamiast tego
     DEF PlayerStartPos/Dir/Up Info) ale i tak warto o tym wspomniec:
     poczatkowa pozycja i kierunek lotu i pion statku sa odczytywane
     z ustawienia kamery (tylko PerspectiveCamera) w VRMLach levelu.

     BTW, zgodnie z ustaleniami na poczatku X3DNodes, dlugosc camera-dir
     jest bez znaczenia (uzywamy TFlatScene.GetCamera ktore zawsze zwraca
     znormalizowany CamDir).
     Robimy to takze po to zeby statek gracza zawsze latal z taka sama
     predkoscia (w stosunku do predkosci i wielkosci torped; no i powinienes
     tak przeskalowac level zeby graczowi wydawalo sie ze podobne obiekty
     przesuwaja sie z podobna szybkoscia).

   Notka - wszystkie levele musza byc zrobione w tej samej skali,
   chociazby po to zeby torpedy i alienships mogly byc zawsze renderowane
   w odpowiedniej wielkosci. Po co mielibysmy zaprzatac sobie glowe
   skalowaniem torped i alienshipow ?
   Prosciej przeskalowac level dodajac mu prosty node Scale.
*)

interface

uses SysUtils, GameGeneral, CastleWindow, CastleScene, X3DFields, X3DNodes,
  CastleClassUtils, Boxes3D, Shape, CastleGLUtils;

type
  { levelType wplywa na wiele rzeczy. Ponizej bede dokumentowal sobie
    je wszystkie :
    - rozny levelType to roznie ustalany domyslny MoveLimit w LoadLevel }
  TLevelType = (ltPlanet, ltSpace);

  TMalfunctionLevelInfoNode = class(TX3DNode)
    procedure CreateNode; override;
    class function ClassNodeTypeName: string; override;

    private FFdSky: TSFString;
    public property FdSky: TSFString read FFdSky;

    private FFdType: TSFString;
    public property FdType: TSFString read FFdType;
  end;

var
  levelScene: TCastleScene;
  levelType: TLevelType;
  levelInfo: TMalfunctionLevelInfoNode;
  MoveLimit: TBox3D; { poza ten box nie moze NIC wyleciec }

{ Loading and free'ing level NEEDS active gl context.
  Zwalnianie nie zainicjowanego levelu nie powoduje bledu,
    po prostu nic nie robi.
  Poniewaz caly czas tylko jeden level na raz jest zainicjowany
    (w rezultacie czego zmienne w rodzaju levelScene moga byc
    zwyczajne, globalne, a nie opakowane w jakas klase "TLevel")
    level jest zawsze automatycznie zwalniany przed kazdym LoadLevel
    i w czasie Window.EventClose. W rezultacie wlasciwie mozesz nigdy nie
    wywolywac FreeLevel z zewnatrz tego modulu.
  LoadLevel jest odpowiedzialne za czesciowa inicjalizacje PlayerShip.  }
procedure LoadLevel(const SceneFileName: string);
procedure FreeLevel;

{ LoadGame loads NewPlayer and then loads LoadLevel and then
  SetGameMode(modeGame).

  You should terminate any TCastleWindowBase event handling after PlayGame call. }
procedure PlayGame(const SceneFileName: string);

implementation

uses VectorMath, CastleUtils, PlayerShipUnit, ShipsAndRockets,
  CastleMessages, CastleSceneCore, UIControls;

{ TMalfunctionInfoNode ----------------------------------------------- }

procedure TMalfunctionLevelInfoNode.CreateNode;
begin
  inherited;

  FFdsky := TSFString.Create(Self, 'sky', '');
  Fields.Add(FFdsky);

  FFdtype := TSFString.Create(Self, 'type', 'planet');
  Fields.Add(FFdtype);
end;

class function TMalfunctionLevelInfoNode.ClassNodeTypeName: string;
begin
  result := 'MalfunctionLevelInfo';
end;

{ enemy ship nodes ------------------------------------------------------------ }

type
  TVRMLMalfunctionEnemyNode = class(TX3DNode)
    procedure CreateNode; override;

    private FFdKind: TSFString;
    public property FdKind: TSFString read FFdKind;

    function Kind: TEnemyShipKind;
    function CreateEnemyShip: TEnemyShip; virtual; abstract;
  end;

  TMalfunctionNotMovingEnemyNode = class(TVRMLMalfunctionEnemyNode)
    procedure CreateNode; override;
    class function ClassNodeTypeName: string; override;

    private FFdPosition: TSFVec3f;
    public property FdPosition: TSFVec3f read FFdPosition;

    function CreateEnemyShip: TEnemyShip; override;
  end;

  TMalfunctionCircleMovingEnemyNode = class(TVRMLMalfunctionEnemyNode)
    procedure CreateNode; override;
    class function ClassNodeTypeName: string; override;

    private FFdCircleCenter: TSFVec3f;
    public property FdCircleCenter: TSFVec3f read FFdCircleCenter;

    private FFdCircleRadius: TSFFloat;
    public property FdCircleRadius: TSFFloat read FFdCircleRadius;

    private FFdUniqueCircleMovingSpeed: TSFFloat;
    public property FdUniqueCircleMovingSpeed: TSFFloat read FFdUniqueCircleMovingSpeed;

    function CreateEnemyShip: TEnemyShip; override;
  end;

  TMalfunctionHuntingEnemyNode = class(TVRMLMalfunctionEnemyNode)
    procedure CreateNode; override;
    class function ClassNodeTypeName: string; override;

    private FFdPosition: TSFVec3f;
    public property FdPosition: TSFVec3f read FFdPosition;

    function CreateEnemyShip: TEnemyShip; override;
  end;

procedure TVRMLMalfunctionEnemyNode.CreateNode;
begin
  inherited;

  FFdkind := TSFString.Create(Self, 'kind', 'hedgehog');
  Fields.Add(FFdkind);
end;

function TVRMLMalfunctionEnemyNode.Kind: TEnemyShipKind;
begin
  result := NameShcutToEnemyShipKind(FdKind.Value);
end;

procedure TMalfunctionNotMovingEnemyNode.CreateNode;
begin
  inherited;

  FFdposition := TSFVec3f.Create(Self, 'position', Vector3Single(0, 0, 0));
  Fields.Add(FFdposition);
end;

class function TMalfunctionNotMovingEnemyNode.ClassNodeTypeName: string;
begin
  result := 'MalfunctionNotMovingEnemy';
end;

function TMalfunctionNotMovingEnemyNode.CreateEnemyShip: TEnemyShip;
begin
  result := TNotMovingEnemyShip.Create(Kind, FdPosition.Value);
end;

procedure TMalfunctionCircleMovingEnemyNode.CreateNode;
begin
  inherited;

  FFdcircleCenter := TSFVec3f.Create(Self, 'circleCenter', Vector3Single(0, 0, 0));
  Fields.Add(FFdcircleCenter);

  FFdcircleRadius := TSFFloat.Create(Self, 'circleRadius', 1.0);
  Fields.Add(FFdcircleRadius);

  FFduniqueCircleMovingSpeed := TSFFloat.Create(Self, 'uniqueCircleMovingSpeed', 1.0);
  Fields.Add(FFduniqueCircleMovingSpeed);
end;

class function TMalfunctionCircleMovingEnemyNode.ClassNodeTypeName: string;
begin
  result := 'MalfunctionCircleMovingEnemy';
end;

function TMalfunctionCircleMovingEnemyNode.CreateEnemyShip: TEnemyShip;
begin
  result := TCircleMovingEnemyShip.Create(Kind, FdCircleCenter.Value,
    FdCircleRadius.Value, FdUniqueCircleMovingSpeed.Value);
end;

procedure TMalfunctionHuntingEnemyNode.CreateNode;
begin
  inherited;

  FFdposition := TSFVec3f.Create(Self, 'position', Vector3Single(0, 0, 0));
  Fields.Add(FFdposition);
end;

class function TMalfunctionHuntingEnemyNode.ClassNodeTypeName: string;
begin
  result := 'MalfunctionHuntingEnemy';
end;

function TMalfunctionHuntingEnemyNode.CreateEnemyShip: TEnemyShip;
begin
  result := THuntingEnemyShip.Create(Kind, FdPosition.Value);
end;

{ -------------------------------------------------------------------- }

type
  TEnemiesConstructor = class
    class procedure ConstructEnemy(node: TX3DNode);
  end;

  class procedure TEnemiesConstructor.ConstructEnemy(node: TX3DNode);
  begin
   EnemyShips.Add(TVRMLMalfunctionEnemyNode(node).CreateEnemyShip);
  end;

procedure LoadLevel(const SceneFileName: string);
var
  vMiddle, vSizes: TVector3Single;
  halfMaxSize: Single;
  MoveLimitShape: TShape;
  EnemiesConstructor: TEnemiesConstructor;
  DummyGravityUp: TVector3Single;
  BaseLights: TLightInstancesList;
begin
 FreeLevel;

 try
  levelScene := TCastleScene.Create(nil);
  levelScene.Load(SceneFileName);
  levelScene.GetPerspectiveViewpoint(playerShip.shipPos, playerShip.shipDir,
    playerShip.shipUp,
    { We don't need GravityUp, we know it should be +Z in malfunction
      levels. }
    DummyGravityUp);
  levelInfo := TMalfunctionLevelInfoNode(levelScene.RootNode.FindNode(TMalfunctionLevelInfoNode, true));
  levelType := TLevelType(ArrayPosText(levelInfo.FdType.Value, ['planet', 'space'] ));

  { Calculate MoveLimit }
  MoveLimitShape := levelScene.Shapes.FindBlenderMesh('CasMoveLimit');
  if MoveLimitShape <> nil then
  begin
   { When node with name 'CasMoveLimit' is found, then we calculate our
     MoveLimit from this node (and we delete 'CasMoveLimit' from the scene,
     as it should not be visible).
     This way we can comfortably set MoveLimit from Blender. }
   MoveLimit := MoveLimitShape.BoundingBox;
   levelScene.RemoveShapeGeometry(MoveLimitShape);
  end else
  begin
   {ustal domyslnego MoveLimit na podstawie levelScene.BoundingBox}
   if levelType = ltSpace then
   begin
    {ustalamy shipPosBox na box o srodku tam gdzie levelScene.BoundingBox
     i rozmiarach piec razy wiekszych niz najwiekszy rozmiar
     levelScene.BounxingBox.}
    vSizes := levelScene.BoundingBox.Sizes;
    halfMaxSize := max(vSizes[0], vSizes[1], vSizes[2])* 2.5;
    vSizes := Vector3Single(halfMaxSize, halfMaxSize, halfMaxSize);
    vMiddle := levelScene.BoundingBox.Middle;
    MoveLimit.Data[0] := VectorSubtract(vMiddle, vSizes);
    MoveLimit.Data[1] := VectorAdd(vMiddle, vSizes);
   end else
   begin
    {Ustalamy shipPosBox na box levelu, za wyjatkiem z-ta ktorego przedluzamy
       5 razy. Czyli nie pozwalamy statkowi wyleciec poza x, y-levelu ani ponizej
       z-ow, ale moze wzleciec dosc wysoko ponad z-ty.}
    MoveLimit := levelScene.BoundingBox;
    MoveLimit.Data[1, 2] := MoveLimit.Data[1, 2] +
                       4 * (MoveLimit.Data[1, 2] -
                            MoveLimit.Data[0, 2]);
   end;
  end;

  {pamietaj ze konstruowanie octree musi byc PO ew. usunieciu node'a MoveLimitXY}
  levelScene.TriangleOctreeProgressTitle := 'Loading ...';
  levelScene.Spatial := [ssDynamicCollisions];

  rockets := TRocketList.Create(false);

  {read enemy ships from file}
  enemyShips := TEnemyShipList.Create(false);
  levelScene.RootNode.EnumerateNodes(TVRMLMalfunctionEnemyNode,
    @EnemiesConstructor.ConstructEnemy, true);

  {reset some ship variables}
  playerShip.shipRotationSpeed := 0.0;
  playerShip.shipVertRotationSpeed := 0.0;
  playerShip.shipSpeed := 5;

  { zeby pierwsze OnDraw gry nie zajmowalo zbyt duzo czasu zeby enemyShips
    nie strzelaly od razu kilkoma rakietami na starcie po zaladowaniu
    levelu. }
  { TODO: it's not clean to create BaseLights here,
    we should use SceneManager.BaseLights }
  BaseLights := TLightInstancesList.Create;
  try
    levelScene.PrepareResources([prRender, prBackground, prBoundingBox], false, BaseLights);
  finally FreeAndNil(BaseLights) end;

  Notifications.Clear;
  Notifications.Show('Level '+SceneFileName+' loaded.');
 except FreeLevel; raise end;
end;

procedure FreeLevel;
begin
 FreeAndNil(levelScene);
 if rockets <> nil then
 begin
   rockets.FreeObjects := true;
   FreeAndNil(rockets);
 end;
 if enemyShips <> nil then
 begin
   enemyShips.FreeObjects := true;
   FreeAndNil(enemyShips);
 end;
end;

procedure PlayGame(const SceneFileName: string);
begin
 NewPlayerShip;
 LoadLevel(SceneFileName);
 SetGameMode(modeGame);
end;

{ glw callbacks ----------------------------------------------------------- }

procedure WindowClose(const Container: IUIContainer);
begin
 FreeLevel;
end;

initialization
 OnGLContextClose.Add(@WindowClose);
 NodesManager.RegisterNodeClasses([ TMalfunctionLevelInfoNode,
   TMalfunctionNotMovingEnemyNode,
   TMalfunctionCircleMovingEnemyNode,
   TMalfunctionHuntingEnemyNode ]);
end.
