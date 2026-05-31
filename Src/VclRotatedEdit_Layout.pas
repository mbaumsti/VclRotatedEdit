Unit VclRotatedEdit_Layout;


{
  VclRotatedEdit_Layout.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Canonical layout engine of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Moteur de layout canonique du composant VCL VclRotatedEdit.

  Cette unité calcule le texte, le caret, la sélection, le scroll et les rectangles canoniques avant projection. Elle constitue la frontière principale entre le modèle d’édition et le rendu tourné.
}

Interface

Uses
    Winapi.Windows,
    System.Classes,
    System.Types,
    System.UITypes,
    System.Math,
    Vcl.Graphics,
    VclRotatedEdit_Types;

Type
    TRotatedEditLayoutInput = Record
        ClientRect: TRect;

        LogicalLength: Integer;
        LogicalThickness: Integer;

        //-----------------------------------------------------------------
        //Preferred logical thickness used as the normal single-line edit
        //height reference. It is intentionally distinct from
        //LogicalThickness: callers may reduce LogicalThickness manually, in
        //which case the layout keeps the normal top margin and clips the
        //overflow at the bottom, like a native TEdit. If LogicalThickness is
        //larger than this value, the text is centered again in the enlarged
        //band. Zero means "use LogicalThickness as the reference".
        //-----------------------------------------------------------------
        PreferredLogicalThickness: Integer;

        BorderWidth: Integer;
        BorderMetrics: TRotatedEditBorderMetrics;
        PaddingLeft: Integer;
        PaddingTop: Integer;
        PaddingRight: Integer;
        PaddingBottom: Integer;

        Text: String;
        Angle: Double;
        ScrollOffset: Integer;

        CaretIndex: Integer;
        SelStart: Integer;
        SelLength: Integer;

        //-----------------------------------------------------------------
        //Visual selection switch for the current layout pass. The stored
        //selection range remains in SelStart/SelLength even when this flag is
        //False; renderers simply receive no selection geometry to paint.
        //-----------------------------------------------------------------
        SelectionVisible: Boolean;

        CaretThickness: Integer;

        Alignment: TAlignment;

        //-----------------------------------------------------------------
        //Optional actual-origin override.
        //
        //Default behavior centers the projected edit surface inside ClientRect.
        //When the designer resizes the external VCL bounds, Core can instead
        //supply an internal origin so the edit surface keeps a logical anchor
        //stable inside the externally-managed BoundsRect.
        //-----------------------------------------------------------------
        UseCustomActualOrigin: Boolean;
        CustomActualOriginX: Double;
        CustomActualOriginY: Double;
    End;

    TRotatedEditLayout = Class
    private
        Class Function BuildCanonicalRectQuad(Const ARect: TRect): TRotatedEditFloatQuad; Static;

        Class Function QuadBounds(Const AQuad: TRotatedEditFloatQuad): TRect; Static;

        Class Function BuildActualOrigin(
            Const AClientRect: TRect;
            Const ACanonicalEditRect: TRect;
            AAngle: Double): TRotatedEditFloatPoint; Static;

        Class Function IsOrthogonalAngle(
            AAngle: Double): Boolean; Static;

        Class Function CreateRotationSafeMeasurementFont(
            ACanvas: TCanvas;
            AAngle: Double): HFONT; Static;

        Class Procedure BeginMeasurementWorldTransform(
            ACanvas: TCanvas;
            AAngle: Double;
            Out ASavedXForm: TXForm;
            Out ASavedGraphicsMode: Integer); Static;

        Class Procedure EndMeasurementWorldTransform(
            ACanvas: TCanvas;
            Const ASavedXForm: TXForm;
            ASavedGraphicsMode: Integer); Static;

        Class Procedure BuildTextAdvances(
            ACanvas: TCanvas;
            Const AText: String;
            AAngle: Double;
            Out AAdvances: TArray<Integer>;
            Out ATextSize: TSize); Static;

        Class Function GetAdvanceAtIndex(
            Const AAdvances: TArray<Integer>;
            AIndex: Integer): Integer; Static;

        Class Function MeasureRepresentativeGlyphBand(
            ACanvas: TCanvas;
            Out AVisualTopInCell: Integer;
            Out AVisualHeight: Integer): Boolean; Static;

    public
        {
          Builds all geometry needed for one rendering pass.

          The result contains canonical and actual geometry. The core control
          should store back only ScrollOffset. All other geometry is transient.
        }
        Class Function BuildLayout(
            ACanvas: TCanvas;
            Const AInput: TRotatedEditLayoutInput): TRotatedEditLayoutResult; Static;

        {
          Converts a text index to a canonical flow coordinate.

          caret positions are measured from successive complete
          text prefixes in the same GDI font/transform policy as the rotated
          TextOut renderer.
        }
        Class Function TextIndexToCanonicalFlow(
            ACanvas: TCanvas;
            Const AText: String;
            AIndex: Integer;
            AAngle: Double = 0.0): Double; Static;

        {
          Converts a canonical flow coordinate to an insertion index.

          Rule:
          The insertion index is determined by character midpoints in canonical
          coordinates, never by actual screen-space top-left points.
        }
        Class Function CanonicalFlowToTextIndex(
            ACanvas: TCanvas;
            Const AText: String;
            AFlow: Double;
            AAngle: Double = 0.0): Integer; Static;

        {
          Ensures that the caret remains visible along the canonical flow axis.

          ScrollOffset is expressed in canonical pixels and is therefore valid
          for every angle.
        }
        Class Function EnsureCaretVisible(
            ACanvas: TCanvas;
            Const AText: String;
            ACaretIndex: Integer;
            ACurrentScrollOffset: Integer;
            Const ACanonicalContentRect: TRect;
            AAngle: Double = 0.0): Integer; Static;

        {
          Builds canonical and actual caret geometry.

          The caret center is the reference point. It represents both the
          insertion position between characters and the vertical center of the
          edited line.
        }
        Class Function BuildCaretGeometry(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            ACaretIndex: Integer;
            ACaretThickness: Integer): TRotatedEditCaretGeometry; Static;

        {
          Builds selection geometry as actual quads.

          Placeholder for the next implementation phase.
        }
        Class Function BuildSelectionGeometry(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            ASelStart: Integer;
            ASelLength: Integer): TArray<TRotatedEditFloatQuad>; Static;

        {
          Hit-tests a mouse point.

          The point is first converted actual -> canonical using the same origin
          and angle as the renderer. The insertion index is then computed from
          canonical character midpoints.
        }
        Class Function HitTest(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult;
            Const AActualPoint: TPoint): TRotatedEditHitTestResult; Static;
    End;

