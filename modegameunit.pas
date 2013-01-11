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

unit ModeGameUnit;

{ zeby wejsc w modeGame level musi byc loaded.
  I nie wolno robic FreeLevel dopoki jestesmy w modeGame. }

interface

implementation

uses CastleVectors, SysUtils, GL, CastleWindow, GameGeneral, CastleGLUtils,
  CastleUtils, LevelUnit, CastleBoxes, CastleMessages, PlayerShipUnit, CastleImages,
  ShipsAndRockets, CastleKeysMouse, CastleFilesUtils,
  CastleStringUtils, CastleScene, CastleGLImages, SkyCube, X3DNodes,
  CastleSceneManager, CastleUIControls, CastleCameras, Castle3D, CastleRenderingCamera;

var
  kokpit_gl: TGLImage;
  crossh_gl: TGLImage;
  sky: TSkyCube;
  {crossh_orig_* to oryginalne (tzn. wzgledem ekranu 640x480) rozmiary
   crosshair image (upakowanego w crossh_list) }
  crossh_orig_width, crossh_orig_height: integer;

{ TMalfunctionSceneManager --------------------------------------------------- }

type
  TMalfunctionSceneManager = class(TCastleSceneManager)
    procedure ApplyProjection; override;
    procedure RenderFromViewEverything; override;
    function Headlight(out CustomHeadlight: TAbstractLightNode): boolean; override;
  end;

procedure TMalfunctionSceneManager.ApplyProjection;
var
  projNear, projFar: TGLfloat;
  wholeMoveLimit: TBox3D;
begin
  { Player jest zawsze w obrebie MoveLimit i widzi rzeczy w obrebie
    levelScene.BoundingBox. Wiec far = dlugosc przekatnej
    Box3DSum(MoveLimit, levelScene.BoundingBox) bedzie na pewno wystarczajace.

    Near wybieramy arbitralnie jako PLAYER_SHIP_CAMERA_RADIUS. }
  projNear := PLAYER_SHIP_CAMERA_RADIUS;
  wholeMoveLimit := levelScene.BoundingBox + MoveLimit;
  projFar := PointsDistance(wholeMoveLimit.Data[0], wholeMoveLimit.Data[1]);
  PerspectiveProjection(30, Window.width/Window.height, projNear, projFar);

  if Sky = nil then
    sky := TSkyCube.Create(skiesDir +levelInfo.FdSky.Value, projNear, projFar);
end;

procedure TMalfunctionSceneManager.RenderFromViewEverything;

  procedure RenderAll(Params: TRenderParams);
  begin
    { TODO: RenderingCamera.Frustum is actually invalid, it's not derived from
      current camera. But we pass TestShapeVisibility = nil, and we don't use
      VisibilitySensor inside these models, so frustum value isn't really used.

      We should remake Level to be placed on scene manager,
      and camera updated when it should be, then this whole
      unit can be trivial. }

    levelScene.Render(nil, RenderingCamera.Frustum, Params);
    ShipsRender(Params);
    RocketsRender(Params);
  end;

var
  Params: TBasicRenderParams;
begin
  {no need to clear COLOR_BUFFER - sky will cover everything}
  glClear(GL_DEPTH_BUFFER_BIT);
  glLoadIdentity;

  glPushMatrix;
    playerShip.PlayerShipApplyMatrixNoTranslate;
    sky.Render;
  glPopMatrix;

  playerShip.PlayerShipApplyMatrix;

  Params := TBasicRenderParams.Create;
  try
    { Synchronize Camera with playerShip right before using BaseLights,
      as BaseLights initializes headlight based on Camera. }
    Camera.SetView(playerShip.shipPos,
      Normalized(playerShip.shipDir), playerShip.shipUp);
    Params.FBaseLights.Assign(BaseLights);

    Params.Transparent := false; Params.ShadowVolumesReceivers := false; RenderAll(Params);
    Params.Transparent := false; Params.ShadowVolumesReceivers := true ; RenderAll(Params);
    Params.Transparent := true ; Params.ShadowVolumesReceivers := false; RenderAll(Params);
    Params.Transparent := true ; Params.ShadowVolumesReceivers := true ; RenderAll(Params);
  finally FreeAndNil(Params) end;
end;

function TMalfunctionSceneManager.Headlight(out CustomHeadlight: TAbstractLightNode): boolean;
begin
  Result := true;
  CustomHeadlight := nil;
