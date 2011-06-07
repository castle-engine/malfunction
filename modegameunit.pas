{
  Copyright 2003-2011 Michalis Kamburelis.

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

uses VectorMath, SysUtils, GL, GLU, GLExt, GLWindow, GameGeneral, KambiGLUtils,
  KambiUtils, LevelUnit, Boxes3D, GLWinMessages, PlayerShipUnit, Images,
  ShipsAndRockets, GLNotifications, KeysMouse, KambiFilesUtils,
  KambiStringUtils, VRMLGLScene, GLImages, SkyCube, VRMLNodes, Base3D;

var kokpitbg_list: TGLuint;
    crossh_list: TGLuint;
    sky: TSkyCube;
    {crossh_orig_* to oryginalne (tzn. wzgledem ekranu 640x480) rozmiary
     crosshair image (upakowanego w crossh_list) }
    crossh_orig_width, crossh_orig_height: integer;

{ mode enter/exit ----------------------------------------------------------- }

procedure draw(Window: TGLWindow); forward;
procedure KeyDown(Window: TGLWindow; key: TKey; c: char); forward;
procedure idle(Window: TGLWindow); forward;

procedure modeEnter;
var projNear, projFar: TGLfloat;
    wholeLevelBox: TBox3D;
begin
 Assert(levelScene <> nil,
   'Error - setting game mode to modeGame but level uninitialized');

 {teraz rzecz ktorej nie mozemy spieprzyc bo bedziemy mieli niedokladny Zbufor:
  near i far projection.

  Player jest zawsze w obrebie levelBox i widzi rzeczy w obrebie
  levelScene.BoundingBox. Wiec far = dlugosc przekatnej
  Box3DSum(levelBox, levelScene.BoundingBox) bedzie na pewno wystarczajace.

  Near wybieramy arbitralnie jako PLAYER_SHIP_CAMERA_RADIUS. }
 projNear := PLAYER_SHIP_CAMERA_RADIUS;
 wholeLevelBox := Box3DSum(levelScene.BoundingBox, levelBox);
 projFar := PointsDistance(wholeLevelBox[0], wholeLevelBox[1]);
 ProjectionGLPerspective(30, Window.width/Window.height, projNear, projFar);

 glEnable(GL_DEPTH_TEST);
 glEnable(GL_LIGHTING);

 {default OpenGL light 0 properties :}
 glLightv(GL_LIGHT0, GL_AMBIENT, Black4Single);
 glLightv(GL_LIGHT0, GL_DIFFUSE, White4Single);
 glLightv(GL_LIGHT0, GL_SPECULAR, White4Single);
 glLightv(GL_LIGHT0, GL_POSITION, Vector4Single(0, 0, 1, 0));
 glLighti(GL_LIGHT0, GL_SPOT_CUTOFF, 180);
 glEnable(GL_LIGHT0);

 if (LevelScene.FogNode <> nil) and
    (LevelScene.FogNode.FdVolumetric.Value) and
    (not GL_EXT_fog_coord) then
   MessageOK(Window,
     'Your OpenGL implementation doesn''t support GL_EXT_fog_coord. '+
     'Everything will work correctly but the results will not be as beatiful '+
     'as they could be.');

 Window.OnDraw := @draw;
 Window.OnKeyDown := @KeyDown;
 Window.OnIdle := @idle;

 Window.AutoRedisplay := true;

 sky := TSkyCube.Create(skiesDir +levelInfo.FdSky.Value, projNear, projFar);
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

 FreeAndNil(sky);
end;

{ glw callbacks ----------------------------------------------------------- }

procedure draw2d(draw2dData: Pointer);

  procedure radarDraw2D;
  const
    { na ekranie jest kwadrat radaru wielkosci Size oddalony od gornej
      i prawej krawedzi ekranu o ScreenMargin. We wnetrzu tego kwadratu
      w srodku jest mniejszy kwadrat wielkosci Size-2*InsideMargin
      i jego wnetrze odpowiada powierzchni XY levelBoxa. }
    ScreenMargin = 10;
    Size = 100;
    InsideMargin = 5;
    MinInsideX = 640-ScreenMargin-Size+InsideMargin;
    MaxInsideX = 640-ScreenMargin-InsideMargin;
    MinInsideY = 480-ScreenMargin-Size+InsideMargin;
    MaxInsideY = 480-ScreenMargin-InsideMargin;

    procedure LevelBoxPosToPixel(const pos: TVector3Single; var x, y: TGLint);
    begin
     x := Round(MapRange(pos[0], levelBox[0, 0], levelBox[1, 0], MinInsideX, MaxInsideX));
     y := Round(MapRange(pos[1], levelBox[0, 1], levelBox[1, 1], MinInsideY, MaxInsideY));
    end;

  var i: integer;
      x, y: TGLint;
  begin
   glColor4f(0, 0, 0, 0.5);
   glRectf(640-ScreenMargin-Size, 480-ScreenMargin-Size,
           640-ScreenMargin, 480-ScreenMargin);

   LevelBoxPosToPixel(playerShip.shipPos, x, y);
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
       LevelBoxPosToPixel(enemyShips[i].shipPos, x, y);
       glVertex2i(x, y);
      end;
   glEnd;
   glPointSize(1);
  end;

begin
 { TODO: uzyj kokpitu przez stencil bufor raczej }
 glLoadIdentity;
 glRasterPos2i(0, 0);

 glAlphaFunc(GL_GREATER, 0.5);
 glEnable(GL_ALPHA_TEST);
 glCallList(kokpitbg_list);
 glDisable(GL_ALPHA_TEST);

 if playerShip.drawCrosshair then
 begin
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_BLEND);
  glRasterPos2i((640 - crossh_orig_width) div 2, (480 - crossh_orig_height) div 2);
  glCallList(crossh_list);
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
 Notifications.Draw2D(640, 480, Window.width, Window.height);
