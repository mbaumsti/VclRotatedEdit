Unit VclRotatedEdit_RenderBackend_Direct2D;

{
  VclRotatedEdit_RenderBackend_Direct2D.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Direct2D / DirectWrite rendering backend of the VclRotatedEdit VCL
  component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Backend de rendu Direct2D / DirectWrite du composant VCL VclRotatedEdit.

  Responsabilités
  ----------------
  Cette unité encapsule le rendu Direct2D lorsque la propriété RenderBackend
  vaut rebDirect2D. Elle prend en charge les ressources natives Direct2D /
  DirectWrite, le render target DC lié au HDC VCL courant, le fond, le cadre,
  le texte, la sélection et le caret.

  Le fallback GDI reste présent uniquement comme sécurité : si les ressources
  Direct2D / DirectWrite ne sont pas disponibles, ou si une opération native
  échoue pendant le dessin, le composant doit rester utilisable.

  Règle d'architecture impérative
  -------------------------------
  Le backend Direct2D doit dessiner dans le repère final du contrôle. Il ne doit
  pas dessiner un edit droit dans un bitmap pour ensuite le tourner ou le
  projeter.

  Si un double-buffer devient nécessaire, le bitmap mémoire devra déjà
  représenter la surface finale orientée du contrôle. Les géométries Direct2D
  devront donc y être dessinées directement dans leur orientation finale.

  Cette règle évite les artefacts de projection observés avec le pipeline GDI
  historique, notamment les cadres fins qui peuvent devenir irréguliers après
  rasterisation puis transformation.

  Notes PasDoc
  ------------
  Les types et méthodes de cette unité sont volontairement internes au backend.
  L'API publique reste portée par TRotatedEdit et par le contrat commun
  IRotatedEditRenderBackend.
}

Interface

Uses
    System.SysUtils,
    System.Types,
    System.Math,
    //-------------------------------------------------------------------------
    // Low-level Direct2D / DirectWrite declarations.
    //
    // Winapi.DWrite is intentionally kept out of this uses clause because the
    // supported Delphi target resolves the required DirectWrite symbols through
    // the Direct2D-related declarations already present here.
    //-------------------------------------------------------------------------
    Winapi.Windows,
    Winapi.DXGIFormat,
    Winapi.D2D1,
    Vcl.Graphics,
    VclRotatedEdit_RenderBackend,
    VclRotatedEdit_Types,
    VclRotatedEdit_Layout,
    VclRotatedEdit_Style;

Type
    {
      State of the Direct2D / DirectWrite backend.

      This enumeration is deliberately private to this backend unit. The common
      renderer contract only needs to select and use a backend; it must not know
      about Direct2D lifecycle details. The values make GetBackendName useful
      during development without exposing a new published API too early.
    }
    TRotatedEditDirect2DRenderState = (
        //---------------------------------------------------------------------
        // No initialization path has run yet. This is normally visible only
        // during construction or after the resources have been explicitly
        // released during destruction.
        //---------------------------------------------------------------------
        rddsNotInitialized,


        //---------------------------------------------------------------------
        // Both native factories were successfully created. The DC render target
        // may still fail independently, so this state only proves that the
        // factory layer is available.
        //---------------------------------------------------------------------
        rddsFactoriesAvailable,

        //---------------------------------------------------------------------
        // D2D1CreateFactory failed. The backend remains usable through its GDI
        // fallback and must not raise during component construction.
        //---------------------------------------------------------------------
        rddsDirect2DFactoryFailed,

        //---------------------------------------------------------------------
        // DWriteCreateFactory failed. The backend remains usable through its GDI
        // fallback and must not raise during component construction.
        //---------------------------------------------------------------------
        rddsDirectWriteFactoryFailed,

        //---------------------------------------------------------------------
        // DirectWrite returned an object that could not be queried as
        // IDWriteFactory. This should be unusual, but keeping a distinct state
        // keeps the backend state precise for debug traces and fallback decisions.
        //---------------------------------------------------------------------
        rddsDirectWriteFactoryQueryFailed,

        //---------------------------------------------------------------------
        // The Direct2D / DirectWrite factories were created, but the DC
        // render target could not be created. The backend remains usable
        // through its GDI fallback and must not raise during construction.
        //---------------------------------------------------------------------
        rddsDCRenderTargetFailed,

        //---------------------------------------------------------------------
        // The DC render target exists, but BindDC failed for the current VCL
        // Canvas.Handle and paint rectangle. The backend remains usable through
        // the GDI fallback and must not raise during painting.
        //---------------------------------------------------------------------
        rddsDCRenderTargetBindFailed,

        //---------------------------------------------------------------------
        // The DC render target was successfully bound to the current VCL HDC.
        //---------------------------------------------------------------------
        rddsDCRenderTargetBound,

        //---------------------------------------------------------------------
        // The Direct2D content paint failed. This remains non-fatal because
        // the validated GDI fallback has already produced the real control
        // image before the overlay attempt.
        //---------------------------------------------------------------------
        rddsRenderFailed,

        //---------------------------------------------------------------------
        // The Direct2D content paint completed successfully.
        //---------------------------------------------------------------------
        rddsRenderCompleted,

        //---------------------------------------------------------------------
        // Resources were explicitly released. This is mainly useful during
        // destructor-time tracing or device-loss handling.
        //---------------------------------------------------------------------
        rddsReleased
    );

    {
      Private lifecycle state of the Direct2D / DirectWrite backend.

      The record keeps the native resource state separate from the public
      backend contract. It stores both the readable state used by GetBackendName
      and the last native HRESULT reported by Direct2D or DirectWrite.
    }
    TRotatedEditDirect2DResourceState = Record
        //---------------------------------------------------------------------
        // True once the Direct2D resource initialization path has been called.
        // This does not imply that the render target is available; use
        // NativeResourcesAvailable and Direct2DRenderTargetAvailable for that.
        //---------------------------------------------------------------------
        Initialized: Boolean;

        //---------------------------------------------------------------------
        // True only when the Direct2D and DirectWrite factories are available.
        // The DC render target has its own availability test because it can fail
        // independently from factory creation.
        //---------------------------------------------------------------------
        NativeResourcesAvailable: Boolean;

        //---------------------------------------------------------------------
        // Readable state used by GetBackendName and debug traces.
        // It intentionally stays out of the published component API.
        //---------------------------------------------------------------------
        RenderState: TRotatedEditDirect2DRenderState;

        //---------------------------------------------------------------------
        // Last native HRESULT returned by a Direct2D / DirectWrite call.
        // Zero means that no native failure has been recorded. Integer is used
        // to keep this state independent from public API exposure decisions.
        //---------------------------------------------------------------------
        LastNativeError: Integer;

        //---------------------------------------------------------------------
        // True when the backend is currently expected to delegate visible work
        // to the validated GDI backend. A resource failure or render failure
        // may reactivate this safety path.
        //---------------------------------------------------------------------
        FallbackActive: Boolean;
    End;

    {
      Direct2D / DirectWrite backend implementation.

      The class implements IRotatedEditRenderBackend directly instead of
      inheriting from the GDI backend. The GDI renderer is kept only as a private
      safety fallback.

      Important invariant: editable text must keep drawing and metrics aligned.
      Direct2D drawing should therefore use DirectWrite-compatible positions for
      selection and caret placement.
    }
    TRotatedEditDirect2DRenderBackend = Class(TInterfacedObject, IRotatedEditRenderBackend)
    private
        //---------------------------------------------------------------------
        // Safety fallback backend.
        //
        // This object preserves the validated GDI behavior when Direct2D /
        // DirectWrite resources are unavailable or when the Direct2D path fails.
        // Keeping the fallback as a private field rather than a base class is
        // intentional: the Direct2D backend must not be architecturally derived
        // from the historical GDI renderer.
        //---------------------------------------------------------------------
        FGdiFallback: IRotatedEditRenderBackend;

        //---------------------------------------------------------------------
        // Lifecycle state reserved for the real Direct2D / DirectWrite backend.
        //
        // The state is intentionally owned by the Direct2D backend instead of
        // the common backend contract. GDI must not know anything about these
        // resources, and TRotatedEditCore must remain renderer-agnostic.
        //---------------------------------------------------------------------
        FD2DState: TRotatedEditDirect2DResourceState;

        //---------------------------------------------------------------------
        // Native Direct2D factory owned by the Direct2D backend.
        // Creation failure is non-fatal because the backend can still use the
        // validated GDI fallback.
        //---------------------------------------------------------------------
        FD2DFactory: ID2D1Factory;

        //---------------------------------------------------------------------
        // Native DirectWrite factory owned by the Direct2D backend.
        // Text rendering, text metrics, caret placement and selection geometry
        // must remain aligned with DirectWrite in this backend.
        //---------------------------------------------------------------------
        FDWriteFactory: IDWriteFactory;

        //---------------------------------------------------------------------
        // Direct2D DC render target bound to the VCL paint HDC during the
        // Direct2D paint path. If creation or binding fails, the caller falls
        // back to the historical GDI backend.
        //---------------------------------------------------------------------
        FDCRenderTarget: ID2D1DCRenderTarget;

        Procedure InitializeDirect2DResources;
        Procedure ReleaseDirect2DResources;
        Procedure ReleaseDirect2DRenderTarget;
        Procedure CreateDirect2DRenderTarget;
        Function BindDirect2DRenderTargetToCanvas(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult): Boolean;
        Function RunDirect2DContentPaint(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            Const ATextHint: String): Boolean;
        Function Direct2DResourcesAvailable: Boolean;
        Function Direct2DRenderTargetAvailable: Boolean;
        Function Direct2DRenderStateToText(
            AState: TRotatedEditDirect2DRenderState): String;
        Function Direct2DLastNativeErrorText: String;
        Function Direct2DStateText: String;
        Function ShouldUseDirect2DContentPath: Boolean;

        //---------------------------------------------------------------------
        //Helpers partagés entre le rendu, le caret, la sélection et le hit-test.
        //
        //Ces deux méthodes factorisent la création du IDWriteTextFormat et du
        //IDWriteTextLayout DirectWrite, qui était précédemment dupliquée dans
        //chaque procédure locale de DrawContentWithDirect2DPath et DrawCaret.
        //Centraliser ici garantit que toutes les mesures (sélection, caret,
        //hit-test souris) utilisent exactement le même format que le texte affiché.
        //---------------------------------------------------------------------
        Function CreateD2DTextFormat(
            ACanvas: TCanvas;
            Out ATextFormat: IDWriteTextFormat): Boolean;

        Function CreateD2DTextLayout(
            Const AText: String;
            ATextFormat: IDWriteTextFormat;
            AMaxHeight: Single;
            Out ATextLayout: IDWriteTextLayout): Boolean;

        //---------------------------------------------------------------------
        //Recalcul du scroll offset via métriques DirectWrite.
        //
        //EnsureCaretVisible dans Layout.pas utilise les métriques GDI. Quand le
        //backend Direct2D est actif, le texte est rendu par DirectWrite dont les
        //avances peuvent différer légèrement de GDI (sous-pixels, hinting).
        //Cette méthode recalcule le scroll en demandant à DirectWrite la position
        //exacte du caret, garantissant que le scroll est cohérent avec le rendu.
        //---------------------------------------------------------------------
        Function EnsureCaretVisibleD2D(
            ACanvas: TCanvas;
            Const AText: String;
            ACaretIndex: Integer;
            ACurrentScrollOffset: Integer;
            Const ACanonicalContentRect: TRect): Integer;

        Function DrawContentWithDirect2DPath(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            ABackgroundBitmap: TBitmap;
            Var ABackgroundBitmapValid: Boolean;
            AContentBitmap: TBitmap;
            Var AContentBitmapValid: Boolean;
            AShowDebugBounds: Boolean;
            Const ATextHint: String): Boolean;

    public
        Constructor Create;
        Destructor Destroy; Override;

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
    VclRotatedEdit_Geometry,
    VclRotatedEdit_RenderBackend_GDI;

