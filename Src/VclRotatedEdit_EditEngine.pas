Unit VclRotatedEdit_EditEngine;


{
  VclRotatedEdit_EditEngine.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Pure text editing engine of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Moteur pur d’édition de texte du composant VCL VclRotatedEdit.

  Cette unité applique les mutations de texte indépendamment de la géométrie : insertion, suppression, sélection normalisée, MaxLength et ReadOnly.
}

Interface

Type
    TRotatedEditEditState = Record
        Text: String;
        CaretIndex: Integer;
        SelStart: Integer;
        SelLength: Integer;
        ReadOnly: Boolean;
        MaxLength: Integer;
    End;

    TRotatedEditEditEngine = Class
    public
        Class Procedure NormalizeState(
            Var AState: TRotatedEditEditState); Static;

        Class Function HasSelection(
            Const AState: TRotatedEditEditState): Boolean; Static;

        Class Procedure DeleteSelection(
            Var AState: TRotatedEditEditState); Static;

        Class Procedure InsertText(
            Var AState: TRotatedEditEditState;
            Const AText: String); Static;

        Class Procedure DeleteBackward(
            Var AState: TRotatedEditEditState); Static;

        Class Procedure DeleteForward(
            Var AState: TRotatedEditEditState); Static;

        Class Procedure MoveCaretLeft(
            Var AState: TRotatedEditEditState;
            AExtendSelection: Boolean); Static;

        Class Procedure MoveCaretRight(
            Var AState: TRotatedEditEditState;
            AExtendSelection: Boolean); Static;

        Class Procedure MoveCaretHome(
            Var AState: TRotatedEditEditState;
            AExtendSelection: Boolean); Static;

        Class Procedure MoveCaretEnd(
            Var AState: TRotatedEditEditState;
            AExtendSelection: Boolean); Static;

        Class Procedure SelectAll(
            Var AState: TRotatedEditEditState); Static;
    End;

Implementation

Class Procedure TRotatedEditEditEngine.NormalizeState(
    Var AState: TRotatedEditEditState);
Begin
    If AState.MaxLength < 0 Then
        AState.MaxLength := 0;

    If AState.SelStart < 0 Then
        AState.SelStart := 0;

    If AState.SelStart > Length(AState.Text) Then
        AState.SelStart := Length(AState.Text);

    If AState.SelLength < 0 Then
        AState.SelLength := 0;

    If AState.SelStart + AState.SelLength > Length(AState.Text) Then
        AState.SelLength := Length(AState.Text) - AState.SelStart;

    If AState.CaretIndex < 0 Then
        AState.CaretIndex := 0;

    If AState.CaretIndex > Length(AState.Text) Then
        AState.CaretIndex := Length(AState.Text);
End;

Class Function TRotatedEditEditEngine.HasSelection(
    Const AState: TRotatedEditEditState): Boolean;
Begin
    Result := AState.SelLength > 0;
End;

Class Procedure TRotatedEditEditEngine.DeleteSelection(
    Var AState: TRotatedEditEditState);
Begin
    NormalizeState(AState);

    If AState.ReadOnly Then
        Exit;

    If Not HasSelection(AState) Then
        Exit;

    Delete(
        AState.Text,
        AState.SelStart + 1,
        AState.SelLength);

    AState.CaretIndex := AState.SelStart;
    AState.SelLength := 0;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.InsertText(
    Var AState: TRotatedEditEditState;
    Const AText: String);
Var
    LText: String;
    LAvailable: Integer;
Begin
    NormalizeState(AState);

    If AState.ReadOnly Then
        Exit;

    If HasSelection(AState) Then
        DeleteSelection(AState);

    LText := AText;

    If AState.MaxLength > 0 Then Begin
        LAvailable := AState.MaxLength - Length(AState.Text);

        If LAvailable <= 0 Then
            Exit;

        If Length(LText) > LAvailable Then
            LText := Copy(
                LText,
                1,
                LAvailable);
    End;

    Insert(
        LText,
        AState.Text,
        AState.CaretIndex + 1);

    Inc(
        AState.CaretIndex,
        Length(LText));

    AState.SelStart := AState.CaretIndex;
    AState.SelLength := 0;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.DeleteBackward(
    Var AState: TRotatedEditEditState);
Begin
    NormalizeState(AState);

    If AState.ReadOnly Then
        Exit;

    If HasSelection(AState) Then Begin
        DeleteSelection(AState);
        Exit;
    End;

    If AState.CaretIndex <= 0 Then
        Exit;

    Delete(
        AState.Text,
        AState.CaretIndex,
        1);

    Dec(AState.CaretIndex);
    AState.SelStart := AState.CaretIndex;
    AState.SelLength := 0;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.DeleteForward(
    Var AState: TRotatedEditEditState);
Begin
    NormalizeState(AState);

    If AState.ReadOnly Then
        Exit;

    If HasSelection(AState) Then Begin
        DeleteSelection(AState);
        Exit;
    End;

    If AState.CaretIndex >= Length(AState.Text) Then
        Exit;

    Delete(
        AState.Text,
        AState.CaretIndex + 1,
        1);

    AState.SelStart := AState.CaretIndex;
    AState.SelLength := 0;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.MoveCaretLeft(
    Var AState: TRotatedEditEditState;
    AExtendSelection: Boolean);
Begin
    NormalizeState(AState);

    If AState.CaretIndex > 0 Then
        Dec(AState.CaretIndex);

    If Not AExtendSelection Then Begin
        AState.SelStart := AState.CaretIndex;
        AState.SelLength := 0;
    End;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.MoveCaretRight(
    Var AState: TRotatedEditEditState;
    AExtendSelection: Boolean);
Begin
    NormalizeState(AState);

    If AState.CaretIndex < Length(AState.Text) Then
        Inc(AState.CaretIndex);

    If Not AExtendSelection Then Begin
        AState.SelStart := AState.CaretIndex;
        AState.SelLength := 0;
    End;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.MoveCaretHome(
    Var AState: TRotatedEditEditState;
    AExtendSelection: Boolean);
Begin
    NormalizeState(AState);

    AState.CaretIndex := 0;

    If Not AExtendSelection Then Begin
        AState.SelStart := AState.CaretIndex;
        AState.SelLength := 0;
    End;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.MoveCaretEnd(
    Var AState: TRotatedEditEditState;
    AExtendSelection: Boolean);
Begin
    NormalizeState(AState);

    AState.CaretIndex := Length(AState.Text);

    If Not AExtendSelection Then Begin
        AState.SelStart := AState.CaretIndex;
        AState.SelLength := 0;
    End;

    NormalizeState(AState);
End;

Class Procedure TRotatedEditEditEngine.SelectAll(
    Var AState: TRotatedEditEditState);
Begin
    NormalizeState(AState);

    AState.SelStart := 0;
    AState.SelLength := Length(AState.Text);
    AState.CaretIndex := Length(AState.Text);

    NormalizeState(AState);
End;

End.
