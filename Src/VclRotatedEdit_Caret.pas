Unit VclRotatedEdit_Caret;


{
  VclRotatedEdit_Caret.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Caret blink controller of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Contrôleur de clignotement du caret du composant VCL VclRotatedEdit.

  Cette unité gère uniquement l’état de clignotement et les notifications d’invalidation. La géométrie du caret reste calculée par le layout.
}

Interface

Uses
    System.Classes,
    Vcl.ExtCtrls;

Type
    TRotatedEditCaretController = Class(TComponent)
    private
        FTimer: TTimer;
        FCaretVisible: Boolean;
        FBlinkEnabled: Boolean;
        FOnCaretChanged: TNotifyEvent;

        Procedure TimerTick(Sender: TObject);

    public
        Constructor Create(AOwner: TComponent); Override;
        Destructor Destroy; Override;

        Procedure StartBlink;
        Procedure StopBlink;
        Procedure ResetBlink;
        Procedure ToggleCaretVisible;

        Property CaretVisible: Boolean Read FCaretVisible;
        Property BlinkEnabled: Boolean Read FBlinkEnabled;
        Property OnCaretChanged: TNotifyEvent Read FOnCaretChanged Write FOnCaretChanged;
    End;

Implementation

Constructor TRotatedEditCaretController.Create(AOwner: TComponent);
Begin
    Inherited Create(AOwner);

    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 530;
    FTimer.OnTimer := TimerTick;

    FCaretVisible := False;
    FBlinkEnabled := False;
End;

Destructor TRotatedEditCaretController.Destroy;
Begin
    FTimer.Free;

    Inherited Destroy;
End;

Procedure TRotatedEditCaretController.TimerTick(Sender: TObject);
Begin
    ToggleCaretVisible;
End;

Procedure TRotatedEditCaretController.StartBlink;
Begin
    FBlinkEnabled := True;
    FCaretVisible := True;
    FTimer.Enabled := True;

    If Assigned(FOnCaretChanged) Then
        FOnCaretChanged(Self);
End;

Procedure TRotatedEditCaretController.StopBlink;
Begin
    FTimer.Enabled := False;
    FBlinkEnabled := False;
    FCaretVisible := False;

    If Assigned(FOnCaretChanged) Then
        FOnCaretChanged(Self);
End;

Procedure TRotatedEditCaretController.ResetBlink;
Begin
    If Not FBlinkEnabled Then
        Exit;

    FTimer.Enabled := False;
    FCaretVisible := True;
    FTimer.Enabled := True;

    If Assigned(FOnCaretChanged) Then
        FOnCaretChanged(Self);
End;

Procedure TRotatedEditCaretController.ToggleCaretVisible;
Begin
    If Not FBlinkEnabled Then
        Exit;

    FCaretVisible := Not FCaretVisible;

    If Assigned(FOnCaretChanged) Then
        FOnCaretChanged(Self);
End;

End.