Constructor TRotatedEditDirect2DRenderBackend.Create;
Begin
    Inherited Create;

    //--------------------------------------------------------------------------
    // Temporary fallback.
    //
    // The fallback is created once with the Direct2D backend. It is deliberately
    // held through the common interface so the Direct2D class does not depend on
    // the concrete GDI class except at this construction boundary.
    //--------------------------------------------------------------------------
    FGdiFallback := TRotatedEditGDIRenderBackend.Create;

    //--------------------------------------------------------------------------
    // Native Direct2D / DirectWrite preparation step.
    //
    // Resource creation is deliberately non-fatal. If Direct2D or DirectWrite
    // cannot be initialized, this backend continues through the GDI fallback.
    //--------------------------------------------------------------------------
    InitializeDirect2DResources;
End;

Destructor TRotatedEditDirect2DRenderBackend.Destroy;
Begin
    //--------------------------------------------------------------------------
    // Keep the release hook present from the start of the Direct2D work. Native
    // COM resources will be released here in a later pass, before the inherited
    // interface reference cleanup runs.
    //--------------------------------------------------------------------------
    ReleaseDirect2DResources;

    Inherited Destroy;
End;

Procedure TRotatedEditDirect2DRenderBackend.InitializeDirect2DResources;
Var
    LD2DResult: HResult;
    LDWriteResult: HResult;
    LWriteFactoryUnknown: IUnknown;
Begin
    //--------------------------------------------------------------------------
    // Initializes the native Direct2D / DirectWrite resource layer.
    //
    // Important maintenance rule:
    // Do not raise an exception here. Direct2D initialization is preparatory and
    // must never make the edit control unusable while the GDI fallback remains
    // the real rendering path. Failure only marks the native resources as
    // unavailable and the backend continues through FGdiFallback.
    //--------------------------------------------------------------------------
    FD2DState.Initialized := True;
    FD2DState.NativeResourcesAvailable := False;
    FD2DState.RenderState := rddsNotInitialized;
    FD2DState.LastNativeError := 0;
    FD2DState.FallbackActive := True;

    FD2DState.RenderState := rddsNotInitialized;
    FD2DFactory := Nil;
    FDWriteFactory := Nil;
    LWriteFactoryUnknown := Nil;

    //--------------------------------------------------------------------------
    // Create the shared Direct2D factory.
    //
    // A single-threaded factory is sufficient for this VCL control because all
    // painting is expected to happen on the UI thread. If the component later
    // gains background rendering, this choice must be revisited explicitly.
    //--------------------------------------------------------------------------
    LD2DResult := D2D1CreateFactory(
        D2D1_FACTORY_TYPE_SINGLE_THREADED,
        ID2D1Factory,
        Nil,
        FD2DFactory);

    If LD2DResult < 0 Then
    Begin
        FD2DState.RenderState := rddsDirect2DFactoryFailed;
        FD2DState.LastNativeError := LD2DResult;
        FD2DFactory := Nil;
        FDWriteFactory := Nil;
        Exit;
    End;

    //--------------------------------------------------------------------------
    // Create the shared DirectWrite factory.
    //
    // The Direct2D backend must use DirectWrite for text metrics, caret
    // placement, hit-testing and selection rectangles, not only for drawing.
    // Creating the factory now validates that the optional API path can own the
    // native DirectWrite entry point without changing visible behavior.
    //--------------------------------------------------------------------------
    LDWriteResult := DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        IDWriteFactory,
        LWriteFactoryUnknown);

    If LDWriteResult < 0 Then
    Begin
        FD2DState.RenderState := rddsDirectWriteFactoryFailed;
        FD2DState.LastNativeError := LDWriteResult;
        LWriteFactoryUnknown := Nil;
        FDWriteFactory := Nil;
        FD2DFactory := Nil;
        Exit;
    End;

    If Not Supports(LWriteFactoryUnknown, IDWriteFactory, FDWriteFactory) Then
    Begin
        FD2DState.RenderState := rddsDirectWriteFactoryQueryFailed;
        FD2DState.LastNativeError := 0;
        LWriteFactoryUnknown := Nil;
        FDWriteFactory := Nil;
        FD2DFactory := Nil;
        Exit;
    End;

    LWriteFactoryUnknown := Nil;

    FD2DState.NativeResourcesAvailable := Assigned(FD2DFactory) And
        Assigned(FDWriteFactory);

    If FD2DState.NativeResourcesAvailable Then
    Begin
        FD2DState.RenderState := rddsFactoriesAvailable;
        FD2DState.LastNativeError := 0;

        //------------------------------------------------------------------
        //  creates the DC render target immediately after the factories
        // become available. The object is still inert: it is not bound to a
        // Canvas HDC and it is not used for visible drawing yet.
        //------------------------------------------------------------------
        CreateDirect2DRenderTarget;

        If Assigned(FDCRenderTarget) Then
            FD2DState.FallbackActive := False;
    End;
End;

Procedure TRotatedEditDirect2DRenderBackend.ReleaseDirect2DResources;
Begin
    //--------------------------------------------------------------------------
    // Native resources may exist. The state is reset anyway so repeated
    // construction/destruction during
    // design-time property changes remains deterministic and easy to inspect.
    //--------------------------------------------------------------------------
    ReleaseDirect2DRenderTarget;
    FD2DState.NativeResourcesAvailable := False;
    FD2DState.Initialized := False;
    FD2DState.RenderState := rddsReleased;
    FD2DState.LastNativeError := 0;
    FD2DState.FallbackActive := True;

    //--------------------------------------------------------------------------
    // Interface references are released explicitly to make the native resource
    // lifecycle obvious. This is harmless when the fields are Nil and releases
    // the factories created by the optional initialization path.
    //--------------------------------------------------------------------------
    FDWriteFactory := Nil;
    FD2DFactory := Nil;
End;

Procedure TRotatedEditDirect2DRenderBackend.ReleaseDirect2DRenderTarget;
Begin
    //--------------------------------------------------------------------------
    // The DC render target is owned by this backend and may be recreated later
    // if the Direct2D drawing path needs different render target properties.
    //  may bind it to a VCL HDC in the Direct2D branch, but it still owns
    // no visible Direct2D drawing state beyond the COM render target itself.
    //--------------------------------------------------------------------------
    FDCRenderTarget := Nil;
End;

Procedure TRotatedEditDirect2DRenderBackend.CreateDirect2DRenderTarget;
Var
    LProperties: D2D1_RENDER_TARGET_PROPERTIES;
    LResult: HResult;
Begin
    //--------------------------------------------------------------------------
    //  creates the DC render target. Binding to the current
    // Canvas.Handle is handled separately by BindDirect2DRenderTargetToCanvas
    // so the risky HDC interaction remains isolated from object creation.
    //
    // Important maintenance rule:
    // Creation failure must not raise an exception. The GDI fallback remains the
    // real renderer while Direct2D/DirectWrite is being developed.
    //--------------------------------------------------------------------------
    ReleaseDirect2DRenderTarget;

    If Not Assigned(FD2DFactory) Then
        Exit;

    //--------------------------------------------------------------------------
    // Do not initialize D2D1_RENDER_TARGET_PROPERTIES field by field here.
    // Delphi versions do not expose the record member named "type" with a
    // stable Pascal identifier: some headers use a renamed field, while others
    // reject the historical "_type" spelling. The helper constructor provided
    // by Winapi.D2D1 is the most compatible way to build this record.
    //
    // A DC render target is intended to interoperate with a GDI HDC. The
    // Direct2D documentation recommends a concrete BGRA format with an alpha
    // mode such as IGNORE or PREMULTIPLIED for this scenario; using an explicit
    // format is safer than leaving the pixel format unknown for future BindDC
    // tests.
    //--------------------------------------------------------------------------
    LProperties := D2D1RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT,
        D2D1PixelFormat(
            DXGI_FORMAT_B8G8R8A8_UNORM,
            D2D1_ALPHA_MODE_IGNORE),
        0.0,
        0.0,
        D2D1_RENDER_TARGET_USAGE_NONE,
        D2D1_FEATURE_LEVEL_DEFAULT);

    LResult := FD2DFactory.CreateDCRenderTarget(
        LProperties,
        FDCRenderTarget);

    If LResult < 0 Then
    Begin
        FD2DState.RenderState := rddsDCRenderTargetFailed;
        FD2DState.LastNativeError := LResult;
        FDCRenderTarget := Nil;
        Exit;
    End;

    If Assigned(FDCRenderTarget) Then
    Begin
        FD2DState.RenderState := rddsFactoriesAvailable;
        FD2DState.LastNativeError := 0;
    End;
End;

