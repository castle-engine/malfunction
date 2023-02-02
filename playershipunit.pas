{
  Copyright 2003-2023 Michalis Kamburelis.

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
  CastleApplicationProperties, CastleInternalGLUtils;

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

procedure TPlayerShip.PlayerShipUpdate;

  procedure RotationSpeedBackToZero(var rotSpeed: Single;
    const rotSpeedChange: Single);
  { ship*RotationSpeed z czasem same wracaja do zera.
    Jezeli sa one bardzo blisko zera to juz nie wracamy ich do zera
    tylko ustawiamy je na zero - zeby nie bylo tak ze ich wartosci "skacza
    nad zerem" to na dodatnia to na ujemna strone. Granica wynosi
    (rotSpeedBack*2/3)*Window.SecondsPassed * 50 bo musi byc wieksza niz
    rotSpeedBack *Window.SecondsPassed * 50/2 (zeby zawsze przesuwajac sie o
    rotSpeedBack *Window.SecondsPassed * 50 trafic do tej granicy; chociaz tak naprawde
    Window.SecondsPassed zmienia sie w czasie wiec nic nie jest pewne). }
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
var
  NewTranslation, shipSideAxis, T: TVector3;
  sCollider: TEnemyShip;
  UpZSign: Single;
begin
 {odczytaj wcisniete klawisze}
 with Window do
 begin
  if Pressed[keyArrowLeft] then shipRotationSpeed += ROT_SPEED_CHANGE * Window.Fps.SecondsPassed * 50;
  if Pressed[keyArrowRight] then shipRotationSpeed -= ROT_SPEED_CHANGE * Window.Fps.SecondsPassed * 50;
  if Pressed[keyArrowUp] then shipVertRotationSpeed -= ROT_VERT_SPEED_CHANGE * Window.Fps.SecondsPassed * 50;
  if Pressed[keyArrowDown] then shipVertRotationSpeed += ROT_VERT_SPEED_CHANGE * Window.Fps.SecondsPassed * 50;
  if Pressed[keyA] then shipSpeed := Math.min(playerShipAbsoluteMaxSpeed, shipSpeed + SPEED_CHANGE * Window.Fps.SecondsPassed * 50);
  if Pressed[keyZ] then shipSpeed := Math.max(playerShipAbsoluteMinSpeed, shipSpeed - SPEED_CHANGE * Window.Fps.SecondsPassed * 50);
 end;

 {move ship using shipSpeed,
  check for collisions with level using octree,
  check for collisions with enemyShips using simple sphere collision detecion}
 NewTranslation := Translation + Direction *
   (shipSpeed * Window.Fps.SecondsPassed * 50);
 if CheatDontCheckCollisions then
  Translation := NewTranslation else
 begin
  sCollider := CollisionWithOtherEnemyShip(NewTranslation);
  if sCollider <> nil then
  begin
   Crash(Random(20)+20, '"'+sCollider.ShipName+'"');
   Notifications.Show('"'+sCollider.ShipName+'" was destroyed by the crash.');
   sCollider.Free;
  end else
  if not levelScene.InternalOctreeCollisions.MoveCollision(
    Translation, NewTranslation, true, shipRadius,
    { boxes will be just ignored } TBox3D.Empty, TBox3D.Empty) then
   Crash(Random(40)+40, '') else
   Translation := NewTranslation;
 end;

 {apply shipRotationSpeed variable and rotate ship around (0, 0, 1) or (0, 0, -1)
  (we use 1 or -1 to allow rotation direction consistent with keys left-right) }
 UpZSign := Sign(Up[2]);
 if UpZSign <> 0 then
 begin
  Direction := RotatePointAroundAxisDeg(shipRotationSpeed * Window.Fps.SecondsPassed * 50, Direction, Vector3(0, 0, UpZSign));
  Up := RotatePointAroundAxisDeg(shipRotationSpeed * Window.Fps.SecondsPassed * 50, Up, Vector3(0, 0, UpZSign));
 end;
 {apply speed vertical - here we will need shipSideAxis}
 shipSideAxis := TVector3.CrossProduct(Direction, Up);
 Direction := RotatePointAroundAxisDeg(shipVertRotationSpeed * Window.Fps.SecondsPassed * 50, Direction, shipSideAxis);
 Up := RotatePointAroundAxisDeg(shipVertRotationSpeed * Window.Fps.SecondsPassed * 50, Up, shipSideAxis);

 {decrease rotations speeds}
 RotationSpeedBackToZero(shipRotationSpeed, ROT_SPEED_CHANGE * Window.Fps.SecondsPassed * 50);
 RotationSpeedBackToZero(shipVertRotationSpeed, ROT_VERT_SPEED_CHANGE * Window.Fps.SecondsPassed * 50);

 {apply MoveLimit}
 T := Translation;
 MoveLimit.ClampVar(T);
 Translation := T;

 if FadeOutIntensity > 0 then
   FadeOutIntensity -= 0.02 * Window.Fps.SecondsPassed * 50;
end;

procedure TPlayerShip.PlayerShipDraw2d;
const
  {ponizsze stale musza byc skoordynowane z kokpit.png}
  SpeedRect: TRectangle = (Left: 80; Bottom: 20; Width: 30; Height: 70);
  LiveRect : TRectangle = (Left: 30; Bottom: 20; Width: 30; Height: 70);
  RectMargin = 2;
  kompasMiddle: TVector2 = (X: 560; Y: 52);
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

  { Draw arrow shape. Arrow is placed on Z = 0 plane, points to the up,
    has height = 2 (from y = 0 to y = 2) and width 1 (from x = -0.5 to 0.5).

    Everything is drawn CCW when seen from standard view (x grows right, y up).
    Uses current OpenGL color. }
  procedure GLDrawArrow(HeadThickness: TGLfloat = 0.4;
    HeadLength: TGLfloat = 0.5);
  begin
    HeadLength := 2*HeadLength; { map HeadLength to 0..2 }

    glBegin(GL_TRIANGLES);
      glVertex2f(0, 2);
      glVertex2f(-1, HeadLength);
      glVertex2f(-HeadThickness, HeadLength);

      glVertex2f(0, 2);
      glVertex2f(-HeadThickness, HeadLength);
      glVertex2f(HeadThickness, HeadLength);

      glVertex2f(0, 2);
      glVertex2f(HeadThickness, HeadLength);
      glVertex2f(1, HeadLength);
    glEnd;

    glBegin(GL_QUADS);
      glVertex2f(-HeadThickness, HeadLength);
      glVertex2f(-HeadThickness, 0);
      glVertex2f(HeadThickness, 0);
      glVertex2f(HeadThickness, HeadLength);
    glEnd;
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
  { TODO: seems to be drawn at wrong position now }
  glTranslatef(kompasMiddle[0], kompasMiddle[1], 0);
  glRotatef(RadToDeg(AngleRadPointToPoint(0, 0, Direction[0], Direction[1]))-90, 0, 0, 1);
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
