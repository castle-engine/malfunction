{
  Copyright 2002-2012 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Background as 6 textures (TSkyCube). }
unit SkyCube;

interface

uses X3DNodes, Background, CastleColors;

type
  { Draw background as a cube usign 6 textures.
    This is a subset of TBackground, with somewhat older standards:
    bottom is in -Z, top in +Z. Constructor automatically loads images
    using BackgroundImagesLoadFromOldNamePattern. }
  TSkyCube = class(TBackground)
  public
    constructor Create(const SkyNamePattern: string; zNear, zFar: Single); overload;
    constructor Create(const Imgs: TBackgroundImages; zNear, zFar: Single); overload;
  end;

{ Load background textures from files named in old "panoramaToSzescian"
  convention. This is deprecated, used only by old "szklane lasy"
  and old "malfunction" versions. @deprecated

  SkyNamePattern is the base filename. To construct actual filename,
  we will append to them '_' (underscore character) followed by one
  letter indicating cube side:

  @unorderedList(
    @item 'u'/ = (up) top
    @item 'd'/ = (down) bottom
    @item 'l'/ = right (!)
    @item 'r'/ = left  (!)
    @item 'f'/ = front
    @item 'b'  = back
  )

  If file for any cube side will not exist, we will try appending
  '_any' (useful if some sides use the same texture, for example top
  and bottom are sometimes just one black pixel).

  Some reasoning:

  @orderedList(
    @item('u' / 'd' were chosen to name up / down, more commonly
      (in VRML/X3D) named top / bottom. Reason: "bottom" and "back"
      would otherwise start with the same letter.)

    @item(Note (!) that left / right textures are swapped.
      Reason: I defined it like this in "panoramaToSzescian" and
      much later realized VRML Background node (and so my TBackground class)
      has it exactly inverted.

      (In "panoramaToSzescian" one the images sequence
      @italic(front, left, back, right) were matching
      when show in that order. In VRML/X3D the matching image sequence
      is @italic(front, right, back, left).))
  )

  Filename extension for textures is guessed by FindExistingImageExt.
  Images will be loaded by LoadTextureImage(FileName)
  so they will be forced into some format renderable as OpenGL texture. }
function BackgroundImagesLoadFromOldNamePattern(
  const SkyNamePattern: string): TBackgroundImages;

implementation

uses VectorMath, TextureImages, Images;

{ TSkyCube ------------------------------------------------------------------- }

constructor TSkyCube.Create(const SkyNamePattern: string; zNear, zFar: Single);
var SkyImgs: TBackgroundImages;
begin
 SkyImgs := BackgroundImagesLoadFromOldNamePattern(SkyNamePattern);
 try
  Create(SkyImgs, zNear, zFar);
 finally SkyImgs.FreeAll(nil) end;
end;

constructor TSkyCube.Create(const Imgs: TBackgroundImages; zNear, zFar: Single);
begin
  inherited Create(
    nil, 0, nil, 0, Imgs, nil, 0, @Black3Single, 1,
    NearFarToSkySphereRadius(zNear, zFar));
  Transform := RotationMatrixRad(Pi/2, Vector3Single(1, 0, 0));
end;

{ global --------------------------------------------------------------------- }

function BackgroundImagesLoadFromOldNamePattern(
  const SkyNamePattern: string): TBackgroundImages;
const
  names_suffix: array[TBackgroundSide]of string = ('b', 'd', 'f', 'r', 'l', 'u');
var
  ImgFileName: string;
  bs: TBackgroundSide;
begin
 for bs := Low(bs) to High(bs) do
 begin
  ImgFileName :=
    TryFindExistingImageExt(SkyNamePattern +'_' +names_suffix[bs], true);
  if ImgFileName = '' then
   ImgFileName := FindExistingImageExt(SkyNamePattern +'_any', true);
  result.Images[bs] := LoadTextureImage(ImgFileName);
 end;
end;

end.
