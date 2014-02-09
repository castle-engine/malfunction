{
  Copyright 2002-2014 Michalis Kamburelis.

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

program malfunction;

{
  klawisze do wlaczania "CHEATING MODES", przydatne do testowania programu :
      Shift+Ctrl+C wlacz/wylacz sprawdzanie kolizji playerShip z enemyShips i levelem
      Shift+Ctrl+I wlacz/wylacz tryb "Immune to rockets"
}
{ TODO:
  - Simplify all the mess with so-called "modes" in this unit:
    thanks to CastleWindowModes unit I can now code this in much more
    clear way (using normal sequential code, like in kambi_lines
    or castle, instead of only event-driven). To be done if I ever
    will want to do anything larger with malfunction.
}

{$apptype GUI}

uses CastleWindow, GameGeneral, SysUtils, CastleUtils, ModeMenuUnit, ModeGameUnit,
  CastleParameters, CastleClassUtils, CastleFilesUtils, CastleKeysMouse,
  CastleURIUtils;

{ params ------------------------------------------------------------ }

const
  Options: array[0..1]of TOption = (
    (Short: 'h'; Long: 'help'; Argument: oaNone),
    (Short: 'v'; Long: 'version'; Argument: oaNone)
  );

procedure OptionProc(OptionNum: Integer; HasArgument: boolean;
  const Argument: string; const SeparateArgs: TSeparateArgs; Data: Pointer);
begin
 case OptionNum of
  0: begin
      InfoWrite(
        'malfunction: small 3d game in OpenGL.' +nl+
        'Accepted command-line options:' +nl+
        HelpOptionHelp+ nl+
        VersionOptionHelp +nl+
        TCastleWindowCustom.ParseParametersHelp(StandardParseOptions, true) +nl+
        'By default, window size will be 640x480 (if your screen has size'+nl+
        '  640x480 then we will run in --fullscreen).'+nl+
        nl+
        SCastleEngineProgramHelpSuffix(DisplayApplicationName, Version, true));
      ProgramBreak;
     end;
  1: begin
      WritelnStr(Version);
      ProgramBreak;
     end;
  else raise EInternalError.Create('OptionProc');
 end;
end;

{ main program ------------------------------------------------------- }

begin
  { This must be done before initial Application.ScreenWidth,
    since Application.ScreenWidth already initializes display. }
  Window.ParseParameters([poDisplay]);

  { set initial size/fullscreen mode }
  if (Application.ScreenWidth = 640) and (Application.ScreenHeight = 480) then
   Window.FullScreen := true else
  begin
   Window.Width := 640;
   Window.Height := 480;
  end;

  { parse params }
  Window.ParseParameters(StandardParseOptions);
  Parameters.Parse(Options, @OptionProc, nil);
  if Parameters.High > 0 then
    raise EInvalidParams.Create('Unrecognized parameter : ' + Parameters[1]);

  { Mouse is useless, so hide }
  Window.Cursor := mcNone;

  SetGameMode(modeMenu);
  Window.OpenAndRun;
end.