Function TRotatedEditDirect2DRenderBackend.BindDirect2DRenderTargetToCanvas(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult): Boolean;
Var
    LBindRect: TRect;
    LResult: HResult;
Begin
    //--------------------------------------------------------------------------
    //  Direct2D DC binding.
    //
    // This method associates the already-created ID2D1DCRenderTarget with the
    // VCL Canvas.Handle used by the current paint pass. It deliberately does
    // not call BeginDraw or EndDraw; the caller owns the Direct2D drawing
    // transaction so binding, painting and error handling stay in one place.
    //
    // Maintenance rule:
    // Failure must not raise from here. The Direct2D backend records the native
    // HRESULT and lets the caller use the GDI fallback for the current paint.
    //--------------------------------------------------------------------------
    Result := False;

    If Not Assigned(ACanvas) Then
        Exit;

    If Not Assigned(FDCRenderTarget) Then
        Exit;

    LBindRect := ALayout.ClientRect;

    If IsRectEmpty(LBindRect) Then
        LBindRect := ALayout.ActualEditBounds;

    If IsRectEmpty(LBindRect) Then
        Exit;

    //--------------------------------------------------------------------------
    // Delphi's Winapi.D2D1 declaration expects the TRect value itself here, not
    // a pointer. Passing @LBindRect is a C-header reflex and fails on Delphi
    // versions where BindDC is declared with a TRect parameter.
    //--------------------------------------------------------------------------
    LResult := FDCRenderTarget.BindDC(
        ACanvas.Handle,
        LBindRect);

    If LResult < 0 Then
    Begin
        FD2DState.RenderState := rddsDCRenderTargetBindFailed;
        FD2DState.LastNativeError := LResult;
        Exit;
    End;

    FD2DState.RenderState := rddsDCRenderTargetBound;
    FD2DState.LastNativeError := 0;
    Result := True;
End;