Implementation

Uses
    VclRotatedEdit_Geometry;

Class Function TRotatedEditLayout.BuildCanonicalRectQuad(Const ARect: TRect): TRotatedEditFloatQuad;
Begin
    Result.P1 := TRotatedEditFloatPoint.Create(
        ARect.Left,
        ARect.Top);
    Result.P2 := TRotatedEditFloatPoint.Create(
        ARect.Right,
        ARect.Top);
    Result.P3 := TRotatedEditFloatPoint.Create(
        ARect.Right,
        ARect.Bottom);
    Result.P4 := TRotatedEditFloatPoint.Create(
        ARect.Left,
        ARect.Bottom);
End;

Class Function TRotatedEditLayout.QuadBounds(Const AQuad: TRotatedEditFloatQuad): TRect;
Var
    LMinX: Double;
    LMaxX: Double;
    LMinY: Double;
    LMaxY: Double;
Begin
    LMinX := Min(
        Min(AQuad.P1.X, AQuad.P2.X),
        Min(AQuad.P3.X, AQuad.P4.X));
    LMaxX := Max(
        Max(AQuad.P1.X, AQuad.P2.X),
        Max(AQuad.P3.X, AQuad.P4.X));
    LMinY := Min(
        Min(AQuad.P1.Y, AQuad.P2.Y),
        Min(AQuad.P3.Y, AQuad.P4.Y));
    LMaxY := Max(
        Max(AQuad.P1.Y, AQuad.P2.Y),
        Max(AQuad.P3.Y, AQuad.P4.Y));

    Result := Rect(
        Floor(LMinX),
        Floor(LMinY),
        Ceil(LMaxX),
        Ceil(LMaxY));
End;

Class Function TRotatedEditLayout.BuildActualOrigin(
    Const AClientRect: TRect;
    Const ACanonicalEditRect: TRect;
    AAngle: Double): TRotatedEditFloatPoint;
Var
    LQuad:          TRotatedEditFloatQuad;
    LBounds:        TRect;
    LClientCenterX: Double;
    LClientCenterY: Double;
    LBoundsCenterX: Double;
    LBoundsCenterY: Double;
Begin
    //-------------------------------------------------------------------------
    //The projected edit surface is centered inside the physical VCL ClientRect.
    //
    //This is deliberately independent from layout:
    //- layout decides where text/caret live in canonical coordinates;
    //- this method only decides where the rotated canonical surface appears on
    //the screen.
    //-------------------------------------------------------------------------

    LQuad := TRotatedEditGeometry.TransformQuad(
        BuildCanonicalRectQuad(ACanonicalEditRect),
        TRotatedEditFloatPoint.Create(0.0, 0.0),
        AAngle);

    LBounds := QuadBounds(LQuad);

    LClientCenterX := (AClientRect.Left + AClientRect.Right) / 2.0;
    LClientCenterY := (AClientRect.Top + AClientRect.Bottom) / 2.0;

    LBoundsCenterX := (LBounds.Left + LBounds.Right) / 2.0;
    LBoundsCenterY := (LBounds.Top + LBounds.Bottom) / 2.0;

    Result := TRotatedEditFloatPoint.Create(
        LClientCenterX - LBoundsCenterX,
        LClientCenterY - LBoundsCenterY);
End;

Class Function TRotatedEditLayout.IsOrthogonalAngle(
    AAngle: Double): Boolean;
Var
    LAngle: Double;
    LNearestQuarter: Double;
Begin
    //-------------------------------------------------------------------------
    //Returns True for the four angles where the original font quality can be
    //kept. This intentionally mirrors the GDI renderer rule: non-orthogonal
    //angles use a rotation-safe grayscale antialiased font, while orthogonal
    //angles keep the source font quality.
    //-------------------------------------------------------------------------
    LAngle := TRotatedEditGeometry.NormalizeAngle(AAngle);
    LNearestQuarter := Round(LAngle / 90.0) * 90.0;

    Result := Abs(LAngle - LNearestQuarter) < 0.001;
End;

Class Function TRotatedEditLayout.CreateRotationSafeMeasurementFont(
    ACanvas: TCanvas;
    AAngle: Double): HFONT;
Var
    LLogFont: TLogFont;
Begin
    //-------------------------------------------------------------------------
    //Creates the measurement font used by caret, selection, scrolling and
    //hit-testing.
    //
    //Important rule
    //--------------
    //This helper must remain aligned with
    //TRotatedEditGDIRenderer.CreateRotationSafeFont. The renderer draws text
    //with a temporary unrotated HFONT and lets the world transform own the
    //rotation. For arbitrary angles it also disables ClearType and requests
    //ANTIALIASED_QUALITY. If the layout measures with ACanvas.Font directly,
    //the caret can drift progressively away from the rendered text.
    //
    //The duplication is deliberate for now: the layout unit must not depend on
    //the concrete GDI renderer unit, but both sides need the same GDI font
    //policy until the backend owns text metrics explicitly.
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

    If Not IsOrthogonalAngle(AAngle) Then
        LLogFont.lfQuality := ANTIALIASED_QUALITY;

    Result := CreateFontIndirect(LLogFont);
