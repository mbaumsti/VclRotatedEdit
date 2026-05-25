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

Uses
    Vcl.Graphics,
    Vcl.Controls,
    Vcl.Forms,
    Vcl.Themes;

Type
    {
      Fully resolved rendering contract used by TRotatedEditRenderer.

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
        //Runtime keeps the existing v76 behavior because it already resolves
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
    public
        {
          Resolves all colors and style switches for the current control state.

          AUseStylePalette is the Core-level PaletteMode decision:
          - True  = repmStyle;
          - False = repmCustom.

          AStyleName identifies an optional control-level VCL style override.

          Delphi 12.2 note:
          ThemeServices does not provide a Handle overload. Runtime keeps the
          existing v76 style-service order because it already works. Design-time
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
    End;

Implementation

Uses
    System.Classes,
    System.UITypes;

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
        //Important v77 rule:
        //- runtime keeps the v76 resolution sequence unchanged because it
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
        LStyleServices := Nil;

        If AStyleName <> '' Then
            LStyleServices := TStyleManager.Style[AStyleName];

        If LStyleServices = Nil Then Begin
            If (AControl <> Nil) And
               (csDesigning In AControl.ComponentState) Then Begin
                //-------------------------------------------------------------
                //Design-time branch only.
                //
                //The parent is preferred because it belongs to the designed
                //form/control hierarchy. This is the closest available context
                //to the visual style that the designer applies to ordinary VCL
                //controls such as TEdit.
                //-------------------------------------------------------------
                If AControl.Parent <> Nil Then
                    LStyleServices := StyleServices(AControl.Parent);

                If LStyleServices = Nil Then
                    LStyleServices := StyleServices(AControl);
            End Else Begin
                //-------------------------------------------------------------
                //Runtime branch.
                //
                //Do not change this order unless the runtime behavior becomes
                //wrong. In v76 this path already resolves the correct colors in
                //executed applications.
                //-------------------------------------------------------------
                LStyleServices := ThemeServices;

                If LStyleServices = Nil Then
                    LStyleServices := TStyleManager.ActiveStyle;

                If LStyleServices = Nil Then
                    LStyleServices := StyleServices;
            End;
        End;

        If LStyleServices = Nil Then
            LStyleServices := StyleServices;

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

End.
