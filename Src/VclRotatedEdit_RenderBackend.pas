Unit VclRotatedEdit_RenderBackend;


{
  VclRotatedEdit_RenderBackend.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Rendering backend contract of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Contrat de backend du composant VCL VclRotatedEdit.

  Cette unité introduit volontairement une frontière plus large qu'un simple
  dessin final. Un backend de rendu possède aussi les mesures de texte et les
  calculs dépendants de ces mesures : layout, hit-test, caret et sélection.

  Règle d'architecture importante
  --------------------------------
  Le futur backend Direct2D/DirectWrite ne devra pas réutiliser les mesures GDI
  pour positionner les caractères, le caret ou la sélection. Si le texte est
  dessiné par DirectWrite, les positions du caret et des sélections doivent être
  issues du même moteur de mesure. Sinon des décalages apparaîtront entre le
  rendu réel du texte et les coordonnées manipulées par l'édition.

  Cette première étape fournit uniquement le backend GDI historique, mais le
  composant ne dépend déjà plus directement de TRotatedEditGDIRenderer ni de
  TRotatedEditLayout pour les opérations dépendantes du rendu.
}

Interface

Uses
    System.Types,
    Vcl.Graphics,
    VclRotatedEdit_Types,
    VclRotatedEdit_Layout,
    VclRotatedEdit_Style;

Type
    {
      Complete rendering and text-metric backend contract.

      The interface is intentionally broader than DrawContent / DrawCaret.
      BuildLayout and HitTest are part of the same backend because they depend
      on text metrics. The GDI backend delegates these operations to the
      historical layout engine. A future DirectWrite backend will replace them
      with DirectWrite-native text layout and hit-test calculations.
    }
    IRotatedEditRenderBackend = Interface
        ['{8F59E292-8DD6-4E23-9E65-8B36DE2E1A71}']

        Function GetBackendName: String;

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

        Property BackendName: String Read GetBackendName;
    End;

    {
      Historical GDI backend.

      This class is intentionally thin. It preserves the exact existing GDI
      behavior by delegating to the previous static helper classes. Its purpose
      is not to redesign GDI; it is to move GDI behind the same contract that
      the Direct2D/DirectWrite backend will implement later.
    }
    TRotatedEditGDIRenderBackend = Class(TInterfacedObject, IRotatedEditRenderBackend)
    public
        Function GetBackendName: String;

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
