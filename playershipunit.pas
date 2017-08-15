{
  Copyright 2003-2017 Michalis Kamburelis.

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

unit PlayerShipUnit;

{
  Notka : Pamietaj ze ladowanie levelu moze tez jakos inicjowac playerShip.
    Dlatego zawsze dbaj aby przy inicjalizacji levelu playerShip JUZ byl
    zainicjowany.
}

{$I castleconf.inc}

interface

uses CastleBoxes, ShipsAndRockets, SysUtils, CastleGLUtils, CastleColors,
  CastleKeysMouse, CastleVectors;

const
  playerShipAbsoluteMaxSpeed = 45.0;
  playerShipAbsoluteMinSpeed = -20.0;

  { PLAYER_SHIP_CAMERA_RADIUS jest tak dobrane aby bylo mniej wiecej
    1/100 * przecietne projection far wyznaczane w ModeGamUnit. On wyznacza
    wielkosc projection near, a wiec nie moze byc za maly zeby Zbufor
    mial dobra dokladnosc. PLAYER_SHIP_RADIUS wyznacza PlayerShip.shipRadius
    dla kolizji i musi byc wieksze od PLAYER_SHIP_CAMERA_RADIUS.
    (bo inaczej bedzie widac jak near projection obcina obiekty) }
  PLAYER_SHIP_CAMERA_RADIUS = 80.0;
  PLAYER_SHIP_RADIUS = PLAYER_SHIP_CAMERA_RADIUS * 1.1;

type
  TPlayerShip = class(TSpaceShip)
  private
    FCheatDontCheckCollisions, FCheatImmuneToRockets: boolean;
    procedure SetCheatDontCheckCollisions(value: boolean);
    procedure SetCheatImmuneToRockets(value: boolean);
  private
    FadeOutIntensity: TGLfloat;
    FadeOutColor: TCastleColor; //< color's alpha doesn't matter
  public
    shipRotationSpeed: Single;
    shipVertRotationSpeed: Single;
    shipSpeed: Single;

    drawCrosshair: boolean; { = true }
    drawRadar: boolean;  { = true }

    { wszystkie Cheat sa rowne false po skonstruowaniu obiektu. }
    property CheatDontCheckCollisions: boolean read FCheatDontCheckCollisions
      write SetCheatDontCheckCollisions;
    property CheatImmuneToRockets: boolean read FCheatImmuneToRockets
      write SetCheatImmuneToRockets;

    { Make FadeOut with given Color. }
    procedure FadeOut(const Color: TCastleColor);

    { zawsze ran player ship przez WoundPlayerShip albo przynajmniej
      po zmniejszeniu ShipLife rob WoundedPlayerShip. To zapewnia
      odpowiedni message i ew. red-out dla gracza, i byc moze jakies
      inne efekty w przyszlosci. }
    procedure WoundPlayerShip(DecreaseLife: Single; const Messg: string); overload;
    procedure WoundedPlayerShip(const Messg: string); overload;

    constructor Create;
    destructor Destroy; override;

    procedure HitByRocket; override;
    function shipRadius: Single; override;

    { multiply curr OpenGL matrix by player ship camera matrix.
      "NoTranslate" version applies matrix not taking shipPos into account -
      - like if shipPos would be = (0, 0, 0). }
    procedure PlayerShipApplyMatrix;
    procedure PlayerShipApplyMatrixNoTranslate;
    { call PlayerShipUpdate in Update in modeGame }
    procedure PlayerShipUpdate;

    { draw some 2D things after displaying the scene. Current projection should
      be Ortho(0, 640, 0, 480) and all attribs should be set up for
      usual 2D drawing (no light, no depth test, no textures and so on).
      Ignores and modifies current matrix and color. }
    procedure PlayerShipDraw2d;
  end;

var
  playerShip: TPlayerShip;

{ uzywaj tego aby stworzyc nowy player ship. Automatyczne zajmie sie
  zwolnieniem playerShip jesli juz istanial. Acha, i nie martw sie o
  zwolnienie ostatniego playerShip : zostanie zwolnione w Window.Close. }
procedure NewPlayerShip;

implementation

uses CastleGL, GameGeneral, CastleWindow, CastleUtils, Math,
  LevelUnit, CastleMessages, CastleUIControls, CastleRectangles,
  CastleApplicationProperties;

constructor TPlayerShip.Create;
begin
 inherited Create(100);
 MaxFiredRocketsCount := 50;
 drawRadar := true;
 drawCrosshair := true;
end;

destructor TPlayerShip.Destroy;
begin
 inherited;
end;

procedure TPlayerShip.SetCheatDontCheckCollisions(value: boolean);
begin
 if FCheatDontCheckCollisions <> value then
 begin
  if value then
   Notifications.Show('CHEATER ! Collision checking off.') else
   Notifications.Show('Collision checking on.');
  FCheatDontCheckCollisions := value;
 end;
end;

procedure TPlayerShip.SetCheatImmuneToRockets(value: boolean);
begin
 if FCheatImmuneToRockets <> value then
 begin
  if value then
   Notifications.Show('CHEATER ! You''re immune to rockets.') else
   Notifications.Show('You''re no longer immune to rockets.');
  FCheatImmuneToRockets := value;
 end;
end;

procedure TPlayerShip.FadeOut(const color: TCastleColor);
begin
 FadeOutColor := color;
 FadeOutIntensity := 1;
end;

function TPlayerShip.shipRadius: Single;
begin
 result := PLAYER_SHIP_RADIUS;
end;

procedure TPlayerShip.WoundPlayerShip(DecreaseLife: Single; const Messg: string);
begin
 ShipLife := ShipLife - DecreaseLife;
 WoundedPlayership(Messg);
end;

procedure TPlayerShip.WoundedPlayerShip(const Messg: string);
begin
 Notifications.Show(Messg+' Ship damaged in '+IntToStr(Round(100-ShipLife))+'%.');
 FadeOut(Red);
end;

procedure TPlayerShip.HitByRocket;
begin
 inherited;
 if CheatImmuneToRockets then ShipLife := MaxShipLife;
 WoundedPlayerShip('You were hit by the rocket !');
end;

procedure TPlayerShip.PlayerShipApplyMatrix;
var shipCenter: TVector3Single;
begin
 shipCenter := VectorAdd(shipPos, shipDir);
 gluLookAt(shipPos[0], shipPos[1], shipPos[2],
           shipCenter[0], shipCenter[1], shipCenter[2],
           shipUp[0], shipUp[1], shipUp[2]);
end;

procedure TPlayerShip.PlayerShipApplyMatrixNoTranslate;
begin
 gluLookAt(0, 0, 0, shipDir[0], shipDir[1], shipDir[2],
                    shipUp[0] , shipUp[1] , shipUp[2]);
end;

procedure TPlayerShip.PlayerShipUpdate;

  procedure RotationSpeedBackToZero(var rotSpeed: Single;
    const rotSpeedChange: Single);
  { ship*RotationSpeed z czasem same wracaja do zera.
    Jezeli sa one bardzo blisko zera to juz nie wracamy ich do zera
    tylko ustawiamy je na zero - zeby nie bylo tak ze ich wartosci "skacza
    nad zerem" to na dodatnia to na ujemna strone. Granica wynosi
    (rotSpeedBack*2/3)*Window.UpdateSecondsPassed * 50 bo musi byc wieksza niz
    rotSpeedBack *Window.UpdateSecondsPassed * 50/2 (zeby zawsze przesuwajac sie o
    rotSpeedBack *Window.UpdateSecondsPassed * 50 trafic do tej granicy; chociaz tak naprawde
    Window.UpdateSecondsPassed zmienia sie w czasie wiec nic nie jest pewne). }
  var rotSpeedBack: Single;
  begin
   rotSpeedBack := rotSpeedChange * 2/5;
   if Abs(rotSpeed) < rotSpeedBack * 2/3 then
    rotSpeed := 0 else
    rotSpeed := rotSpeed - Sign(rotSpeed) * rotSpeedBack;
  end;

  procedure Crash(const DecreaseLife: Single; const CrashedWithWhat: string);
  begin
   if CrashedWithWhat <> '' then
    WoundPlayerShip(DecreaseLife, 'CRASHHH ! You crashed with '+CrashedWithWhat+' !') else
    WoundPlayerShip(DecreaseLife, 'CRASHHH ! You crashed !');
   shipSpeed := Clamped(-shipSpeed, playerShipAbsoluteMinSpeed, playerShipAbsoluteMaxSpeed);
  end;

const
  ROT_SPEED_CHANGE = 0.3;
  ROT_VERT_SPEED_CHANGE = 0.24;
  SPEED_CHANGE = 2;
var newShipPos, shipSideAxis: TVector3Single;
    sCollider: TEnemyShip;
    shipUpZSign: Single;
begin
 {odczytaj wcisniete klawisze}
 with Window do
 begin
  if Pressed[K_Left] then shipRotationSpeed += ROT_SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50;
  if Pressed[K_Right] then shipRotationSpeed -= ROT_SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50;
  if Pressed[K_Up] then shipVertRotationSpeed -= ROT_VERT_SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50;
  if Pressed[K_Down] then shipVertRotationSpeed += ROT_VERT_SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50;
  if Pressed[K_A] then shipSpeed := Math.min(playerShipAbsoluteMaxSpeed, shipSpeed + SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50);
  if Pressed[K_Z] then shipSpeed := Math.max(playerShipAbsoluteMinSpeed, shipSpeed - SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50);
 end;

 {move ship using shipSpeed,
  check for collisions with level using octree,
  check for collisions with enemyShips using simple sphere collision detecion}
 newShipPos := VectorAdd(shipPos, shipDir *
   (shipSpeed * Window.Fps.UpdateSecondsPassed * 50));
 if CheatDontCheckCollisions then
  shipPos := newShipPos else
 begin
  sCollider := CollisionWithOtherEnemyShip(newShipPos);
  if sCollider <> nil then
  begin
   Crash(Random(20)+20, '"'+sCollider.ShipName+'"');
   Notifications.Show('"'+sCollider.ShipName+'" was destroyed by the crash.');
   sCollider.Free;
  end else
  if not levelScene.InternalOctreeCollisions.MoveCollision(
    shipPos, newShipPos, true, shipRadius,
    { boxes will be just ignored } EmptyBox3D, EmptyBox3D) then
   Crash(Random(40)+40, '') else
   shipPos := newShipPos;
 end;

 {apply shipRotationSpeed variable and rotate ship around (0, 0, 1) or (0, 0, -1)
  (we use 1 or -1 to allow rotation direction consistent with keys left-right) }
 shipUpZSign := Sign(shipUp[2]);
 if shipUpZSign <> 0 then
 begin
  shipDir := RotatePointAroundAxisDeg(shipRotationSpeed * Window.Fps.UpdateSecondsPassed * 50, shipDir, Vector3Single(0, 0, shipUpZSign));
  shipUp := RotatePointAroundAxisDeg(shipRotationSpeed * Window.Fps.UpdateSecondsPassed * 50, shipUp, Vector3Single(0, 0, shipUpZSign));
 end;
 {apply speed vertical - here we will need shipSideAxis}
 shipSideAxis := VectorProduct(shipDir, shipUp);
 shipDir := RotatePointAroundAxisDeg(shipVertRotationSpeed * Window.Fps.UpdateSecondsPassed * 50, shipDir, shipSideAxis);
 shipUp := RotatePointAroundAxisDeg(shipVertRotationSpeed * Window.Fps.UpdateSecondsPassed * 50, shipUp, shipSideAxis);

 {decrease rotations speeds}
 RotationSpeedBackToZero(shipRotationSpeed, ROT_SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50);
 RotationSpeedBackToZero(shipVertRotationSpeed, ROT_VERT_SPEED_CHANGE * Window.Fps.UpdateSecondsPassed * 50);

 {apply shipPosBox}
 MoveLimit.ClampVar(shipPos);

 if FadeOutIntensity > 0 then
   FadeOutIntensity -= 0.02 * Window.Fps.UpdateSecondsPassed * 50;
end;

procedure TPlayerShip.PlayerShipDraw2d;
const
  {ponizsze stale musza byc skoordynowane z kokpit.png}
  SpeedRect: TRectangle = (Left: 80; Bottom: 20; Width: 30; Height: 70);
  LiveRect : TRectangle = (Left: 30; Bottom: 20; Width: 30; Height: 70);
  RectMargin = 2;
  kompasMiddle: TVector2f = (Data: (560, 480 - 428));
  kompasSrednica = 70;

  procedure DrawIndicator(R: TRectangle;
    const BorderColor, BGColor, InsideCol: TCastleColor;
    const Height, MinHeight, MaxHeight: Single);
  begin
    DrawRectangle(R, BorderColor);
    R := R.Grow(-RectMargin);
    DrawRectangle(R, BGColor);
    R.Height := Max(0, Round(MapRange(Height, MinHeight, MaxHeight, 0, R.Height)));
    DrawRectangle(R, InsideCol);
  end;

begin
  glLoadIdentity;

  { Sizes below are adjusted to 640x480, it's easiest to just scale
    to make them work for all window sizes }
  glScalef(Window.Width / 640, Window.Height / 480, 1);

  {draw speed and live indicators}
  DrawIndicator(speedRect, Yellow, Black, LightBlue,
    shipSpeed, playerShipAbsoluteMinSpeed, playerShipAbsoluteMaxSpeed);
  DrawIndicator(liveRect, Yellow, Black, Red,
    Math.max(shipLife, 0.0) , 0, MaxShipLife);

  {draw kompas arrow}
  glTranslatef(kompasMiddle[0], kompasMiddle[1], 0);
  glRotatef(RadToDeg(AngleRadPointToPoint(0, 0, shipDir[0], shipDir[1]))-90, 0, 0, 1);
  glScalef(10, kompasSrednica/2, 1);
  glTranslatef(0, -1, 0);
  glColorv(Yellow);
  GLDrawArrow(0.3, 0.8);

  {draw FadeOut}
  glLoadIdentity;
  GLFadeRectangleDark(Window.Rect, FadeOutColor, FadeOutIntensity);
end;

{ globa procs ------------------------------------------------------------ }

procedure NewPlayerShip;
begin
 FreeAndNil(PlayerShip);
 PlayerShip := TPlayerShip.Create;
end;

{ glw callbacks ----------------------------------------------------------- }

procedure ContextClose;
begin
 FreeAndNil(PlayerShip);
end;

initialization
 ApplicationProperties.OnGLContextClose.Add(@ContextClose);
end.
