Unit VclRotatedEdit_Render;


{
  VclRotatedEdit_Render.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Rendering support layer of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Couche de support du rendu du composant VCL VclRotatedEdit.

  Cette unité dessine le fond, la bordure, le texte, la sélection et le caret à partir du layout résolu. Elle ne décide jamais de l’index du caret, de la sélection ou de la logique d’édition.
}

Interface

Uses
    Winapi.Windows,
    System.Math,
    System.Classes,
    Vcl.Graphics,
    Vcl.Themes,
    VclRotatedEdit_Types,
    VclRotatedEdit_Style;

Type
    TRotatedEditRenderer = Class
    private
        Class Procedure PrepareBackgroundBitmap(
            ABitmap: TBitmap;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors); Static;

        Class Procedure BeginWorldTransform(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Out ASavedXForm: TXForm;
            Out ASavedGraphicsMode: Integer); Static;

        Class Procedure EndWorldTransform(
            ACanvas: TCanvas;
            Const ASavedXForm: TXForm;
            ASavedGraphicsMode: Integer); Static;

        Class Function CreateEditSurfaceRegion(
            Const ALayout: TRotatedEditLayoutResult): HRGN; Static;

        Class Function ResolveProjectedGapFillColor(
            ABackgroundBitmap: TBitmap;
            Const AColors: TRotatedEditStyleColors): TColor; Static;

        Class Function ComputeCanonicalTextY(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult): Integer; Static;

        Class Procedure DrawSelectionOnCanonicalCanvas(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors); Static;

        Class Procedure PrepareContentBitmap(
            ASourceCanvas: TCanvas;
            AContentBitmap: TBitmap;
            ABackgroundBitmap: TBitmap;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            Const ATextHint: String); Static;

    public
        Class Procedure DrawBackground(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            ABackgroundBitmap: TBitmap;
            Var ABackgroundBitmapValid: Boolean;
            AShowDebugBounds: Boolean); Static;

        Class Procedure DrawSelection(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors); Static;

        Class Procedure DrawContent(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            ABackgroundBitmap: TBitmap;
            Var ABackgroundBitmapValid: Boolean;
            AContentBitmap: TBitmap;
            Var AContentBitmapValid: Boolean;
            AShowDebugBounds: Boolean;
            Const ATextHint: String); Static;


        Class Procedure DrawCaret(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            ACaretVisible: Boolean); Static;
    End;

Implementation

Uses
    VclRotatedEdit_Geometry;



Class Procedure TRotatedEditRenderer.PrepareBackgroundBitmap(
    ABitmap: TBitmap;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors);
Var
    LFullRect: TRect;
    LClientRect: TRect;
    LDetails: TThemedElementDetails;