Function TRotatedEditDirect2DRenderBackend.RunDirect2DContentPaint(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    Const ATextHint: String): Boolean;
Var
    LBindRect: TRect;
    LResolvedBackgroundColor: TColor;
    LResolvedBorderColor: TColor;
    LBackgroundBrushColor: D2D1_COLOR_F;
    LBorderBrushColor: D2D1_COLOR_F;
    LSelectionBrushColor: D2D1_COLOR_F;
    LBackgroundBrush: ID2D1SolidColorBrush;
    LBorderBrush: ID2D1SolidColorBrush;
    LSelectionBrush: ID2D1SolidColorBrush;
    LOuterQuad: TRotatedEditFloatQuad;
    LInnerQuad: TRotatedEditFloatQuad;
    LUnderFrameQuad: TRotatedEditFloatQuad;
    LEditGeometry: ID2D1PathGeometry;
    LUnderFrameGeometry: ID2D1PathGeometry;
    LFrameGeometry: ID2D1PathGeometry;
    LTextBrushColor: D2D1_COLOR_F;
    LTextBrush: ID2D1SolidColorBrush;
    LTextFormat: IDWriteTextFormat;
    LFrameThickness: Double;
    LUnderFrameMargin: Double;
    LResult: HResult;

    Function MakeD2DPoint(AX: Double; AY: Double): D2D1_POINT_2F;
    Begin
        //---------------------------------------------------------------------
        //Keep the conversion local to the Direct2D renderer. The real backend
        //will later need a shared geometry bridge, but the current Direct2D
        //work is still intentionally isolated from the public renderer contract.
        //---------------------------------------------------------------------
        Result.x := Single(AX);
        Result.y := Single(AY);
    End;

    Procedure ResolveD2DColor(AColor: TColor; Var AResult: D2D1_COLOR_F);
    Var
        LColor: TColor;
    Begin
        //---------------------------------------------------------------------
        //Direct2D expects normalized RGB components. ColorToRGB is mandatory
        //because the style layer can return system colors such as clWindow or
        //style-resolved colors still encoded as VCL TColor values.
        //---------------------------------------------------------------------
        LColor := ColorToRGB(AColor);

        FillChar(AResult, SizeOf(AResult), 0);
        AResult.r := GetRValue(LColor) / 255.0;
        AResult.g := GetGValue(LColor) / 255.0;
        AResult.b := GetBValue(LColor) / 255.0;
        AResult.a := 1.0;
    End;

    Function ResolveDirect2DBorderColor: TColor;
    Begin
        //---------------------------------------------------------------------
        // Direct2D Direct2D border color rule.
        //
        //The current Direct2D Direct2D path draws the frame itself instead of
        //delegating it to VCL StyleServices. Therefore it must not blindly use a
        //focus-highlight color as the frame color. Some VCL styles keep a
        //normal TEdit frame color when the edit receives focus; using the
        //selection/highlight color here made the Direct2D frame look selected.
        //
        //Keep the drawing geometry unchanged and only neutralize the styled
        //focused-border color choice in this Direct2D path path. The historical GDI
        //renderer remains untouched: when UseStyledBorder is true it still asks
        //StyleServices.DrawElement to draw the real frame.
        //---------------------------------------------------------------------
        Result := AColors.BorderColor;

        If AColors.UseStyledBorder And
           (AColors.VclStyleServices <> Nil) And
           AColors.VclStyleServices.Enabled Then
            Result := AColors.VclStyleServices.GetSystemColor(clBtnShadow);
    End;

    Function CreateSolidBrush(
        Const AColor: D2D1_COLOR_F;
        Var ABrush: ID2D1SolidColorBrush): Boolean;
    Begin
        //---------------------------------------------------------------------
        //Delphi compatibility note:
        //ID2D1RenderTarget.CreateSolidColorBrush expects the optional brush
        //properties pointer as the second argument and the output brush as the
        //third argument. Nil means "use default brush properties".
        //---------------------------------------------------------------------
        Result := False;
        ABrush := Nil;

        LResult := FDCRenderTarget.CreateSolidColorBrush(
            AColor,
            Nil,
            ABrush);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            ABrush := Nil;
            Exit;
        End;

        Result := True;
    End;

    Function BuildQuadGeometry(
        Const AQuad: TRotatedEditFloatQuad;
        Var AGeometry: ID2D1PathGeometry): Boolean;
    Var
        LGeometrySink: ID2D1GeometrySink;
        LPoint1: D2D1_POINT_2F;
        LPoint2: D2D1_POINT_2F;
        LPoint3: D2D1_POINT_2F;
        LPoint4: D2D1_POINT_2F;
    Begin
        //---------------------------------------------------------------------
        //Builds a closed Direct2D path from a final-coordinate quad. The
        //Direct2D path keeps this helper local because the public renderer contract
        //must not yet expose Direct2D-specific geometry types.
        //---------------------------------------------------------------------
        Result := False;
        AGeometry := Nil;

        LPoint1 := MakeD2DPoint(AQuad.P1.X, AQuad.P1.Y);
        LPoint2 := MakeD2DPoint(AQuad.P2.X, AQuad.P2.Y);
        LPoint3 := MakeD2DPoint(AQuad.P3.X, AQuad.P3.Y);
        LPoint4 := MakeD2DPoint(AQuad.P4.X, AQuad.P4.Y);

        LResult := FD2DFactory.CreatePathGeometry(AGeometry);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        LResult := AGeometry.Open(LGeometrySink);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        LGeometrySink.BeginFigure(
            LPoint1,
            D2D1_FIGURE_BEGIN_FILLED);
        LGeometrySink.AddLine(LPoint2);
        LGeometrySink.AddLine(LPoint3);
        LGeometrySink.AddLine(LPoint4);
        LGeometrySink.EndFigure(D2D1_FIGURE_END_CLOSED);

        LResult := LGeometrySink.Close;
        LGeometrySink := Nil;

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        Result := True;
    End;

    Function BuildFrameGeometry(
        Const AOuterQuad: TRotatedEditFloatQuad;
        Const AInnerQuad: TRotatedEditFloatQuad;
        Var AGeometry: ID2D1PathGeometry): Boolean;
    Var
        LGeometrySink: ID2D1GeometrySink;
        LOuterPoint1: D2D1_POINT_2F;
        LOuterPoint2: D2D1_POINT_2F;
        LOuterPoint3: D2D1_POINT_2F;
        LOuterPoint4: D2D1_POINT_2F;
        LInnerPoint1: D2D1_POINT_2F;
        LInnerPoint2: D2D1_POINT_2F;
        LInnerPoint3: D2D1_POINT_2F;
        LInnerPoint4: D2D1_POINT_2F;
    Begin
        //---------------------------------------------------------------------
        // final-coordinate frame geometry.
        //
        //The Direct2D backend must not draw a straight edit and rotate it
        //afterwards. The frame is therefore expressed directly as a final
        //oriented ring: an outer quad and an inner quad, both already projected
        //to the control's final coordinate system. Filling this ring avoids the
        //stroke-centering issues seen with DrawGeometry while keeping the
        //operation vectorial and final-space.
        //---------------------------------------------------------------------
        Result := False;
        AGeometry := Nil;

        LOuterPoint1 := MakeD2DPoint(AOuterQuad.P1.X, AOuterQuad.P1.Y);
        LOuterPoint2 := MakeD2DPoint(AOuterQuad.P2.X, AOuterQuad.P2.Y);
        LOuterPoint3 := MakeD2DPoint(AOuterQuad.P3.X, AOuterQuad.P3.Y);
        LOuterPoint4 := MakeD2DPoint(AOuterQuad.P4.X, AOuterQuad.P4.Y);

        LInnerPoint1 := MakeD2DPoint(AInnerQuad.P1.X, AInnerQuad.P1.Y);
        LInnerPoint2 := MakeD2DPoint(AInnerQuad.P2.X, AInnerQuad.P2.Y);
        LInnerPoint3 := MakeD2DPoint(AInnerQuad.P3.X, AInnerQuad.P3.Y);
        LInnerPoint4 := MakeD2DPoint(AInnerQuad.P4.X, AInnerQuad.P4.Y);

        LResult := FD2DFactory.CreatePathGeometry(AGeometry);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        LResult := AGeometry.Open(LGeometrySink);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        //------------------------------------------------------------------
        //Use alternate fill mode so the second closed figure acts as the hole
        //of the frame. This avoids relying on the winding direction of the two
        //figures, which keeps the code clearer and less fragile while the
        //Direct2D Direct2D path evolves.
        //------------------------------------------------------------------
        LGeometrySink.SetFillMode(D2D1_FILL_MODE_ALTERNATE);

        LGeometrySink.BeginFigure(
            LOuterPoint1,
            D2D1_FIGURE_BEGIN_FILLED);
        LGeometrySink.AddLine(LOuterPoint2);
        LGeometrySink.AddLine(LOuterPoint3);
        LGeometrySink.AddLine(LOuterPoint4);
        LGeometrySink.EndFigure(D2D1_FIGURE_END_CLOSED);

        LGeometrySink.BeginFigure(
            LInnerPoint1,
            D2D1_FIGURE_BEGIN_FILLED);
        LGeometrySink.AddLine(LInnerPoint2);
        LGeometrySink.AddLine(LInnerPoint3);
        LGeometrySink.AddLine(LInnerPoint4);
        LGeometrySink.EndFigure(D2D1_FIGURE_END_CLOSED);

        LResult := LGeometrySink.Close;
        LGeometrySink := Nil;

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        Result := True;
    End;

    Function BuildActualQuadFromCanonicalCoords(
        ALeft: Double;
        ATop: Double;
        ARight: Double;
        ABottom: Double): TRotatedEditFloatQuad;
    Var
        LCanonicalQuad: TRotatedEditFloatQuad;
    Begin
        //---------------------------------------------------------------------
        //The Direct2D Direct2D path must use the same canonical-to-actual transform
        //as text, caret, selection and hit-test. Border and background quads
        //are therefore derived in canonical coordinates and projected through
        //TRotatedEditGeometry instead of being guessed in final coordinates.
        //---------------------------------------------------------------------
        LCanonicalQuad.P1 := TRotatedEditFloatPoint.Create(ALeft, ATop);
        LCanonicalQuad.P2 := TRotatedEditFloatPoint.Create(ARight, ATop);
        LCanonicalQuad.P3 := TRotatedEditFloatPoint.Create(ARight, ABottom);
        LCanonicalQuad.P4 := TRotatedEditFloatPoint.Create(ALeft, ABottom);

        Result := TRotatedEditGeometry.TransformQuad(
            LCanonicalQuad,
            ALayout.ActualOrigin,
            ALayout.Angle);
    End;

    Function ResolveDirect2DFrameThickness: Double;
    Var
        LMetricMax: Integer;
        LMetricCandidate: Double;
    Begin
        //---------------------------------------------------------------------
        // Direct2D Direct2D path frame thickness.
        //
        //The GDI-styled frame has a visual thickness that is not represented
        //perfectly by a single Direct2D stroke. For the final-coordinate ring
        //Direct2D path, use the largest resolved border metric as the base and keep
        //a small minimum/boost so the frame remains comparable to the styled VCL
        //border without returning to a bitmap projection.
        //---------------------------------------------------------------------
        LMetricMax := ALayout.BorderMetrics.Left;

        If ALayout.BorderMetrics.Top > LMetricMax Then
            LMetricMax := ALayout.BorderMetrics.Top;

        If ALayout.BorderMetrics.Right > LMetricMax Then
            LMetricMax := ALayout.BorderMetrics.Right;

        If ALayout.BorderMetrics.Bottom > LMetricMax Then
            LMetricMax := ALayout.BorderMetrics.Bottom;

        LMetricCandidate := LMetricMax + 1.0;

        If LMetricCandidate < 2.5 Then
            LMetricCandidate := 2.5;

        Result := LMetricCandidate;
    End;

    Function ResolveDWriteFontWeight: DWRITE_FONT_WEIGHT;
    Begin
        //---------------------------------------------------------------------
        //DirectWrite text Direct2D path.
        //
        //Keep the mapping deliberately simple in . The goal is to validate
        //a first DirectWrite text pass in the same paint cycle as the final-space
        //Direct2D frame, not to reproduce every possible TFont weight yet.
        //---------------------------------------------------------------------
        If fsBold In ACanvas.Font.Style Then
            Result := DWRITE_FONT_WEIGHT_BOLD
        Else
            Result := DWRITE_FONT_WEIGHT_NORMAL;
    End;

    Function ResolveDWriteFontStyle: DWRITE_FONT_STYLE;
    Begin
        If fsItalic In ACanvas.Font.Style Then
            Result := DWRITE_FONT_STYLE_ITALIC
        Else
            Result := DWRITE_FONT_STYLE_NORMAL;
    End;

    Function ResolveDWriteFontSize: Single;
    Begin
        //---------------------------------------------------------------------
        //DirectWrite expects DIPs. TFont.Size is expressed in points when it is
        //positive, so convert points to 96-DPI DIPs. If the font does not carry
        //a positive Size, fall back to the absolute pixel height as a reasonable
        //development approximation. This is sufficient for the first text pass;
        //the real backend will later own metrics and caret positions together.
        //---------------------------------------------------------------------
        If ACanvas.Font.Size > 0 Then
            Result := ACanvas.Font.Size * 96.0 / 72.0
        Else If ACanvas.Font.Height <> 0 Then
            Result := Abs(ACanvas.Font.Height)
        Else
            Result := 12.0;
    End;

    Function CreateTextFormat(Var ATextFormat: IDWriteTextFormat): Boolean;
    Begin
        //---------------------------------------------------------------------
        //Délègue à la méthode de classe CreateD2DTextFormat.
        //La méthode de classe est la source unique de création du format :
        //rendu, caret, sélection et hit-test utilisent tous le même format.
        //---------------------------------------------------------------------
        Result := CreateD2DTextFormat(ACanvas, ATextFormat);
    End;

    Function CreateTextLayout(
        Const ADisplayText: String;
        ATextFormat: IDWriteTextFormat;
        Var ATextLayout: IDWriteTextLayout): Boolean;
    Var
        LMaxHeight: Single;
    Begin
        //---------------------------------------------------------------------
        //Délègue à la méthode de classe CreateD2DTextLayout.
        //La hauteur canonique du contenu est passée comme contrainte de layout ;
        //CreateD2DTextLayout applique un plancher si elle est nulle ou négative.
        //---------------------------------------------------------------------
        LMaxHeight := Single(ALayout.CanonicalContentRect.Height);
        Result := CreateD2DTextLayout(ADisplayText, ATextFormat, LMaxHeight, ATextLayout);
    End;

    Procedure DrawDirect2DSelection;
    Var
        LDisplayText: String;
        LSelStart: Integer;
        LSelEnd: Integer;
        LStartX: Single;
        LStartY: Single;
        LEndX: Single;
        LEndY: Single;
        LStartMetrics: DWRITE_HIT_TEST_METRICS;
        LEndMetrics: DWRITE_HIT_TEST_METRICS;
        LTextFormatForMetrics: IDWriteTextFormat;
        LTextLayout: IDWriteTextLayout;
        LCanonicalQuad: TRotatedEditFloatQuad;
        LSelectionQuad: TRotatedEditFloatQuad;
        LSelectionGeometry: ID2D1PathGeometry;
        LLeft: Double;
        LRight: Double;
        LResultLocal: HResult;
    Begin
        //---------------------------------------------------------------------
        // first DirectWrite-native selection metric Direct2D path.
        //
        // painted ALayout.SelectionQuads. Those quads are stable and
        //rotation-safe, but their horizontal extents still come from the GDI
        //layout metrics. Since the visible text is now drawn by DirectWrite,
        //this first Direct2D metric pass asks IDWriteTextLayout for the leading
        //edge of the selection start and end positions.
        //
        //This deliberately does not yet implement the GDI  prefix measuring
        //fallback. The point of  is to verify whether native DirectWrite
        //positions are already coherent enough for caret/selection geometry.
        //---------------------------------------------------------------------
        If Not ALayout.SelectionVisible Then
            Exit;

        If ALayout.SelLength <= 0 Then
            Exit;

        LDisplayText := ALayout.Text;

        If LDisplayText = '' Then
            Exit;

        LSelStart := ALayout.SelStart;
        LSelEnd := ALayout.SelStart + ALayout.SelLength;

        If LSelStart < 0 Then
            LSelStart := 0;

        If LSelStart > Length(LDisplayText) Then
            LSelStart := Length(LDisplayText);

        If LSelEnd < LSelStart Then
            LSelEnd := LSelStart;

        If LSelEnd > Length(LDisplayText) Then
            LSelEnd := Length(LDisplayText);

        If LSelEnd <= LSelStart Then
            Exit;

        If Not CreateTextFormat(LTextFormatForMetrics) Then
            Exit;

        If Not CreateTextLayout(
            LDisplayText,
            LTextFormatForMetrics,
            LTextLayout) Then
        Begin
            LTextFormatForMetrics := Nil;
            Exit;
        End;

        FillChar(LStartMetrics, SizeOf(LStartMetrics), 0);
        FillChar(LEndMetrics, SizeOf(LEndMetrics), 0);

        LResultLocal := LTextLayout.HitTestTextPosition(
            LSelStart,
            False,
            LStartX,
            LStartY,
            LStartMetrics);

        If LResultLocal < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResultLocal;
            LTextLayout := Nil;
            LTextFormatForMetrics := Nil;
            Exit;
        End;

        LResultLocal := LTextLayout.HitTestTextPosition(
            LSelEnd,
            False,
            LEndX,
            LEndY,
            LEndMetrics);

        If LResultLocal < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResultLocal;
            LTextLayout := Nil;
            LTextFormatForMetrics := Nil;
            Exit;
        End;

        LTextLayout := Nil;
        LTextFormatForMetrics := Nil;

        LLeft := ALayout.TextOriginCanonical.X + Min(LStartX, LEndX);
        LRight := ALayout.TextOriginCanonical.X + Max(LStartX, LEndX);

        If LRight <= LLeft Then
            Exit;

        // Keep the single-line selection height aligned with the edit content
        // band for now.  tests the native DirectWrite horizontal metrics;
        // vertical metrics and selected-text color remain separate passes.
        LCanonicalQuad.P1 := TRotatedEditFloatPoint.Create(
            LLeft,
            ALayout.CanonicalContentRect.Top);

        LCanonicalQuad.P2 := TRotatedEditFloatPoint.Create(
            LRight,
            ALayout.CanonicalContentRect.Top);

        LCanonicalQuad.P3 := TRotatedEditFloatPoint.Create(
            LRight,
            ALayout.CanonicalContentRect.Bottom);

        LCanonicalQuad.P4 := TRotatedEditFloatPoint.Create(
            LLeft,
            ALayout.CanonicalContentRect.Bottom);

        LSelectionQuad := TRotatedEditGeometry.TransformQuad(
            LCanonicalQuad,
            ALayout.ActualOrigin,
            ALayout.Angle);

        ResolveD2DColor(AColors.SelectionColor, LSelectionBrushColor);

        If Not CreateSolidBrush(LSelectionBrushColor, LSelectionBrush) Then
            Exit;

        If Not BuildQuadGeometry(
            LSelectionQuad,
            LSelectionGeometry) Then
        Begin
            LSelectionBrush := Nil;
            Exit;
        End;

        Try
            FDCRenderTarget.FillGeometry(
                LSelectionGeometry,
                LSelectionBrush,
                Nil);
        Finally
            LSelectionGeometry := Nil;
            LSelectionBrush := Nil;
        End;
    End;

    Procedure DrawDirect2DText;
    Var
        LDisplayText: String;
        LTextColor: TColor;
        LTextRect: D2D1_RECT_F;
        LTextMatrix: D2D1_MATRIX_3X2_F;
        LIdentityMatrix: D2D1_MATRIX_3X2_F;
        LRad: Double;
        LCos: Double;
        LSin: Double;
    Begin
        //---------------------------------------------------------------------
        // first text Direct2D path.
        //
        //The frame/background rule validated in  remains unchanged: shape
        //geometry is built in final coordinates. For the first DirectWrite text
        //pass, the string is still drawn through a Direct2D vector transform,
        //not by rendering a horizontal bitmap and projecting that bitmap. This
        //keeps glyph rasterization under Direct2D/DirectWrite control and avoids
        //the historical GDI PlgBlt model.
        //
        //Selection, selected text color, caret and DirectWrite hit-testing are
        //intentionally not handled in this first pass.
        //---------------------------------------------------------------------
        LDisplayText := ALayout.Text;
        LTextColor := AColors.TextColor;

        If (LDisplayText = '') And (ATextHint <> '') Then
        Begin
            LDisplayText := ATextHint;
            LTextColor := AColors.HintTextColor;
        End;

        If LDisplayText = '' Then
            Exit;

        ResolveD2DColor(LTextColor, LTextBrushColor);

        If Not CreateSolidBrush(LTextBrushColor, LTextBrush) Then
            Exit;

        If Not CreateTextFormat(LTextFormat) Then
        Begin
            LTextBrush := Nil;
            Exit;
        End;

        // Keep the visual DrawText path single-line, matching the DirectWrite
        // layout object used by the  selection metric Direct2D path.
        LTextFormat.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);

        LRad := -ALayout.Angle * Pi / 180.0;
        LCos := Cos(LRad);
        LSin := Sin(LRad);

        FillChar(LTextMatrix, SizeOf(LTextMatrix), 0);
        LTextMatrix._11 := Single(LCos);
        LTextMatrix._12 := Single(LSin);
        LTextMatrix._21 := Single(-LSin);
        LTextMatrix._22 := Single(LCos);
        LTextMatrix._31 := Single(ALayout.ActualOrigin.X);
        LTextMatrix._32 := Single(ALayout.ActualOrigin.Y);

        LTextRect.left := Single(ALayout.TextOriginCanonical.X);
        LTextRect.top := Single(ALayout.TextOriginCanonical.Y);
        LTextRect.right := Single(ALayout.CanonicalContentRect.Right);
        LTextRect.bottom := Single(ALayout.CanonicalContentRect.Bottom);

        FillChar(LIdentityMatrix, SizeOf(LIdentityMatrix), 0);
        LIdentityMatrix._11 := 1.0;
        LIdentityMatrix._22 := 1.0;

        FDCRenderTarget.SetTransform(LTextMatrix);
        Try
            FDCRenderTarget.DrawText(
                PWideChar(WideString(LDisplayText)),
                Length(LDisplayText),
                LTextFormat,
                LTextRect,
                LTextBrush,
                D2D1_DRAW_TEXT_OPTIONS_CLIP,
                DWRITE_MEASURING_MODE_NATURAL);
        Finally
            FDCRenderTarget.SetTransform(LIdentityMatrix);
            LTextFormat := Nil;
            LTextBrush := Nil;
        End;
    End;
