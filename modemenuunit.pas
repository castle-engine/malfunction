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

unit ModeMenuUnit;

{$I castleconf.inc}

interface

implementation

uses SysUtils, CastleWindow, GameGeneral, CastleFonts,
  CastleTextureFont_suckgolf_32, CastleGLUtils, CastleMessages, LevelUnit,
  CastleImages, CastleVectors, CastleUtils, CastleGLImages, CastleColors,
  CastleUIControls, CastleKeysMouse, CastleControls, CastleRectangles,
  CastleFilesUtils, CastleApplicationProperties;

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

var
  currentMenu: TMenuItem = Low(TMenuItem);
  listBg: TGLImage;
  menuFont: TTextureFont;

{ mode enter/exit ----------------------------------------------------------- }

procedure Render(Container: TUIContainer); forward;
procedure Press(Container: TUIContainer; const Event: TInputPressRelease); forward;

procedure modeEnter;
begin
  OrthoProjection(0, Window.width, 0, Window.height);
  Window.OnRender := @Render;
  Window.OnPress := @Press;
end;

procedure modeExit;
begin
end;

{ window callbacks ----------------------------------------------------------- }

procedure Render(Container: TUIContainer);
var
  mi: TMenuItem;
  X, Y: Integer;
  Color: TCastleColor;
begin
  listBg.Draw(0, 0);

  X := Window.width*50 div 640;
  Y := Window.height*350 div 480;
  for mi := Low(mi) to High(mi) do
  begin
    Y -= menufont.RowHeight+10;
    if mi = currentMenu then
    begin
      Theme.Draw(Rectangle(X - 10, Y - menufont.Descend,
        menufont.TextWidth(menuNames[mi]) + 20,
        menufont.Descend + menuFont.RowHeight), tiActiveFrame);
      Color := Yellow;
    end else
      Color := White;
    menufont.Print(X, Y, Color, menuNames[mi]);
  end;
end;

procedure Press(Container: TUIContainer; const Event: TInputPressRelease);
begin
  if Event.EventType <> itKey then Exit;
  case Event.key of
    K_Up:
      begin
        if currentMenu = Low(currentMenu) then
          currentMenu := High(currentMenu) else
          currentMenu := Pred(currentMenu);
        Window.Invalidate;
      end;
    K_Down:
      begin
        if currentMenu = High(currentMenu) then
          currentMenu := Low(currentMenu) else
          currentMenu := Succ(currentMenu);
        Window.Invalidate;
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
            SCastleEngineProgramHelpSuffix(DisplayApplicationName, Version, false));
        miPlaySunnyDay: PlayGame(ApplicationData('vrmls/lake.wrl'));
        miPlayDeepSpace: PlayGame(ApplicationData('vrmls/mobius.wrl'));
        miPlayRainMountains: PlayGame(ApplicationData('vrmls/wawoz.wrl'));
        miQuit:
          if MessageYesNo(Window, 'Are you sure you want to quit ?') then Window.close;
      end;
  end;
end;

procedure ContextOpen;
begin
  listBg := TGLImage.Create(ApplicationData('images/menubg.png'), [TRGBImage],
    Window.width, Window.height, riBilinear);
  menuFont := TTextureFont.Create(TextureFont_suckgolf_32);
end;

procedure ContextClose;
begin
  FreeAndNil(menuFont);
  FreeAndNil(ListBG);
end;

initialization
  gameModeEnter[modeMenu] := @modeEnter;
  gameModeExit[modeMenu] := @modeExit;
  ApplicationProperties.OnGLContextOpen.Add(@ContextOpen);
  ApplicationProperties.OnGLContextClose.Add(@ContextClose);
end.