Begin
    //-------------------------------------------------------------------------
    //Draws the edit background and border in canonical coordinates.
    //
    //Responsibility of this method
    //-----------------------------
    //This method is the single place where the component prepares the horizontal
    //edit surface before projection. It should not invent a separate border
    //model. It chooses the appropriate existing rendering engine:
    //
    //- the resolved control StyleServices when the VCL style is enabled and
    //  seBorder participates;
    //- classic Windows/VCL drawing when styled border rendering is disabled;
    //- explicit Color filling when styled client rendering is disabled.
    //
    //Canonical rectangles
    //--------------------
    //LFullRect is the whole logical edit surface:
    //  LogicalLength x LogicalThickness.
    //
    //LClientRect is the useful inner edit area calculated by the layout engine.
    //It already accounts for border and padding choices. The renderer must not
    //recalculate a BorderWidth from those rectangles; it may only use the inner
    //rectangle as the client area to refill when seClient is disabled.
    //
    //PaletteMode rule
    //------------------
    //UseStyledBorder:
    //  The edit frame is delegated to StyleServices.DrawElement.
    //
    //not UseStyledBorder:
    //  The frame is drawn by the component as a simple flat rectangle.
    //
    //UseStyledClient:
    //  The client fill produced by the style is kept.
    //
    //not UseStyledClient:
    //  The client area is explicitly filled with BackgroundColor. This is how
    //  Color remains meaningful when seClient is excluded from StyleElements.
    //
    //Important:
    //The bitmap must stay opaque. Transparent text/content bitmaps previously
    //created color-key artifacts when projected at arbitrary angles.
    //-------------------------------------------------------------------------
    If ABitmap.Width <> ALayout.LogicalLength Then
        ABitmap.Width := ALayout.LogicalLength;

    If ABitmap.Height <> ALayout.LogicalThickness Then
        ABitmap.Height := ALayout.LogicalThickness;

    LFullRect := Rect(
        0,
        0,
        ALayout.LogicalLength,
        ALayout.LogicalThickness);

    LClientRect := ALayout.CanonicalContentRect;

    //---------------------------------------------------------------------
    //Safety fill.
    //
    //Even if the palette/frame renderer leaves a pixel untouched, the bitmap
    //remains fully opaque and uses the resolved background color as fallback.
    //---------------------------------------------------------------------
    ABitmap.Canvas.Brush.Style := bsSolid;
    ABitmap.Canvas.Brush.Color := AColors.BackgroundColor;
    ABitmap.Canvas.FillRect(LFullRect);

    If AColors.BorderVisible And
       (AColors.VclStyleServices <> Nil) And
       AColors.VclStyleServices.Enabled And
       AColors.UseStyledBorder Then Begin
        //-----------------------------------------------------------------
        //Styled border path.
        //
        //The complete edit frame is delegated to the resolved style services.
        //
        //The renderer deliberately does not choose the style source. That
        //decision belongs to TRotatedEditStyle.ResolveColors so runtime can
        //keep the already valid v76 behavior while design-time can use the
        //parent/control style context discovered in v77.
        //-----------------------------------------------------------------
        LDetails := AColors.VclStyleServices.GetElementDetails(teEditTextNormal);

        AColors.VclStyleServices.DrawElement(
            ABitmap.Canvas.Handle,
            LDetails,
            LFullRect);
    End Else If AColors.BorderVisible Then Begin
        //-----------------------------------------------------------------
        //Flat owner-drawn border path.
        //
        //This path is used when:
        //- PaletteMode is flat;
        //- or VCL styles are disabled;
        //- or seBorder is removed from PaletteMode.
        //
        //The component deliberately does not emulate Ctl3D/WS_EX_CLIENTEDGE.
        //TRotatedEdit is an owner-drawn projected edit; a clear flat fallback is
        //more predictable than a partial imitation of TEdit non-client painting.
        //-----------------------------------------------------------------
        ABitmap.Canvas.Brush.Style := bsClear;
        ABitmap.Canvas.Pen.Style := psSolid;
        ABitmap.Canvas.Pen.Width := 1;
        ABitmap.Canvas.Pen.Color := AColors.BorderColor;
        ABitmap.Canvas.Rectangle(LFullRect);
    End;

    If Not AColors.UseStyledClient Then Begin
        //-----------------------------------------------------------------
        //Classic client fill.
        //
        //When seClient is excluded from StyleElements, the style is allowed to
        //draw the border only, but the editable client area must use the
        //resolved Color value.
        //
        //The client rectangle comes from the layout engine. This avoids
        //duplicating border-width logic in the renderer.
        //-----------------------------------------------------------------
        If Not IsRectEmpty(LClientRect) Then Begin
            ABitmap.Canvas.Brush.Style := bsSolid;
            ABitmap.Canvas.Brush.Color := AColors.BackgroundColor;
            ABitmap.Canvas.FillRect(LClientRect);
        End;
    End;
End;

Class Procedure TRotatedEditRenderer.BeginWorldTransform(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Out ASavedXForm: TXForm;
    Out ASavedGraphicsMode: Integer);
Var
    LRad: Double;
    LCos: Double;
    LSin: Double;
    LXForm: TXForm;
