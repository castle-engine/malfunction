{
  Copyright 2003-2005 Michalis Kamburelis.

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

uses SysUtils, GameGeneral, GLWindow, VRMLFlatSceneGL, VRMLFields, VRMLNodes,
  VRMLTriangleOctree, KambiClassUtils, OpenGLh, Boxes3d, VRMLShapeState;

type
  { levelType wplywa na wiele rzeczy. Ponizej bede dokumentowal sobie
    je wszystkie :
    - rozny levelType to roznie ustalany domyslny LevelBox w LoadLevel }
  TLevelType = (ltPlanet, ltSpace);

  TNodeMalfunctionLevelInfo = class(TVRMLNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;
    property FdSky: TSFString index 0 read GetFieldAsSFString;
    property FdType: TSFString index 1 read GetFieldAsSFString;
  end;

var
  levelScene: TVRMLFlatSceneGL;
  levelType: TLevelType;
  levelInfo: TNodeMalfunctionLevelInfo;
  LevelBox: TBox3d; { poza ten box nie moze NIC wyleciec }

{ Loading and free'ing level NEEDS active gl context.
  Zwalnianie nie zainicjowanego levelu nie powoduje bledu,
    po prostu nic nie robi.
  Poniewaz caly czas tylko jeden level na raz jest zainicjowany
    (w rezultacie czego zmienne w rodzaju levelScene moga byc
    zwyczajne, globalne, a nie opakowane w jakas klase "TLevel")
    level jest zawsze automatycznie zwalniany przed kazdym LoadLevel
    i w czasie glw.EventClose. W rezultacie wlasciwie mozesz nigdy nie
    wywolywac FreeLevel z zewnatrz tego modulu.
  LoadLevel jest odpowiedzialne za czesciowa inicjalizacje PlayerShip.  }
procedure LoadLevel(const vrmlSceneFName: string);
procedure FreeLevel;

{ LoadGame loads NewPlayer and then loads LoadLevel and then
  SetGameMode(modeGame) (so it raises EExitFromGLWinEvent) }
procedure PlayGame(const vrmlSceneFName: string);

implementation

uses VectorMath, KambiUtils, PlayerShipUnit, ShipsAndRockets,
  TimeMessages, GLWinMessages;

{ TNodeMalfunctionInfo ----------------------------------------------- }

constructor TNodeMalfunctionLevelInfo.Create(const ANodeName: string; const AWWWBasePath: string);
begin
 inherited;
 Fields.Add(TSFString.Create('sky', ''));
 Fields.Add(TSFString.Create('type', 'planet'));
end;

class function TNodeMalfunctionLevelInfo.ClassNodeTypeName: string;
begin
 result := 'MalfunctionLevelInfo';
end;

{ enemy ship nodes ------------------------------------------------------------ }

type
  TNodeGeneralMalfunctionEnemy = class(TVRMLNode)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    property FdKind: TSFString index 0 read GetFieldAsSFString;
    function Kind: TEnemyShipKind;
    function CreateEnemyShip: TEnemyShip; virtual; abstract;
  end;

  TNodeMalfunctionNotMovingEnemy = class(TNodeGeneralMalfunctionEnemy)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;
    property FdPosition: TSFVec3f index 1 read GetFieldAsSFVec3f;
    function CreateEnemyShip: TEnemyShip; override;
  end;

  TNodeMalfunctionCircleMovingEnemy = class(TNodeGeneralMalfunctionEnemy)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;
    property FdCircleCenter: TSFVec3f index 1 read GetFieldAsSFVec3f;
    property FdCircleRadius: TSFFloat index 2 read GetFieldAsSFFloat;
    property FdUniqueCircleMovingSpeed: TSFFloat index 3 read GetFieldAsSFFloat;
    function CreateEnemyShip: TEnemyShip; override;
  end;

  TNodeMalfunctionHuntingEnemy = class(TNodeGeneralMalfunctionEnemy)
    constructor Create(const ANodeName: string; const AWWWBasePath: string); override;
    class function ClassNodeTypeName: string; override;
    property FdPosition: TSFVec3f index 1 read GetFieldAsSFVec3f;
    function CreateEnemyShip: TEnemyShip; override;
  end;

constructor TNodeGeneralMalfunctionEnemy.Create(const ANodeName: string; const AWWWBasePath: string);
begin
 inherited;
 Fields.Add(TSFString.Create('kind', 'hedgehog'));
end;

function TNodeGeneralMalfunctionEnemy.Kind: TEnemyShipKind;
begin
 result := NameShcutToEnemyShipKind(FdKind.Value);
end;

constructor TNodeMalfunctionNotMovingEnemy.Create(const ANodeName: string; const AWWWBasePath: string);
begin
 inherited;
 Fields.Add(TSFVec3f.Create('position', Vector3Single(0, 0, 0)));
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
 Fields.Add(TSFVec3f.Create('circleCenter', Vector3Single(0, 0, 0)));
 Fields.Add(TSFFloat.Create('circleRadius', 1.0));
 Fields.Add(TSFFloat.Create('uniqueCircleMovingSpeed', 1.0));
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
 Fields.Add(TSFVec3f.Create('position', Vector3Single(0, 0, 0)));
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
   EnemyShips.Add(TNodeGeneralMalfunctionEnemy(node).CreateEnemyShip);
  end;

procedure LoadLevel(const vrmlSceneFName: string);
var vMiddle, vSizes: TVector3Single;
    halfMaxSize: Single;
    LevelBoxIndex: integer;
begin
 FreeLevel;

 try
  levelScene := TVRMLFlatSceneGL.Create(ParseVRMLFile(vrmlSceneFName, false),
    true, roSceneAsAWhole);
  levelScene.Attributes.UseLights := true;
  levelScene.Attributes.FirstGLFreeLight := 1; { swiatla 0 bedziemy uzywac }
  levelScene.GetPerspectiveViewpoint(playerShip.shipPos, playerShip.shipDir, playerShip.shipUp);
  levelInfo := TNodeMalfunctionLevelInfo(levelScene.RootNode.FindNode(TNodeMalfunctionLevelInfo, true));
  levelType := TLevelType(ArrayPosText(levelInfo.FdType.Value, ['planet', 'space'] ));

  { This causes much better much, see e.g. on lake.wrl level
    when looking at textures in the distance (e.g. at the plate texture). }
  levelScene.Attributes.TextureMinFilter := GL_LINEAR_MIPMAP_LINEAR;

  { Calculate LevelBox }
  LevelBoxIndex := levelScene.ShapeStates.IndexOfShapeWithParentNamed('LevelBox');
  if LevelBoxIndex <> -1 then
  begin
   { When node with name 'LevelBox' is found, then we calculate our
     LevelBox from this node (and we delete 'LevelBox' from the scene,
     as it should not be visible).
     This way we can comfortably set LevelBox from Blender. }
   LevelBox := levelScene.ShapeStates[LevelBoxIndex].BoundingBox;
   levelScene.ShapeStates[LevelBoxIndex].ShapeNode.FreeRemovingFromAllParentNodes;
   levelScene.ChangedAll;
  end else
  begin
   {ustal domyslnego LevelBoxa na podstawie levelScene.BoundingBox}
   if levelType = ltSpace then
   begin
    {ustalamy shipPosBox na box o srodku tam gdzie levelScene.BoundingBox
     i rozmiarach piec razy wiekszych niz najwiekszy rozmiar
     levelScene.BounxingBox.}
    vSizes := Box3dSizes(levelScene.BoundingBox);
    halfMaxSize := max(vSizes[0], vSizes[1], vSizes[2])* 2.5;
    vSizes := Vector3f(halfMaxSize, halfMaxSize, halfMaxSize);
    vMiddle := Box3dMiddle(levelScene.BoundingBox);
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
  levelScene.DefaultTriangleOctree :=
    levelScene.CreateTriangleOctree('Loading ...');

  rockets := TRocketsList.Create;

  {read enemy ships from file}
  enemyShips := TEnemyShipsList.Create;
  levelScene.RootNode.EnumerateNodes(TNodeGeneralMalfunctionEnemy,
    TEnemiesConstructor.ConstructEnemy, true);

  {reset some ship variables}
  playerShip.shipRotationSpeed := 0.0;
  playerShip.shipVertRotationSpeed := 0.0;
  playerShip.shipSpeed := 5;

  { zeby pierwsze OnDraw gry nie zajmowalo zbyt duzo czasu zeby enemyShips
    nie strzelaly od razu kilkoma rakietami na starcie po zaladowaniu
    levelu. }
  levelScene.PrepareRender(true, true, false, false);

  TimeMsg.Clear;
  TimeMsg.Show('Level '+vrmlSceneFName+' loaded.');
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

procedure CloseGLWin(glwin: TGLWindow);
begin
 FreeLevel;
end;

initialization
 glw.OnCloseList.AppendItem(@CloseGLWin);
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