end;

{ TGame2DControls ------------------------------------------------------------ }

type
  TGame2DControls = class(TUIControl)
  public
    procedure Draw; override;
    function DrawStyle: TUIControlDrawStyle; override;
  end;

function TGame2DControls.DrawStyle: TUIControlDrawStyle;
begin
  Result := ds2D;
end;

procedure TGame2DControls.Draw;

  procedure radarDraw2D;
  const
    { na ekranie jest kwadrat radaru wielkosci Size oddalony od gornej
      i prawej krawedzi ekranu o ScreenMargin. We wnetrzu tego kwadratu
      w srodku jest mniejszy kwadrat wielkosci Size-2*InsideMargin
      i jego wnetrze odpowiada powierzchni XY MoveLimit. }
    ScreenMargin = 10;
    Size = 100;
    InsideMargin = 5;
  var
    MinInsideX, MaxInsideX, MinInsideY, MaxInsideY: Integer;

    procedure MoveLimitPosToPixel(const pos: TVector3Single; var x, y: TGLint);
    begin
     x := Round(MapRange(pos[0], MoveLimit.Data[0, 0], MoveLimit.Data[1, 0], MinInsideX, MaxInsideX));
     y := Round(MapRange(pos[1], MoveLimit.Data[0, 1], MoveLimit.Data[1, 1], MinInsideY, MaxInsideY));
    end;

  var
    i: integer;
    x, y: TGLint;
  begin
    MinInsideX := Window.Width - ScreenMargin - Size + InsideMargin;
    MaxInsideX := Window.Width - ScreenMargin - InsideMargin;
    MinInsideY := Window.Height - ScreenMargin - Size + InsideMargin;
    MaxInsideY := Window.Height - ScreenMargin - InsideMargin;

   glColor4f(0, 0, 0, 0.5);
   glRectf(Window.Width-ScreenMargin-Size, Window.Height-ScreenMargin-Size,
           Window.Width-ScreenMargin, Window.Height-ScreenMargin);

   MoveLimitPosToPixel(playerShip.shipPos, x, y);
   glColor4f(1, 1, 1, 0.8);
   glBegin(GL_LINES);
     glVertex2i(MinInsideX, y);  glVertex2i(MaxInsideX, y);
     glVertex2i(x, MinInsideY);  glVertex2i(x, MaxInsideY);
   glEnd;

   glColor4f(1, 1, 0, 0.8);
   glPointSize(2);
   glBegin(GL_POINTS);
     for i := 0 to enemyShips.Count-1 do
      if enemyShips[i] <> nil then
      begin
       MoveLimitPosToPixel(enemyShips[i].shipPos, x, y);
       glVertex2i(x, y);
      end;
   glEnd;
   glPointSize(1);
  end;

begin
 glLoadIdentity;
 glRasterPos2i(0, 0);

 glAlphaFunc(GL_GREATER, 0.5);
 glEnable(GL_ALPHA_TEST);
 kokpit_gl.Draw;
 glDisable(GL_ALPHA_TEST);

 if playerShip.drawCrosshair then
 begin
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_BLEND);
  glRasterPos2i(
    (Window.Width - crossh_orig_width) div 2,
    (Window.Height - crossh_orig_height) div 2);
  crossh_gl.Draw;
  glDisable(GL_BLEND);
 end;

 if playerShip.drawRadar then
 begin
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_BLEND);
  radarDraw2D;
  glDisable(GL_BLEND);
 end;

 playerShip.PlayerShipDraw2D;
end;

{ mode enter/exit ----------------------------------------------------------- }

var
  SceneManager: TMalfunctionSceneManager;
  Controls: TGame2DControls;
  Camera: TWalkCamera;

procedure Press(Window: TCastleWindowBase; const Event: TInputPressRelease); forward;
procedure idle(Window: TCastleWindowBase); forward;

procedure modeEnter;
begin
 Assert(levelScene <> nil,
   'Error - setting game mode to modeGame but level uninitialized');

 if (LevelScene.FogStack.Top <> nil) and
    (LevelScene.FogStack.Top.FdVolumetric.Value) and
    (not GL_EXT_fog_coord) then
   MessageOK(Window,
     'Your OpenGL implementation doesn''t support GL_EXT_fog_coord. '+
     'Everything will work correctly but the results will not be as beautiful '+
     'as they could be.');

 Window.Controls.Add(Controls);
 Window.Controls.Add(Notifications);
 Window.Controls.Add(SceneManager);

 Window.OnPress := @Press;
 Window.OnIdle := @idle;

 Window.AutoRedisplay := true;