Begin
    //-------------------------------------------------------------------------
    //Applies the same canonical -> actual projection used by the layout engine.
    //
    //Any drawing performed while this transform is active may use canonical
    //coordinates directly.
    //-------------------------------------------------------------------------

    ASavedGraphicsMode := SetGraphicsMode(
        ACanvas.Handle,
        GM_ADVANCED);

    GetWorldTransform(
        ACanvas.Handle,
        ASavedXForm);

    //Positive angles are counter-clockwise in the public API.
    //Because Windows Y coordinates grow downward, the drawing transform
    //uses the inverted mathematical sign, exactly like Geometry.TransformPoint.
    LRad := -ALayout.Angle * Pi / 180.0;
    LCos := Cos(LRad);
    LSin := Sin(LRad);

    LXForm.eM11 := LCos;
    LXForm.eM12 := LSin;
    LXForm.eM21 := -LSin;
    LXForm.eM22 := LCos;
    LXForm.eDx := ALayout.ActualOrigin.X;
    LXForm.eDy := ALayout.ActualOrigin.Y;

    SetWorldTransform(
        ACanvas.Handle,
        LXForm);
End;

Class Procedure TRotatedEditRenderer.EndWorldTransform(
    ACanvas: TCanvas;
    Const ASavedXForm: TXForm;
    ASavedGraphicsMode: Integer);
Begin
    SetWorldTransform(
        ACanvas.Handle,
        ASavedXForm);

    SetGraphicsMode(
        ACanvas.Handle,
        ASavedGraphicsMode);
End;


Class Function TRotatedEditRenderer.CreateEditSurfaceRegion(
    Const ALayout: TRotatedEditLayoutResult): HRGN;
Var
    LPoints: Array[0..3] Of TPoint;
Begin
    //-------------------------------------------------------------------------
    //Creates a region from the projected edit surface.
    //
    //This is used only as a painting helper. Unlike SetWindowRgn, this region
    //is not transferred to Windows ownership and must be deleted by the caller.
    //-------------------------------------------------------------------------
    LPoints[0] := Point(
        Round(ALayout.ActualEditQuad.P1.X),
        Round(ALayout.ActualEditQuad.P1.Y));

    LPoints[1] := Point(
        Round(ALayout.ActualEditQuad.P2.X),
        Round(ALayout.ActualEditQuad.P2.Y));

    LPoints[2] := Point(
        Round(ALayout.ActualEditQuad.P3.X),
        Round(ALayout.ActualEditQuad.P3.Y));

    LPoints[3] := Point(
        Round(ALayout.ActualEditQuad.P4.X),
        Round(ALayout.ActualEditQuad.P4.Y));

    Result := CreatePolygonRgn(
        LPoints,
        Length(LPoints),
        WINDING);
End;

Class Function TRotatedEditRenderer.ResolveProjectedGapFillColor(
    ABackgroundBitmap: TBitmap;
    Const AColors: TRotatedEditStyleColors): TColor;
Var
    LX: Integer;
    LY: Integer;
Begin
    //-------------------------------------------------------------------------
    //Resolves the color used to pre-fill tiny projected gaps.
    //
    //Why this method samples the background bitmap
    //--------------------------------------------
    //The pre-fill is not a semantic style choice. It is only an anti-artifact
    //operation used before drawing a rotated bitmap. The safest color is
    //therefore the color actually painted by the style in the canonical
    //background bitmap.
    //
    //Do not sample the content bitmap here.
    //
    //The content bitmap contains text and selection. Sampling it can pick an
    //anti-aliased text pixel, a selection pixel or some other dynamic content
    //color, which creates visible colored/rose lines on the projected edge.
    //
    //Fallback:
    //If the background bitmap is not available, use AColors.BackgroundColor.
    //-------------------------------------------------------------------------
    Result := AColors.BackgroundColor;

    If ABackgroundBitmap = Nil Then
        Exit;

    If (ABackgroundBitmap.Width <= 0) Or (ABackgroundBitmap.Height <= 0) Then
        Exit;

    LX := ABackgroundBitmap.Width Div 2;
    LY := ABackgroundBitmap.Height Div 2;

    Result := ABackgroundBitmap.Canvas.Pixels[LX, LY];