End;

Class Procedure TRotatedEditLayout.BeginMeasurementWorldTransform(
    ACanvas: TCanvas;
    AAngle: Double;
    Out ASavedXForm: TXForm;
    Out ASavedGraphicsMode: Integer);
Var
    LRad: Double;
    LCos: Double;
    LSin: Double;
    LXForm: TXForm;
Begin
    //-------------------------------------------------------------------------
    //Applies the same GDI advanced transform model as the final text renderer
    //while measuring text prefixes.
    //
    //The measured value we keep is still the canonical flow width returned by
    //GetTextExtentPoint32, but the selected DC state now matches the real
    //TextOut path as closely as possible: GM_ADVANCED is enabled, the same
    //rotation sign convention is used, and the rotation-safe HFONT is selected
    //before this method is called.
    //-------------------------------------------------------------------------
    ASavedGraphicsMode := SetGraphicsMode(
        ACanvas.Handle,
        GM_ADVANCED);

    GetWorldTransform(
        ACanvas.Handle,
        ASavedXForm);

    LRad := -AAngle * Pi / 180.0;
    LCos := Cos(LRad);
    LSin := Sin(LRad);

    LXForm.eM11 := LCos;
    LXForm.eM12 := LSin;
    LXForm.eM21 := -LSin;
    LXForm.eM22 := LCos;
    LXForm.eDx := 0.0;
    LXForm.eDy := 0.0;

    SetWorldTransform(
        ACanvas.Handle,
        LXForm);
End;

