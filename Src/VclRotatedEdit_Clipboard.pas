Unit VclRotatedEdit_Clipboard;


{
  VclRotatedEdit_Clipboard.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Clipboard helper layer of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Couche d’aide au presse-papiers du composant VCL VclRotatedEdit.

  Cette unité isole les accès au presse-papiers Windows pour les opérations copier, couper et coller du contrôle.
}

Interface

Uses
    Winapi.Windows,
    Vcl.Clipbrd;

Type
    TRotatedEditClipboard = Class
    public
        Class Function CanPasteText: Boolean; Static;
        Class Function GetClipboardText: String; Static;
        Class Procedure SetClipboardText(Const AText: String); Static;
    End;

Implementation



Class Function TRotatedEditClipboard.CanPasteText: Boolean;
Begin
    Result := Clipboard.HasFormat(CF_TEXT) Or
        Clipboard.HasFormat(CF_UNICODETEXT);
End;

Class Function TRotatedEditClipboard.GetClipboardText: String;
Begin
    Result := Clipboard.AsText;
End;

Class Procedure TRotatedEditClipboard.SetClipboardText(Const AText: String);
Begin
    Clipboard.AsText := AText;
End;

End.
