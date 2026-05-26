Unit VclRotatedEdit_Reg;


{
  VclRotatedEdit_Reg.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Design-time registration unit of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Unité d’enregistrement design-time du composant VCL VclRotatedEdit.

  Cette unité enregistre TRotatedEdit dans la palette de composants et initialise le support design-time associé.
}

Interface

Procedure Register;

Implementation

Uses
    System.Classes,
    DesignIntf,
    VclRotatedEdit,
    VclRotatedEdit_Design;

Procedure Register;
Begin
    RegisterComponents(
        'Samples',
        [TRotatedEdit]);

    //---------------------------------------------------------------------
    //Cursor is intentionally controlled by the component itself.
    //
    //TRotatedEdit builds an orientation-aware I-beam cursor from the current
    //angle. Publishing the inherited Cursor property would suggest that the
    //user can choose a fixed cursor, but such a value would be immediately
    //contradicted by the WM_SETCURSOR handling.
    //
    //The inherited RTTI property still exists at run time, as for every
    //TControl descendant, but the design-time package hides it from the Object
    //Inspector so the public design surface reflects the actual behaviour of
    //the component.
    //---------------------------------------------------------------------
    UnlistPublishedProperty(
        TRotatedEdit,
        'Cursor');

    RegisterRotatedEditDesignSupport;
End;

End.
