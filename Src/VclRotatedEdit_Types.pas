Unit VclRotatedEdit_Types;


{
  VclRotatedEdit_Types.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Shared public and internal types of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Types publics et internes partagés du composant VCL VclRotatedEdit.

  Cette unité définit le vocabulaire commun : orientation, dimensions logiques, géométrie projetée, résultats de layout, hit-test et signatures d’événements.
}

Interface

Uses
    System.Types;

Type
    {
      Common orientation values exposed in the Object Inspector.

      Angle remains the source of truth for future arbitrary rotations.
      Orientation is a convenience layer for the three common edit directions.
    }
    TRotatedEditOrientation = (
        reoHorizontal,
        reoVerticalDown,
        reoVerticalUp,
        reoCustomAngle
    );

    {
      Editing completion reason passed to OnEditingDone.
    }
    TRotatedEditEditingDoneReason = (
        redrEnter,
        redrEscape,
        redrFocusLost,
        redrProgrammatic
    );

    {
      Validation result passed by OnValidate.

      revAccept keeps the new text.
      revReject keeps focus/editing active.
      revCancel rejects the text and lets the component finish editing.
    }
    TRotatedEditValidationResult = (
        revAccept,
        revReject,
        revCancel
    );

    {
      Floating point used by the geometry pipeline.

      Integer coordinates are intentionally delayed until the final drawing step
      to avoid accumulating rounding errors when rotating caret and selection
      geometry.
    }
    TRotatedEditFloatPoint = Record
        X: Double;
        Y: Double;

        Class Function Create(
            AX: Double;
            AY: Double): TRotatedEditFloatPoint; Static;
    End;

    {
      Oriented quadrilateral.

      The editable surface, caret and selection are not necessarily screen-
      aligned rectangles once rotation is applied.
    }
    TRotatedEditFloatQuad = Record
        P1: TRotatedEditFloatPoint;
        P2: TRotatedEditFloatPoint;
        P3: TRotatedEditFloatPoint;
        P4: TRotatedEditFloatPoint;
    End;

    {
      Resolved edit-frame metrics in canonical coordinates.

      These values describe the real visual/content inset of the editable
      surface, not an arbitrary owner-drawn pen width. They are deliberately
      asymmetric because VCL styles can return content rectangles where the top,
      bottom, left and right insets are not identical.

      The layout engine uses these metrics to build CanonicalContentRect. The
      renderer must then draw the frame according to the same style contract,
      without inventing another implicit 1-pixel border model.
    }
    TRotatedEditBorderMetrics = Record
        Left: Integer;
        Top: Integer;
        Right: Integer;
        Bottom: Integer;
    End;

    {
      Caret geometry.

      The caret is not represented by a screen top-left point.

      It is built from a canonical insertion segment and then transformed to
      screen coordinates. The HotPoint is the center of the caret geometry and
      is the common reference used by scroll, hit-test diagnostics and optional
      popup positioning.

      This HotPoint represents both:
      - the insertion position between two characters along the text flow axis;
      - the vertical middle of the edited line along the cross axis.
    }
    TRotatedEditCaretGeometry = Record
        Index: Integer;

        Flow: Double;
        CrossTop: Double;
        CrossBottom: Double;
        Thickness: Double;

        CanonicalSegmentStart: TRotatedEditFloatPoint;
        CanonicalSegmentEnd: TRotatedEditFloatPoint;
        CanonicalQuad: TRotatedEditFloatQuad;
        CanonicalHotPoint: TRotatedEditFloatPoint;

        ActualSegmentStart: TRotatedEditFloatPoint;
        ActualSegmentEnd: TRotatedEditFloatPoint;
        ActualQuad: TRotatedEditFloatQuad;
        ActualHotPoint: TRotatedEditFloatPoint;
    End;

    {
      Full layout result for one paint/edit pass.

      The layout result intentionally exposes both the physical VCL rectangle and
      the logical canonical edit surface.

      ClientRect
        Physical screen-space rectangle of the VCL control.

      LogicalLength / LogicalThickness
        Canonical dimensions of the editable surface.

      CanonicalEditRect
        Edit surface rectangle before rotation. Normally:
        (0, 0, LogicalLength, LogicalThickness).

      CanonicalContentRect
        Canonical area after border and padding. Text, caret and selection live
        in this rectangle.

      ActualOrigin
        Actual screen-space origin used to project canonical coordinates.

      ActualEditQuad
        Rotated editable surface in screen-space coordinates.
    }
    TRotatedEditLayoutResult = Record
        ClientRect: TRect;

        LogicalLength: Integer;
        LogicalThickness: Integer;

        CanonicalEditRect: TRect;
        CanonicalContentRect: TRect;

        ActualOrigin: TRotatedEditFloatPoint;
        ActualEditQuad: TRotatedEditFloatQuad;
        ActualContentQuad: TRotatedEditFloatQuad;
        ActualEditBounds: TRect;

        Text: String;
        TextLength: Integer;
        TextThickness: Integer;

        Angle: Double;
        ScrollOffset: Integer;

        TextOriginCanonical: TRotatedEditFloatPoint;
        TextOriginActual: TRotatedEditFloatPoint;

        Caret: TRotatedEditCaretGeometry;
        SelectionQuads: TArray<TRotatedEditFloatQuad>;
    End;

    {
      Result of a mouse hit-test.

      ActualPoint is the original mouse coordinate.
      CanonicalPoint is the same point transformed back into the edit's
      canonical coordinate system.
    }
    TRotatedEditHitTestResult = Record
        ActualPoint: TPoint;
        CanonicalPoint: TRotatedEditFloatPoint;
        InTextBand: Boolean;
        InsertionIndex: Integer;
    End;

    TRotatedEditValidateEvent = Procedure(
        Sender: TObject;
        Const AText: String;
        Var AResult: TRotatedEditValidationResult) Of Object;

    TRotatedEditEditingDoneEvent = Procedure(
        Sender: TObject;
        AReason: TRotatedEditEditingDoneReason) Of Object;

    {
      Immediate text-change veto event.

      OnCanChange is called before an individual normalized text candidate is
      accepted. It is intentionally distinct from OnValidate, which validates
      the final value when an editing session is completed.
    }
    TRotatedEditCanChangeEvent = Procedure(
        Sender: TObject;
        Const AOldText: String;
        Const ANewText: String;
        Var ACanChange: Boolean) Of Object;

Implementation

Class Function TRotatedEditFloatPoint.Create(
    AX: Double;
    AY: Double): TRotatedEditFloatPoint;
Begin
    Result.X := AX;
    Result.Y := AY;
End;

End.