Begin
    //--------------------------------------------------------------------------
    //  Direct2D content paint.
    //
    // The pipeline now implements the  architecture rule directly: all
    // visible shapes are built in the final coordinate system. The frame is no
    // longer a stroke centered on a polygon and it is not produced by rotating a
    // pre-rendered bitmap. It is a filled final-coordinate ring built from the
    // outer edit quad and an inner quad derived from the resolved frame
    // thickness. This should give more stable border thickness while preserving
    // the no-projection Direct2D strategy.
    //--------------------------------------------------------------------------
    Result := False;

    If Not Assigned(ACanvas) Then
        Exit;

    If Not Assigned(FDCRenderTarget) Then
        Exit;

    If IsRectEmpty(ALayout.ClientRect) Then
        Exit;

    LBindRect := ALayout.ClientRect;

    LResult := FDCRenderTarget.BindDC(
        ACanvas.Handle,
        LBindRect);

    If LResult < 0 Then
    Begin
        FD2DState.RenderState := rddsDCRenderTargetBindFailed;
        FD2DState.LastNativeError := LResult;
        Exit;
    End;

    LResolvedBackgroundColor := AColors.BackgroundColor;
    LResolvedBorderColor := ResolveDirect2DBorderColor;

    ResolveD2DColor(LResolvedBackgroundColor, LBackgroundBrushColor);
    ResolveD2DColor(LResolvedBorderColor, LBorderBrushColor);

    If Not CreateSolidBrush(LBackgroundBrushColor, LBackgroundBrush) Then
        Exit;

    If Not CreateSolidBrush(LBorderBrushColor, LBorderBrush) Then
    Begin
        LBackgroundBrush := Nil;
        Exit;
    End;

    //--------------------------------------------------------------------------
    // final-coordinate frame and background.
    //
    //Do not Clear the whole bound HDC: the transparent area outside the rotated
    //edit must continue to come from the parent paint performed by the control
    //Paint method. The under-frame quad only provides a controlled color below
    //the antialiased exterior pixels of the frame.
    //--------------------------------------------------------------------------
    LFrameThickness := ResolveDirect2DFrameThickness;
    LUnderFrameMargin := LFrameThickness + 1.0;

    LUnderFrameQuad := BuildActualQuadFromCanonicalCoords(
        -LUnderFrameMargin,
        -LUnderFrameMargin,
        ALayout.LogicalLength + LUnderFrameMargin,
        ALayout.LogicalThickness + LUnderFrameMargin);

    LOuterQuad := BuildActualQuadFromCanonicalCoords(
        0.0,
        0.0,
        ALayout.LogicalLength,
        ALayout.LogicalThickness);

    LInnerQuad := BuildActualQuadFromCanonicalCoords(
        LFrameThickness,
        LFrameThickness,
        ALayout.LogicalLength - LFrameThickness,
        ALayout.LogicalThickness - LFrameThickness);

    If Not BuildQuadGeometry(LUnderFrameQuad, LUnderFrameGeometry) Then
    Begin
        LBackgroundBrush := Nil;
        LBorderBrush := Nil;
        Exit;
    End;

    If Not BuildQuadGeometry(LInnerQuad, LEditGeometry) Then
    Begin
        LUnderFrameGeometry := Nil;
        LBackgroundBrush := Nil;
        LBorderBrush := Nil;
        Exit;
    End;

    If Not BuildFrameGeometry(LOuterQuad, LInnerQuad, LFrameGeometry) Then
    Begin
        LEditGeometry := Nil;
        LUnderFrameGeometry := Nil;
        LBackgroundBrush := Nil;
        LBorderBrush := Nil;
        Exit;
    End;

    FDCRenderTarget.BeginDraw;

    //--------------------------------------------------------------------------
    //Prepare the outside antialiasing support, fill the frame as a real final
    //coordinate ring, then fill the inner edit surface. This avoids both the
    //historical GDI bitmap projection and the  centered-stroke model.
    //--------------------------------------------------------------------------
    FDCRenderTarget.FillGeometry(
        LUnderFrameGeometry,
        LBackgroundBrush,
        Nil);

    If AColors.BorderVisible Then
    Begin
        FDCRenderTarget.FillGeometry(
            LFrameGeometry,
            LBorderBrush,
            Nil);
    End;

    FDCRenderTarget.FillGeometry(
        LEditGeometry,
        LBackgroundBrush,
        Nil);

    DrawDirect2DSelection;
    DrawDirect2DText;

    LResult := FDCRenderTarget.EndDraw(Nil, Nil);

    LFrameGeometry := Nil;
    LUnderFrameGeometry := Nil;
    LEditGeometry := Nil;
    LBackgroundBrush := Nil;
    LBorderBrush := Nil;

    If LResult < 0 Then
    Begin
        FD2DState.RenderState := rddsRenderFailed;
        FD2DState.LastNativeError := LResult;
        Exit;
    End;

    FD2DState.RenderState := rddsRenderCompleted;
    FD2DState.LastNativeError := 0;
    Result := True;
End;

Function TRotatedEditDirect2DRenderBackend.Direct2DResourcesAvailable: Boolean;
Begin
    Result := FD2DState.Initialized And FD2DState.NativeResourcesAvailable;
End;

Function TRotatedEditDirect2DRenderBackend.Direct2DRenderTargetAvailable: Boolean;
Begin
    //--------------------------------------------------------------------------
    // Direct2D is now a normal backend implementation. The DC render target may
    // still be Nil if native initialization failed; in that case the caller keeps
    // using the validated GDI fallback.
    //--------------------------------------------------------------------------
    Result := Assigned(FDCRenderTarget);
End;

Function TRotatedEditDirect2DRenderBackend.Direct2DRenderStateToText(
    AState: TRotatedEditDirect2DRenderState): String;
