Unit VclRotatedEdit_Geometry;


{
  VclRotatedEdit_Geometry.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Geometry and projection helpers of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Outils de géométrie et de projection du composant VCL VclRotatedEdit.

  Cette unité centralise les conversions entre coordonnées canoniques non tournées et coordonnées client réelles. Le renderer, le caret, la sélection, le hit-test et le layout doivent tous respecter cette convention.
}

Interface

Uses
    System.Math,
    System.Types,
    VclRotatedEdit_Types;

Type
    {
      Stateless geometry helper.

      All methods are static because the geometry model is fully determined by
      the supplied points, origin and angle.
    }
    TRotatedEditGeometry = Class
    public
        {
          Converts a common orientation helper into the corresponding angle.

          Angle remains the source of truth. The orientation enum is only a
          friendly way to expose common values in the Object Inspector.
        }
        Class Function OrientationToAngle(
            AOrientation: TRotatedEditOrientation;
            ACustomAngle: Double): Double; Static;

        {
          Normalizes an angle to the [0, 360) range.

          This method does not change the public angle convention. It only keeps
          numeric values predictable.
        }
        Class Function NormalizeAngle(
            AAngle: Double): Double; Static;

        {
          Projects a canonical point to actual screen coordinates.

          AOrigin is the actual screen-space origin of the canonical coordinate
          system. The public angle convention is counter-clockwise positive, so
          the internal screen projection uses the inverted mathematical sign.
        }
        Class Function TransformPoint(
            Const APoint: TRotatedEditFloatPoint;
            Const AOrigin: TRotatedEditFloatPoint;
            AAngle: Double): TRotatedEditFloatPoint; Static;

        {
          Converts an actual screen point back into canonical coordinates.

          Mouse hit-testing must always use this method before calculating an
          insertion index.
        }
        Class Function InverseTransformPoint(
            Const APoint: TRotatedEditFloatPoint;
            Const AOrigin: TRotatedEditFloatPoint;
            AAngle: Double): TRotatedEditFloatPoint; Static;

        {
          Projects a canonical quad to actual screen coordinates.
        }
        Class Function TransformQuad(
            Const AQuad: TRotatedEditFloatQuad;
            Const AOrigin: TRotatedEditFloatPoint;
            AAngle: Double): TRotatedEditFloatQuad; Static;

        {
          Builds a thin quad around a caret segment.

          The segment is the center line of the caret. Thickness expands it on
          both sides along the perpendicular axis. The resulting quad is useful
          for future filled-caret rendering or precise invalidation.
        }
        Class Function BuildCaretQuad(
            Const AStartPoint: TRotatedEditFloatPoint;
            Const AEndPoint: TRotatedEditFloatPoint;
            AThickness: Double): TRotatedEditFloatQuad; Static;

        {
          Converts a floating-point point to a VCL TPoint.

          Rounding is intentionally delayed until the final drawing step.
        }
        Class Function FloatPointToPoint(
            Const APoint: TRotatedEditFloatPoint): TPoint; Static;
    End;

Implementation

Class Function TRotatedEditGeometry.OrientationToAngle(
    AOrientation: TRotatedEditOrientation;
    ACustomAngle: Double): Double;
Begin
    //-------------------------------------------------------------------------
    //Maps the public orientation helper to the internal public-angle value.
    //
    //Important convention validated for TRotatedEdit:
    //- reoVerticalDown means that the visual text flow starts near the top of
    //  the control and continues downward;
    //- reoVerticalUp means that the visual text flow starts near the bottom of
    //  the control and continues upward.
    //
    //Because screen coordinates grow downward and the geometry helper applies
    //the corresponding inverse mathematical rotation internally, the visual
    //"down" direction is represented by 270 degrees here, not 90 degrees.
    //
    //Do not compensate for this in the renderer. Rendering, caret placement,
    //selection, hit-testing and layout must all consume the same Angle.
    //-------------------------------------------------------------------------
    Case AOrientation Of
        reoHorizontal:
            Result := 0.0;

        reoVerticalDown:
            Result := 270.0;

        reoVerticalUp:
            Result := 90.0;

        reoCustomAngle:
            Result := ACustomAngle;
    Else
        Result := 0.0;
    End;

    Result := NormalizeAngle(Result);
End;

Class Function TRotatedEditGeometry.NormalizeAngle(
    AAngle: Double): Double;
