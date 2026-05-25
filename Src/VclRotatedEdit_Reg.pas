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
    VclRotatedEdit,
    VclRotatedEdit_Design;

Procedure Register;
Begin
    RegisterComponents(
        'Samples',
        [TRotatedEdit]);

    RegisterRotatedEditDesignSupport;
End;

End.
