{
  Copyright 2003-2010 Michalis Kamburelis.

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
   it's VRML scene, sky images and so on.

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

   - DEF LevelBox <dowolny-node-o-niepustym-BoundingBox> { ... }
     taki node jest dozwolony (chociaz nie wymagany).
     Jezeli go znajdziemy to wymiary LevelBox'a beda wziete z wymiarow
     BoundingBox'a tego node'a (a sam node bedzie usuniety ze sceny,
     zeby nie byl nigdy renderowany i nie bylo z nim kolizji...).
     Jezeli nie bedzie takiego node'a na scenie to zostanie obliczony pewien
     domyslny zazwyczaj sensowny LevelBox (bedzie roznie liczony w zaleznosci
     od LevelType)

   - To nie jest specjalne (kiedys bylo specjalne, kiedys byly zamiast tego
     DEF PlayerStartPos/Dir/Up Info) ale i tak warto o tym wspomniec:
     poczatkowa pozycja i kierunek lotu i pion statku sa odczytywane
     z ustawienia kamery (tylko PerspectiveCamera) w VRMLach levelu.

     BTW, zgodnie z ustaleniami na poczatku VRMLNodes, dlugosc camera-dir
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

uses SysUtils, GameGeneral, GLWindow, VRMLGLScene, VRMLFields, VRMLNodes,
  VRMLTriangleOctree, KambiClassUtils, GL, GLU, GLExt, Boxes3D, VRMLShape,
  KambiGLUtils;

type
  { levelType wplywa na wiele rzeczy. Ponizej bede dokumentowal sobie
    je wszystkie :
    - rozny levelType to roznie ustalany domyslny LevelBox w LoadLevel }
  TLevelType = (ltPlanet, ltSpace);

  TNodeMalfunctionLevelInfo = class(TVRMLNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;

    private FFdSky: TSFString;
    public property FdSky: TSFString read FFdSky;

    private FFdType: TSFString;
    public property FdType: TSFString read FFdType;
  end;

var
  levelScene: TVRMLGLScene;
  levelType: TLevelType;
  levelInfo: TNodeMalfunctionLevelInfo;
  LevelBox: TBox3D; { poza ten box nie moze NIC wyleciec }

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
procedure LoadLevel(const vrmlSceneFName: string);
procedure FreeLevel;

{ LoadGame loads NewPlayer and then loads LoadLevel and then
  SetGameMode(modeGame).
  
  You should terminate any TGLWindow event handling after PlayGame call. }
procedure PlayGame(const vrmlSceneFName: string);

implementation

uses VectorMath, KambiUtils, PlayerShipUnit, ShipsAndRockets,
  GLNotifications, GLWinMessages, VRMLScene;

{ TNodeMalfunctionInfo ----------------------------------------------- }

constructor TNodeMalfunctionLevelInfo.Create(const ANodeName: string; const AWWWBasePath: string);
begin
  inherited;

  FFdsky := TSFString.Create(Self, 'sky', '');
  Fields.Add(FFdsky);

  FFdtype := TSFString.Create(Self, 'type', 'planet');
  Fields.Add(FFdtype);
end;

class function TNodeMalfunctionLevelInfo.ClassNodeTypeName: string;
begin
  result := 'MalfunctionLevelInfo';
end;

{ enemy ship nodes ------------------------------------------------------------ }

type
  TVRMLMalfunctionEnemyNode = class(TVRMLNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;

    private FFdKind: TSFString;
    public property FdKind: TSFString read FFdKind;

    function Kind: TEnemyShipKind;
    function CreateEnemyShip: TEnemyShip; virtual; abstract;
  end;

  TNodeMalfunctionNotMovingEnemy = class(TVRMLMalfunctionEnemyNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;

    private FFdPosition: TSFVec3f;
    public property FdPosition: TSFVec3f read FFdPosition;

    function CreateEnemyShip: TEnemyShip; override;
  end;

  TNodeMalfunctionCircleMovingEnemy = class(TVRMLMalfunctionEnemyNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;

    private FFdCircleCenter: TSFVec3f;
    public property FdCircleCenter: TSFVec3f read FFdCircleCenter;

    private FFdCircleRadius: TSFFloat;
    public property FdCircleRadius: TSFFloat read FFdCircleRadius;

    private FFdUniqueCircleMovingSpeed: TSFFloat;
    public property FdUniqueCircleMovingSpeed: TSFFloat read FFdUniqueCircleMovingSpeed;

    function CreateEnemyShip: TEnemyShip; override;
  end;

  TNodeMalfunctionHuntingEnemy = class(TVRMLMalfunctionEnemyNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;

    private FFdPosition: TSFVec3f;
    public property FdPosition: TSFVec3f read FFdPosition;

    function CreateEnemyShip: TEnemyShip; override;
  end;

constructor TVRMLMalfunctionEnemyNode.Create(const ANodeName: string; const AWWWBasePath: string);
begin
  inherited;

  FFdkind := TSFString.Create(Self, 'kind', 'hedgehog');
  Fields.Add(FFdkind);
end;

function TVRMLMalfunctionEnemyNode.Kind: TEnemyShipKind;
begin
  result := NameShcutToEnemyShipKind(FdKind.Value);
end;

constructor TNodeMalfunctionNotMovingEnemy.Create(const ANodeName: string; const AWWWBasePath: string);
begin
  inherited;

  FFdposition := TSFVec3f.Create(Self, 'position', Vector3Single(0, 0, 0));
  Fields.Add(FFdposition);
end;

class function TNodeMalfunctionNotMovingEnemy.ClassNodeTypeName: string;
begin
  result := 'MalfunctionNotMovingEnemy';
end;

function TNodeMalfunctionNotMovingEnemy.CreateEnemyShip: TEnemyShip;
begin
  result := TNotMovingEnemyShip.Create(Kind, FdPosition.Value);
end;

constructor TNodeMalfunctionCircleMovingEnemy.Create(const ANodeName: string; const AWWWBasePath: string);
begin
  inherited;

  FFdcircleCenter := TSFVec3f.Create(Self, 'circleCenter', Vector3Single(0, 0, 0));
  Fields.Add(FFdcircleCenter);

  FFdcircleRadius := TSFFloat.Create(Self, 'circleRadius', 1.0);
  Fields.Add(FFdcircleRadius);

  FFduniqueCircleMovingSpeed := TSFFloat.Create(Self, 'uniqueCircleMovingSpeed', 1.0);
  Fields.Add(FFduniqueCircleMovingSpeed);
end;

class function TNodeMalfunctionCircleMovingEnemy.ClassNodeTypeName: string;
begin
  result := 'MalfunctionCircleMovingEnemy';
end;

function TNodeMalfunctionCircleMovingEnemy.CreateEnemyShip: TEnemyShip;
begin
  result := TCircleMovingEnemyShip.Create(Kind, FdCircleCenter.Value,
    FdCircleRadius.Value, FdUniqueCircleMovingSpeed.Value);
end;

constructor TNodeMalfunctionHuntingEnemy.Create(const ANodeName: string; const AWWWBasePath: string);
begin
  inherited;

  FFdposition := TSFVec3f.Create(Self, 'position', Vector3Single(0, 0, 0));
  Fields.Add(FFdposition);
end;

class function TNodeMalfunctionHuntingEnemy.ClassNodeTypeName: string;
begin
  result := 'MalfunctionHuntingEnemy';
end;

function TNodeMalfunctionHuntingEnemy.CreateEnemyShip: TEnemyShip;
begin
  result := THuntingEnemyShip.Create(Kind, FdPosition.Value);
end;

{ -------------------------------------------------------------------- }

type
  TEnemiesConstructor = class
    class procedure ConstructEnemy(node: TVRMLNode);
  end;

  class procedure TEnemiesConstructor.ConstructEnemy(node: TVRMLNode);
  begin
   EnemyShips.Add(TVRMLMalfunctionEnemyNode(node).CreateEnemyShip);
  end;

procedure LoadLevel(const vrmlSceneFName: string);
var vMiddle, vSizes: TVector3Single;
    halfMaxSize: Single;
    LevelBoxShape: TVRMLShape;
    EnemiesConstructor: TEnemiesConstructor;
    DummyGravityUp: TVector3Single;
begin
 FreeLevel;

 try
  levelScene := TVRMLGLScene.Create(nil);
  levelScene.Load(vrmlSceneFName);
  levelScene.GetPerspectiveViewpoint(playerShip.shipPos, playerShip.shipDir,
    playerShip.shipUp,
    { We don't need GravityUp, we know it should be +Z in malfunction
      levels. }
    DummyGravityUp);
  levelInfo := TNodeMalfunctionLevelInfo(levelScene.RootNode.FindNode(TNodeMalfunctionLevelInfo, true));
  levelType := TLevelType(ArrayPosText(levelInfo.FdType.Value, ['planet', 'space'] ));

  { Calculate LevelBox }
  LevelBoxShape := levelScene.Shapes.FindBlenderMesh('LevelBox');
  if LevelBoxShape <> nil then
  begin
   { When node with name 'LevelBox' is found, then we calculate our
     LevelBox from this node (and we delete 'LevelBox' from the scene,
     as it should not be visible).
     This way we can comfortably set LevelBox from Blender. }
   LevelBox := LevelBoxShape.BoundingBox;
   levelScene.RemoveShapeGeometry(LevelBoxShape);
  end else
  begin
   {ustal domyslnego LevelBoxa na podstawie levelScene.BoundingBox}
   if levelType = ltSpace then
   begin
    {ustalamy shipPosBox na box o srodku tam gdzie levelScene.BoundingBox
     i rozmiarach piec razy wiekszych niz najwiekszy rozmiar
     levelScene.BounxingBox.}
    vSizes := Box3DSizes(levelScene.BoundingBox);
    halfMaxSize := max(vSizes[0], vSizes[1], vSizes[2])* 2.5;
    vSizes := Vector3Single(halfMaxSize, halfMaxSize, halfMaxSize);
    vMiddle := Box3DMiddle(levelScene.BoundingBox);
    LevelBox[0] := VectorSubtract(vMiddle, vSizes);
    LevelBox[1] := VectorAdd(vMiddle, vSizes);
   end else
   begin
    {Ustalamy shipPosBox na box levelu, za wyjatkiem z-ta ktorego przedluzamy
       5 razy. Czyli nie pozwalamy statkowi wyleciec poza x, y-levelu ani ponizej
       z-ow, ale moze wzleciec dosc wysoko ponad z-ty.}
    LevelBox := levelScene.BoundingBox;
    LevelBox[1, 2] := LevelBox[1, 2]+4*(LevelBox[1, 2]-LevelBox[0, 2]);
   end;
  end;

  {pamietaj ze konstruowanie octree musi byc PO ew. usunieciu node'a LevelBoxXY}
  levelScene.TriangleOctreeProgressTitle := 'Loading ...';
  levelScene.Spatial := [ssDynamicCollisions];

  rockets := TRocketsList.Create;

  {read enemy ships from file}
  enemyShips := TEnemyShipsList.Create;
  levelScene.RootNode.EnumerateNodes(TVRMLMalfunctionEnemyNode,
    @EnemiesConstructor.ConstructEnemy, true);

  {reset some ship variables}
  playerShip.shipRotationSpeed := 0.0;
  playerShip.shipVertRotationSpeed := 0.0;
  playerShip.shipSpeed := 5;

  { zeby pierwsze OnDraw gry nie zajmowalo zbyt duzo czasu zeby enemyShips
    nie strzelaly od razu kilkoma rakietami na starcie po zaladowaniu
    levelu. }
  levelScene.PrepareResources([prRender, prBackground, prBoundingBox], false);

  Notifications.Clear;
  Notifications.Show('Level '+vrmlSceneFName+' loaded.');
 except FreeLevel; raise end;
end;

procedure FreeLevel;
begin
 FreeAndNil(levelScene);
 FreeWithContentsAndNil(rockets);
 FreeWithContentsAndNil(enemyShips);
end;

procedure PlayGame(const vrmlSceneFName: string);
begin
 NewPlayerShip;
 LoadLevel(vrmlSceneFName);
 SetGameMode(modeGame);
end;

{ glw callbacks ----------------------------------------------------------- }

procedure CloseGLWin(Window: TGLWindow);
begin
 FreeLevel;
end;

initialization
 Window.OnCloseList.Add(@CloseGLWin);
 NodesManager.RegisterNodeClasses([ TNodeMalfunctionLevelInfo,
   TNodeMalfunctionNotMovingEnemy,
   TNodeMalfunctionCircleMovingEnemy,
   TNodeMalfunctionHuntingEnemy ]);
end.

{ ---------------------------------------
  OLD UNUSED (but possibly not outdated) CODE:

  function SceneInfoNodeToVector3Single(const nodeName: string): TVector3Single;
  begin
   result := Vector3SingleFromStr(
    (levelScene.RootNode.FindNodeByName(nodeName, false) as TNodeInfo).FdString.Value);
  end;
}