Begin
    Case AState Of
        rddsNotInitialized:
            Result := 'Direct2D resources not initialized';

        rddsFactoriesAvailable:
            Result := 'Direct2D and DirectWrite factories available';

        rddsDirect2DFactoryFailed:
            Result := 'Direct2D factory creation failed';

        rddsDirectWriteFactoryFailed:
            Result := 'DirectWrite factory creation failed';

        rddsDirectWriteFactoryQueryFailed:
            Result := 'DirectWrite factory query failed';

        rddsDCRenderTargetFailed:
            Result := 'Direct2D DC render target creation failed';

        rddsDCRenderTargetBindFailed:
            Result := 'Direct2D DC render target BindDC failed';

        rddsDCRenderTargetBound:
            Result := 'Direct2D DC render target bound to Canvas HDC';

        rddsRenderFailed:
            Result := 'Direct2D Direct2D content paint failed';

        rddsRenderCompleted:
            Result := 'Direct2D Direct2D content paint completed';

        rddsReleased:
            Result := 'Direct2D resources released';

    Else
        Result := 'Unknown Direct2D state';
    End;
End;

Function TRotatedEditDirect2DRenderBackend.Direct2DLastNativeErrorText: String;
Begin
    If FD2DState.LastNativeError = 0 Then
    Begin
        Result := '';
        Exit;
    End;

    Result := ' HRESULT=$' + IntToHex(FD2DState.LastNativeError, 8);
End;

Function TRotatedEditDirect2DRenderBackend.Direct2DStateText: String;
Begin
    Result := Direct2DRenderStateToText(FD2DState.RenderState) +
        Direct2DLastNativeErrorText;

    If FD2DState.FallbackActive Then
        Result := Result + '; using GDI fallback'
    Else
        Result := Result + '; Direct2D rendering active';

    If Direct2DRenderTargetAvailable Then
        Result := Result + '; DC render target available'
    Else
        Result := Result + '; DC render target not created';
End;

Function TRotatedEditDirect2DRenderBackend.ShouldUseDirect2DContentPath: Boolean;
Begin
    //-------------------------------------------------------------------------
    //  Direct2D activation rule.
    //
    // RenderBackend = rebDirect2D now uses the Direct2D implementation whenever
    // the native factories and DC render target were created successfully. If
    // anything failed during initialization, this returns False and DrawContent
    // uses the validated GDI fallback.
    //-------------------------------------------------------------------------
    Result := Direct2DResourcesAvailable And
        Direct2DRenderTargetAvailable;
End;

Function TRotatedEditDirect2DRenderBackend.DrawContentWithDirect2DPath(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ABackgroundBitmap: TBitmap;
    Var ABackgroundBitmapValid: Boolean;
    AContentBitmap: TBitmap;
    Var AContentBitmapValid: Boolean;
    AShowDebugBounds: Boolean;
    Const ATextHint: String): Boolean;
Begin
    //-------------------------------------------------------------------------
    //  Direct2D content branch.
    //
    // The Direct2D branch has become the active Direct2D renderer. It
    // draws the final-space background, frame, selection and DirectWrite text
    // without using a straight bitmap projected by PlgBlt.
    //
    // The bitmap validity flags are deliberately left unchanged. They belong to
    // the GDI cache pipeline and must not be marked valid by the Direct2D path,
    // which does not populate those bitmaps.
    //-------------------------------------------------------------------------
    Result := RunDirect2DContentPaint(
        ACanvas,
        ALayout,
        AColors,
        ATextHint);
End;

Function TRotatedEditDirect2DRenderBackend.CreateD2DTextFormat(
    ACanvas: TCanvas;
    Out ATextFormat: IDWriteTextFormat): Boolean;
Var
    LFontName:    WideString;
    LLocaleName:  WideString;
    LFontSize:    Single;
    LFontWeight:  DWRITE_FONT_WEIGHT;
    LFontStyle:   DWRITE_FONT_STYLE;
    LResult:      HResult;
Begin
    //-------------------------------------------------------------------------
    //Crée un IDWriteTextFormat à partir des propriétés de ACanvas.Font.
    //
    //Règle d'unicité
    //---------------
    //Cette méthode est la seule source de création d'un IDWriteTextFormat dans
    //ce backend. Toute autre création locale (dans DrawCaret, DrawDirect2DSelection,
    //HitTest) doit passer par ici pour garantir que le texte affiché et les
    //métriques de caret/sélection/hit-test utilisent strictement le même format.
    //
    //Conversion taille
    //-----------------
    //DirectWrite attend des DIPs (Device-Independent Pixels à 96 DPI).
    //TFont.Size > 0 est en points typographiques (72 pts = 1 pouce).
    //Conversion : Size_pts * 96 / 72 = Size_DIPs.
    //Si Font.Height est utilisé (valeur négative = pixels logiques GDI),
    //on prend la valeur absolue comme approximation raisonnable en pixels.
    //
    //Locale
    //------
    //'fr-FR' était codé en dur dans les variantes locales précédentes.
    //On conserve ce choix pour la cohérence avec l'existant. Une future
    //version pourra passer la locale en paramètre si nécessaire.
    //-------------------------------------------------------------------------
    Result      := False;
    ATextFormat := Nil;

    If Not Assigned(FDWriteFactory) Then
        Exit;

    If ACanvas.Font.Size > 0 Then
        LFontSize := ACanvas.Font.Size * 96.0 / 72.0
    Else If ACanvas.Font.Height <> 0 Then
        LFontSize := Abs(ACanvas.Font.Height)
    Else
        LFontSize := 12.0;

    If fsBold In ACanvas.Font.Style Then
        LFontWeight := DWRITE_FONT_WEIGHT_BOLD
    Else
        LFontWeight := DWRITE_FONT_WEIGHT_NORMAL;

    If fsItalic In ACanvas.Font.Style Then
        LFontStyle := DWRITE_FONT_STYLE_ITALIC
    Else
        LFontStyle := DWRITE_FONT_STYLE_NORMAL;

    LFontName   := ACanvas.Font.Name;
    LLocaleName := 'fr-FR';

    LResult := FDWriteFactory.CreateTextFormat(
        PWideChar(LFontName),
        Nil,
        LFontWeight,
        LFontStyle,
        DWRITE_FONT_STRETCH_NORMAL,
        LFontSize,
        PWideChar(LLocaleName),
        ATextFormat);

    If LResult < 0 Then Begin
        ATextFormat := Nil;
        Exit;
    End;

    If Assigned(ATextFormat) Then
        ATextFormat.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);

    Result := Assigned(ATextFormat);
End;

Function TRotatedEditDirect2DRenderBackend.CreateD2DTextLayout(
    Const AText: String;
    ATextFormat: IDWriteTextFormat;
    AMaxHeight: Single;
    Out ATextLayout: IDWriteTextLayout): Boolean;
Var
    LWideText:  WideString;
    LMaxHeight: Single;
    LResult:    HResult;
Begin
    //-------------------------------------------------------------------------
    //Crée un IDWriteTextLayout à partir d'un texte et d'un format.
    //
    //Règle d'unicité
    //---------------
    //Même principe que CreateD2DTextFormat : source unique pour tous les
    //consommateurs (rendu, caret, sélection, hit-test), afin que les métriques
    //soient strictement cohérentes avec le texte affiché.
    //
    //LMaxWidth
    //---------
    //La largeur maximale est volontairement très grande (100000 px). Le
    //composant est mono-ligne sans retour à la ligne (DWRITE_WORD_WRAPPING_NO_WRAP
    //positionné dans CreateD2DTextFormat). Cette valeur évite que DirectWrite
    //tronque le texte lors de la mesure tout en restant un Single valide.
    //
    //AMaxHeight
    //----------
    //Le caller passe la hauteur de la zone de contenu canonique, qui doit
    //être positive. Si elle est nulle ou négative on applique un plancher.
    //-------------------------------------------------------------------------
    Result      := False;
    ATextLayout := Nil;

    If Not Assigned(FDWriteFactory) Then
        Exit;

    If Not Assigned(ATextFormat) Then
        Exit;

    LMaxHeight := AMaxHeight;

    If LMaxHeight < 1.0 Then
        LMaxHeight := 1000.0;

    LWideText := AText;

    LResult := FDWriteFactory.CreateTextLayout(
        PWideChar(LWideText),
        Length(LWideText),
        ATextFormat,
        100000.0,
        LMaxHeight,
        ATextLayout);

    If LResult < 0 Then Begin
        ATextLayout := Nil;
        Exit;
    End;

    Result := Assigned(ATextLayout);
End;

Function TRotatedEditDirect2DRenderBackend.GetBackendName: String;
Begin
    Result := Direct2DStateText;
End;

Function TRotatedEditDirect2DRenderBackend.EnsureCaretVisibleD2D(
    ACanvas: TCanvas;
    Const AText: String;
    ACaretIndex: Integer;
    ACurrentScrollOffset: Integer;
    Const ACanonicalContentRect: TRect): Integer;
Var
    LTextFormat:    IDWriteTextFormat;
    LTextLayout:    IDWriteTextLayout;
    LHitMetrics:    DWRITE_HIT_TEST_METRICS;
    LCaretX:        Single;
    LCaretY:        Single;
    LHResult:       HResult;
    LIndex:         Integer;
    LContentWidth:  Integer;
    LVisibleLeft:   Double;
    LVisibleRight:  Double;
    LMargin:        Integer;