end;

type
  TSimpleRenderParams = class(TVRMLRenderParams)
  public
    FBaseLights: TDynLightInstanceArray;
    constructor Create;
    destructor Destroy; override;
    function BaseLights(Scene: T3D): TDynLightInstanceArray; override;
  end;

constructor TSimpleRenderParams.Create;
begin
  inherited;
  FBaseLights := TDynLightInstanceArray.Create;
  InShadow := false;
  TransparentGroup := tgAll;
end;

destructor TSimpleRenderParams.Destroy;
begin
  FreeAndNil(FBaseLights);
  inherited;
end;

function TSimpleRenderParams.BaseLights(Scene: T3D): TDynLightInstanceArray;
begin
  Result := FBaseLights;
end;

procedure draw(Window: TGLWindow);
var
  Params: TSimpleRenderParams;
  H: PLightInstance;
begin
 {no need to clear COLOR_BUFFER - sky will cover everything}
 glClear(GL_DEPTH_BUFFER_BIT);
 glLoadIdentity;

 glPushMatrix;
   playerShip.PlayerShipApplyMatrixNoTranslate;
   sky.Render;
 glPopMatrix;

 playerShip.PlayerShipApplyMatrix;

 Params := TSimpleRenderParams.Create;
 try
   H := levelScene.Headlight(playerShip.shipPos, Normalized(playerShip.shipDir));
   if H <> nil then
     Params.FBaseLights.Add(H^);

   levelScene.Render(nil, Params);
   ShipsRender(Params);

   glPushAttrib(GL_ENABLE_BIT);
     glDisable(GL_LIGHTING);
     RocketsRender(Params);

     glDisable(GL_DEPTH_TEST);
     glProjectionPushPopOrtho2D(@Draw2D, nil, 0, 640, 0, 480);
   glPopAttrib;
 finally FreeAndNil(Params) end;
end;

procedure KeyDown(Window: TGLWindow; key: TKey; c: char);
var fname: string;
begin
 case key of
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

procedure idle(Window: TGLWindow);
begin
 if playerShip.ShipLife <= 0 then
 begin
  MessageOK(Window,['Your ship has been destroyed !','Game over.']);
  SetGameMode(modeMenu);
  Exit;
 end;

 playerShip.PlayerShipIdle;
 ShipsAndRocketsIdle;
 Notifications.Idle;
end;

{ Open/Close glwin -------------------------------------------------------- }

procedure OpenGLwin(Window: TGLWindow);
var crossh_img: TImage;
    kokpit_img: TImage;
begin
 kokpit_img := LoadImage(imagesDir +'kokpit.png',
   [TRGBAlphaImage, TGrayscaleAlphaImage], [ilcAlphaAdd]);
 try
  kokpit_img.Resize(Window.width, kokpit_img.Height * Window.Height div 480);
  kokpitbg_list := ImageDrawToDisplayList(kokpit_img);
 finally kokpit_img.Free end;

 { przyjmujemy ze crosshair.png bylo przygotowane dla ekranu 640x480.
   Resizujemy odpowiednio do naszego okienka. }
 crossh_img := LoadImage(imagesDir +'crosshair.png',
   [TRGBAlphaImage, TGrayscaleAlphaImage], [ilcAlphaAdd]);
 try
  crossh_orig_width := crossh_img.Width;
  crossh_orig_height := crossh_img.Height;
  crossh_img.Resize(crossh_img.Width * Window.width div 640,
                    crossh_img.Height * Window.height div 480);
  crossh_list := ImageDrawToDisplayList(crossh_img);
 finally crossh_img.Free end;

 glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE);
end;

procedure CloseGLwin(Window: TGLWindow);
begin

end;

initialization
 gameModeEnter[modeGame] := @modeEnter;
 gameModeExit[modeGame] := @modeExit;
 Window.OnOpenList.Add(@OpenGLwin);
 Window.OnCloseList.Add(@CloseGLwin);
end.

(* --------------------------------------------------------------------------------

starocie : crosshair rysowany jakby XORem

  {czego my chcemy od tej blending function ?
   Nasz crosshair wyglada tak : ma czarny kolor i alpha = 0 tam gdzie
     nie chcemy zeby sie pojawil (tzn. tam ma zostac ten kolor co juz jest
     w buforze);
   ma jasny (niekoniecznie bialy) kolor i alpha = 1 tam gdzie chcemy zeby sie
     pojawil odwracajac kolor jaki jest w buforze (wiec z jasnego zrobi ciemny a
     z ciemnego jasny).
   Factor GL_ONE_MINUS_DST_COLOR to wlasnie odwrocony kolor w buforze;
     tam gdzie nasz crosshair jest czarny to i tak wyjdzie source = black;
     tam gdzie nasz crosshair jest jasny wyjdzie ten odwrocony kolor bufora
     (moze troche sciemniony jezeli nasz kolor nie bedzie w pelni white tylko
     troche mniejszy od white);
   Pozostaje nam aby zachowywac kolor dest gdy nasze alpha = 0
     i kasowac go gdy nasze alpha = 1. Osiagamy to
     faktorem GL_ONE_MINUS_SRC_ALPHA. }
  glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA);

------------------------------------------------------------
stary sposob ladowania kokpit.png

  function LoadAlphaImgToDisplayList(const imgFName: string; w, h: integer): TGLuint;
  var img: TImage;
  begin
   img := LoadImage(imagesDir +imgFName, frWithAlpha, false, w, h);
   try
    result := ImageDrawToDisplayList(img);
   finally ImageFree(img) end;
  end;
*)
