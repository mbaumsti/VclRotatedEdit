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

        BorderWidth: Integer;
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

        Class Procedure BuildTextAdvances(
            ACanvas: TCanvas;
            Const AText: String;
            Out AAdvances: TArray<Integer>;
            Out ATextSize: TSize); Static;

        Class Function GetAdvanceAtIndex(
            Const AAdvances: TArray<Integer>;
            AIndex: Integer): Integer; Static;

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

          V1 uses TextWidth(Copy(Text, 1, Index)). Later versions may cache
          per-character advances, but the rule must remain the same.
        }
        Class Function TextIndexToCanonicalFlow(
            ACanvas: TCanvas;
            Const AText: String;
            AIndex: Integer): Double; Static;

        {
          Converts a canonical flow coordinate to an insertion index.

          Rule:
          The insertion index is determined by character midpoints in canonical
          coordinates, never by actual screen-space top-left points.
        }
        Class Function CanonicalFlowToTextIndex(
            ACanvas: TCanvas;
            Const AText: String;
            AFlow: Double): Integer; Static;

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
            Const ACanonicalContentRect: TRect): Integer; Static;

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

Class Procedure TRotatedEditLayout.BuildTextAdvances(
    ACanvas: TCanvas;
    Const AText: String;
    Out AAdvances: TArray<Integer>;
    Out ATextSize: TSize);
Var
    LFit:        Integer;
    LTextLength: Integer;
    LOk:         Boolean;
Begin
    //-------------------------------------------------------------------------
    //Builds cumulative character advances for a complete text run.
    //
    //Why this method exists
    //----------------------
    //A rotated edit control makes small metric differences very visible.
    //
    //The renderer draws the whole text with GDI TextOut. If the layout places
    //the caret using TextWidth(Copy(Text, 1, Index)), the caret can slowly drift
    //away from the visually rendered glyphs because each prefix measurement may
    //round slightly differently from the full rendered text run.
    //
    //GetTextExtentExPoint returns cumulative advances for the complete string in
    //one GDI call. Those advances are therefore a better source for:
    //- caret X position;
    //- selection geometry;
    //- hit-testing by character midpoint;
    //- scroll-to-caret calculations.
    //
    //Important limitation
    //--------------------
    //This is still a GDI metric model. It does not implement Unicode shaping,
    //surrogate pairs, ligature clusters or bidirectional text. That is
    //acceptable for the current single-line V1 component, but this method is the
    //place to replace if a future version moves to Uniscribe / DirectWrite.
    //-------------------------------------------------------------------------
    LTextLength := Length(AText);

    SetLength(
        AAdvances,
        LTextLength);

    ATextSize.cx := 0;
    ATextSize.cy := 0;

    If LTextLength = 0 Then
        Exit;

    LFit := 0;

    LOk := GetTextExtentExPoint(
        ACanvas.Handle,
        PChar(AText),
        LTextLength,
        MaxInt,
        @LFit,
        @AAdvances[0],
        ATextSize);

    If Not LOk Then Begin
        //---------------------------------------------------------------------
        //Fallback path.
        //
        //This should rarely be used, but keeping a deterministic fallback is
        //safer than returning a half-built advance table. The fallback preserves
        //the old behavior and is therefore acceptable as degraded mode.
        //---------------------------------------------------------------------
        ATextSize.cx := ACanvas.TextWidth(AText);
        ATextSize.cy := ACanvas.TextHeight('Wg');

        For LFit := 1 To LTextLength Do
            AAdvances[LFit - 1] := ACanvas.TextWidth(Copy(AText, 1, LFit));
    End;
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
    LLogicalLength:    Integer;
    LLogicalThickness: Integer;
    LContentWidth:     Integer;
    LTextOriginX:      Double;
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

    Result.CanonicalContentRect := Rect(
        AInput.BorderWidth + AInput.PaddingLeft,
        AInput.BorderWidth + AInput.PaddingTop,
        LLogicalLength - AInput.BorderWidth - AInput.PaddingRight,
        LLogicalThickness - AInput.BorderWidth - AInput.PaddingBottom);

    If Result.CanonicalContentRect.Right < Result.CanonicalContentRect.Left Then
        Result.CanonicalContentRect.Right := Result.CanonicalContentRect.Left;

    If Result.CanonicalContentRect.Bottom < Result.CanonicalContentRect.Top Then
        Result.CanonicalContentRect.Bottom := Result.CanonicalContentRect.Top;

    Result.Text := AInput.Text;
    //-------------------------------------------------------------------------
    //TextLength / TextThickness are layout estimates used by rendering and
    //scrolling. TextLength is resolved through the same cumulative-advance
    //policy as caret placement so long text and rotated text do not drift.
    //-------------------------------------------------------------------------
    Result.TextLength := Round(TextIndexToCanonicalFlow(ACanvas, AInput.Text, Length(AInput.Text)));

    Result.TextThickness := ACanvas.TextHeight('Wg');
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
        Result.CanonicalContentRect);

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

    Result.TextOriginCanonical := TRotatedEditFloatPoint.Create(
        LTextOriginX,
        Result.CanonicalContentRect.Top + ((Result.CanonicalContentRect.Height - Result.TextThickness) / 2.0));

    Result.TextOriginActual := TRotatedEditGeometry.TransformPoint(
        Result.TextOriginCanonical,
        Result.ActualOrigin,
        Result.Angle);

    Result.Caret := BuildCaretGeometry(
        ACanvas,
        Result,
        AInput.CaretIndex,
        AInput.CaretThickness);

    Result.SelectionQuads := BuildSelectionGeometry(
        ACanvas,
        Result,
        AInput.SelStart,
        AInput.SelLength);
End;

Class Function TRotatedEditLayout.TextIndexToCanonicalFlow(
    ACanvas: TCanvas;
    Const AText: String;
    AIndex: Integer): Double;
Var
    LIndex:    Integer;
    LAdvances: TArray<Integer>;
    LTextSize: TSize;
Begin
    //-------------------------------------------------------------------------
    //Converts a text insertion index to a canonical flow coordinate.
    //
    //This method is deliberately based on GetTextExtentExPoint through
    //BuildTextAdvances instead of TextWidth(Copy(...)).
    //
    //Reason:
    //The text renderer draws the complete string. If caret placement is measured
    //from independently-rendered prefixes, tiny rounding differences can
    //accumulate. At arbitrary angles those tiny differences become visible as a
    //caret drift that appears to grow with the distance from the text origin.
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
        LAdvances,
        LTextSize);

    Result := GetAdvanceAtIndex(
        LAdvances,
        LIndex);
End;

Class Function TRotatedEditLayout.CanonicalFlowToTextIndex(
    ACanvas: TCanvas;
    Const AText: String;
    AFlow: Double): Integer;
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
    //TextIndexToCanonicalFlow. Never mix TextWidth(Copy(...)) here, otherwise
    //mouse hit-testing and caret rendering can disagree.
    //-------------------------------------------------------------------------
    Result := 0;

    If AFlow <= 0.0 Then
        Exit;

    If Length(AText) = 0 Then
        Exit;

    BuildTextAdvances(
        ACanvas,
        AText,
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
    Const ACanonicalContentRect: TRect): Integer;
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
        ACaretIndex);

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
        ACaretIndex);

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
            LSelStart);

    LFlowEnd := ALayout.TextOriginCanonical.X +
        TextIndexToCanonicalFlow(
            ACanvas,
            ALayout.Text,
            LSelEnd);

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
        LFlow);
End;

End.
