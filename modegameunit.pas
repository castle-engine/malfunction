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

unit ModeGameUnit;

interface

uses X3DNodes, CastleSceneManager, CastleProjection, CastleTransform;

type
  TMalfunctionSceneManager = class(TCastleSceneManager)
  public
    procedure Update(const SecondsPassed: Single;
      var HandleInput: Boolean); override;
    procedure AdjustProjection;
  end;

var
  SceneManager: TMalfunctionSceneManager;

procedure PlayGame(const SceneURL: string);

implementation

uses SysUtils, Math,
  CastleWindow, GameGeneral, CastleGLUtils,
  CastleVectors, CastleUtils, LevelUnit, CastleBoxes, CastleMessages, PlayerShipUnit,
  CastleImages,
  ShipsAndRockets, CastleKeysMouse, CastleFilesUtils, CastleColors,
  CastleStringUtils, CastleScene, CastleGLImages,
  CastleUIControls, CastleCameras, CastleApplicationProperties,
  CastleRenderContext;

var
  kokpit_gl: TDrawableImage;
  crossh_gl: TDrawableImage;
  {crossh_orig_* to oryginalne (tzn. wzgledem ekranu 640x480) rozmiary
   crosshair image (upakowanego w crossh_list) }
  crossh_orig_width, crossh_orig_height: integer;

{ TMalfunctionSceneManager --------------------------------------------------- }

procedure TMalfunctionSceneManager.AdjustProjection;
var
  wholeMoveLimit: TBox3D;
const
  AngleOfViewY = 30;
begin
  Camera.ProjectionType := ptPerspective;
  Camera.Perspective.FieldOfView := DegToRad(AngleOfViewY);
  Camera.Perspective.FieldOfViewAxis := faVertical;
  Camera.ProjectionNear := PLAYER_SHIP_CAMERA_RADIUS;
  { Player jest zawsze w obrebie MoveLimit i widzi rzeczy w obrebie
    levelScene.BoundingBox. Wiec far = dlugosc przekatnej
    Box3DSum(MoveLimit, levelScene.BoundingBox) bedzie na pewno wystarczajace. }
  wholeMoveLimit := levelScene.BoundingBox + MoveLimit;
  Camera.ProjectionFar := PointsDistance(wholeMoveLimit.Data[0], wholeMoveLimit.Data[1]);
end;

procedure TMalfunctionSceneManager.Update(const SecondsPassed: Single;
  var HandleInput: Boolean);
begin
  inherited;
  Camera.SetView(
    playerShip.Translation,
    playerShip.Direction,
    playerShip.Up);
end;

{ TGame2DControls ------------------------------------------------------------ }

type
  TGame2DControls = class(TCastleUserInterface)
  public
    procedure Render; override;
  end;

procedure TGame2DControls.Render;

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

    procedure MoveLimitPosToPixel(const pos: TVector3; var x, y: TGLint);
    begin
     x := Round(MapRange(pos[0], MoveLimit.Data[0].X, MoveLimit.Data[1].X, MinInsideX, MaxInsideX));
     y := Round(MapRange(pos[1], MoveLimit.Data[0].Y, MoveLimit.Data[1].Y, MinInsideY, MaxInsideY));
    end;

  var
    i: integer;
    x, y: TGLint;
  begin
    // TODO: No direct drawing using GL fixed-function anymore
    (*

    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_BLEND);

    MinInsideX := Window.Width - ScreenMargin - Size + InsideMargin;
    MaxInsideX := Window.Width - ScreenMargin - InsideMargin;
    MinInsideY := Window.Height - ScreenMargin - Size + InsideMargin;
    MaxInsideY := Window.Height - ScreenMargin - InsideMargin;

    glColor4f(0, 0, 0, 0.5);
    glRectf(Window.Width-ScreenMargin-Size, Window.Height-ScreenMargin-Size,
            Window.Width-ScreenMargin, Window.Height-ScreenMargin);

    MoveLimitPosToPixel(playerShip.Translation, x, y);
    glColor4f(1, 1, 1, 0.8);
    glBegin(GL_LINES);
      glVertex2i(MinInsideX, y);  glVertex2i(MaxInsideX, y);
      glVertex2i(x, MinInsideY);  glVertex2i(x, MaxInsideY);
    glEnd;

    glColor4f(1, 1, 0, 0.8);
    RenderContext.PointSize := 2;
    glBegin(GL_POINTS);
      for i := 0 to enemyShips.Count-1 do
       if enemyShips[i] <> nil then
       begin
        MoveLimitPosToPixel(enemyShips[i].Translation, x, y);
        glVertex2i(x, y);
       end;
    glEnd;
    RenderContext.PointSize := 1;

    glDisable(GL_BLEND);
    *)
  end;

begin
 kokpit_gl.Draw(0, 0);

 if playerShip.drawCrosshair then
  crossh_gl.Draw(
    (Window.Width - crossh_orig_width) div 2,
    (Window.Height - crossh_orig_height) div 2);

 if playerShip.drawRadar then
  radarDraw2D;

 playerShip.PlayerShipDraw2D;
