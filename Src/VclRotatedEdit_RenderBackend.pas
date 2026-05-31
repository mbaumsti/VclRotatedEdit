Unit VclRotatedEdit_RenderBackend;


{
  VclRotatedEdit_RenderBackend.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Common rendering backend contract and backend factory of the VclRotatedEdit
  VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Socle commun des backends de rendu du composant VCL VclRotatedEdit.

  Cette unité ne doit pas contenir l'implémentation concrète d'un moteur de
  rendu. Elle définit uniquement :

  - le contrat IRotatedEditRenderBackend ;
  - la fonction de création du backend effectif ;
  - les règles communes qui garantissent que le coeur du composant reste
    indépendant du moteur de rendu choisi.

   les sources sont volontairement séparées en trois familles :

  - VclRotatedEdit_RenderBackend.pas : contrat commun et factory ;
  - VclRotatedEdit_RenderBackend_GDI.pas : backend GDI historique ;
  - VclRotatedEdit_RenderBackend_Direct2D.pas : squelette Direct2D/DirectWrite.

  Règle d'architecture importante
  --------------------------------
  Le futur backend Direct2D/DirectWrite ne devra pas réutiliser les mesures GDI
  pour positionner les caractères, le caret ou la sélection. Si le texte est
  dessiné par DirectWrite, les positions du caret et des sélections doivent être
  issues du même moteur de mesure. Sinon des décalages apparaîtront entre le
  rendu réel du texte et les coordonnées manipulées par l'édition.

  Cette unité reste donc le seul point connu du coeur du composant. Les unités
  concrètes GDI et Direct2D sont seulement référencées dans l'implémentation de
  la factory, afin d'éviter que VclRotatedEdit_Core.pas dépende directement
  d'un renderer précis.
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
  Creates the effective rendering backend for the requested backend kind.

  rebDirect2D is the normal default backend. It routes drawing and text metrics
  through the native Direct2D/DirectWrite implementation when those resources
  are available. rebGDI remains a selectable compatibility backend and is also
  used as a safety fallback by the Direct2D backend.

  The factory keeps the component core independent from concrete rendering
  units. The core requests a backend kind; the factory owns the knowledge of
  which implementation class must be instantiated.
}
Function CreateRotatedEditRenderBackend(
    ABackendKind: TRotatedEditRenderBackendKind): IRotatedEditRenderBackend;

Implementation

Uses
    VclRotatedEdit_RenderBackend_GDI,
    VclRotatedEdit_RenderBackend_Direct2D;

Function CreateRotatedEditRenderBackend(
    ABackendKind: TRotatedEditRenderBackendKind): IRotatedEditRenderBackend;
Begin
    Case ABackendKind Of
        rebGDI:
            Result := TRotatedEditGDIRenderBackend.Create;

        rebDirect2D:
            Begin
                //-------------------------------------------------------------
                //The Direct2D backend is selected through its own unit so the
                //Direct2D/DirectWrite dependencies stay isolated from the
                //component core and from the GDI implementation. The backend
                //itself owns its GDI fallback and uses it only when native
                //Direct2D resources or a Direct2D drawing pass fail.
                //-------------------------------------------------------------
                Result := TRotatedEditDirect2DRenderBackend.Create;
            End;
    Else
        Result := TRotatedEditGDIRenderBackend.Create;
    End;
End;

End.