Begin
    //-------------------------------------------------------------------------
    //Recalcul du scroll offset avec la position de caret DirectWrite.
    //
    //Pourquoi ce recalcul
    //---------------------
    //EnsureCaretVisible dans TRotatedEditLayout utilise les métriques GDI
    //(TextIndexToCanonicalFlow via GetTextExtentExPoint). Quand le backend
    //Direct2D est actif, le texte est affiché par DirectWrite dont les avances
    //peuvent différer de celles de GDI (hinting sous-pixel, arrondi de DIP).
    //La divergence est faible par caractère mais s'accumule : sur 30 caractères,
    //elle peut dépasser la marge de 2px d'EnsureCaretVisible, ce qui fait que
    //le caret DirectWrite se retrouve visuellement hors de la zone de contenu
    //même si le scroll GDI le considère visible.
    //
    //Solution : HitTestTextPosition donne la position X du caret dans le repère
    //du IDWriteTextLayout (départ à x=0). On applique la même logique que
    //EnsureCaretVisible mais avec cette position DirectWrite, garantissant
    //la cohérence entre le scroll et le rendu.
    //
    //Fallback
    //--------
    //Si les ressources DirectWrite ne sont pas disponibles ou si la création
    //du layout échoue, on conserve le scroll GDI déjà calculé.
    //-------------------------------------------------------------------------
    Result := ACurrentScrollOffset;

    If Not Direct2DResourcesAvailable Then
        Exit;

    If AText = '' Then
        Exit;

    LIndex := ACaretIndex;

    If LIndex < 0 Then
        LIndex := 0;

    If LIndex > Length(AText) Then
        LIndex := Length(AText);

    If Not CreateD2DTextFormat(ACanvas, LTextFormat) Then
        Exit;

    If Not CreateD2DTextLayout(
        AText,
        LTextFormat,
        Single(ACanonicalContentRect.Height),
        LTextLayout) Then Begin
        LTextFormat := Nil;
        Exit;
    End;

    LCaretX := 0.0;
    LCaretY := 0.0;
    FillChar(LHitMetrics, SizeOf(LHitMetrics), 0);

    LHResult := LTextLayout.HitTestTextPosition(
        LIndex,
        False,
        LCaretX,
        LCaretY,
        LHitMetrics);

    LTextLayout := Nil;
    LTextFormat := Nil;

    If LHResult < 0 Then
        Exit;

    //Même logique qu'EnsureCaretVisible, mais avec LCaretX DirectWrite.
    //LCaretX est relatif à l'origine du layout (x=0 = début du texte).
    //Le scroll est la distance entre le début du texte et le bord gauche
    //de la zone visible, donc LCaretX joue le même rôle que LCaretFlow dans
    //EnsureCaretVisible.
    LMargin       := 2;
    LContentWidth := ACanonicalContentRect.Width;
    LVisibleLeft  := Result;
    LVisibleRight := Result + LContentWidth - (2 * LMargin);

    If LCaretX < LVisibleLeft Then
        Result := Trunc(LCaretX)
    Else If LCaretX > LVisibleRight Then
        Result := Trunc(LCaretX - LContentWidth + (2 * LMargin));

    If Result < 0 Then
        Result := 0;
End;

Function TRotatedEditDirect2DRenderBackend.BuildLayout(
    ACanvas: TCanvas;
    Const AInput: TRotatedEditLayoutInput): TRotatedEditLayoutResult;
Begin
    //-------------------------------------------------------------------------
    //Calcul du layout via le backend GDI, puis correction du scroll en D2D.
    //
    //Le layout canonique (positions de texte, de caret, geometrie) est calculé
    //par le backend GDI car il repose sur des métriques GDI cohérentes avec le
    //renderer GDI de secours. Seul le scroll offset est ensuite recalibré avec
    //les métriques DirectWrite quand le chemin D2D est actif.
    //
    //Pourquoi ne pas tout recalculer en D2D
    //---------------------------------------
    //BuildLayout construit la géométrie canonique complète (quads, origin,
    //caret, sélection). Ces calculs dépendent de TextIndexToCanonicalFlow qui
    //est GDI. Remplacer tout le layout par DirectWrite nécessiterait de porter
    //les métriques D2D dans TRotatedEditLayoutResult, ce qui est une refonte
    //majeure. La correction du seul scroll offset est suffisante pour que le
    //caret D2D soit toujours visible après une navigation (HOME, END, flèches).
    //-------------------------------------------------------------------------
    Result := FGdiFallback.BuildLayout(ACanvas, AInput);

    //Recalibration du scroll avec les métriques DirectWrite si le chemin D2D
    //est actif. On utilise AInput.ScrollOffset comme point de départ car
    //FGdiFallback.BuildLayout a déjà ajusté Result.ScrollOffset selon GDI ;
    //on recalcule depuis l'offset GDI produit pour ne pas partir d'une valeur
    //obsolète.
    If ShouldUseDirect2DContentPath Then Begin
        Result.ScrollOffset := EnsureCaretVisibleD2D(
            ACanvas,
            AInput.Text,
            AInput.CaretIndex,
            Result.ScrollOffset,
            Result.CanonicalContentRect);

        //Recalculer TextOriginCanonical.X et TextOriginActual avec le nouveau
        //scroll D2D. Si le texte tient dans la zone, le scroll est zéro et
        //l'alignement est déjà correct (pas de correction nécessaire).
        If Result.TextLength > Result.CanonicalContentRect.Width Then Begin
            Result.TextOriginCanonical.X :=
                Result.CanonicalContentRect.Left - Result.ScrollOffset;

            //TextOriginActual doit rester cohérent avec TextOriginCanonical.
            Result.TextOriginActual := TRotatedEditGeometry.TransformPoint(
                Result.TextOriginCanonical,
                Result.ActualOrigin,
                Result.Angle);
        End;
    End;
End;

Function TRotatedEditDirect2DRenderBackend.HitTest(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AActualPoint: TPoint): TRotatedEditHitTestResult;
Var
    LActual:         TRotatedEditFloatPoint;
    LCanonical:      TRotatedEditFloatPoint;
    LRelX:           Single;
    LRelY:           Single;
    LIsTrailingHit:  BOOL;
    LIsInside:       BOOL;
    LHitMetrics:     DWRITE_HIT_TEST_METRICS;
    LTextFormat:     IDWriteTextFormat;
    LTextLayout:     IDWriteTextLayout;
    LHResult:        HResult;
    LInsertionIndex: Integer;
    LMaxHeight:      Single;
Begin
    //-------------------------------------------------------------------------
    //Hit-test souris via DirectWrite — cohérence métrique avec le rendu.
    //
    //Problème résolu
    //---------------
    //Quand le backend Direct2D est actif, le texte est affiché par DirectWrite.
    //L'ancienne implémentation déléguait le hit-test au backend GDI, qui
    //mesurait les positions de caractères via GetTextExtentPoint32. Les avances
    //GDI et DirectWrite divergent légèrement (crénage, hinting, sous-pixels) ;
    //l'écart s'accumule caractère par caractère et provoque un drift croissant
    //entre la position cliquée et l'index de caret calculé.
    //
    //Solution
    //--------
    //On utilise IDWriteTextLayout.HitTestPoint, qui opère sur le même objet
    //de layout que celui utilisé pour dessiner le texte et positionner le caret.
    //Les métriques sont donc garanties cohérentes avec l'affichage.
    //
    //Coordonnées relatives
    //---------------------
    //HitTestPoint attend des coordonnées relatives à l'origine du layout
    //DirectWrite, soit (TextOriginCanonical.X, TextOriginCanonical.Y).
    //On projette d'abord le point écran → canonique via InverseTransformPoint,
    //puis on soustrait l'origine du texte.
    //
    //Trailing hit → index d'insertion
    //---------------------------------
    //DirectWrite retourne isTrailingHit=True quand le clic est dans la moitié
    //droite d'un glyphe. Dans ce cas l'index d'insertion est textPosition+1,
    //ce qui correspond au comportement d'un TEdit natif Windows.
    //
    //Fallback GDI
    //------------
    //Si Direct2D n'est pas disponible ou si la création du layout échoue,
    //on délègue au backend GDI pour garantir un comportement dégradé cohérent.
    //-------------------------------------------------------------------------

    //Fallback GDI si le chemin Direct2D n'est pas actif
    If Not ShouldUseDirect2DContentPath Then Begin
        Result := FGdiFallback.HitTest(ACanvas, ALayout, AActualPoint);
        Exit;
    End;

    Result.ActualPoint := AActualPoint;

    //1. Projection écran → canonique (même règle que TRotatedEditLayout.HitTest)
    LActual := TRotatedEditFloatPoint.Create(AActualPoint.X, AActualPoint.Y);

    LCanonical := TRotatedEditGeometry.InverseTransformPoint(
        LActual,
        ALayout.ActualOrigin,
        ALayout.Angle);

    Result.CanonicalPoint := LCanonical;

    Result.InTextBand :=
        (LCanonical.Y >= ALayout.TextOriginCanonical.Y) And
        (LCanonical.Y <= ALayout.TextOriginCanonical.Y + ALayout.TextThickness);

    //2. Coordonnées relatives à l'origine du layout DirectWrite
    //   HitTestPoint opère dans le repère du IDWriteTextLayout, dont l'origine
    //   correspond à TextOriginCanonical dans notre système canonique.
    LRelX := Single(LCanonical.X - ALayout.TextOriginCanonical.X);
    LRelY := Single(LCanonical.Y - ALayout.TextOriginCanonical.Y);

    //Les coordonnées négatives signifient un clic avant le début du texte :
    //on clampte à zéro pour que DirectWrite retourne l'index 0.
    If LRelX < 0.0 Then
        LRelX := 0.0;

    If LRelY < 0.0 Then
        LRelY := 0.0;

    //3. Création du layout DirectWrite avec le même format que le rendu
    LMaxHeight := Single(ALayout.CanonicalContentRect.Height);

    If Not CreateD2DTextFormat(ACanvas, LTextFormat) Then Begin
        Result := FGdiFallback.HitTest(ACanvas, ALayout, AActualPoint);
        Exit;
    End;

    If Not CreateD2DTextLayout(
        ALayout.Text,
        LTextFormat,
        LMaxHeight,
        LTextLayout) Then Begin
        LTextFormat := Nil;
        Result := FGdiFallback.HitTest(ACanvas, ALayout, AActualPoint);
        Exit;
    End;

    //4. Hit-test DirectWrite natif
    LIsTrailingHit := False;
    LIsInside      := False;
    FillChar(LHitMetrics, SizeOf(LHitMetrics), 0);

    LHResult := LTextLayout.HitTestPoint(
        LRelX,
        LRelY,
        LIsTrailingHit,
        LIsInside,
        LHitMetrics);

    LTextLayout := Nil;
    LTextFormat := Nil;

    If LHResult < 0 Then Begin
        //Échec DirectWrite : repli GDI
        Result := FGdiFallback.HitTest(ACanvas, ALayout, AActualPoint);
        Exit;
    End;

    //5. Conversion trailing hit → index d'insertion (comportement TEdit natif)
    //   textPosition est l'index du caractère touché (0-based).
    //   Si isTrailingHit, le clic est dans la moitié droite : le caret se place
    //   après ce caractère, donc index = textPosition + 1.
    LInsertionIndex := Integer(LHitMetrics.textPosition);

    If LIsTrailingHit Then
        Inc(LInsertionIndex);

    //Clamp défensif
    If LInsertionIndex < 0 Then
        LInsertionIndex := 0;

    If LInsertionIndex > Length(ALayout.Text) Then
        LInsertionIndex := Length(ALayout.Text);

    Result.InsertionIndex := LInsertionIndex;
