Unit VclRotatedEdit_Render;


{
  VclRotatedEdit_Render.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Historical GDI rendering support layer of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Couche de support du rendu GDI historique du composant VCL VclRotatedEdit.

  Cette unité dessine le fond, la bordure, le texte, la sélection et le caret à partir du layout résolu en utilisant le pipeline GDI historique. Elle est désormais appelée uniquement par le backend GDI.

  TODO GDI / post-Direct2D
  -----------------------
  Le pipeline GDI historique projette encore certaines surfaces préparées dans
  un bitmap canonique droit vers le quadrilatère final du contrôle. Ce modèle a
  montré ses limites sur les faibles angles : un cadre fin ou stylé, déjà
  rastérisé dans le bitmap source, peut être épaissi ou dédoublé par la
  projection GDI.

  Si le backend GDI devait être repris plus tard, la règle à viser serait la
  même que pour Direct2D : utiliser le bitmap uniquement comme double-buffer
  final, c'est-à-dire comme surface déjà orientée, puis dessiner fond, cadre,
  texte, sélection et caret directement dans le repère final. Il ne faut pas
  ajouter de nouveaux chemins qui dessinent un contrôle droit pour le tourner
  après coup.
}

Interface

Uses
    Winapi.Windows,
    System.Math,
    System.Classes,
    Vcl.Graphics,
    Vcl.Themes,
    VclRotatedEdit_Types,
    VclRotatedEdit_Layout,
    VclRotatedEdit_Style;

Type
    TRotatedEditGDIRenderer = Class
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

        Class Procedure DrawProjectedBitmap(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            ABitmap: TBitmap); Static;

        Class Function CreateEditSurfaceRegion(
            Const ALayout: TRotatedEditLayoutResult): HRGN; Static;

        Class Function ResolveProjectedGapFillColor(
            ABackgroundBitmap: TBitmap;
            Const AColors: TRotatedEditStyleColors): TColor; Static;

        Class Function ComputeCanonicalTextY(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult): Integer; Static;

        Class Function IsOrthogonalAngle(
            AAngle: Double): Boolean; Static;

        Class Function CreateRotationSafeFont(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult): HFONT; Static;

        Class Function CreateContentClipRegion(
            Const ALayout: TRotatedEditLayoutResult): HRGN; Static;

        Class Procedure DrawTextDirectOnFinalCanvas(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AColors: TRotatedEditStyleColors;
            Const ATextHint: String); Static;

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

    {
      Backward-compatible public type name.

      The backend refactor briefly renamed the historical renderer helper from
      TRotatedEditRenderer to TRotatedEditGDIRenderer. That rename is not worth
      the package/DCU/build-path fragility it introduces during a corrective
      release. Keeping this alias lets both names resolve while the source base
      is being stabilized.
    }
    TRotatedEditRenderer = TRotatedEditGDIRenderer;

Implementation

Uses
    VclRotatedEdit_Geometry;



