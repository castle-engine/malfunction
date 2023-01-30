{
  Copyright 2002-2023 Michalis Kamburelis.

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
  CastleURIUtils, CastleLog, CastleApplicationProperties;

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
        TCastleWindow.ParseParametersHelp +nl+
        nl+
        ApplicationProperties.Description);
      Halt;
     end;
  1: begin
      WritelnStr(Version);
      Halt;
     end;
  else raise EInternalError.Create('OptionProc');
 end;
end;

{ main program ------------------------------------------------------- }

begin
  ApplicationProperties.ApplicationName := DisplayApplicationName;
  ApplicationProperties.Version := Version;

  Window.FullScreen := true;

  { parse params }
  Window.ParseParameters(StandardParseOptions);
  Parameters.Parse(Options, @OptionProc, nil);
  if Parameters.High > 0 then
    raise EInvalidParams.Create('Unrecognized parameter : ' + Parameters[1]);

  InitializeLog;

  SetGameMode(modeMenu);
  Window.OpenAndRun;
end.