End;

Procedure TRotatedEditDirect2DRenderBackend.DrawContent(
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
    //--------------------------------------------------------------------------
    //  Direct2D content branch.
    //
    // When the native Direct2D/DirectWrite resources are available, this backend
    // now draws the real Direct2D path for RenderBackend = rebDirect2D. If that
    // path is unavailable or fails, the validated GDI fallback remains the
    // safety path.
    //--------------------------------------------------------------------------
    If ShouldUseDirect2DContentPath Then
    Begin
        If DrawContentWithDirect2DPath(
            ACanvas,
            ALayout,
            AColors,
            ABackgroundBitmap,
            ABackgroundBitmapValid,
            AContentBitmap,
            AContentBitmapValid,
            AShowDebugBounds,
            ATextHint) Then
            Exit;
    End;

    FGdiFallback.DrawContent(
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

Procedure TRotatedEditDirect2DRenderBackend.DrawCaret(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ACaretVisible: Boolean);
Var
    LBindRect: TRect;
    LResult: HResult;
    LCaretBrushColor: D2D1_COLOR_F;
    LCaretBrush: ID2D1SolidColorBrush;
    LCaretGeometry: ID2D1PathGeometry;
    LCaretCanonicalQuad: TRotatedEditFloatQuad;
    LCaretActualQuad: TRotatedEditFloatQuad;
    LTextFormat: IDWriteTextFormat;
    LTextLayout: IDWriteTextLayout;
    LHitMetrics: DWRITE_HIT_TEST_METRICS;
    LCaretX: Single;
    LCaretY: Single;
    LCaretIndex: Integer;
    LCaretThickness: Double;

    Function MakeD2DPoint(AX: Double; AY: Double): D2D1_POINT_2F;
    Begin
        Result.x := Single(AX);
        Result.y := Single(AY);
    End;

    Procedure ResolveD2DColor(AColor: TColor; Var AResult: D2D1_COLOR_F);
    Var
        LColor: TColor;
    Begin
        LColor := ColorToRGB(AColor);

        FillChar(AResult, SizeOf(AResult), 0);
        AResult.r := GetRValue(LColor) / 255.0;
        AResult.g := GetGValue(LColor) / 255.0;
        AResult.b := GetBValue(LColor) / 255.0;
        AResult.a := 1.0;
    End;

    Function CreateSolidBrush(
        Const AColor: D2D1_COLOR_F;
        Var ABrush: ID2D1SolidColorBrush): Boolean;
    Begin
        Result := False;
        ABrush := Nil;

        LResult := FDCRenderTarget.CreateSolidColorBrush(
            AColor,
            Nil,
            ABrush);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            ABrush := Nil;
            Exit;
        End;

        Result := Assigned(ABrush);
    End;

    Function BuildQuadGeometry(
        Const AQuad: TRotatedEditFloatQuad;
        Var AGeometry: ID2D1PathGeometry): Boolean;
    Var
        LGeometrySink: ID2D1GeometrySink;
    Begin
        Result := False;
        AGeometry := Nil;

        LResult := FD2DFactory.CreatePathGeometry(AGeometry);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        LResult := AGeometry.Open(LGeometrySink);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        LGeometrySink.BeginFigure(
            MakeD2DPoint(AQuad.P1.X, AQuad.P1.Y),
            D2D1_FIGURE_BEGIN_FILLED);
        LGeometrySink.AddLine(MakeD2DPoint(AQuad.P2.X, AQuad.P2.Y));
        LGeometrySink.AddLine(MakeD2DPoint(AQuad.P3.X, AQuad.P3.Y));
        LGeometrySink.AddLine(MakeD2DPoint(AQuad.P4.X, AQuad.P4.Y));
        LGeometrySink.EndFigure(D2D1_FIGURE_END_CLOSED);

        LResult := LGeometrySink.Close;
        LGeometrySink := Nil;

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            AGeometry := Nil;
            Exit;
        End;

        Result := True;
    End;

    Function ResolveDWriteFontWeight: DWRITE_FONT_WEIGHT;
    Begin
        If fsBold In ACanvas.Font.Style Then
            Result := DWRITE_FONT_WEIGHT_BOLD
        Else
            Result := DWRITE_FONT_WEIGHT_NORMAL;
    End;

    Function ResolveDWriteFontStyle: DWRITE_FONT_STYLE;
    Begin
        If fsItalic In ACanvas.Font.Style Then
            Result := DWRITE_FONT_STYLE_ITALIC
        Else
            Result := DWRITE_FONT_STYLE_NORMAL;
    End;

    Function ResolveDWriteFontSize: Single;
    Begin
        If ACanvas.Font.Size > 0 Then
            Result := ACanvas.Font.Size * 96.0 / 72.0
        Else If ACanvas.Font.Height <> 0 Then
            Result := Abs(ACanvas.Font.Height)
        Else
            Result := 12.0;
    End;

    Function CreateTextFormat(Var ATextFormat: IDWriteTextFormat): Boolean;
    Begin
        //Délègue à la méthode de classe — source unique du format DirectWrite.
        Result := CreateD2DTextFormat(ACanvas, ATextFormat);
    End;

    Function CreateTextLayout(
        ATextFormat: IDWriteTextFormat;
        Var ATextLayout: IDWriteTextLayout): Boolean;
    Var
        LMaxHeight: Single;
    Begin
        //Délègue à la méthode de classe — source unique du layout DirectWrite.
        LMaxHeight := Single(ALayout.CanonicalContentRect.Height);
        Result := CreateD2DTextLayout(ALayout.Text, ATextFormat, LMaxHeight, ATextLayout);
    End;
Begin
    //--------------------------------------------------------------------------
    //  Direct2D caret Direct2D path.
    //
    // When the Direct2D content path is active, the caret is drawn
    // with Direct2D too. Its horizontal position comes from DirectWrite
    // HitTestTextPosition, matching the  selection metrics and avoiding a
    // mixed GDI/DirectWrite metric model in the Direct2D path. The resulting caret
    // quad is still built in final coordinates, following the / rule.
    //--------------------------------------------------------------------------
    If ShouldUseDirect2DContentPath Then
    Begin
        If Not ACaretVisible Then
            Exit;

        If Not Assigned(ACanvas) Then
            Exit;

        If Not Assigned(FDCRenderTarget) Then
            Exit;

        If IsRectEmpty(ALayout.ClientRect) Then
            Exit;

        LCaretIndex := ALayout.Caret.Index;

        If LCaretIndex < 0 Then
            LCaretIndex := 0;

        If LCaretIndex > Length(ALayout.Text) Then
            LCaretIndex := Length(ALayout.Text);

        LCaretX := 0.0;
        LCaretY := 0.0;

        If ALayout.Text <> '' Then
        Begin
            If Not CreateTextFormat(LTextFormat) Then
                Exit;

            If Not CreateTextLayout(LTextFormat, LTextLayout) Then
            Begin
                LTextFormat := Nil;
                Exit;
            End;

            FillChar(LHitMetrics, SizeOf(LHitMetrics), 0);

            LResult := LTextLayout.HitTestTextPosition(
                LCaretIndex,
                False,
                LCaretX,
                LCaretY,
                LHitMetrics);

            LTextLayout := Nil;
            LTextFormat := Nil;

            If LResult < 0 Then
            Begin
                FD2DState.RenderState := rddsRenderFailed;
                FD2DState.LastNativeError := LResult;
                Exit;
            End;
        End;

        LCaretThickness := ALayout.Caret.Thickness;

        If LCaretThickness < 1.0 Then
            LCaretThickness := 1.0;

        LCaretCanonicalQuad.P1 := TRotatedEditFloatPoint.Create(
            ALayout.TextOriginCanonical.X + LCaretX - (LCaretThickness / 2.0),
            ALayout.CanonicalContentRect.Top);
        LCaretCanonicalQuad.P2 := TRotatedEditFloatPoint.Create(
            ALayout.TextOriginCanonical.X + LCaretX + (LCaretThickness / 2.0),
            ALayout.CanonicalContentRect.Top);
        LCaretCanonicalQuad.P3 := TRotatedEditFloatPoint.Create(
            ALayout.TextOriginCanonical.X + LCaretX + (LCaretThickness / 2.0),
            ALayout.CanonicalContentRect.Bottom);
        LCaretCanonicalQuad.P4 := TRotatedEditFloatPoint.Create(
            ALayout.TextOriginCanonical.X + LCaretX - (LCaretThickness / 2.0),
            ALayout.CanonicalContentRect.Bottom);

        LCaretActualQuad := TRotatedEditGeometry.TransformQuad(
            LCaretCanonicalQuad,
            ALayout.ActualOrigin,
            ALayout.Angle);

        ResolveD2DColor(AColors.CaretColor, LCaretBrushColor);

        If Not CreateSolidBrush(LCaretBrushColor, LCaretBrush) Then
            Exit;

        If Not BuildQuadGeometry(LCaretActualQuad, LCaretGeometry) Then
        Begin
            LCaretBrush := Nil;
            Exit;
        End;

        LBindRect := ALayout.ClientRect;

        LResult := FDCRenderTarget.BindDC(
            ACanvas.Handle,
            LBindRect);

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsDCRenderTargetBindFailed;
            FD2DState.LastNativeError := LResult;
            LCaretGeometry := Nil;
            LCaretBrush := Nil;
            Exit;
        End;

        FDCRenderTarget.BeginDraw;
        FDCRenderTarget.FillGeometry(
            LCaretGeometry,
            LCaretBrush,
            Nil);
        LResult := FDCRenderTarget.EndDraw(Nil, Nil);

        LCaretGeometry := Nil;
        LCaretBrush := Nil;

        If LResult < 0 Then
        Begin
            FD2DState.RenderState := rddsRenderFailed;
            FD2DState.LastNativeError := LResult;
            Exit;
        End;

        FD2DState.RenderState := rddsRenderCompleted;
        FD2DState.LastNativeError := 0;
        Exit;
    End;

    FGdiFallback.DrawCaret(
        ACanvas,
        ALayout,
        AColors,
        ACaretVisible);
End;

End.