End;

Class Procedure TRotatedEditRenderer.DrawBackground(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ABackgroundBitmap: TBitmap;
    Var ABackgroundBitmapValid: Boolean;
    AShowDebugBounds: Boolean);
Var
    LSavedXForm: TXForm;
    LSavedGraphicsMode: Integer;
    LEditRegion: HRGN;
Begin
    //-------------------------------------------------------------------------
    //Do not fill ALayout.ClientRect here.
    //
    //The physical VCL rectangle may be much larger than the projected edit
    //surface, especially for arbitrary angles. Pixels outside the projected
    //surface must remain visually transparent and let the parent show through.
    //-------------------------------------------------------------------------
    If ABackgroundBitmap = Nil Then
        Exit;

    If Not ABackgroundBitmapValid Then Begin
        PrepareBackgroundBitmap(
            ABackgroundBitmap,
            ALayout,
            AColors);

        ABackgroundBitmapValid := True;
    End;

    //-------------------------------------------------------------------------
    //Pre-fill the actual projected region before drawing the rotated bitmap.
    //
    //Why this is needed:
    //At arbitrary angles, GDI bitmap projection can leave a thin unpainted strip
    //along one edge because source bitmap pixels and destination polygon pixels
    //do not map perfectly.
    //
    //Why FillRgn instead of a transformed Rectangle:
    //The region is already the actual projected edit surface. Filling it in
    //actual coordinates avoids another transform/rounding step.
    //
    //Why the color is sampled from the bitmap:
    //AColors.BackgroundColor is a logical fallback. In styled applications the
    //actual edit interior may be different. Sampling the prepared background
    //bitmap avoids filling the strip with white when the style interior is dark.
    //-------------------------------------------------------------------------
    LEditRegion := CreateEditSurfaceRegion(ALayout);
    Try
        If LEditRegion <> 0 Then Begin
            ACanvas.Brush.Style := bsSolid;
            ACanvas.Brush.Color := ResolveProjectedGapFillColor(
                ABackgroundBitmap,
                AColors);

            FillRgn(
                ACanvas.Handle,
                LEditRegion,
                ACanvas.Brush.Handle);
        End;
    Finally
        If LEditRegion <> 0 Then
            DeleteObject(LEditRegion);
    End;

    BeginWorldTransform(
        ACanvas,
        ALayout,
        LSavedXForm,
        LSavedGraphicsMode);
    Try
        ACanvas.Draw(
            0,
            0,
            ABackgroundBitmap);
    Finally
        EndWorldTransform(
            ACanvas,
            LSavedXForm,
            LSavedGraphicsMode);
    End;

    If AShowDebugBounds Then Begin
        //---------------------------------------------------------------------
        //Debug only.
        //
        //This rectangle is the physical VCL bounding box. It is intentionally
        //not the edit surface. The actual editable surface is the projected
        //LogicalLength x LogicalThickness bitmap.
        //---------------------------------------------------------------------
        ACanvas.Brush.Style := bsClear;
        ACanvas.Pen.Style := psDot;
        ACanvas.Pen.Width := 1;
        ACanvas.Pen.Color := clRed;
        ACanvas.Rectangle(ALayout.ClientRect);
        ACanvas.Pen.Style := psSolid;
    End;


    BeginWorldTransform(
        ACanvas,
        ALayout,
        LSavedXForm,
        LSavedGraphicsMode);
    Try
        //---------------------------------------------------------------------
        //Fill projected edit region before drawing the cached bitmap.
        //
        //At arbitrary angles some GDI bitmap projections can leave a one-pixel
        //unpainted strip along an edge because of rounding. Filling the same
        //canonical rectangle under the same world transform removes that visual
        //artifact before the styled bitmap is drawn.
        //---------------------------------------------------------------------
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := AColors.BackgroundColor;
        ACanvas.Pen.Style := psClear;
        ACanvas.Rectangle(
            0,
            0,
            ALayout.LogicalLength,
            ALayout.LogicalThickness);
        ACanvas.Pen.Style := psSolid;

        ACanvas.Draw(
            0,
            0,
            ABackgroundBitmap);
    Finally
        EndWorldTransform(
            ACanvas,
            LSavedXForm,
            LSavedGraphicsMode);
    End;
