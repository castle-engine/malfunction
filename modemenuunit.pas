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

unit ModeMenuUnit;

interface

implementation

uses GL, SysUtils, CastleWindow, GameGeneral, OpenGLBmpFonts,
  BFNT_Isuckatgolf_m32_Unit, CastleGLUtils, CastleMessages, LevelUnit, CastleImages,
  VectorMath, CastleUtils, GLImages, CastleColors, UIControls, KeysMouse;

{ module consts and vars ---------------------------------------------------- }

type
  TMenuItem = (miGameManual, miPlaySunnyDay, miPlayDeepSpace, miPlayRainMountains,
    miQuit);

const
  menuNames: array[TMenuItem]of string = (
    'Read *SHORT* game instructions',
    'Play - "sunny day" level',
    'Play - "Mobius in space" level',
    'Play - "fog & mountains" level',
    'Quit');

var currentMenu: TMenuItem = Low(TMenuItem);
    listBg: TGLImage;
    menuFont: TGLBitmapFont;

{ mode enter/exit ----------------------------------------------------------- }

procedure draw(Window: TCastleWindowBase); forward;
procedure Press(Window: TCastleWindowBase; const Event: TInputPressRelease); forward;

procedure modeEnter;
begin
 OrthoProjection(0, Window.width, 0, Window.height);
 Window.OnDraw := @draw;
 Window.OnPress := @Press;
end;

procedure modeExit;
begin
end;

{ glw callbacks ----------------------------------------------------------- }

procedure draw(Window: TCastleWindowBase);
var mi: TMenuItem;
{const SLower = 'by Michalis Kamburelis';}
begin
 glLoadIdentity;
 glRasterPos2i(0, 0);
 listBg.Draw;

 glTranslatef(Window.width*50 div 640, Window.height*350 div 480, 0);
 for mi := Low(mi) to High(mi) do
 begin
  glPushMatrix;
    glTranslatef(0, -Ord(mi)*(menufont.RowHeight+10), 0);

    if mi = currentMenu then
    begin
     glColorv(White3Single);
     glLineWidth(1.0);
     drawGLRectBorder(-10, -menufont.Descend, menufont.TextWidth(menuNames[mi])+10, menuFont.RowHeight);
     glColorv(Yellow3Single);
    end else
     glColorv(White3Single);

    glRasterPos2i(0, 0);
    menufont.print(menuNames[mi]);
  glPopMatrix;
 end;

{ glLoadIdentity;
 glColorv(Yellow3f);
 glRasterPos2i((Window.width-courierFont.TextWidth(SLower))div 2,
	       courierFont.Descend+5);
 courierFont.print(SLower);}
end;

procedure Press(Window: TCastleWindowBase; const Event: TInputPressRelease);
begin
 if Event.EventType <> itKey then Exit;
 case Event.key of
  K_Up:
    begin
     if currentMenu = Low(currentMenu) then
      currentMenu := High(currentMenu) else
      currentMenu := Pred(currentMenu);
     Window.PostRedisplay;
    end;
  K_Down:
    begin
     if currentMenu = High(currentMenu) then
      currentMenu := Low(currentMenu) else
      currentMenu := Succ(currentMenu);
     Window.PostRedisplay;
    end;
  K_Enter:
    case currentMenu of
     miGameManual:
       MessageOK(Window,
         'If you want, you can dream that you''re a saviour of galaxy or' +
         ' something like that. The truth is:' +nl+
         '1. You sit inside the most junky and malfunctioning space ship in the whole universe.' +nl+
         '2. Noone knows what''s going on but there are some ' +
         'freakin'' ALIEN SPACESHIPS everywhere around, and THEY JUST GOT' +
         ' DOWN ON YOU.' +nl+
         nl+
         'Keys :' +nl+
         '  Arrows = rotate' +nl+
         '  A/Z = increase/decrease speed ' +
         '(note that your spaceship can also fly backwards if you decrease '+
         'your speed too much)' +nl+
         '  Space = fire rocket !' +nl+
         '  C = crosshair on/off' +nl+
         '  R = radar on/off' +nl+
         '  Esc = exit to menu' +nl+
         '  F5 = save screen to PNG' +nl+
         nl+
         'There is only one goal: destroy all enemy ships on every level.' +nl+
         nl+
         SCastleEngineProgramHelpSuffix(DisplayProgramName, Version, false),
	 taLeft);
     miPlaySunnyDay: PlayGame(vrmlsDir +'lake.wrl');
     miPlayDeepSpace: PlayGame(vrmlsDir +'mobius.wrl');
     miPlayRainMountains: PlayGame(vrmlsDir +'wawoz.wrl');
     miQuit:
       if MessageYesNo(Window, 'Are you sure you want to quit ?') then Window.close;
    end;
 end;
end;

procedure WindowOpen(const Container: IUIContainer);
begin
 listBg := TGLImage.Create(imagesDir +'menubg.png', [TRGBImage], [], Window.width, Window.height);
 menuFont := TGLBitmapFont.Create(@BFNT_Isuckatgolf_m32);
end;

procedure WindowClose(const Container: IUIContainer);
begin
 FreeAndNil(menuFont);
 FreeAndNil(ListBG);
end;

initialization
 gameModeEnter[modeMenu] := @modeEnter;
 gameModeExit[modeMenu] := @modeExit;
 OnGLContextOpen.Add(@WindowOpen);
 OnGLContextClose.Add(@WindowClose);
end.
