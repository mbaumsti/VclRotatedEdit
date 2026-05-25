Unit VclRotatedEdit;


{
  VclRotatedEdit.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Public entry point of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Point d’entrée public du composant VCL VclRotatedEdit.

  Cette unité expose TRotatedEdit et garde volontairement la façade publique aussi petite et stable que possible. L’implémentation réelle reste répartie dans les unités Core, Layout, Geometry, Render, Style et EditEngine.
}

Interface

Uses
    VclRotatedEdit_Core;

Type
    {
      Public single-line edit control with orientation-aware rendering.

      TRotatedEdit exposes the stable component class used by applications and
      the Object Inspector. The implementation is inherited from
      TRotatedEditCore so the public unit remains a small and predictable entry
      point for packages and projects.
    }
    TRotatedEdit = Class(TRotatedEditCore)
    End;

Implementation

End.
