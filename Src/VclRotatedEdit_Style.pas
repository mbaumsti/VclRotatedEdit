Unit VclRotatedEdit_Style;


{
  VclRotatedEdit_Style.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Style and color resolution layer of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Couche de résolution des styles et couleurs du composant VCL VclRotatedEdit.

  Cette unité centralise la résolution des couleurs effectives en tenant compte de PaletteMode, StyleElements, du contexte runtime et du contexte design-time.
}

Interface

{$IF CompilerVersion >= 34.0}
  {$DEFINE VCLROTATEDEDIT_HAS_CONTROL_STYLE_NAME}
  {$DEFINE VCLROTATEDEDIT_HAS_CONTROL_STYLE_SERVICES}
{$IFEND}

Uses
    System.Types,
    Vcl.Graphics,
    Vcl.Controls,
    Vcl.Forms,
    Vcl.Themes,
    VclRotatedEdit_Types;

Type
    {
      Fully resolved rendering contract used by the active render backend.

      The renderer must not decide whether a style is active, whether the border
      is visible, or which fallback color should be used. Those decisions are
      fixed here so rendering stays deterministic.
    }
    TRotatedEditStyleColors = Record
        BackgroundColor: TColor;
        TextColor: TColor;
        BorderColor: TColor;
        SelectionColor: TColor;
        SelectionTextColor: TColor;
        CaretColor: TColor;
        HintTextColor: TColor;

        //-----------------------------------------------------------------
        //Style service selected for this control.
        //
        //Runtime keeps the established behavior because it already resolves
        //the expected application colors. Design-time can use a different
        //style service source, resolved from the parent/control context, to
        //match the form designer more closely.
        //-----------------------------------------------------------------
        VclStyleServices: TCustomStyleServices;

        UseStyledClient: Boolean;
        UseStyledFont: Boolean;
        UseStyledBorder: Boolean;
        BorderVisible: Boolean;
    End;

    TRotatedEditStyle = Class
    private
        Class Function ResolveStyleServices(
            AControl: TControl;
            AUseStylePalette: Boolean;
            AStyleName: String): TCustomStyleServices; Static;

    public
        {
          Resolves all colors and style switches for the current control state.

          AUseStylePalette is the Core-level PaletteMode decision:
          - True  = repmStyle;
          - False = repmCustom.

          AStyleName identifies an optional control-level VCL style override.

          Delphi 12.2 note:
          ThemeServices does not provide a Handle overload. Runtime keeps the
          existing style-service order because it already works. Design-time
          first tries the parent/control StyleServices context because the global
          active style can be the IDE/default Windows context instead of the
          style selected for the current project form.

          AStyleElements keeps the familiar VCL styled-control behavior when
          PaletteMode is repmStyle.

          ABorderStyle keeps the familiar VCL meaning:
          - bsSingle = frame visible;
          - bsNone   = no frame.
        }
        Class Function ResolveColors(
            AControl: TControl;
            AEnabled: Boolean;
            AFocused: Boolean;
            AColor: TColor;
            AFontColor: TColor;
            ABorderColor: TColor;
            AUseStylePalette: Boolean;
            AStyleName: String;
            AStyleElements: TStyleElements;
            ABorderStyle: TBorderStyle): TRotatedEditStyleColors; Static;

        {
          Resolves the real canonical content insets of the edit frame.

          The layout engine needs this before drawing, because these metrics
          define the rectangle where text, caret, selection and hit-testing live.
          A styled VCL edit does not always have a 1-pixel border. In several
          styles the visual frame consumes two pixels on the top/bottom, and the
          returned content rectangle can be asymmetric.

          The method intentionally receives a canvas: StyleServices can need a
          valid HDC to compute GetElementContentRect for the current style.
        }
        Class Function ResolveBorderMetrics(
            ACanvas: TCanvas;
            AControl: TControl;
            AUseStylePalette: Boolean;
            AStyleName: String;
            AStyleElements: TStyleElements;
            ABorderStyle: TBorderStyle): TRotatedEditBorderMetrics; Static;
    End;

Implementation

Uses
    Winapi.Windows,
    System.Classes,
    System.SysUtils,
    System.UITypes;

Class Function TRotatedEditStyle.ResolveStyleServices(
    AControl: TControl;
    AUseStylePalette: Boolean;
    AStyleName: String): TCustomStyleServices;