Begin
    Result := AAngle;

    While Result < 0.0 Do
        Result := Result + 360.0;

    While Result >= 360.0 Do
        Result := Result - 360.0;
End;

Class Function TRotatedEditGeometry.TransformPoint(
    Const APoint: TRotatedEditFloatPoint;
    Const AOrigin: TRotatedEditFloatPoint;
    AAngle: Double): TRotatedEditFloatPoint;
Var
    LRad: Double;
    LCos: Double;
    LSin: Double;
Begin
    //-------------------------------------------------------------------------
    //Public angle convention:
    //  positive angle = counter-clockwise.
    //
    //Screen projection convention:
    //  Windows Y grows downward, therefore the mathematical sign is inverted.
    //
    //The renderer must use the same convention when it sets its world transform.
    //-------------------------------------------------------------------------
    LRad := -NormalizeAngle(AAngle) * Pi / 180.0;
    LCos := Cos(LRad);
    LSin := Sin(LRad);

    Result.X := AOrigin.X + (APoint.X * LCos) - (APoint.Y * LSin);
    Result.Y := AOrigin.Y + (APoint.X * LSin) + (APoint.Y * LCos);
End;

Class Function TRotatedEditGeometry.InverseTransformPoint(
    Const APoint: TRotatedEditFloatPoint;
    Const AOrigin: TRotatedEditFloatPoint;
    AAngle: Double): TRotatedEditFloatPoint;
Var
    LLocal: TRotatedEditFloatPoint;
Begin
    //-------------------------------------------------------------------------
    //Reverse projection used by mouse hit-testing.
    //
    //The mouse point is first translated back to the canonical origin, then the
    //opposite rotation is applied.
    //-------------------------------------------------------------------------
    LLocal.X := APoint.X - AOrigin.X;
    LLocal.Y := APoint.Y - AOrigin.Y;

    Result := TransformPoint(
        LLocal,
        TRotatedEditFloatPoint.Create(0.0, 0.0),
        -AAngle);
End;

Class Function TRotatedEditGeometry.TransformQuad(
    Const AQuad: TRotatedEditFloatQuad;
    Const AOrigin: TRotatedEditFloatPoint;
    AAngle: Double): TRotatedEditFloatQuad;
Begin
    Result.P1 := TransformPoint(AQuad.P1, AOrigin, AAngle);
    Result.P2 := TransformPoint(AQuad.P2, AOrigin, AAngle);
    Result.P3 := TransformPoint(AQuad.P3, AOrigin, AAngle);
    Result.P4 := TransformPoint(AQuad.P4, AOrigin, AAngle);
End;

Class Function TRotatedEditGeometry.BuildCaretQuad(
    Const AStartPoint: TRotatedEditFloatPoint;
    Const AEndPoint: TRotatedEditFloatPoint;
    AThickness: Double): TRotatedEditFloatQuad;
Var
    LDX: Double;
    LDY: Double;
    LLength: Double;
    LNX: Double;
    LNY: Double;
    LHalfThickness: Double;
Begin
    LDX := AEndPoint.X - AStartPoint.X;
    LDY := AEndPoint.Y - AStartPoint.Y;
    LLength := Sqrt((LDX * LDX) + (LDY * LDY));

    If LLength <= 0.0 Then Begin
        LNX := 1.0;
        LNY := 0.0;
    End Else Begin
        LNX := -LDY / LLength;
        LNY := LDX / LLength;
    End;

    LHalfThickness := AThickness / 2.0;

    Result.P1 := TRotatedEditFloatPoint.Create(
        AStartPoint.X + (LNX * LHalfThickness),
        AStartPoint.Y + (LNY * LHalfThickness));

    Result.P2 := TRotatedEditFloatPoint.Create(
        AEndPoint.X + (LNX * LHalfThickness),
        AEndPoint.Y + (LNY * LHalfThickness));

    Result.P3 := TRotatedEditFloatPoint.Create(
        AEndPoint.X - (LNX * LHalfThickness),
        AEndPoint.Y - (LNY * LHalfThickness));

    Result.P4 := TRotatedEditFloatPoint.Create(
        AStartPoint.X - (LNX * LHalfThickness),
        AStartPoint.Y - (LNY * LHalfThickness));
End;

Class Function TRotatedEditGeometry.FloatPointToPoint(
    Const APoint: TRotatedEditFloatPoint): TPoint;
Begin
    Result := Point(
        Round(APoint.X),
        Round(APoint.Y));
End;

End.
