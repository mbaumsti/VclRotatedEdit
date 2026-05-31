Unit VclRotatedEdit_RenderBackend_GDI;


{
  VclRotatedEdit_RenderBackend_GDI.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Historical GDI rendering backend of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Backend GDI historique du composant VCL VclRotatedEdit.

  Cette unité contient uniquement l'implémentation GDI concrète du contrat
  IRotatedEditRenderBackend. Elle conserve le comportement validé avant le
  travail Direct2D :

  - layout construit par VclRotatedEdit_Layout ;
  - hit-test construit par VclRotatedEdit_Layout ;
  - dessin du contenu et du caret confié à VclRotatedEdit_Render.

  Règle de maintenance
  --------------------
  Cette classe est volontairement mince. Elle ne doit pas devenir un nouveau
  moteur parallèle. Son rôle est d'encapsuler le pipeline GDI existant derrière
  la même interface que le futur backend Direct2D/DirectWrite.

   cette unité est séparée du contrat commun afin que les futures
  dépendances Direct2D puissent rester dans leur propre unité sans polluer le
  backend GDI ni le coeur du composant.

   les clauses Uses de cette unité sont volontairement explicites :
  l'unité dépend du contrat commun, des types publics partagés, du layout et de
  la résolution de style, mais elle ne dépend pas du backend Direct2D.
}

Interface

Uses
    System.Types,
    Vcl.Graphics,
    VclRotatedEdit_RenderBackend,
    VclRotatedEdit_Types,
    VclRotatedEdit_Layout,
    VclRotatedEdit_Style;

Type
    {
      Historical GDI backend.

      This class preserves the exact existing GDI behavior by delegating to the
      previous static helper classes. Its purpose is not to redesign GDI; it is
      to move GDI behind the same contract that the Direct2D/DirectWrite backend
      will implement later.
    }
    TRotatedEditGDIRenderBackend = Class(TInterfacedObject, IRotatedEditRenderBackend)
    public
        Function GetBackendName: String; Virtual;

        Function BuildLayout(
            ACanvas: TCanvas;
            Const AInput: TRotatedEditLayoutInput): TRotatedEditLayoutResult;

        Function HitTest(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AActualPoint: TPoint): TRotatedEditHitTestResult;

        Procedure DrawContent(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            ABackgroundBitmap: TBitmap;
            Var ABackgroundBitmapValid: Boolean;
            AContentBitmap: TBitmap;
            Var AContentBitmapValid: Boolean;
            AShowDebugBounds: Boolean;
            Const ATextHint: String);

        Procedure DrawCaret(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            ACaretVisible: Boolean);
    End;

Implementation

Uses
    VclRotatedEdit_Render;

Function TRotatedEditGDIRenderBackend.GetBackendName: String;
Begin
    Result := 'GDI';
End;

Function TRotatedEditGDIRenderBackend.BuildLayout(
    ACanvas: TCanvas;
    Const AInput: TRotatedEditLayoutInput): TRotatedEditLayoutResult;
Begin
    Result := TRotatedEditLayout.BuildLayout(
        ACanvas,
        AInput);
End;

Function TRotatedEditGDIRenderBackend.HitTest(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AActualPoint: TPoint): TRotatedEditHitTestResult;
Begin
    Result := TRotatedEditLayout.HitTest(
        ACanvas,
        ALayout,
        AActualPoint);
End;

Procedure TRotatedEditGDIRenderBackend.DrawContent(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ABackgroundBitmap: TBitmap;
    Var ABackgroundBitmapValid: Boolean;
    AContentBitmap: TBitmap;
    Var AContentBitmapValid: Boolean;
    AShowDebugBounds: Boolean;
    Const ATextHint: String);
Begin
    TRotatedEditRenderer.DrawContent(
        ACanvas,
        ALayout,
        AColors,
        ABackgroundBitmap,
        ABackgroundBitmapValid,
        AContentBitmap,
        AContentBitmapValid,
        AShowDebugBounds,
        ATextHint);
End;

Procedure TRotatedEditGDIRenderBackend.DrawCaret(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ACaretVisible: Boolean);
Begin
    TRotatedEditRenderer.DrawCaret(
        ACanvas,
        ALayout,
        AColors,
        ACaretVisible);
End;

End.