End;

Class Procedure TRotatedEditRenderer.DrawSelection(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors);
Var
    I: Integer;
    LPoints: Array[0..3] Of TPoint;
Begin
    //-------------------------------------------------------------------------
    //Draws the selected background.
    //
    //Selection geometry is already computed by the layout engine as actual
    //quads. The renderer must not recalculate SelStart/SelLength or try to
    //build a screen-aligned rectangle.
    //
    //Text color note:
    //This method paints the selection background only. Rendering selected text
    //with SelectionTextColor will require splitting DrawText into selected and
    //unselected text segments or clipping text against the selection region.
    //That is a separate phase. The important rule already established here is
    //that selection background is geometric and rotation-safe.
    //-------------------------------------------------------------------------
    If Length(ALayout.SelectionQuads) = 0 Then
        Exit;

    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColors.SelectionColor;
    ACanvas.Pen.Style := psClear;

    For I := 0 To High(ALayout.SelectionQuads) Do Begin
        LPoints[0] := Point(
            Round(ALayout.SelectionQuads[I].P1.X),
            Round(ALayout.SelectionQuads[I].P1.Y));

        LPoints[1] := Point(
            Round(ALayout.SelectionQuads[I].P2.X),
            Round(ALayout.SelectionQuads[I].P2.Y));

        LPoints[2] := Point(
            Round(ALayout.SelectionQuads[I].P3.X),
            Round(ALayout.SelectionQuads[I].P3.Y));

        LPoints[3] := Point(
            Round(ALayout.SelectionQuads[I].P4.X),
            Round(ALayout.SelectionQuads[I].P4.Y));

        ACanvas.Polygon(LPoints);
    End;

    ACanvas.Pen.Style := psSolid;
End;



Class Function TRotatedEditRenderer.ComputeCanonicalTextY(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult): Integer;
Var
    LTextMetric: TTextMetric;
    LContentHeight: Integer;
    LTextHeight: Integer;
Begin
    //-------------------------------------------------------------------------
    //Computes the canonical Y coordinate passed to TextOut.
    //
    //This method is kept in the renderer because it depends on the actual
    //selected canvas font. The layout engine only estimates text thickness; the
    //renderer owns the final top coordinate used by TextOut.
    //
    //Important rule:
    //TextOut positions the complete font cell. The safest first approximation
    //is therefore to center tmHeight inside CanonicalContentRect. Previous tests
    //showed that subtracting tmInternalLeading moved the text too high, while
    //centering only tmHeight - tmInternalLeading moved it too low.
    //
    //Do not replace this with DrawText(DT_VCENTER) without also reviewing the
    //caret and hit-test metrics. DrawText previously introduced a horizontal
    //caret/text mismatch.
    //-------------------------------------------------------------------------
    GetTextMetrics(
        ACanvas.Handle,
        LTextMetric);

    LContentHeight := ALayout.CanonicalContentRect.Height;
    LTextHeight := LTextMetric.tmHeight;

    If LTextHeight < 1 Then
        LTextHeight := ALayout.TextThickness;

    Result := ALayout.CanonicalContentRect.Top +
        ((LContentHeight - LTextHeight) Div 2);
End;