end;

procedure modeExit;
begin
 glDisable(GL_DEPTH_TEST);
 glDisable(GL_LIGHTING);
 glDisable(GL_LIGHT0);

 { Check Window <> nil, as it may be already nil (during destruction)
   now in case of some errors }
 if Window <> nil then
   Window.AutoRedisplay := false;

 Window.Controls.Remove(Controls);
 Window.Controls.Remove(Notifications);

 Window.Controls.Remove(SceneManager);

 FreeAndNil(sky);
end;

{ glw callbacks ----------------------------------------------------------- }

procedure Press(Window: TCastleWindowBase; const Event: TInputPressRelease);
var fname: string;
begin
 if Event.EventType <> itKey then Exit;
 case Event.key of
  K_Space: playerShip.FireRocket(playerShip.shipDir, 1);
  K_Escape:
    if MessageYesNo(Window, 'End this game and return to menu ?') then
      SetGameMode(modeMenu);
  K_C:
    if Window.Pressed.Modifiers=[mkShift, mkCtrl] then
     with playerShip do CheatDontCheckCollisions := not CheatDontCheckCollisions else
    if Window.Pressed.Modifiers=[] then
     with playerShip do drawCrosshair := not drawCrosshair;
  K_I:
    if Window.Pressed[K_Shift] and Window.Pressed[K_Ctrl] then
     with playerShip do CheatImmuneToRockets := not CheatImmuneToRockets;
  K_R:
    with playerShip do drawRadar := not drawRadar;
  K_F5:
    begin
     fname := FileNameAutoInc(SUnformattable(UserConfigPath)+
       'malfunction_screen_%d.png');
     Window.SaveScreen(fname);
     Notifications.Show('Screen saved to '+fname);
    end;
 end;
end;

procedure idle(Window: TCastleWindowBase);
begin
 if playerShip.ShipLife <= 0 then
 begin
  MessageOK(Window,['Your ship has been destroyed !','Game over.']);
  SetGameMode(modeMenu);
  Exit;
 end;

 playerShip.PlayerShipIdle;
 ShipsAndRocketsIdle;
end;

{ Open/Close glwin -------------------------------------------------------- }

procedure WindowOpen(const Container: IUIContainer);
var crossh_img: TCastleImage;
    kokpit_img: TCastleImage;
begin
 kokpit_img := LoadImage(imagesDir +'kokpit.png',
   [TRGBAlphaImage, TGrayscaleAlphaImage]);
 try
  kokpit_img.Resize(Window.width, kokpit_img.Height * Window.Height div 480);
  kokpit_gl := TGLImage.Create(kokpit_img);
 finally kokpit_img.Free end;

 { przyjmujemy ze crosshair.png bylo przygotowane dla ekranu 640x480.
   Resizujemy odpowiednio do naszego okienka. }
 crossh_img := LoadImage(imagesDir +'crosshair.png',
   [TRGBAlphaImage, TGrayscaleAlphaImage]);
 try
  crossh_orig_width := crossh_img.Width;
  crossh_orig_height := crossh_img.Height;
  crossh_img.Resize(crossh_img.Width * Window.width div 640,
                    crossh_img.Height * Window.height div 480);
  crossh_gl := TGLImage.Create(crossh_img);
 finally crossh_img.Free end;
end;

procedure WindowClose(const Container: IUIContainer);
begin
  FreeAndNil(kokpit_gl);
  FreeAndNil(crossh_gl);
end;

initialization
 gameModeEnter[modeGame] := @modeEnter;
 gameModeExit[modeGame] := @modeExit;
 OnGLContextOpen.Add(@WindowOpen);
 OnGLContextClose.Add(@WindowClose);

 Controls := TGame2DControls.Create(nil);
 SceneManager := TMalfunctionSceneManager.Create(nil);
 Camera := TWalkCamera.Create(SceneManager);
 Camera.Input := [];
 SceneManager.Camera := Camera;
finalization
 FreeAndNil(Controls);
 FreeAndNil(SceneManager);
end.