end;

{ mode enter/exit ----------------------------------------------------------- }

var
  Controls: TGame2DControls;

  { Set before SetGameMode(modeGame); }
  GameModeLevelUrl: String;

procedure Press(Container: TUIContainer; const Event: TInputPressRelease); forward;
procedure Update(Container: TUIContainer); forward;

procedure modeEnter;
begin
  Controls := TGame2DControls.Create(nil);
  SceneManager := TMalfunctionSceneManager.Create(nil);
  SceneManager.AutoNavigation := false;

  Window.Controls.InsertFront(SceneManager);
  Window.Controls.InsertFront(Controls);
  Window.Controls.InsertFront(Notifications);

  Window.OnPress := @Press;
  Window.OnUpdate := @Update;

  Window.AutoRedisplay := true;

  NewPlayerShip;
  LoadLevel(GameModeLevelUrl);

  // once LevelScene initialized
  SceneManager.AdjustProjection;
end;

procedure modeExit;
begin
  PlayerShip := nil; // will be freed be freeing SceneManager that owns it
  UnloadLevel;

  { Check Window <> nil, as it may be already nil (during destruction)
    now in case of some errors }
  if Window <> nil then
    Window.AutoRedisplay := false;

  Window.Controls.Remove(Controls);
  Window.Controls.Remove(Notifications);
  Window.Controls.Remove(SceneManager);

  FreeAndNil(Controls);
  FreeAndNil(SceneManager);
end;

procedure PlayGame(const SceneURL: string);
begin
  GameModeLevelUrl := SceneURL;
  SetGameMode(modeGame);
end;

{ glw callbacks ----------------------------------------------------------- }

procedure Press(Container: TUIContainer; const Event: TInputPressRelease);
var fname: string;
begin
  if Event.EventType <> itKey then Exit;
  case Event.key of
    keySpace: playerShip.FireRocket(playerShip.Direction, 1);
    keyEscape:
      if MessageYesNo(Window, 'End this game and return to menu ?') then
        SetGameMode(modeMenu);
    keyC:
      if Window.Pressed.Modifiers=[mkShift, mkCtrl] then
        with playerShip do CheatDontCheckCollisions := not CheatDontCheckCollisions else
      if Window.Pressed.Modifiers=[] then
        with playerShip do drawCrosshair := not drawCrosshair;
    keyI:
      if Window.Pressed[keyShift] and Window.Pressed[keyCtrl] then
        with playerShip do CheatImmuneToRockets := not CheatImmuneToRockets;
    keyR:
      with playerShip do drawRadar := not drawRadar;
    keyF5:
      begin
        fname := FileNameAutoInc('malfunction_screen_%d.png');
        Window.SaveScreen(fname);
        Notifications.Show('Screen saved to '+fname);
      end;
  end;
end;

procedure Update(Container: TUIContainer);
begin
  if playerShip.ShipLife <= 0 then
  begin
    MessageOK(Window,['Your ship has been destroyed !','Game over.']);
    SetGameMode(modeMenu);
    Exit;
  end;

  playerShip.PlayerShipUpdate;
  ShipsAndRocketsUpdate;
end;

{ Open/Close Window -------------------------------------------------------- }

procedure ContextOpen;
var
  crossh_img: TCastleImage;
  kokpit_img: TCastleImage;
begin
  kokpit_img := LoadImage('castle-data:/images/kokpit.png',
    [TRGBAlphaImage, TGrayscaleAlphaImage]);
  kokpit_img.Resize(Window.width, kokpit_img.Height * Window.Height div 480);
  kokpit_gl := TDrawableImage.Create(kokpit_img, false { smooth scaling }, true { owns image });

  { przyjmujemy ze crosshair.png bylo przygotowane dla ekranu 640x480.
    Resizujemy odpowiednio do naszego okienka. }
  crossh_img := LoadImage('castle-data:/images/crosshair.png',
    [TRGBAlphaImage, TGrayscaleAlphaImage]);
  crossh_orig_width := crossh_img.Width;
  crossh_orig_height := crossh_img.Height;
  crossh_img.Resize(crossh_img.Width * Window.width div 640,
                    crossh_img.Height * Window.height div 480);
  crossh_gl := TDrawableImage.Create(crossh_img, false { smooth scaling }, true { owns image });
end;

procedure ContextClose;
begin
  FreeAndNil(kokpit_gl);
  FreeAndNil(crossh_gl);
end;

initialization
  // TODO: we need EnableFixedFunction to work, as we do some rendering directly
  TGLFeatures.RequestCapabilities := rcForceFixedFunction;

  gameModeEnter[modeGame] := @modeEnter;
  gameModeExit[modeGame] := @modeExit;
  ApplicationProperties.OnGLContextOpen.Add(@ContextOpen);
  ApplicationProperties.OnGLContextClose.Add(@ContextClose);
end.