Class Procedure TRotatedEditGDIRenderer.PrepareBackgroundBitmap(
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
        //keep the established runtime behavior while design-time can use the
        //parent/control style context resolved for the designed form.
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

Class Procedure TRotatedEditGDIRenderer.BeginWorldTransform(
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

Class Procedure TRotatedEditGDIRenderer.EndWorldTransform(
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


Class Procedure TRotatedEditGDIRenderer.DrawProjectedBitmap(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    ABitmap: TBitmap);
Var
    LDestPoints: Array [0 .. 2] Of TPoint;
    LOldStretchMode: Integer;
Begin
    //-------------------------------------------------------------------------
    //Projects a canonical bitmap onto the actual rotated edit parallelogram.
    //
    //Important GDI fallback rule:
    //Do not draw cached bitmaps through SetWorldTransform + TCanvas.Draw. That
    //path eventually relies on BitBlt-like raster operations whose behavior is
    //driver-dependent for rotations and shears. Around shallow arbitrary angles
    //(for example 10/11 degrees), it can produce corrupted or apparently random
    //pixels although the canonical bitmap itself is valid.
    //
    //PlgBlt is the GDI API designed to copy a rectangular source bitmap into an
    //arbitrary destination parallelogram. The three destination points are:
    //- upper-left  = canonical P1 projected to actual coordinates;
    //- upper-right = canonical P2 projected to actual coordinates;
    //- lower-left  = canonical P4 projected to actual coordinates.
    //
    //The source bitmap is intentionally opaque, so no mask is supplied.
    //-------------------------------------------------------------------------
    If ABitmap = Nil Then
        Exit;

    If (ABitmap.Width <= 0) Or (ABitmap.Height <= 0) Then
        Exit;

    LDestPoints[0] := Point(
        Round(ALayout.ActualEditQuad.P1.X),
        Round(ALayout.ActualEditQuad.P1.Y));

    LDestPoints[1] := Point(
        Round(ALayout.ActualEditQuad.P2.X),
        Round(ALayout.ActualEditQuad.P2.Y));

    LDestPoints[2] := Point(
        Round(ALayout.ActualEditQuad.P4.X),
        Round(ALayout.ActualEditQuad.P4.Y));

    LOldStretchMode := SetStretchBltMode(
        ACanvas.Handle,
        HALFTONE);
    Try
        SetBrushOrgEx(
            ACanvas.Handle,
            0,
            0,
            Nil);

        PlgBlt(
            ACanvas.Handle,
            LDestPoints,
            ABitmap.Canvas.Handle,
            0,
            0,
            ABitmap.Width,
            ABitmap.Height,
            0,
            0,
            0);
    Finally
        SetStretchBltMode(
            ACanvas.Handle,
            LOldStretchMode);
    End;
End;


Class Function TRotatedEditGDIRenderer.CreateEditSurfaceRegion(
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

Class Function TRotatedEditGDIRenderer.ResolveProjectedGapFillColor(
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

Class Procedure TRotatedEditGDIRenderer.DrawBackground(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    ABackgroundBitmap: TBitmap;
    Var ABackgroundBitmapValid: Boolean;
    AShowDebugBounds: Boolean);
Var
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

    DrawProjectedBitmap(
        ACanvas,
        ALayout,
        ABackgroundBitmap);

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

End;

Class Procedure TRotatedEditGDIRenderer.DrawSelection(
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



Class Function TRotatedEditGDIRenderer.ComputeCanonicalTextY(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult): Integer;
Begin
    //-------------------------------------------------------------------------
    //Returns the canonical top coordinate owned by the layout engine.
    //
    //The renderer must not recompute vertical centering independently. Text,
    //caret, selection and hit-testing all depend on TextOriginCanonical.Y. If
    //the renderer applies a local Y correction here, the visible text can drift
    //away from the caret and from mouse hit-testing.
    //
    //The GDI layout currently derives TextOriginCanonical.Y from tmHeight and
    //tmInternalLeading. A future DirectWrite backend will provide its own metric
    //model through its own layout implementation.
    //-------------------------------------------------------------------------
    Result := Round(ALayout.TextOriginCanonical.Y);
End;

Class Function TRotatedEditGDIRenderer.IsOrthogonalAngle(
    AAngle: Double): Boolean;
Var
    LAngle: Double;
    LNearestQuarter: Double;
Begin
    //-------------------------------------------------------------------------
    //Returns True for the four angles where ClearType/subpixel orientation is
    //not problematic for the historical GDI renderer.
    //
    //For arbitrary angles the renderer must avoid ClearType. ClearType is a
    //subpixel technique tied to the physical horizontal RGB order of the
    //monitor. Once glyphs are rotated, especially at shallow angles such as
    //9, 10, 11 or 20 degrees, color fringes can become severe and may look like
    //random corrupted pixels.
    //-------------------------------------------------------------------------
    LAngle := TRotatedEditGeometry.NormalizeAngle(AAngle);
    LNearestQuarter := Round(LAngle / 90.0) * 90.0;

    Result := Abs(LAngle - LNearestQuarter) < 0.001;
End;

Class Function TRotatedEditGDIRenderer.CreateRotationSafeFont(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult): HFONT;
Var
    LLogFont: TLogFont;
Begin
    //-------------------------------------------------------------------------
    //Creates a temporary font suitable for direct rotated GDI text output.
    //
    //Why this helper exists
    //----------------------
    //The old GDI fallback rendered text horizontally into a cached bitmap and
    //then projected that bitmap at the edit angle. That is unsafe when the font
    //uses ClearType: the subpixel RGB data is already baked into the bitmap in
    //horizontal screen order, and rotating the bitmap makes those color samples
    //visible as blue/orange/green fragments.
    //
    //The corrected fallback draws text directly on the final canvas while the
    //same world transform as the geometry pipeline is active. The font itself
    //must stay unrotated: the world transform owns the rotation. This avoids the
    //double-model problem where the text anchor is transformed manually while
    //GDI also applies lfEscapement / lfOrientation to the glyphs.
    //
    //For arbitrary angles the cloned font disables ClearType and uses grayscale
    //antialiasing. That is the actual bug fix: the text is rasterized after the
    //rotation model is active, instead of rotating an already ClearType-colored
    //bitmap.
    //
    //Orthogonal angles keep the source quality. They do not suffer from the
    //same subpixel resampling issue and preserving the original quality keeps
    //horizontal rendering visually close to a normal TEdit.
    //-------------------------------------------------------------------------
    Result := 0;

    FillChar(
        LLogFont,
        SizeOf(LLogFont),
        0);

    If GetObject(
        ACanvas.Font.Handle,
        SizeOf(LLogFont),
        @LLogFont) = 0 Then
        Exit;

    LLogFont.lfEscapement := 0;
    LLogFont.lfOrientation := 0;

    If Not IsOrthogonalAngle(ALayout.Angle) Then
        LLogFont.lfQuality := ANTIALIASED_QUALITY;

    Result := CreateFontIndirect(LLogFont);
End;

Class Function TRotatedEditGDIRenderer.CreateContentClipRegion(
    Const ALayout: TRotatedEditLayoutResult): HRGN;
Var
    LPoints: Array[0..3] Of TPoint;
Begin
    //-------------------------------------------------------------------------
    //Creates a clipping region from the projected canonical content rectangle.
    //
    //The text is now drawn directly on the final canvas, not inside the cached
    //content bitmap. Therefore the old canonical rectangular clip used by
    //PrepareContentBitmap is no longer sufficient. The clip must be expressed
    //in actual coordinates and must follow the rotated content quad.
    //-------------------------------------------------------------------------
    LPoints[0] := Point(
        Round(ALayout.ActualContentQuad.P1.X),
        Round(ALayout.ActualContentQuad.P1.Y));

    LPoints[1] := Point(
        Round(ALayout.ActualContentQuad.P2.X),
        Round(ALayout.ActualContentQuad.P2.Y));

    LPoints[2] := Point(
        Round(ALayout.ActualContentQuad.P3.X),
        Round(ALayout.ActualContentQuad.P3.Y));

    LPoints[3] := Point(
        Round(ALayout.ActualContentQuad.P4.X),
        Round(ALayout.ActualContentQuad.P4.Y));

    Result := CreatePolygonRgn(
        LPoints,
        Length(LPoints),
        WINDING);
End;

Class Procedure TRotatedEditGDIRenderer.DrawTextDirectOnFinalCanvas(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AColors: TRotatedEditStyleColors;
    Const ATextHint: String);
Var
    LDisplayText: String;
    LDisplayTextColor: TColor;
    LTextY: Integer;
    LClipRegion: HRGN;
    LSavedDC: Integer;
    LSavedBkMode: Integer;
    LSavedTextAlign: UINT;
    LSavedXForm: TXForm;
    LSavedGraphicsMode: Integer;
    LFont: HFONT;
    LOldFont: HGDIOBJ;
    LTextMetric: TTextMetric;
    LTextBaselineY: Integer;
Begin
    //-------------------------------------------------------------------------
    //Draws the editable text directly on the final canvas.
    //
    //This is the critical bug fix for the GDI backend.
    //
    //Old pipeline:
    //  TextOut with possible ClearType -> cached bitmap -> rotated bitmap.
    //
    //Corrected GDI fallback:
    //  final canvas clip -> world transform -> TextOut in canonical coords.
    //
    //This keeps glyph rasterization in the final orientation and avoids rotating
    //an already subpixel-rasterized text bitmap. It also keeps the same canonical
    //coordinates as the existing layout/caret model, so the fallback remains
    //compatible with the current hit-test and scroll calculations.
    //
    //Selection text color:
    //The historical renderer did not split the string into selected/unselected
    //runs. This fix preserves that behavior intentionally. A later improvement
    //can draw selected runs separately, but it must be done in the same backend
    //that owns text metrics.
    //-------------------------------------------------------------------------
    LDisplayText := ALayout.Text;
    LDisplayTextColor := AColors.TextColor;

    If (LDisplayText = '') And (ATextHint <> '') Then Begin
        LDisplayText := ATextHint;
        LDisplayTextColor := AColors.HintTextColor;
    End;

    If LDisplayText = '' Then
        Exit;

    LFont := CreateRotationSafeFont(
        ACanvas,
        ALayout);

    If LFont = 0 Then
        Exit;

    LClipRegion := CreateContentClipRegion(ALayout);
    LSavedDC := SaveDC(ACanvas.Handle);
    LOldFont := 0;
    Try
        If LClipRegion <> 0 Then
            SelectClipRgn(
                ACanvas.Handle,
                LClipRegion);

        LOldFont := SelectObject(
            ACanvas.Handle,
            LFont);

        SetTextColor(
            ACanvas.Handle,
            ColorToRGB(LDisplayTextColor));

        LSavedBkMode := SetBkMode(
            ACanvas.Handle,
            TRANSPARENT);

        LSavedTextAlign := SetTextAlign(
            ACanvas.Handle,
            TA_LEFT Or TA_BASELINE Or TA_NOUPDATECP);
        Try
            //-----------------------------------------------------------------
            //Direct rotated-text cross-axis centering rule.
            //
            //This path deliberately keeps the same world transform as the
            //background, selection and caret geometry. The previous attempt to
            //draw with a manually transformed anchor plus lfEscapement created
            //a second rotation model and could make the text turn in the wrong
            //direction on some Delphi/GDI combinations.
            //
            //The only change compared with the first antialias fix is the text
            //anchor: instead of using TA_TOP, the renderer uses TA_BASELINE and
            //computes the canonical baseline from the selected rotation-safe
            //font metrics. Baseline anchoring is the native GDI text model and
            //is more stable under GM_ADVANCED world transforms. The font cell
            //remains centered inside CanonicalContentRect, so the text is
            //centered in the edit thickness before projection.
            //-----------------------------------------------------------------
            GetTextMetrics(
                ACanvas.Handle,
                LTextMetric);

            LTextY := ComputeCanonicalTextY(
                ACanvas,
                ALayout);

            LTextBaselineY := LTextY + LTextMetric.tmAscent;

            BeginWorldTransform(
                ACanvas,
                ALayout,
                LSavedXForm,
                LSavedGraphicsMode);
            Try
                If ALayout.Text = '' Then
                    TextOut(
                        ACanvas.Handle,
                        ALayout.CanonicalContentRect.Left,
                        LTextBaselineY,
                        PChar(LDisplayText),
                        Length(LDisplayText))
                Else
                    TextOut(
                        ACanvas.Handle,
                        Round(ALayout.TextOriginCanonical.X),
                        LTextBaselineY,
                        PChar(LDisplayText),
                        Length(LDisplayText));
            Finally
                EndWorldTransform(
                    ACanvas,
                    LSavedXForm,
                    LSavedGraphicsMode);
            End;
        Finally
            SetTextAlign(
                ACanvas.Handle,
                LSavedTextAlign);

            SetBkMode(
                ACanvas.Handle,
                LSavedBkMode);
        End;
    Finally
        If LOldFont <> 0 Then
            SelectObject(
                ACanvas.Handle,
                LOldFont);

        RestoreDC(
            ACanvas.Handle,
            LSavedDC);

        If LClipRegion <> 0 Then
            DeleteObject(LClipRegion);

        DeleteObject(LFont);
    End;
End;

Class Procedure TRotatedEditGDIRenderer.DrawSelectionOnCanonicalCanvas(
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

Class Procedure TRotatedEditGDIRenderer.PrepareContentBitmap(
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

Class Procedure TRotatedEditGDIRenderer.DrawContent(
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
    LEditRegion: HRGN;
Begin
    //-------------------------------------------------------------------------
    //Draws the complete non-caret content for the GDI backend.
    //
    //Important 114 bug-fix rule
    //-----------------------------
    //The GDI fallback must not draw the text into a bitmap that is then rotated
    //or projected. That old pipeline corrupts ClearType/subpixel glyphs at some
    //arbitrary angles, especially shallow angles around 9, 10, 11 and 20 degrees.
    //
    //The safe fallback pipeline is now:
    //  1. prepare the canonical background/border bitmap;
    //  2. pre-fill the projected edit surface to hide projection rounding gaps;
    //  3. project only the background/border bitmap;
    //  4. draw the selection background directly from actual selection quads;
    //  5. draw the text directly on the final canvas under the same world
    //     transform as the geometry engine, using a rotation-safe font quality.
    //
    //The AContentBitmap parameters are retained for API/package compatibility
    //with the current backend interface step. They are deliberately not used by
    //this corrected path because the cached content bitmap is precisely what
    //caused the rotated ClearType artifacts.
    //-------------------------------------------------------------------------
    AContentBitmapValid := False;

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
    //Pre-fill the actual projected region before the bitmap projection.
    //
    //Only the background/border bitmap is projected now. Text is drawn later as
    //real GDI text, not as rotated pixels. The pre-fill still prevents tiny
    //empty strips along the edge of the projected edit surface.
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

    DrawProjectedBitmap(
        ACanvas,
        ALayout,
        ABackgroundBitmap);

    DrawSelection(
        ACanvas,
        ALayout,
        AColors);

    DrawTextDirectOnFinalCanvas(
        ACanvas,
        ALayout,
        AColors,
        ATextHint);

    If AShowDebugBounds Then Begin
        ACanvas.Brush.Style := bsClear;
        ACanvas.Pen.Style := psDot;
        ACanvas.Pen.Width := 1;
        ACanvas.Pen.Color := clRed;
        ACanvas.Rectangle(ALayout.ClientRect);
        ACanvas.Pen.Style := psSolid;
    End;
End;



Class Procedure TRotatedEditGDIRenderer.DrawCaret(
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