Class Procedure TRotatedEditRenderer.DrawSelectionOnCanonicalCanvas(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors);
Var
    I: Integer;
    LQuad: TRotatedEditFloatQuad;
    LCanonicalQuad: TRotatedEditFloatQuad;
    LPoints: Array[0..3] Of TPoint;
Begin
    //-------------------------------------------------------------------------
    //Draws selection into a canonical bitmap.
    //
    //ALayout.SelectionQuads are stored in actual coordinates because the older
    //renderer drew selection directly on the final canvas. For content-bitmap
    //composition, we need canonical coordinates.
    //
    //For the current single-line V1 component the selection geometry is also
    //available through the text/caret model, but keeping this method based on
    //inverse projection makes the renderer robust if selection generation later
    //returns several quads.
    //
    //The selected text itself is still drawn with the normal text color. A later
    //pass can split text rendering to draw selected glyphs with
    //SelectionTextColor. The important change here is that the selection
    //background is part of the same opaque projected surface as the text.
    //-------------------------------------------------------------------------
    If Length(ALayout.SelectionQuads) = 0 Then
        Exit;

    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := AColors.SelectionColor;
    ACanvas.Pen.Style := psClear;

    For I := 0 To High(ALayout.SelectionQuads) Do Begin
        LQuad := ALayout.SelectionQuads[I];

        LCanonicalQuad.P1 := TRotatedEditGeometry.InverseTransformPoint(
            LQuad.P1,
            ALayout.ActualOrigin,
            ALayout.Angle);

        LCanonicalQuad.P2 := TRotatedEditGeometry.InverseTransformPoint(
            LQuad.P2,
            ALayout.ActualOrigin,
            ALayout.Angle);

        LCanonicalQuad.P3 := TRotatedEditGeometry.InverseTransformPoint(
            LQuad.P3,
            ALayout.ActualOrigin,
            ALayout.Angle);

        LCanonicalQuad.P4 := TRotatedEditGeometry.InverseTransformPoint(
            LQuad.P4,
            ALayout.ActualOrigin,
            ALayout.Angle);

        LPoints[0] := Point(
            Round(LCanonicalQuad.P1.X),
            Round(LCanonicalQuad.P1.Y));

        LPoints[1] := Point(
            Round(LCanonicalQuad.P2.X),
            Round(LCanonicalQuad.P2.Y));

        LPoints[2] := Point(
            Round(LCanonicalQuad.P3.X),
            Round(LCanonicalQuad.P3.Y));

        LPoints[3] := Point(
            Round(LCanonicalQuad.P4.X),
            Round(LCanonicalQuad.P4.Y));

        ACanvas.Polygon(LPoints);
    End;

    ACanvas.Pen.Style := psSolid;
End;

Class Procedure TRotatedEditRenderer.PrepareContentBitmap(
    ASourceCanvas: TCanvas;
    AContentBitmap: TBitmap;
    ABackgroundBitmap: TBitmap;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    Const ATextHint: String);
Var
    LSavedBkMode: Integer;
    LSavedDC: Integer;
    LTextY: Integer;
    LClipRegion: HRGN;
    LDisplayText: String;
    LDisplayTextColor: TColor;
