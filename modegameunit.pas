{
  Copyright 2003-2006 Michalis Kamburelis.

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

unit ModeGameUnit;

{ zeby wejsc w modeGame level musi byc loaded.
  I nie wolno robic FreeLevel dopoki jestesmy w modeGame. }

interface

implementation

uses VectorMath, SysUtils, OpenGLh, GLWindow, GameGeneral, KambiGLUtils,
  KambiUtils, LevelUnit, Boxes3d, GLWinMessages, PlayerShipUnit, Images,
  BackgroundGL, ShipsAndRockets, TimeMessages, Keys, KambiFilesUtils,
  KambiStringUtils;

var kokpitbg_list: TGLuint;
    crossh_list: TGLuint;
    sky: TSkyCube;
    {crossh_orig_* to oryginalne (tzn. wzgledem ekranu 640x480) rozmiary
     crosshair image (upakowanego w crossh_list) }
    crossh_orig_width, crossh_orig_height: integer;

{ mode enter/exit ----------------------------------------------------------- }

procedure draw(glwin: TGLWindow); forward;
procedure KeyDown(glwin: TGLWindow; key: TKey; c: char); forward;
procedure idle(glwin: TGLWindow); forward;

procedure modeEnter;
var projNear, projFar: TGLfloat;
    wholeLevelBox: TBox3d;
begin
 Assert(levelScene <> nil,
   'Error - setting game mode to modeGame but level uninitialized');

 {teraz rzecz ktorej nie mozemy spieprzyc bo bedziemy mieli niedokladny Zbufor:
  near i far projection.

  Player jest zawsze w obrebie levelBox i widzi rzeczy w obrebie
  levelScene.BoundingBox. Wiec far = dlugosc przekatnej
  Box3dSum(levelBox, levelScene.BoundingBox) bedzie na pewno wystarczajace.

  Near wybieramy arbitralnie jako PLAYER_SHIP_CAMERA_RADIUS. }
 projNear := PLAYER_SHIP_CAMERA_RADIUS;
 wholeLevelBox := Box3dSum(levelScene.BoundingBox, levelBox);
 projFar := PointsDistance(wholeLevelBox[0], wholeLevelBox[1]);
 ProjectionGLPerspective(30, glw.width/glw.height, projNear, projFar);

 glEnable(GL_DEPTH_TEST);
 glEnable(GL_LIGHTING);

 {default OpenGL light 0 properties :}
 glLightv(GL_LIGHT0, GL_AMBIENT, Black4Single);
 glLightv(GL_LIGHT0, GL_DIFFUSE, White4Single);
 glLightv(GL_LIGHT0, GL_SPECULAR, White4Single);
 glLightv(GL_LIGHT0, GL_POSITION, Vector4f(0, 0, 1, 0));
 glLighti(GL_LIGHT0, GL_SPOT_CUTOFF, 180);
 glEnable(GL_LIGHT0);

 if (LevelScene.FogNode <> nil) and
    (LevelScene.FogNode.FdVolumetric.Value) and
    (not GL_EXT_fog_coord) then
   MessageOK(glw,
     'Your OpenGL implementation doesn''t support GL_EXT_fog_coord. '+
     'Everything will work correctly but the results will not be as beatiful '+
     'as they could be.');

 glw.OnDraw := @draw;
 glw.OnKeyDown := @KeyDown;
 glw.OnIdle := @idle;

 glw.AutoRedisplay := true;

 sky := TSkyCube.Create(skiesDir +levelInfo.FdSky.Value, projNear, projFar);
end;

procedure modeExit;
begin
 glDisable(GL_DEPTH_TEST);
 glDisable(GL_LIGHTING);
 glDisable(GL_LIGHT0);

 glw.AutoRedisplay := false;

 FreeAndNil(sky);
end;

{ glw callbacks ----------------------------------------------------------- }

procedure draw2d(draw2dData: integer);

  procedure radarDraw2d;
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
  radarDraw2d;
  glDisable(GL_BLEND);
 end;

 playerShip.PlayerShipDraw2d;
 TimeMsg.Draw2d(640, 480, glw.width, glw.height);
end;

procedure draw(glwin: TGLWindow);
begin
 {no need to clear COLOR_BUFFER - sky will cover everything}
 glClear(GL_DEPTH_BUFFER_BIT);
 glLoadIdentity;

 glPushMatrix;
   playerShip.PlayerShipApplyMatrixNoTranslate;
   sky.Render;
 glPopMatrix;

 playerShip.PlayerShipApplyMatrix;

 levelScene.Render(nil);
 ShipsRender;

 glPushAttrib(GL_ENABLE_BIT);
   glDisable(GL_LIGHTING);
   RocketsRender;

   glDisable(GL_DEPTH_TEST);
   glProjectionPushPopOrtho2D(@Draw2d, 0, 0, 640, 0, 480);
 glPopAttrib;
end;

procedure KeyDown(glwin: TGLWindow; key: TKey; c: char);
var fname: string;
begin
 case key of
  K_Space: playerShip.FireRocket(playerShip.shipDir, 1);
  K_Escape:
    if MessageYesNo(glwin, 'End this game and return to menu ?') then
     SetGameMode(modeMenu);
  K_C:
    if glwin.ModifiersDown=[mkShift, mkCtrl] then
     with playerShip do CheatDontCheckCollisions := not CheatDontCheckCollisions else
    if glwin.ModifiersDown=[] then
     with playerShip do drawCrosshair := not drawCrosshair;
  K_I:
    if glwin.KeysDown[K_Shift] and glwin.KeysDown[K_Ctrl] then
     with playerShip do CheatImmuneToRockets := not CheatImmuneToRockets;
  K_R:
    with playerShip do drawRadar := not drawRadar;
  K_F5:
    begin
     fname := FNameAutoInc(SUnformattable(UserConfigPath)+
       'malfunction_screen_%d.png');
     glwin.SaveScreen(fname);
     TimeMsg.Show('Screen saved to '+fname);
    end;
 end;
end;

procedure idle(glwin: TGLWindow);
begin
 playerShip.PlayerShipIdle;
 ShipsAndRocketsIdle;
 TimeMsg.Idle;
end;

{ Init/Close glwin -------------------------------------------------------- }

procedure InitGLwin(glwin: TGLWindow);
var crossh_img: TImage;
    kokpit_img: TImage;
begin
 kokpit_img := LoadImage(imagesDir +'kokpit.png', [TAlphaImage], [ilcAlphaAdd]);
 try
  kokpit_img.Resize(glw.width, kokpit_img.Height * glwin.Height div 480);
  kokpitbg_list := ImageDrawToDispList(kokpit_img);
 finally kokpit_img.Free end;

 { przyjmujemy ze crosshair.png bylo przygotowane dla ekranu 640x480.
   Resizujemy odpowiednio do naszego okienka. }
 crossh_img := LoadImage(imagesDir +'crosshair.png', [TAlphaImage], [ilcAlphaAdd]);
 try
  crossh_orig_width := crossh_img.Width;
  crossh_orig_height := crossh_img.Height;
  crossh_img.Resize(crossh_img.Width * glw.width div 640,
                    crossh_img.Height * glw.height div 480);
  crossh_list := ImageDrawToDispList(crossh_img);
 finally crossh_img.Free end;

 glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE);
end;

procedure CloseGLwin(glwin: TGLWindow);
begin

end;

initialization
 gameModeEnter[modeGame] := @modeEnter;
 gameModeExit[modeGame] := @modeExit;
 Glw.OnInitList.AppendItem(@InitGLwin);
 Glw.OnCloseList.AppendItem(@CloseGLwin);
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

  function LoadAlphaImgToDispList(const imgFName: string; w, h: integer): TGLuint;
  var img: TImage;
  begin
   img := LoadImage(imagesDir +imgFName, frWithAlpha, false, w, h);
   try
    result := ImageDrawToDispList(img);
   finally ImageFree(img) end;
  end;
*)
