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

unit PlayerShipUnit;

{
  Notka : Pamietaj ze ladowanie levelu moze tez jakos inicjowac playerShip.
    Dlatego zawsze dbaj aby przy inicjalizacji levelu playerShip JUZ byl
    zainicjowany.
}

interface

uses GL, CastleBoxes, ShipsAndRockets, SysUtils, CastleGLUtils, CastleColors,
  CastleKeysMouse;

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
    FadeOutColor: TVector3f;
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
    procedure FadeOut(const Color: TVector3f);

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
    { call PlayerShipIdle in idle in modeGame }
    procedure PlayerShipIdle;

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

uses GLU, CastleVectors, GameGeneral, CastleWindow, CastleUtils, Math,
  LevelUnit, CastleMessages, UIControls;

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

procedure TPlayerShip.FadeOut(const color: TVector3f);
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
 FadeOut(Red3Single);
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

procedure TPlayerShip.PlayerShipIdle;

  procedure RotationSpeedBackToZero(var rotSpeed: Single;
    const rotSpeedChange: Single);
  { ship*RotationSpeed z czasem same wracaja do zera.
    Jezeli sa one bardzo blisko zera to juz nie wracamy ich do zera
    tylko ustawiamy je na zero - zeby nie bylo tak ze ich wartosci "skacza
    nad zerem" to na dodatnia to na ujemna strone. Granica wynosi
    (rotSpeedBack*2/3)*Window.IdleSpeed * 50 bo musi byc wieksza niz
    rotSpeedBack *Window.IdleSpeed * 50/2 (zeby zawsze przesuwajac sie o
    rotSpeedBack *Window.IdleSpeed * 50 trafic do tej granicy; chociaz tak naprawde
    Window.IdleSpeed zmienia sie w czasie wiec nic nie jest pewne). }
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
  if Pressed[K_Left] then shipRotationSpeed += ROT_SPEED_CHANGE * Window.Fps.IdleSpeed * 50;
  if Pressed[K_Right] then shipRotationSpeed -= ROT_SPEED_CHANGE * Window.Fps.IdleSpeed * 50;
  if Pressed[K_Up] then shipVertRotationSpeed -= ROT_VERT_SPEED_CHANGE * Window.Fps.IdleSpeed * 50;
  if Pressed[K_Down] then shipVertRotationSpeed += ROT_VERT_SPEED_CHANGE * Window.Fps.IdleSpeed * 50;
  if Pressed[K_A] then shipSpeed := CastleUtils.min(playerShipAbsoluteMaxSpeed, shipSpeed + SPEED_CHANGE * Window.Fps.IdleSpeed * 50);
  if Pressed[K_Z] then shipSpeed := CastleUtils.max(playerShipAbsoluteMinSpeed, shipSpeed - SPEED_CHANGE * Window.Fps.IdleSpeed * 50);
 end;

 {move ship using shipSpeed,
  check for collisions with level using octree,
  check for collisions with enemyShips using simple sphere collision detecion}
 newShipPos := VectorAdd(shipPos, VectorScale(shipDir,
   shipSpeed * Window.Fps.IdleSpeed * 50));
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
  if not levelScene.OctreeCollisions.MoveCollision(
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
  shipDir := RotatePointAroundAxisDeg(shipRotationSpeed * Window.Fps.IdleSpeed * 50, shipDir, Vector3Single(0, 0, shipUpZSign));
  shipUp := RotatePointAroundAxisDeg(shipRotationSpeed * Window.Fps.IdleSpeed * 50, shipUp, Vector3Single(0, 0, shipUpZSign));
 end;
 {apply speed vertical - here we will need shipSideAxis}
 shipSideAxis := VectorProduct(shipDir, shipUp);
 shipDir := RotatePointAroundAxisDeg(shipVertRotationSpeed * Window.Fps.IdleSpeed * 50, shipDir, shipSideAxis);
 shipUp := RotatePointAroundAxisDeg(shipVertRotationSpeed * Window.Fps.IdleSpeed * 50, shipUp, shipSideAxis);

 {decrease rotations speeds}
 RotationSpeedBackToZero(shipRotationSpeed, ROT_SPEED_CHANGE * Window.Fps.IdleSpeed * 50);
 RotationSpeedBackToZero(shipVertRotationSpeed, ROT_VERT_SPEED_CHANGE * Window.Fps.IdleSpeed * 50);

 {apply shipPosBox}
 MoveLimit.Clamp(shipPos);

 if FadeOutIntensity > 0 then
   FadeOutIntensity -= 0.02 * Window.Fps.IdleSpeed * 50;
end;

procedure TPlayerShip.PlayerShipDraw2d;
type TRect2d = array[0..1]of TVector2Single;
const
  {ponizsze stale musza byc skoordynowane z kokpit.png}
  speedRect: TRect2d = ((80, 20), (110, 90));
  liveRect: TRect2d = ((30, 20), (60, 90));
  RectMargin = 2.0;
  kompasMiddle: TVector2f = (560, 480-428);
  kompasSrednica = 70;

  procedure DrawIndicator(const r: TRect2d; const BorderColor, BGColor,
    InsideCol: TVector4f; const Height, MinHeight, MaxHeight: Single);
  begin
   drawGLBorderedRectangle(r[0, 0], r[0, 1], r[1, 0], r[1, 1], BGColor, BorderColor);
   glColorv(InsideCol);
   glRectf(r[0, 0]+RectMargin, r[0, 1]+RectMargin, r[1, 0]-RectMargin,
     MapRange(Height, MinHeight, MaxHeight,
       r[0, 1]+RectMargin, r[1, 1]-RectMargin));
  end;

begin
  glLoadIdentity;

  { Sizes below are adjusted to 640x480, it's easiest to just scale
    to make them work for all window sizes }
  glScalef(Window.Width / 640, Window.Height / 480, 1);

  {draw speed and live indicators}
  DrawIndicator(speedRect, Yellow4Single, Black4Single, LightBlue4Single,
    shipSpeed, playerShipAbsoluteMinSpeed, playerShipAbsoluteMaxSpeed);
  DrawIndicator(liveRect, Yellow4Single, Black4Single, Red4Single,
    CastleUtils.max(shipLife, 0.0) , 0, MaxShipLife);

  {draw kompas arrow}
  glTranslatef(kompasMiddle[0], kompasMiddle[1], 0);
  glRotatef(RadToDeg(AngleRadPointToPoint(0, 0, shipDir[0], shipDir[1]))-90, 0, 0, 1);
  glScalef(10, kompasSrednica/2, 1);
  glTranslatef(0, -1, 0);
  glColorv(Yellow3Single);
  drawArrow(0.3, 0.8);

  {draw FadeOut}
  glLoadIdentity;
  GLFadeRectangle(0, 0, Window.Width, Window.Height, FadeOutColor, FadeOutIntensity);
end;

{ globa procs ------------------------------------------------------------ }

procedure NewPlayerShip;
begin
 FreeAndNil(PlayerShip);
 PlayerShip := TPlayerShip.Create;
end;

{ glw callbacks ----------------------------------------------------------- }

procedure WindowOpen(const Container: IUIContainer);
begin
end;

procedure WindowClose(const Container: IUIContainer);
begin
 FreeAndNil(PlayerShip);
end;

initialization
 OnGLContextOpen.Add(@WindowOpen);
 OnGLContextClose.Add(@WindowClose);
end.