Begin
    //-------------------------------------------------------------------------
    //Builds the complete opaque canonical content surface.
    //
    //This method replaces the previous transparent text bitmap.
    //
    //Composition order:
    //1. copy the canonical styled background/border;
    //2. draw selection background in canonical coordinates;
    //3. draw text horizontally in canonical coordinates.
    //
    //Why opaque?
    //The separate transparent text bitmap used clFuchsia as a color key. That
    //color appeared on screen when the bitmap was projected. An opaque content
    //bitmap has no color key and therefore no pink artifact.
    //
    //Why canonical?
    //Text is drawn horizontally in the same coordinate system used by the layout
    //metrics. The complete content bitmap is then projected as one surface.
    //
    //Caret rule:
    //The caret is not drawn here. It blinks independently and remains a separate
    //projected segment drawn by DrawCaret.
    //-------------------------------------------------------------------------
    If AContentBitmap.Width <> ALayout.LogicalLength Then
        AContentBitmap.Width := ALayout.LogicalLength;

    If AContentBitmap.Height <> ALayout.LogicalThickness Then
        AContentBitmap.Height := ALayout.LogicalThickness;

    AContentBitmap.PixelFormat := pf32bit;
    AContentBitmap.Transparent := False;

    If ABackgroundBitmap <> Nil Then
        AContentBitmap.Canvas.Draw(
            0,
            0,
            ABackgroundBitmap)
    Else Begin
        AContentBitmap.Canvas.Brush.Style := bsSolid;
        AContentBitmap.Canvas.Brush.Color := AColors.BackgroundColor;
        AContentBitmap.Canvas.FillRect(
            Rect(
                0,
                0,
                ALayout.LogicalLength,
                ALayout.LogicalThickness));
    End;

    DrawSelectionOnCanonicalCanvas(
        AContentBitmap.Canvas,
        ALayout,
        AColors);

    AContentBitmap.Canvas.Font.Assign(ASourceCanvas.Font);

    LDisplayText := ALayout.Text;
    LDisplayTextColor := AColors.TextColor;

    If (LDisplayText = '') And (ATextHint <> '') Then Begin
        //---------------------------------------------------------------------
        //TextHint rule.
        //
        //The placeholder is rendering-only. It is not part of ALayout.Text and
        //therefore does not affect hit-testing, selection, caret placement or
        //scrolling.
        //---------------------------------------------------------------------
        LDisplayText := ATextHint;
        LDisplayTextColor := AColors.HintTextColor;
    End;

    AContentBitmap.Canvas.Font.Color := LDisplayTextColor;

    LSavedBkMode := SetBkMode(
        AContentBitmap.Canvas.Handle,
        TRANSPARENT);

    LSavedDC := SaveDC(AContentBitmap.Canvas.Handle);
    Try
        //---------------------------------------------------------------------
        //Text clipping rule.
        //
        //The content bitmap contains the whole logical edit surface: border,
        //background, selection and text. The text itself must stay inside the
        //canonical content rectangle. Without this clipping, a long horizontal
        //text can draw a few pixels over the right border before the whole
        //bitmap is projected.
        //
        //The clipping is deliberately done here, in canonical coordinates,
        //before the complete bitmap is rotated/projected.
        //---------------------------------------------------------------------
        LClipRegion := CreateRectRgn(
            ALayout.CanonicalContentRect.Left,
            ALayout.CanonicalContentRect.Top,
            ALayout.CanonicalContentRect.Right,
            ALayout.CanonicalContentRect.Bottom);
        Try
            SelectClipRgn(
                AContentBitmap.Canvas.Handle,
                LClipRegion);

            LTextY := ComputeCanonicalTextY(
                AContentBitmap.Canvas,
                ALayout);

            If ALayout.Text = '' Then
                AContentBitmap.Canvas.TextOut(
                    ALayout.CanonicalContentRect.Left,
                    LTextY,
                    LDisplayText)
            Else
                AContentBitmap.Canvas.TextOut(
                    Round(ALayout.TextOriginCanonical.X),
                    LTextY,
                    LDisplayText);
        Finally
            DeleteObject(LClipRegion);
        End;
    Finally
        RestoreDC(
            AContentBitmap.Canvas.Handle,
            LSavedDC);

        SetBkMode(
            AContentBitmap.Canvas.Handle,
            LSavedBkMode);
    End;
End;

Class Procedure TRotatedEditRenderer.DrawContent(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ABackgroundBitmap: TBitmap;
    Var ABackgroundBitmapValid: Boolean;
    AContentBitmap: TBitmap;
    Var AContentBitmapValid: Boolean;
    AShowDebugBounds: Boolean;
    Const ATextHint: String);
Var
    LSavedXForm: TXForm;
    LSavedGraphicsMode: Integer;
    LEditRegion: HRGN;