Begin
    //-------------------------------------------------------------------------
    //Centralizes the VCL style-service selection used by both color and border
    //metric resolution.
    //
    //Why this helper exists
    //----------------------
    //The layout is now based on the real styled edit content rectangle. If the
    //color resolver and the metric resolver used different StyleServices
    //instances, the renderer could draw one frame while the layout reserves the
    //insets of another. That would reintroduce vertical/cross-axis offsets.
    //
    //Runtime keeps the existing style-service order. Design-time still prefers the
    //parent/control context so a component dropped on a styled form follows the
    //designer surface rather than the IDE/global style.
    //-------------------------------------------------------------------------
    Result := StyleServices;

    If Not AUseStylePalette Then
        Exit;

    Result := Nil;

    {$IFDEF VCLROTATEDEDIT_HAS_CONTROL_STYLE_NAME}
    //---------------------------------------------------------------------
    //Per-control VCL style names were introduced after Delphi 10.2.3.
    //Older compilers must not reference TControl.StyleName nor resolve a
    //style through this newer control-level mechanism. They still use the
    //global application VCL style fallback below.
    //---------------------------------------------------------------------
    If AStyleName <> '' Then
        Result := TStyleManager.Style[AStyleName];
    {$ENDIF}

    If Result = Nil Then Begin
        If (AControl <> Nil) And
           (csDesigning In AControl.ComponentState) Then Begin
            {$IFDEF VCLROTATEDEDIT_HAS_CONTROL_STYLE_SERVICES}
            //-------------------------------------------------------------
            //Recent VCL versions expose StyleServices(Control). Delphi
            //10.2.3 does not. For older compilers, keep the component
            //buildable by falling back to the global StyleServices object.
            //-------------------------------------------------------------
            If AControl.Parent <> Nil Then
                Result := StyleServices(AControl.Parent);

            If Result = Nil Then
                Result := StyleServices(AControl);
            {$ELSE}
            Result := StyleServices;
            {$ENDIF}
        End Else Begin
            Result := ThemeServices;

            If Result = Nil Then
                Result := TStyleManager.ActiveStyle;

            If Result = Nil Then
                Result := StyleServices;
        End;
    End;

    If Result = Nil Then
        Result := StyleServices;
End;

Class Function TRotatedEditStyle.ResolveColors(
    AControl: TControl;
    AEnabled: Boolean;
    AFocused: Boolean;
    AColor: TColor;
    AFontColor: TColor;
    ABorderColor: TColor;
    AUseStylePalette: Boolean;
    AStyleName: String;
    AStyleElements: TStyleElements;
    ABorderStyle: TBorderStyle): TRotatedEditStyleColors;
Var
    LDetails: TThemedElementDetails;
    LColor: TColor;
    LStyleServices: TCustomStyleServices;
Begin
    //-------------------------------------------------------------------------
    //Custom palette / fallback.
    //
    //These values are always meaningful, even when the application has no VCL
    //style active. Style palette mode may replace some of them below.
    //-------------------------------------------------------------------------
    Result.BackgroundColor := AColor;
    Result.TextColor := AFontColor;
    Result.BorderColor := ABorderColor;

    Result.SelectionColor := clHighlight;
    Result.SelectionTextColor := clHighlightText;
    Result.CaretColor := Result.TextColor;
    Result.HintTextColor := clGrayText;
    Result.VclStyleServices := StyleServices;

    Result.BorderVisible := ABorderStyle <> bsNone;

    Result.UseStyledClient := False;
    Result.UseStyledFont := False;
    Result.UseStyledBorder := False;

    //-------------------------------------------------------------------------
    //Style palette mode.
    //
    //PaletteMode chooses the palette family:
    //- repmStyle  uses the style palette if available;
    //- repmCustom uses explicit component colors.
    //
    //StyleElements is still honored inside repmStyle so the component behaves
    //like a normal VCL styled control: the caller can independently opt out of
    //styled client, font or border colors.
    //-------------------------------------------------------------------------
    If AUseStylePalette Then Begin
        //---------------------------------------------------------------------
        //Resolve the style service that belongs to this control.
        //
        //Important rule:
        //- runtime keeps the established resolution sequence unchanged because it
        //  already returns the expected application colors;
        //- design-time avoids TStyleManager.ActiveStyle as the first source
        //  because the component code runs inside the IDE/design package
        //  context. In that situation the global active style can be the IDE or
        //  default Windows style instead of the style used by the designed form.
        //
        //Using the parent/control style context in design-time mirrors the
        //practical behavior of standard controls placed on the same form while
        //keeping the owner-drawn rendering pipeline intact.
        //---------------------------------------------------------------------
        LStyleServices := ResolveStyleServices(
            AControl,
            AUseStylePalette,
            AStyleName);

        Result.VclStyleServices := LStyleServices;

        If Not LStyleServices.Enabled Then
            Exit;

        //---------------------------------------------------------------------
        //StyleElements are honored only in style palette mode.
        //
        //This mirrors normal VCL control behavior better than the previous
        //all-or-nothing style switch and fixes design-time inconsistencies
        //against a normal TEdit placed on the same styled form.
        //---------------------------------------------------------------------
        Result.UseStyledClient := seClient In AStyleElements;
        Result.UseStyledFont := seFont In AStyleElements;
        Result.UseStyledBorder := Result.BorderVisible And (seBorder In AStyleElements);

        //---------------------------------------------------------------------
        //Styled palette fallback rule.
        //
        //In repmStyle, the user expects Color / Font.Color / BorderColor not to
        //drive the main rendering. This must remain true even when:
        //- BorderStyle = bsNone;
        //- the style does not return ecFillColor for teEditTextNormal;
        //- the background is drawn without calling StyleServices.DrawElement.
        //
        //We therefore start with styled system colors, then use more specific
        //element colors if the active style exposes them.
        //---------------------------------------------------------------------
        LDetails := LStyleServices.GetElementDetails(teEditTextNormal);

        If Result.UseStyledClient Then Begin
            Result.BackgroundColor := LStyleServices.GetSystemColor(clWindow);

            If LStyleServices.GetElementColor(
                LDetails,
                ecFillColor,
                LColor) Then
                Result.BackgroundColor := LColor;
        End;

        If Result.UseStyledFont Then Begin
            Result.TextColor := LStyleServices.GetSystemColor(clWindowText);

            If LStyleServices.GetElementColor(
                LDetails,
                ecTextColor,
                LColor) Then
                Result.TextColor := LColor;

            Result.HintTextColor := LStyleServices.GetSystemColor(clGrayText);
        End;

        If Result.UseStyledBorder Then Begin
            Result.BorderColor := LStyleServices.GetSystemColor(clBtnShadow);

            If AFocused Then
                Result.BorderColor := LStyleServices.GetSystemColor(clHighlight);
        End;
    End;

    If Not AEnabled Then Begin
        Result.TextColor := clGrayText;
        Result.CaretColor := clGrayText;
        Result.HintTextColor := clGrayText;
    End Else
        Result.CaretColor := Result.TextColor;

    //-------------------------------------------------------------------------
    //Border color rule.
    //
    //When UseStyledBorder is True the renderer delegates the frame to
    //StyleServices. Otherwise BorderColor is used as-is. We do not force a
    //custom focus highlight because that would make BorderColor unpredictable.
    //-------------------------------------------------------------------------