Class Procedure TRotatedEditLayout.EndMeasurementWorldTransform(
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

Class Procedure TRotatedEditLayout.BuildTextAdvances(
    ACanvas: TCanvas;
    Const AText: String;
    AAngle: Double;
    Out AAdvances: TArray<Integer>;
    Out ATextSize: TSize);
Var
    I:           Integer;
    LTextLength: Integer;
    LPrefix:             String;
    LPrefixSize:         TSize;
    LOk:                 Boolean;
    LFont:               HFONT;
    LOldFont:            HGDIOBJ;
    LSavedXForm:         TXForm;
    LSavedGraphicsMode:  Integer;
    LWorldTransformOpen: Boolean;
Begin
    //-------------------------------------------------------------------------
    //Builds cumulative caret positions for a complete text run.
    //
    //Why this method exists
    //----------------------
    //A rotated edit control makes text metric differences very visible. When the
    //control is displayed at a free angle such as 45 degrees, even a small
    //difference along the canonical text-flow axis is projected on both screen
    //axes and appears as a visible caret drift.
    //
    //Important rule
    //-------------------
    //Each caret position is measured from the complete prefix that precedes the
    //insertion point, but now the measurement DC is also aligned with the final
    //rotated GDI TextOut path:
    //
    //  - same source LOGFONT;
    //  - same ClearType avoidance policy for arbitrary angles;
    //  - same GM_ADVANCED/world-transform model;
    //  - same unrotated HFONT with rotation owned by the transform.
    //
    //A prefix-only correction was not sufficient because it still used
    //the normal canvas font/context while the renderer used a rotation-safe
    //temporary HFONT. That produced a cumulative drift: on a 28-character text,
    //the caret could end almost one character away from the visible text end.
    //
    //Cost model
    //----------
    //This is O(n²) because each prefix is measured as a string. TRotatedEdit is
    //currently a single-line edit control, so this cost is acceptable and the
    //visual correctness is more important than the small extra layout cost.
    //
    //Single metric source
    //--------------------
    //All caret placement, selection geometry, hit-testing and scroll-to-caret
    //logic go through this method. Keeping this as the single metric source is
    //more important than optimizing only one consumer, otherwise the caret could
    //be fixed while selection or mouse hit-testing would still disagree.
    //
    //Current limitation
    //------------------
    //This remains a GDI metric model. It does not implement Unicode shaping,
    //surrogate pairs, ligature clusters or bidirectional text. If a future
    //DirectWrite backend owns text layout, this method is the place where the GDI
    //metric policy can be replaced by backend-owned caret stops.
    //-------------------------------------------------------------------------
    LTextLength := Length(AText);

    SetLength(
        AAdvances,
        LTextLength);

    ATextSize.cx := 0;
    ATextSize.cy := 0;

    If LTextLength = 0 Then
        Exit;

    LOk := True;
    LFont := 0;
    LOldFont := 0;
    LWorldTransformOpen := False;

    LFont := CreateRotationSafeMeasurementFont(
        ACanvas,
        AAngle);

    If LFont <> 0 Then
        LOldFont := SelectObject(
            ACanvas.Handle,
            LFont);

    Try
        BeginMeasurementWorldTransform(
            ACanvas,
            AAngle,
            LSavedXForm,
            LSavedGraphicsMode);
        LWorldTransformOpen := True;

        For I := 1 To LTextLength Do Begin
            LPrefix := Copy(
                AText,
                1,
                I);

            If GetTextExtentPoint32(
                ACanvas.Handle,
                PChar(LPrefix),
                Length(LPrefix),
                LPrefixSize) Then Begin
                AAdvances[I - 1] := LPrefixSize.cx;

                If I = LTextLength Then
                    ATextSize := LPrefixSize;
            End
            Else Begin
                LOk := False;
                Break;
            End;
        End;
    Finally
        If LWorldTransformOpen Then
            EndMeasurementWorldTransform(
                ACanvas,
                LSavedXForm,
                LSavedGraphicsMode);

        If LOldFont <> 0 Then
            SelectObject(
                ACanvas.Handle,
                LOldFont);

        If LFont <> 0 Then
            DeleteObject(LFont);
    End;

    If Not LOk Then Begin
        //---------------------------------------------------------------------
        //Fallback path.
        //
        //This should rarely be used, but keeping a deterministic fallback is
        //safer than returning a partially-built advance table. The fallback uses
        //TCanvas text metrics because they are always available through VCL.
        //---------------------------------------------------------------------
        ATextSize.cx := ACanvas.TextWidth(AText);
        ATextSize.cy := ACanvas.TextHeight('Wg');

        For I := 1 To LTextLength Do
            AAdvances[I - 1] := ACanvas.TextWidth(Copy(AText, 1, I));
    End;
End;



Class Function TRotatedEditLayout.MeasureRepresentativeGlyphBand(
    ACanvas: TCanvas;
    Out AVisualTopInCell: Integer;
    Out AVisualHeight: Integer): Boolean;
Var
    LGlyphMetrics: TGlyphMetrics;
    LMatrix:       TMat2;
    LTextMetric:   TTextMetric;
    LGlyphResult:  DWORD;
Begin
    //-------------------------------------------------------------------------
    //Measures the visible black box of the representative uppercase glyph used
    //for vertical visual centering.
    //
    //Why 'W' and not 'Wg'
    //--------------------
    //A single-line edit control is perceived as centered mostly from the main
    //uppercase/lowercase body of the font. Including a descender sample such as
    //'g' in the centering metric increases the measured band and can shift the
    //visible text away from what a native TEdit appears to do.
    //
    //Why GetGlyphOutline
    //-------------------
    //TCanvas.TextHeight and GetTextExtentPoint32 usually describe the complete
    //font cell, not the actual ink/black-box height of a specific glyph.
    //GetGlyphOutline(GGO_METRICS) gives the glyph black box and its origin from
    //the baseline, which lets the layout compute the corresponding font-cell
    //top without guessing.
    //
    //Returned coordinates
    //--------------------
    //AVisualTopInCell is relative to the top of the GDI font cell. The renderer
    //uses TA_BASELINE with baseline = TextOriginCanonical.Y + tmAscent, so the
    //visible glyph top is:
    //
    //  TextOriginCanonical.Y + AVisualTopInCell
    //
    //This keeps layout and renderer synchronized without introducing a local
    //renderer correction.
    //-------------------------------------------------------------------------
    Result := False;
    AVisualTopInCell := 0;
    AVisualHeight := 0;

    If ACanvas = Nil Then
        Exit;

    If Not GetTextMetrics(ACanvas.Handle, LTextMetric) Then
        Exit;

    FillChar(
        LMatrix,
        SizeOf(LMatrix),
        0);

    LMatrix.eM11.value := 1;
    LMatrix.eM11.fract := 0;
    LMatrix.eM12.value := 0;
    LMatrix.eM12.fract := 0;
    LMatrix.eM21.value := 0;
    LMatrix.eM21.fract := 0;
    LMatrix.eM22.value := 1;
    LMatrix.eM22.fract := 0;

    FillChar(
        LGlyphMetrics,
        SizeOf(LGlyphMetrics),
        0);

    LGlyphResult := GetGlyphOutline(
        ACanvas.Handle,
        Ord('W'),
        GGO_METRICS,
        LGlyphMetrics,
        0,
        Nil,
        LMatrix);

    If LGlyphResult = GDI_ERROR Then
        Exit;

    If LGlyphMetrics.gmBlackBoxY <= 0 Then
        Exit;

    AVisualHeight := LGlyphMetrics.gmBlackBoxY;
    AVisualTopInCell := LTextMetric.tmAscent - LGlyphMetrics.gmptGlyphOrigin.y;

    Result := True;
End;



Class Function TRotatedEditLayout.GetAdvanceAtIndex(
    Const AAdvances: TArray<Integer>;
    AIndex: Integer): Integer;
Var
    LIndex: Integer;
Begin
    //-------------------------------------------------------------------------
    //Returns the cumulative advance at a zero-based caret insertion index.
    //
    //Index convention:
    //- 0 returns 0 because it means before the first character;
    //- 1 returns the advance after the first character;
    //- Length(Text) returns the full text advance.
    //
    //The caller has already built AAdvances from the same string. This method
    //only centralizes the bounds logic so TextIndexToCanonicalFlow and
    //CanonicalFlowToTextIndex cannot accidentally diverge.
    //-------------------------------------------------------------------------
    LIndex := AIndex;

    If LIndex <= 0 Then Begin
        Result := 0;
        Exit;
    End;

    If Length(AAdvances) = 0 Then Begin
        Result := 0;
        Exit;
    End;

    If LIndex > Length(AAdvances) Then
        LIndex := Length(AAdvances);

    Result := AAdvances[LIndex - 1];
End;

Class Function TRotatedEditLayout.BuildLayout(
    ACanvas: TCanvas;
    Const AInput: TRotatedEditLayoutInput): TRotatedEditLayoutResult;
Var
    LLogicalLength:              Integer;
    LLogicalThickness:           Integer;
    LContentWidth:               Integer;
    LTextOriginX:                Double;
    LTextOriginY:                Double;
    LTextMetric:                 TTextMetric;
    LTextThickness:              Integer;
    LRemainingCrossSpace:        Integer;
    LTopCrossPadding:            Integer;
    LVisualTopInCell:            Integer;
    LVisualHeight:               Integer;
    LVisualRemainingCrossSpace:  Integer;
    LVisualTopCrossPadding:      Integer;
    LReferenceLogicalThickness:  Integer;
    LReferenceContentHeight:     Integer;
    LBorderMetrics:              TRotatedEditBorderMetrics;
Begin
    LLogicalLength := AInput.LogicalLength;
    LLogicalThickness := AInput.LogicalThickness;

    If LLogicalLength < 1 Then
        LLogicalLength := 1;

    If LLogicalThickness < 1 Then
        LLogicalThickness := 1;

    Result.ClientRect := AInput.ClientRect;
    Result.LogicalLength := LLogicalLength;
    Result.LogicalThickness := LLogicalThickness;

    Result.CanonicalEditRect := Rect(
        0,
        0,
        LLogicalLength,
        LLogicalThickness);

    LBorderMetrics := AInput.BorderMetrics;

    If (LBorderMetrics.Left = 0) And
       (LBorderMetrics.Top = 0) And
       (LBorderMetrics.Right = 0) And
       (LBorderMetrics.Bottom = 0) And
       (AInput.BorderWidth > 0) Then Begin
        //---------------------------------------------------------------------
        //Compatibility fallback.
        //
        //The Core now supplies BorderMetrics explicitly. This fallback keeps the
        //layout deterministic if a test harness or old caller still fills only
        //the historical scalar BorderWidth field.
        //---------------------------------------------------------------------
        LBorderMetrics.Left := AInput.BorderWidth;
        LBorderMetrics.Top := AInput.BorderWidth;
        LBorderMetrics.Right := AInput.BorderWidth;
        LBorderMetrics.Bottom := AInput.BorderWidth;
    End;

    //-------------------------------------------------------------------------
    //Resolved content rectangle rule.
    //
    //BorderMetrics must come from the active rendering/style backend. A styled
    //TEdit frame is not necessarily a 1-pixel rectangle: many VCL styles return
    //2-pixel top/bottom content margins, and some styles can be asymmetric.
    //
    //Using these metrics here keeps text, caret, selection and hit-testing in
    //the same inner area as the frame actually drawn by the renderer. This is
    //intentionally not corrected in DrawText: local renderer offsets would make
    //the caret and mouse hit-test drift away from the text.
    //-------------------------------------------------------------------------
    Result.BorderMetrics := LBorderMetrics;

    Result.CanonicalContentRect := Rect(
        LBorderMetrics.Left + AInput.PaddingLeft,
        LBorderMetrics.Top + AInput.PaddingTop,
        LLogicalLength - LBorderMetrics.Right - AInput.PaddingRight,
        LLogicalThickness - LBorderMetrics.Bottom - AInput.PaddingBottom);

    If Result.CanonicalContentRect.Right < Result.CanonicalContentRect.Left Then
        Result.CanonicalContentRect.Right := Result.CanonicalContentRect.Left;

    If Result.CanonicalContentRect.Bottom < Result.CanonicalContentRect.Top Then
        Result.CanonicalContentRect.Bottom := Result.CanonicalContentRect.Top;

    Result.Text := AInput.Text;
    Result.SelStart := AInput.SelStart;
    Result.SelLength := AInput.SelLength;
    Result.SelectionVisible := AInput.SelectionVisible;
    //-------------------------------------------------------------------------
    //TextLength / TextThickness are layout estimates used by rendering and
    //scrolling. TextLength is resolved through the same cumulative-advance
    //policy as caret placement so long text and rotated text do not drift.
    //-------------------------------------------------------------------------
    Result.TextLength := Round(TextIndexToCanonicalFlow(
        ACanvas,
        AInput.Text,
        Length(AInput.Text),
        AInput.Angle));

    //-------------------------------------------------------------------------
    //GDI text metric rule.
    //
    //Two different notions are deliberately kept separate here:
    //
    //- TextThickness keeps the complete GDI font cell height. It is the safe
    //  metric for caret height and for hit-testing because it includes the
    //  ascender/descender area that GDI may use when TextOut renders arbitrary
    //  characters.
    //
    //- Vertical centering is resolved from the visible black box of a
    //  representative uppercase glyph, currently 'W'. A native single-line
    //  TEdit visually appears to center the main uppercase glyph body rather
    //  than the full "Wg" cell including descender space. Centering on "Wg"
    //  therefore leaves the text visually too high or too low depending on the
    //  rounding and on the selected style.
    //
    //The renderer still receives a normal canonical TextOriginCanonical.Y. It
    //adds tmAscent and uses TA_BASELINE. Therefore the layout computes the font
    //cell top that makes the representative glyph black box centered inside
    //CanonicalContentRect. No renderer-side magic pixel is required.
    //
    //A future DirectWrite backend must implement the same semantic rule with
    //DirectWrite glyph/run metrics instead of reusing these GDI measurements.
    //-------------------------------------------------------------------------
    If GetTextMetrics(ACanvas.Handle, LTextMetric) Then
        LTextThickness := LTextMetric.tmHeight
    Else
        LTextThickness := ACanvas.TextHeight('Wg');

    If LTextThickness < 1 Then
        LTextThickness := 1;

    Result.TextThickness := LTextThickness;

    //-------------------------------------------------------------------------
    //Normal cross-axis reference height.
    //
    //LogicalThickness remains the user-selected edit-surface thickness. The
    //preferred thickness is the native/edit-like height expected for the current
    //font and border. It is used only as a vertical placement reference:
    //
    //- if the user reduces LogicalThickness below the preferred value, the text
    //  keeps the same top margin it would have had in the normal edit height;
    //  the lower part is clipped by the content rectangle, matching the native
    //  TEdit behavior where text is not compressed;
    //
    //- if the user increases LogicalThickness, the current content height is
    //  used and the text is centered in the enlarged band. This intentionally
    //  differs from TEdit, whose top margin tends to remain fixed.
    //-------------------------------------------------------------------------
    LReferenceLogicalThickness := AInput.PreferredLogicalThickness;

    If LReferenceLogicalThickness < 1 Then
        LReferenceLogicalThickness := LLogicalThickness;

    If LReferenceLogicalThickness < LLogicalThickness Then
        LReferenceLogicalThickness := LLogicalThickness;

    LReferenceContentHeight :=
        LReferenceLogicalThickness -
        LBorderMetrics.Top -
        LBorderMetrics.Bottom -
        AInput.PaddingTop -
        AInput.PaddingBottom;

    If LReferenceContentHeight < Result.CanonicalContentRect.Height Then
        LReferenceContentHeight := Result.CanonicalContentRect.Height;

    If LReferenceContentHeight < 0 Then
        LReferenceContentHeight := 0;

    Result.Angle := AInput.Angle;

    If AInput.UseCustomActualOrigin Then
        Result.ActualOrigin := TRotatedEditFloatPoint.Create(
            AInput.CustomActualOriginX,
            AInput.CustomActualOriginY)
    Else
        Result.ActualOrigin := BuildActualOrigin(
            AInput.ClientRect,
            Result.CanonicalEditRect,
            Result.Angle);

    Result.ActualEditQuad := TRotatedEditGeometry.TransformQuad(
        BuildCanonicalRectQuad(Result.CanonicalEditRect),
        Result.ActualOrigin,
        Result.Angle);

    Result.ActualContentQuad := TRotatedEditGeometry.TransformQuad(
        BuildCanonicalRectQuad(Result.CanonicalContentRect),
        Result.ActualOrigin,
        Result.Angle);

    Result.ActualEditBounds := QuadBounds(Result.ActualEditQuad);

    Result.ScrollOffset := EnsureCaretVisible(
        ACanvas,
        AInput.Text,
        AInput.CaretIndex,
        AInput.ScrollOffset,
        Result.CanonicalContentRect,
        Result.Angle);

    //---------------------------------------------------------------------
    //Horizontal alignment and padding rule.
    //
    //TextPaddingStart / TextPaddingEnd are already included in
    //CanonicalContentRect. Therefore:
    //
    //- taLeftJustify must start at CanonicalContentRect.Left;
    //- taRightJustify must end at CanonicalContentRect.Right;
    //- taCenter must center inside CanonicalContentRect.
    //
    //Regression note:
    //The previous implementation only applied Alignment when ScrollOffset was
    //already zero. After editing or changing padding, an old scroll value could
    //remain even though the text fitted inside the content area. In that case
    //the text origin was calculated as Left - ScrollOffset, making it look as if
    //TextPaddingStart / TextPaddingEnd had no effect.
    //
    //Correct rule:
    //If the complete text fits inside the content width, scrolling is not
    //needed. Reset ScrollOffset to zero and apply alignment directly from the
    //padded content rectangle. If the text does not fit, the caret-visible
    //scroll model owns the origin.
    //---------------------------------------------------------------------
    LContentWidth := Result.CanonicalContentRect.Width;

    If Result.TextLength <= LContentWidth Then Begin
        Result.ScrollOffset := 0;

        Case AInput.Alignment Of
            taCenter:
                LTextOriginX := Result.CanonicalContentRect.Left +
                    ((LContentWidth - Result.TextLength) / 2.0);

            taRightJustify:
                LTextOriginX := Result.CanonicalContentRect.Right -
                    Result.TextLength;
        Else
            LTextOriginX := Result.CanonicalContentRect.Left;
        End;
    End Else
        LTextOriginX := Result.CanonicalContentRect.Left - Result.ScrollOffset;

    LRemainingCrossSpace := LReferenceContentHeight - Result.TextThickness;

    If LRemainingCrossSpace < 0 Then
        LRemainingCrossSpace := 0;

    LTopCrossPadding := LRemainingCrossSpace Div 2;

    If MeasureRepresentativeGlyphBand(
        ACanvas,
        LVisualTopInCell,
        LVisualHeight) Then Begin
        //---------------------------------------------------------------------
        //Visible-glyph centering rule.
        //
        //The glyph black box is expressed relative to the font cell top:
        //
        //  visual top in cell = tmAscent - glyph origin Y
        //
        //We first center that visible black box inside the content rectangle,
        //then derive the font cell top needed by the baseline renderer. If the
        //remaining visual space is odd, integer division assigns the extra
        //pixel to the bottom side, which is the rounding behavior observed on
        //the native styled TEdit in the reference tests.
        //---------------------------------------------------------------------
        LVisualRemainingCrossSpace := LReferenceContentHeight - LVisualHeight;

        If LVisualRemainingCrossSpace < 0 Then
            LVisualRemainingCrossSpace := 0;

        LVisualTopCrossPadding := LVisualRemainingCrossSpace Div 2;

        LTextOriginY :=
            Result.CanonicalContentRect.Top +
            LVisualTopCrossPadding -
            LVisualTopInCell;
    End Else Begin
        //---------------------------------------------------------------------
        //Deterministic fallback.
        //
        //If GetGlyphOutline is not available for the current font, keep the
        //previous complete-cell centering rule. This is still coherent for
        //caret, selection and hit-testing, even if it may be less visually close
        //to a native TEdit for some styled fonts.
        //---------------------------------------------------------------------
        LTextOriginY := Result.CanonicalContentRect.Top + LTopCrossPadding;
    End;

    Result.TextOriginCanonical := TRotatedEditFloatPoint.Create(
        LTextOriginX,
        LTextOriginY);

    Result.TextOriginActual := TRotatedEditGeometry.TransformPoint(
        Result.TextOriginCanonical,
        Result.ActualOrigin,
        Result.Angle);

    Result.Caret := BuildCaretGeometry(
        ACanvas,
        Result,
        AInput.CaretIndex,
        AInput.CaretThickness);

    If Result.SelectionVisible Then
        Result.SelectionQuads := BuildSelectionGeometry(
            ACanvas,
            Result,
            AInput.SelStart,
            AInput.SelLength)
    Else
        SetLength(Result.SelectionQuads, 0);
End;

Class Function TRotatedEditLayout.TextIndexToCanonicalFlow(
    ACanvas: TCanvas;
    Const AText: String;
    AIndex: Integer;
    AAngle: Double): Double;
Var
    LIndex:    Integer;
    LAdvances: TArray<Integer>;
    LTextSize: TSize;
Begin
    //-------------------------------------------------------------------------
    //Converts a text insertion index to a canonical flow coordinate.
    //
    //This method is deliberately based on BuildTextAdvances, whose current policy
    //measures each complete text prefix in the rotated GDI measurement context.
    //
    //Reason:
    //The text renderer draws text as GDI text runs. If caret placement is derived
    //from a different advance model, tiny metric differences can accumulate. At
    //arbitrary angles those differences become visible as a caret drift that
    //appears to grow with the distance from the text origin.
    //
    //All code that needs "where is index N?" must go through this method so the
    //metric policy remains centralized.
    //-------------------------------------------------------------------------
    LIndex := AIndex;

    If LIndex < 0 Then
        LIndex := 0;

    If LIndex > Length(AText) Then
        LIndex := Length(AText);

    If LIndex = 0 Then Begin
        Result := 0.0;
        Exit;
    End;

    BuildTextAdvances(
        ACanvas,
        AText,
        AAngle,
        LAdvances,
        LTextSize);

    Result := GetAdvanceAtIndex(
        LAdvances,
        LIndex);
End;

Class Function TRotatedEditLayout.CanonicalFlowToTextIndex(
    ACanvas: TCanvas;
    Const AText: String;
    AFlow: Double;
    AAngle: Double): Integer;
Var
    I:         Integer;
    LLeft:     Double;
    LRight:    Double;
    LMid:      Double;
    LAdvances: TArray<Integer>;
    LTextSize: TSize;
Begin
    //-------------------------------------------------------------------------
    //Converts a canonical flow coordinate to a caret insertion index.
    //
    //Hit-testing rule:
    //The insertion index is selected by character midpoints. This is the same
    //rule used by native edit controls: clicking in the left half of a glyph
    //places the caret before it, clicking in the right half places it after it.
    //
    //Metric rule:
    //The midpoint calculation uses the same advance table as
    //TextIndexToCanonicalFlow. Never use a different prefix/advance policy here,
    //otherwise mouse hit-testing and caret rendering can disagree.
    //-------------------------------------------------------------------------
    Result := 0;

    If AFlow <= 0.0 Then
        Exit;

    If Length(AText) = 0 Then
        Exit;

    BuildTextAdvances(
        ACanvas,
        AText,
        AAngle,
        LAdvances,
        LTextSize);

    For I := 1 To Length(AText) Do Begin
        LLeft := GetAdvanceAtIndex(
            LAdvances,
            I - 1);

        LRight := GetAdvanceAtIndex(
            LAdvances,
            I);

        LMid := (LLeft + LRight) / 2.0;

        If AFlow < LMid Then Begin
            Result := I - 1;
            Exit;
        End;
    End;

    Result := Length(AText);
End;

Class Function TRotatedEditLayout.EnsureCaretVisible(
    ACanvas: TCanvas;
    Const AText: String;
    ACaretIndex: Integer;
    ACurrentScrollOffset: Integer;
    Const ACanonicalContentRect: TRect;
    AAngle: Double): Integer;
Var
    LCaretFlow:    Double;
    LVisibleLeft:  Double;
    LVisibleRight: Double;
    LMargin:       Integer;
Begin
    Result := ACurrentScrollOffset;

    If Result < 0 Then
        Result := 0;

    LMargin := 2;

    LCaretFlow := TextIndexToCanonicalFlow(
        ACanvas,
        AText,
        ACaretIndex,
        AAngle);

    LVisibleLeft := Result;
    LVisibleRight := Result + ACanonicalContentRect.Width - (2 * LMargin);

    If LCaretFlow < LVisibleLeft Then
        Result := Trunc(LCaretFlow)
    Else If LCaretFlow > LVisibleRight Then
        Result := Trunc(LCaretFlow - ACanonicalContentRect.Width + (2 * LMargin));

    If Result < 0 Then
        Result := 0;
End;

Class Function TRotatedEditLayout.BuildCaretGeometry(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    ACaretIndex: Integer;
    ACaretThickness: Integer): TRotatedEditCaretGeometry;
Var
    LCaretFlow: Double;
    LStart:     TRotatedEditFloatPoint;
    LEnd:       TRotatedEditFloatPoint;
Begin
    LCaretFlow := TextIndexToCanonicalFlow(
        ACanvas,
        ALayout.Text,
        ACaretIndex,
        ALayout.Angle);

    Result.Index := ACaretIndex;
    Result.Flow := ALayout.TextOriginCanonical.X + LCaretFlow;
    Result.CrossTop := ALayout.TextOriginCanonical.Y;
    Result.CrossBottom := ALayout.TextOriginCanonical.Y + ALayout.TextThickness;
    Result.Thickness := ACaretThickness;

    LStart := TRotatedEditFloatPoint.Create(
        Result.Flow,
        Result.CrossTop);

    LEnd := TRotatedEditFloatPoint.Create(
        Result.Flow,
        Result.CrossBottom);

    Result.CanonicalSegmentStart := LStart;
    Result.CanonicalSegmentEnd := LEnd;

    Result.CanonicalQuad := TRotatedEditGeometry.BuildCaretQuad(
        LStart,
        LEnd,
        ACaretThickness);

    Result.CanonicalHotPoint := TRotatedEditFloatPoint.Create(
        Result.Flow,
        (Result.CrossTop + Result.CrossBottom) / 2.0);

    Result.ActualSegmentStart := TRotatedEditGeometry.TransformPoint(
        Result.CanonicalSegmentStart,
        ALayout.ActualOrigin,
        ALayout.Angle);

    Result.ActualSegmentEnd := TRotatedEditGeometry.TransformPoint(
        Result.CanonicalSegmentEnd,
        ALayout.ActualOrigin,
        ALayout.Angle);

    Result.ActualQuad := TRotatedEditGeometry.TransformQuad(
        Result.CanonicalQuad,
        ALayout.ActualOrigin,
        ALayout.Angle);

    Result.ActualHotPoint := TRotatedEditGeometry.TransformPoint(
        Result.CanonicalHotPoint,
        ALayout.ActualOrigin,
        ALayout.Angle);
End;

Class Function TRotatedEditLayout.BuildSelectionGeometry(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    ASelStart: Integer;
    ASelLength: Integer): TArray<TRotatedEditFloatQuad>;
Var
    LSelStart: Integer;
    LSelEnd: Integer;
    LFlowStart: Double;
    LFlowEnd: Double;
    LCanonicalQuad: TRotatedEditFloatQuad;
Begin
    //-------------------------------------------------------------------------
    //Builds the selection geometry for the current single-line edit surface.
    //
    //Selection rule:
    //The selection is first described as a canonical horizontal rectangle, then
    //projected to actual screen coordinates.
    //
    //Why this method is essential now
    //--------------------------------
    //The renderer no longer draws selection directly over the final canvas. It
    //composes an opaque ContentBitmap:
    //
    //  background + selection + text
    //
    //The renderer therefore depends on ALayout.SelectionQuads to know whether a
    //selection exists. If this method returns an empty array, Ctrl+A, double
    //click, triple click and mouse drag can all update the internal selection
    //state correctly while nothing becomes visible on screen.
    //
    //Coordinate contract:
    //- selection indexes are text insertion indexes;
    //- TextIndexToCanonicalFlow converts those indexes to canonical X flow;
    //- the canonical selection rectangle is projected through the same geometry
    //  as background, text, caret and hit-test.
    //
    //V1 limitation:
    //TRotatedEdit is currently single-line, so a selection is represented by one
    //quad. If multi-line editing is introduced later, this method must return
    //one quad per selected visual line.
    //-------------------------------------------------------------------------
    SetLength(Result, 0);

    If ASelLength <= 0 Then
        Exit;

    LSelStart := ASelStart;
    LSelEnd := ASelStart + ASelLength;

    If LSelStart < 0 Then
        LSelStart := 0;

    If LSelStart > Length(ALayout.Text) Then
        LSelStart := Length(ALayout.Text);

    If LSelEnd < LSelStart Then
        LSelEnd := LSelStart;

    If LSelEnd > Length(ALayout.Text) Then
        LSelEnd := Length(ALayout.Text);

    If LSelEnd <= LSelStart Then
        Exit;

    LFlowStart := ALayout.TextOriginCanonical.X +
        TextIndexToCanonicalFlow(
            ACanvas,
            ALayout.Text,
            LSelStart,
            ALayout.Angle);

    LFlowEnd := ALayout.TextOriginCanonical.X +
        TextIndexToCanonicalFlow(
            ACanvas,
            ALayout.Text,
            LSelEnd,
            ALayout.Angle);

    LCanonicalQuad.P1 := TRotatedEditFloatPoint.Create(
        LFlowStart,
        ALayout.CanonicalContentRect.Top);

    LCanonicalQuad.P2 := TRotatedEditFloatPoint.Create(
        LFlowEnd,
        ALayout.CanonicalContentRect.Top);

    LCanonicalQuad.P3 := TRotatedEditFloatPoint.Create(
        LFlowEnd,
        ALayout.CanonicalContentRect.Bottom);

    LCanonicalQuad.P4 := TRotatedEditFloatPoint.Create(
        LFlowStart,
        ALayout.CanonicalContentRect.Bottom);

    SetLength(Result, 1);

    Result[0] := TRotatedEditGeometry.TransformQuad(
        LCanonicalQuad,
        ALayout.ActualOrigin,
        ALayout.Angle);
End;

Class Function TRotatedEditLayout.HitTest(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult;
    Const AActualPoint: TPoint): TRotatedEditHitTestResult;
Var
    LActual:    TRotatedEditFloatPoint;
    LCanonical: TRotatedEditFloatPoint;
    LFlow:      Double;
Begin
    Result.ActualPoint := AActualPoint;

    LActual := TRotatedEditFloatPoint.Create(
        AActualPoint.X,
        AActualPoint.Y);

    LCanonical := TRotatedEditGeometry.InverseTransformPoint(
        LActual,
        ALayout.ActualOrigin,
        ALayout.Angle);

    Result.CanonicalPoint := LCanonical;

    Result.InTextBand := (LCanonical.Y >= ALayout.TextOriginCanonical.Y) And (LCanonical.Y <= ALayout.TextOriginCanonical.Y + ALayout.TextThickness);

    LFlow := LCanonical.X - ALayout.TextOriginCanonical.X;

    Result.InsertionIndex := CanonicalFlowToTextIndex(
        ACanvas,
        ALayout.Text,
        LFlow,
        ALayout.Angle);
End;

End.