Begin
    //-------------------------------------------------------------------------
    //Draws the complete non-caret content.
    //
    //This method is now the normal rendering entry point for the edit surface.
    //It prepares the background cache if needed, composes the opaque content
    //bitmap if needed, pre-fills the actual projected region to avoid thin GDI
    //projection strips, and projects the content bitmap.
    //
    //The caret remains outside this pipeline so the blink timer does not
    //invalidate or rebuild background/content surfaces.
    //-------------------------------------------------------------------------
    If AContentBitmap = Nil Then
        Exit;

    If (ABackgroundBitmap <> Nil) And Not ABackgroundBitmapValid Then Begin
        PrepareBackgroundBitmap(
            ABackgroundBitmap,
            ALayout,
            AColors);

        ABackgroundBitmapValid := True;
        AContentBitmapValid := False;
    End;

    If Not AContentBitmapValid Then Begin
        PrepareContentBitmap(
            ACanvas,
            AContentBitmap,
            ABackgroundBitmap,
            ALayout,
            AColors,
            ATextHint);

        AContentBitmapValid := True;
    End;

    //-------------------------------------------------------------------------
    //Pre-fill the actual projected region.
    //
    //Even with an opaque bitmap, arbitrary-angle bitmap projection can leave a
    //thin strip because of pixel rounding. Filling the actual polygon with the
    //same color as the styled background bitmap prevents visible holes without
    //sampling text or selection pixels from the content bitmap.
    //-------------------------------------------------------------------------
    LEditRegion := CreateEditSurfaceRegion(ALayout);
    Try
        If LEditRegion <> 0 Then Begin
            ACanvas.Brush.Style := bsSolid;
            ACanvas.Brush.Color := ResolveProjectedGapFillColor(
                ABackgroundBitmap,
                AColors);

            FillRgn(
                ACanvas.Handle,
                LEditRegion,
                ACanvas.Brush.Handle);
        End;
    Finally
        If LEditRegion <> 0 Then
            DeleteObject(LEditRegion);
    End;

    BeginWorldTransform(
        ACanvas,
        ALayout,
        LSavedXForm,
        LSavedGraphicsMode);
    Try
        ACanvas.Draw(
            0,
            0,
            AContentBitmap);
    Finally
        EndWorldTransform(
            ACanvas,
            LSavedXForm,
            LSavedGraphicsMode);
    End;

    If AShowDebugBounds Then Begin
        ACanvas.Brush.Style := bsClear;
        ACanvas.Pen.Style := psDot;
        ACanvas.Pen.Width := 1;
        ACanvas.Pen.Color := clRed;
        ACanvas.Rectangle(ALayout.ClientRect);
        ACanvas.Pen.Style := psSolid;
    End;
End;



Class Procedure TRotatedEditRenderer.DrawCaret(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ACaretVisible: Boolean);
Begin
    If Not ACaretVisible Then
        Exit;

    //-------------------------------------------------------------------------
    //Caret rendering rule.
    //
    //The caret is dynamic and must not be part of the cached background.
    //
    //The layout engine owns caret geometry. Rendering only draws the already
    //projected actual segment.
    //
    //Important:
    //ActualSegmentStart / ActualSegmentEnd must be produced by the same angle
    //convention as the text renderer. If the caret does not follow the text,
    //fix the shared projection convention, not this drawing code.
    //
    //This direct actual-coordinate drawing is intentional. Some GDI operations
    //do not behave consistently under world transform depending on the driver
    //and canvas state. The layout projection is deterministic and shared with
    //hit-testing.
    //-------------------------------------------------------------------------
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := AColors.CaretColor;

    ACanvas.MoveTo(
        Round(ALayout.Caret.ActualSegmentStart.X),
        Round(ALayout.Caret.ActualSegmentStart.Y));

    ACanvas.LineTo(
        Round(ALayout.Caret.ActualSegmentEnd.X),
        Round(ALayout.Caret.ActualSegmentEnd.Y));
End;

End.