End;

Class Function TRotatedEditStyle.ResolveBorderMetrics(
    ACanvas: TCanvas;
    AControl: TControl;
    AUseStylePalette: Boolean;
    AStyleName: String;
    AStyleElements: TStyleElements;
    ABorderStyle: TBorderStyle): TRotatedEditBorderMetrics;
Var
    LStyleServices: TCustomStyleServices;
    LDetails: TThemedElementDetails;
    LOuterRect: TRect;
    LContentRect: TRect;
    LEdgeX: Integer;
    LEdgeY: Integer;
Begin
    //-------------------------------------------------------------------------
    //Default contract.
    //
    //No frame means no border inset. The public TextPaddingStart/TextPaddingEnd
    //are still applied later by the layout engine.
    //-------------------------------------------------------------------------
    Result.Left := 0;
    Result.Top := 0;
    Result.Right := 0;
    Result.Bottom := 0;

    If ABorderStyle = bsNone Then
        Exit;

    //-------------------------------------------------------------------------
    //Styled VCL frame path.
    //
    //When seBorder participates in repmStyle, the renderer delegates the edit
    //frame to StyleServices.DrawElement(teEditTextNormal). The matching content
    //insets must therefore also come from StyleServices.GetElementContentRect.
    //This is the important fix: a styled TEdit often reserves more than one
    //pixel, and the content margins are not guaranteed to be symmetric.
    //-------------------------------------------------------------------------
    If AUseStylePalette And
       (seBorder In AStyleElements) Then Begin
        LStyleServices := ResolveStyleServices(
            AControl,
            AUseStylePalette,
            AStyleName);

        If (LStyleServices <> Nil) And
           LStyleServices.Enabled And
           (ACanvas <> Nil) Then Begin
            LOuterRect := Rect(
                0,
                0,
                100,
                100);

            LDetails := LStyleServices.GetElementDetails(teEditTextNormal);

            If LStyleServices.GetElementContentRect(
                ACanvas.Handle,
                LDetails,
                LOuterRect,
                LContentRect) Then Begin
                Result.Left := LContentRect.Left - LOuterRect.Left;
                Result.Top := LContentRect.Top - LOuterRect.Top;
                Result.Right := LOuterRect.Right - LContentRect.Right;
                Result.Bottom := LOuterRect.Bottom - LContentRect.Bottom;

                If Result.Left < 0 Then
                    Result.Left := 0;

                If Result.Top < 0 Then
                    Result.Top := 0;

                If Result.Right < 0 Then
                    Result.Right := 0;

                If Result.Bottom < 0 Then
                    Result.Bottom := 0;

                Exit;
            End;
        End;
    End;

    //-------------------------------------------------------------------------
    //Classic / unstyled fallback.
    //
    //The owner-drawn non-styled path draws a simple one-pixel rectangle. Its
    //layout inset must therefore stay one pixel; using SM_CXEDGE/SM_CYEDGE here
    //would reserve a two-pixel 3D client edge that the renderer does not draw.
    //
    //The system metrics are still read as a documented fallback reference for
    //future changes, but the active fallback remains the actual pen width.
    //-------------------------------------------------------------------------
    LEdgeX := GetSystemMetrics(SM_CXEDGE);
    LEdgeY := GetSystemMetrics(SM_CYEDGE);

    If LEdgeX < 1 Then
        LEdgeX := 1;

    If LEdgeY < 1 Then
        LEdgeY := 1;

    Result.Left := 1;
    Result.Top := 1;
    Result.Right := 1;
    Result.Bottom := 1;
End;

End.
