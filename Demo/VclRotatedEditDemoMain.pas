{
  VclRotatedEditDemoMain.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Main demonstration form for the TRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Fiche principale de démonstration du composant TRotatedEdit.

  Cette unité montre les orientations principales du contrôle, le changement
  d'angle, l'édition réelle du texte, la sélection, la validation et la liste des
  événements publics exposés par le composant.

  La grille d'événements sert volontairement de documentation interactive : elle
  affiche les événements disponibles et incrémente un compteur chaque fois qu'un
  événement est déclenché. Les événements bruyants, comme OnMouseMove, restent
  connectés afin de permettre une vérification immédiate du comportement VCL,
  mais le rafraîchissement visuel de la grille est coalescé pour éviter que
  la démonstration elle-même ne repeigne toute la fiche à chaque frappe, à
  chaque déplacement souris ou à chaque notification répétitive.
}

Unit VclRotatedEditDemoMain;


Interface

Uses
    Winapi.Windows,
    Winapi.Messages,
    System.SysUtils,
    System.Classes,
    Vcl.Graphics,
    Vcl.Controls,
    Vcl.Forms,
    Vcl.StdCtrls,
    Vcl.ExtCtrls,
    Vcl.Grids,
    VclRotatedEdit,
    VclRotatedEdit_Types,
    VclRotatedEdit_Core,
    Vcl.ComCtrls;

Const
    //--------------------------------------------------------------------------
    //Private demo-form message used to coalesce visual event-grid refreshes.
    //
    //A timer would solve delayed repainting, but it would also create the exact
    //kind of heartbeat/battement that the demo must avoid. Posting a private
    //message keeps updates event-driven: if nothing happens, nothing repaints.
    //--------------------------------------------------------------------------
    CWM_REFRESH_EVENT_GRID = WM_APP + 137;

Type
    TRotatedEditDemoForm = Class(TForm)
        TopPanel: TPanel;
        TitleLabel: TLabel;
        InfoLabel: TLabel;
        StandardEdit: TEdit;
        StandardLabel: TLabel;
        HorizontalEdit: TRotatedEdit;
        HorizontalLabel: TLabel;
        VerticalDownEdit: TRotatedEdit;
        VerticalDownLabel: TLabel;
        VerticalUpEdit: TRotatedEdit;
        VerticalUpLabel: TLabel;
        FreeAngleEdit: TRotatedEdit;
        FreeAngleLabel: TLabel;
        TrackBarRotation: TTrackBar;
        GroupBoxEvents: TGroupBox;
        CustomAngleLabel: TLabel;
        EventGrid: TStringGrid;
        EventsLabel: TLabel;
        ResetEventsButton: TButton;
    RotatedEdit1: TRotatedEdit;
        Procedure CustomAngleEditCanChange(
            Sender: TObject;
            Const AOldText, ANewText: String;
            Var ACanChange: Boolean);
        Procedure CustomAngleEditChange(Sender: TObject);
        Procedure CustomAngleEditClick(Sender: TObject);
        Procedure CustomAngleEditContextPopup(
            Sender: TObject;
            MousePos: TPoint;
            Var Handled: Boolean);
        Procedure CustomAngleEditDblClick(Sender: TObject);
        Procedure CustomAngleEditEditingDone(
            Sender: TObject;
            AReason: TRotatedEditEditingDoneReason);
        Procedure CustomAngleEditEditingStart(Sender: TObject);
        Procedure CustomAngleEditEnter(Sender: TObject);
        Procedure CustomAngleEditExit(Sender: TObject);
        Procedure CustomAngleEditKeyDown(
            Sender: TObject;
            Var Key: Word;
            Shift: TShiftState);
        Procedure CustomAngleEditKeyPress(
            Sender: TObject;
            Var Key: Char);
        Procedure CustomAngleEditKeyUp(
            Sender: TObject;
            Var Key: Word;
            Shift: TShiftState);
        Procedure CustomAngleEditMouseDown(
            Sender: TObject;
            Button: TMouseButton;
            Shift: TShiftState;
            X, Y: Integer);
        Procedure CustomAngleEditMouseEnter(Sender: TObject);
        Procedure CustomAngleEditMouseLeave(Sender: TObject);
        Procedure CustomAngleEditMouseMove(
            Sender: TObject;
            Shift: TShiftState;
            X, Y: Integer);
        Procedure CustomAngleEditMouseUp(
            Sender: TObject;
            Button: TMouseButton;
            Shift: TShiftState;
            X, Y: Integer);
        Procedure CustomAngleEditMouseWheel(
            Sender: TObject;
            Shift: TShiftState;
            WheelDelta: Integer;
            MousePos: TPoint;
            Var Handled: Boolean);
        Procedure CustomAngleEditMouseWheelDown(
            Sender: TObject;
            Shift: TShiftState;
            MousePos: TPoint;
            Var Handled: Boolean);
        Procedure CustomAngleEditMouseWheelUp(
            Sender: TObject;
            Shift: TShiftState;
            MousePos: TPoint;
            Var Handled: Boolean);
        Procedure CustomAngleEditSelectionChange(Sender: TObject);
        Procedure CustomAngleEditValidate(
            Sender: TObject;
            Const AText: String;
            Var AResult: TRotatedEditValidationResult);
        Procedure FormCreate(Sender: TObject);
        Procedure ResetEventsButtonClick(Sender: TObject);
        Procedure TrackBarRotationChange(Sender: TObject);
    private
        //---------------------------------------------------------------------
        //Interactive event counter used by the demo form.
        //
        //The demo deliberately keeps every event connected, including noisy
        //events such as OnMouseMove and key events. This turns the grid into a
        //small visual test bench: the first column documents the public events
        //available on TRotatedEdit, and the counter column proves immediately
        //that each handler is reachable.
        //---------------------------------------------------------------------
        FEventCounts: TArray<Integer>;
        FEventLastTimes: TArray<String>;
        FEventLastDetails: TArray<String>;
        FEventGridRefreshPending: Boolean;
        FEventGridRefreshScheduled: Boolean;
        FEventGridDirty: Boolean;
        FLastEventGridRefreshTick: Cardinal;
        FLastSelectionSender: TObject;
        FLastSelectionCaretIndex: Integer;
        FLastSelectionStart: Integer;
        FLastSelectionLength: Integer;
        FLastSelectionValid: Boolean;

        Procedure InitializeEventGrid;
        Procedure ResetEventCounters;
        Function FindEventIndex(Const AEventName: String): Integer;
        Function FindEventRow(Const AEventName: String): Integer;
        Function IsThrottledEvent(Const AEventName: String): Boolean;
        Procedure ScheduleEventGridRefresh;
        Procedure RefreshEventGrid(AForceRedraw: Boolean);
        Procedure RefreshEventGridRow(AEventIndex: Integer);
        Procedure TrackEvent(
            Const AEventName: String;
            Const ADetails: String = '');
        Function SenderName(Sender: TObject): String;
        Function MouseButtonToText(AButton: TMouseButton): String;
        Function ShiftStateToText(AShift: TShiftState): String;
        Function EditingDoneReasonToText(AReason: TRotatedEditEditingDoneReason): String;
        Procedure WMRefreshEventGrid(Var Message: TMessage); message CWM_REFRESH_EVENT_GRID;
    End;

Var
    RotatedEditDemoForm: TRotatedEditDemoForm;

Implementation

{$R *.dfm}

Const
    CEventNames: Array[0..21] Of String = ('OnCanChange', 'OnChange', 'OnClick', 'OnContextPopup', 'OnDblClick', 'OnEditingDone', 'OnEditingStart', 'OnEnter', 'OnExit',
        'OnKeyDown', 'OnKeyPress', 'OnKeyUp', 'OnMouseDown', 'OnMouseEnter', 'OnMouseLeave', 'OnMouseMove', 'OnMouseUp', 'OnMouseWheel', 'OnMouseWheelDown', 'OnMouseWheelUp',
        'OnSelectionChange', 'OnValidate');

    //--------------------------------------------------------------------------
    //The demo intentionally keeps noisy events connected. Without throttling,
    //OnMouseMove can update the TStringGrid hundreds of times per second, which
    //makes the form flicker and hides the actual component behavior being
    //demonstrated. The counters are still updated for every event; only the
    //visual grid refresh is limited.
    //--------------------------------------------------------------------------
    CEventGridRefreshIntervalMs = 250;

Procedure TRotatedEditDemoForm.CustomAngleEditCanChange(
    Sender: TObject;
    Const AOldText, ANewText: String;
    Var ACanChange: Boolean);
Begin
    //-------------------------------------------------------------------------
    //This demo accepts every modification.
    //
    //The purpose of OnCanChange here is not to reject text, but to show when
    //the component asks the application whether a pending text change may be
    //accepted. A real application could set ACanChange to False here.
    //-------------------------------------------------------------------------
    ACanChange := True;

    TrackEvent(
        'OnCanChange',
        Format('%s Old="%s" New="%s" Accepted=%s', [SenderName(Sender), AOldText, ANewText, BoolToStr(ACanChange, True)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditChange(Sender: TObject);
Begin
    TrackEvent(
        'OnChange',
        SenderName(Sender) + ' Text="' + TRotatedEdit(Sender).Text + '"');
End;

Procedure TRotatedEditDemoForm.CustomAngleEditClick(Sender: TObject);
Begin
    TrackEvent(
        'OnClick',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditContextPopup(
    Sender: TObject;
    MousePos: TPoint;
    Var Handled: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Do not mark the message as handled. This lets the normal VCL popup flow
    //continue if the user later assigns a PopupMenu to the control.
    //-------------------------------------------------------------------------
    Handled := False;

    TrackEvent(
        'OnContextPopup',
        Format('%s X=%d Y=%d Handled=%s', [SenderName(Sender), MousePos.X, MousePos.Y, BoolToStr(Handled, True)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditDblClick(Sender: TObject);
Begin
    TrackEvent(
        'OnDblClick',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditEditingDone(
    Sender: TObject;
    AReason: TRotatedEditEditingDoneReason);
Begin
    TrackEvent(
        'OnEditingDone',
        SenderName(Sender) + ' Reason=' + EditingDoneReasonToText(AReason));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditEditingStart(Sender: TObject);
Begin
    TrackEvent(
        'OnEditingStart',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditEnter(Sender: TObject);
Begin
    TrackEvent(
        'OnEnter',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditExit(Sender: TObject);
Begin
    TrackEvent(
        'OnExit',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditKeyDown(
    Sender: TObject;
    Var Key: Word;
    Shift: TShiftState);
Begin
    TrackEvent(
        'OnKeyDown',
        Format('%s Key=%d Shift=%s', [SenderName(Sender), Key, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditKeyPress(
    Sender: TObject;
    Var Key: Char);
Begin
    TrackEvent(
        'OnKeyPress',
        Format('%s Key="%s" Ord=%d', [SenderName(Sender), Key, Ord(Key)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditKeyUp(
    Sender: TObject;
    Var Key: Word;
    Shift: TShiftState);
Begin
    TrackEvent(
        'OnKeyUp',
        Format('%s Key=%d Shift=%s', [SenderName(Sender), Key, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseDown(
    Sender: TObject;
    Button: TMouseButton;
    Shift: TShiftState;
    X, Y: Integer);
Begin
    TrackEvent(
        'OnMouseDown',
        Format('%s Button=%s X=%d Y=%d Shift=%s', [SenderName(Sender), MouseButtonToText(Button), X, Y, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseEnter(Sender: TObject);
Begin
    TrackEvent(
        'OnMouseEnter',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseLeave(Sender: TObject);
Begin
    TrackEvent(
        'OnMouseLeave',
        SenderName(Sender));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseMove(
    Sender: TObject;
    Shift: TShiftState;
    X, Y: Integer);
Begin
    TrackEvent(
        'OnMouseMove',
        Format('%s X=%d Y=%d Shift=%s', [SenderName(Sender), X, Y, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseUp(
    Sender: TObject;
    Button: TMouseButton;
    Shift: TShiftState;
    X, Y: Integer);
Begin
    TrackEvent(
        'OnMouseUp',
        Format('%s Button=%s X=%d Y=%d Shift=%s', [SenderName(Sender), MouseButtonToText(Button), X, Y, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseWheel(
    Sender: TObject;
    Shift: TShiftState;
    WheelDelta: Integer;
    MousePos: TPoint;
    Var Handled: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Keep Handled = False so the demo observes the event without changing the
    //normal message propagation expected by the hosting form.
    //-------------------------------------------------------------------------
    Handled := False;

    TrackEvent(
        'OnMouseWheel',
        Format('%s Delta=%d X=%d Y=%d Shift=%s', [SenderName(Sender), WheelDelta, MousePos.X, MousePos.Y, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseWheelDown(
    Sender: TObject;
    Shift: TShiftState;
    MousePos: TPoint;
    Var Handled: Boolean);
Begin
    Handled := False;

    TrackEvent(
        'OnMouseWheelDown',
        Format('%s X=%d Y=%d Shift=%s', [SenderName(Sender), MousePos.X, MousePos.Y, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditMouseWheelUp(
    Sender: TObject;
    Shift: TShiftState;
    MousePos: TPoint;
    Var Handled: Boolean);
Begin
    Handled := False;

    TrackEvent(
        'OnMouseWheelUp',
        Format('%s X=%d Y=%d Shift=%s', [SenderName(Sender), MousePos.X, MousePos.Y, ShiftStateToText(Shift)]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditSelectionChange(Sender: TObject);
Var
    LEdit: TRotatedEdit;
Begin
    LEdit := TRotatedEdit(Sender);

    //-------------------------------------------------------------------------
    //Some visual operations may notify selection state more often than a human
    //observer expects. The demo only records a selection event when the logical
    //selection/caret state really changed. This keeps a possible caret-blink or
    //paint-side notification from producing a permanent visual heartbeat in the
    //event grid.
    //-------------------------------------------------------------------------
    If FLastSelectionValid And
       (FLastSelectionSender = Sender) And
       (FLastSelectionCaretIndex = LEdit.CaretIndex) And
       (FLastSelectionStart = LEdit.SelStart) And
       (FLastSelectionLength = LEdit.SelLength) Then
        Exit;

    FLastSelectionSender := Sender;
    FLastSelectionCaretIndex := LEdit.CaretIndex;
    FLastSelectionStart := LEdit.SelStart;
    FLastSelectionLength := LEdit.SelLength;
    FLastSelectionValid := True;

    TrackEvent(
        'OnSelectionChange',
        Format('%s Caret=%d SelStart=%d SelLength=%d', [SenderName(Sender), LEdit.CaretIndex, LEdit.SelStart, LEdit.SelLength]));
End;

Procedure TRotatedEditDemoForm.CustomAngleEditValidate(
    Sender: TObject;
    Const AText: String;
    Var AResult: TRotatedEditValidationResult);
Begin
    //-------------------------------------------------------------------------
    //The demo does not reject validation. It only exposes the event and records
    //the text that was validated.
    //-------------------------------------------------------------------------
    AResult := revAccept;

    TrackEvent(
        'OnValidate',
        SenderName(Sender) + ' Text="' + AText + '" Accepted=True');
End;

Function TRotatedEditDemoForm.EditingDoneReasonToText(AReason: TRotatedEditEditingDoneReason): String;
Begin

    Case AReason Of
        redrFocusLost:
            Result := 'FocusLost';

        redrEnter:
            Result := 'EnterKey';

        redrEscape:
            Result := 'EscapeKey';
    Else
        Result := 'Unknown';
    End;
End;

Function TRotatedEditDemoForm.FindEventIndex(Const AEventName: String): Integer;
Var
    LIndex: Integer;
Begin
    Result := -1;

    For LIndex := Low(CEventNames) To High(CEventNames) Do Begin
        If SameText(CEventNames[LIndex], AEventName) Then Begin
            Result := LIndex;
            Exit;
        End;
    End;
End;

Function TRotatedEditDemoForm.FindEventRow(Const AEventName: String): Integer;
Var
    LIndex: Integer;
Begin
    LIndex := FindEventIndex(AEventName);

    If LIndex < 0 Then
        Result := -1
    Else
        Result := LIndex + 1;
End;

Function TRotatedEditDemoForm.IsThrottledEvent(Const AEventName: String): Boolean;
Begin
    //-------------------------------------------------------------------------
    //The event monitor must not become the source of the flicker it is supposed
    //to help diagnose. MouseMove is the obvious noisy event, but keyboard input
    //also raises several events for a single character: OnKeyDown, OnKeyPress,
    //OnCanChange, OnChange, OnSelectionChange, OnValidate and OnKeyUp.
    //
    //The counters and details are still updated synchronously in memory. Only
    //the visual TStringGrid repaint is coalesced. This avoids the visible "top"
    //on every keystroke while preserving the diagnostic value of the demo.
    //-------------------------------------------------------------------------
    Result :=
        SameText(AEventName, 'OnMouseMove') Or
        SameText(AEventName, 'OnKeyDown') Or
        SameText(AEventName, 'OnKeyPress') Or
        SameText(AEventName, 'OnKeyUp') Or
        SameText(AEventName, 'OnCanChange') Or
        SameText(AEventName, 'OnChange') Or
        SameText(AEventName, 'OnSelectionChange') Or
        SameText(AEventName, 'OnValidate');
End;

Procedure TRotatedEditDemoForm.RefreshEventGrid(AForceRedraw: Boolean);
Var
    LIndex: Integer;
Begin
    If EventGrid.HandleAllocated And AForceRedraw Then
        SendMessage(EventGrid.Handle, WM_SETREDRAW, 0, 0);

    Try
        For LIndex := Low(CEventNames) To High(CEventNames) Do
            RefreshEventGridRow(LIndex);
    Finally
        If EventGrid.HandleAllocated And AForceRedraw Then Begin
            SendMessage(EventGrid.Handle, WM_SETREDRAW, 1, 0);
            EventGrid.Invalidate;
        End;
    End;

    FEventGridRefreshPending := False;
    FEventGridDirty := False;
    FLastEventGridRefreshTick := GetTickCount;
End;

Procedure TRotatedEditDemoForm.RefreshEventGridRow(AEventIndex: Integer);
Var
    LRow: Integer;
Begin
    If (AEventIndex < Low(CEventNames)) Or (AEventIndex > High(CEventNames)) Then
        Exit;

    LRow := AEventIndex + 1;

    EventGrid.Cells[0, LRow] := CEventNames[AEventIndex];
    EventGrid.Cells[1, LRow] := IntToStr(FEventCounts[AEventIndex]);
    EventGrid.Cells[2, LRow] := FEventLastTimes[AEventIndex];
    EventGrid.Cells[3, LRow] := FEventLastDetails[AEventIndex];

    FLastEventGridRefreshTick := GetTickCount;
End;

Procedure TRotatedEditDemoForm.FormCreate(Sender: TObject);
Begin
    Caption := 'TRotatedEdit demo';

    //--------------------------------------------------------------------------
    //Keep the DFM readable and close to the published API. The form creation
    //code only initializes dynamic/demo-only parts such as the event grid.
    //--------------------------------------------------------------------------
    InitializeEventGrid;
End;

Procedure TRotatedEditDemoForm.InitializeEventGrid;
Begin
    SetLength(FEventCounts, Length(CEventNames));
    SetLength(FEventLastTimes, Length(CEventNames));
    SetLength(FEventLastDetails, Length(CEventNames));

    FEventGridRefreshPending := False;
    FEventGridRefreshScheduled := False;
    FEventGridDirty := False;
    FLastEventGridRefreshTick := 0;
    FLastSelectionSender := Nil;
    FLastSelectionCaretIndex := -1;
    FLastSelectionStart := -1;
    FLastSelectionLength := -1;
    FLastSelectionValid := False;

    //--------------------------------------------------------------------------
    //The event grid is a diagnostic surface, not the component being tested.
    //Double buffering and batched initialization prevent the event monitor from
    //becoming visually noisier than TRotatedEdit itself.
    //--------------------------------------------------------------------------
    EventGrid.ParentDoubleBuffered := False;
    EventGrid.DoubleBuffered := True;

    EventGrid.ColCount := 4;
    EventGrid.FixedCols := 0;
    EventGrid.FixedRows := 1;
    EventGrid.RowCount := Length(CEventNames) + 1;

    EventGrid.Cells[0, 0] := 'Event';
    EventGrid.Cells[1, 0] := 'Count';
    EventGrid.Cells[2, 0] := 'Last time';
    EventGrid.Cells[3, 0] := 'Last details';

    EventGrid.ColWidths[0] := 130;
    EventGrid.ColWidths[1] := 55;
    EventGrid.ColWidths[2] := 90;
    EventGrid.ColWidths[3] := 280;

    ResetEventCounters;
End;

Function TRotatedEditDemoForm.MouseButtonToText(AButton: TMouseButton): String;
Begin
    Case AButton Of
        mbLeft:
            Result := 'Left';

        mbRight:
            Result := 'Right';

        mbMiddle:
            Result := 'Middle';
    Else
        Result := 'Other';
    End;
End;

Procedure TRotatedEditDemoForm.ResetEventCounters;
Var
    LIndex: Integer;
Begin
    For LIndex := Low(CEventNames) To High(CEventNames) Do Begin
        FEventCounts[LIndex] := 0;
        FEventLastTimes[LIndex] := '';
        FEventLastDetails[LIndex] := '';
    End;

    RefreshEventGrid(True);
End;

Procedure TRotatedEditDemoForm.ResetEventsButtonClick(Sender: TObject);
Begin
    ResetEventCounters;
End;

Function TRotatedEditDemoForm.SenderName(Sender: TObject): String;
Begin
    Result := '';

    If Sender Is TComponent Then
        Result := TComponent(Sender).Name;

    If Result = '' Then
        Result := Sender.ClassName;
End;

Function TRotatedEditDemoForm.ShiftStateToText(AShift: TShiftState): String;
Begin
    Result := '';

    If ssShift In AShift Then
        Result := Result + 'Shift+';

    If ssAlt In AShift Then
        Result := Result + 'Alt+';

    If ssCtrl In AShift Then
        Result := Result + 'Ctrl+';

    If ssLeft In AShift Then
        Result := Result + 'Left+';

    If ssRight In AShift Then
        Result := Result + 'Right+';

    If ssMiddle In AShift Then
        Result := Result + 'Middle+';

    If Result = '' Then
        Result := 'None'
    Else
        Delete(
            Result,
            Length(Result),
            1);
End;

Procedure TRotatedEditDemoForm.ScheduleEventGridRefresh;
Begin
    //-------------------------------------------------------------------------
    //Mark the grid as dirty and post at most one refresh message. The message is
    //handled later by the form message pump, which coalesces bursts of events
    //without introducing a timer. No input event means no posted message and
    //therefore no periodic repaint.
    //-------------------------------------------------------------------------
    FEventGridDirty := True;
    FEventGridRefreshPending := True;

    If FEventGridRefreshScheduled Then
        Exit;

    FEventGridRefreshScheduled := True;

    If HandleAllocated Then
        PostMessage(Handle, CWM_REFRESH_EVENT_GRID, 0, 0);
End;

Procedure TRotatedEditDemoForm.TrackBarRotationChange(Sender: TObject);
Begin
    FreeAngleEdit.Angle := TrackBarRotation.Position;
    FreeAngleEdit.Text := 'Angle ' + IntToStr(TrackBarRotation.Position) + ' degrees';
End;

Procedure TRotatedEditDemoForm.TrackEvent(
    Const AEventName: String;
    Const ADetails: String);
Var
    LIndex: Integer;
Begin
    LIndex := FindEventIndex(AEventName);

    If LIndex < 0 Then
        Exit;

    Inc(FEventCounts[LIndex]);
    FEventLastTimes[LIndex] := FormatDateTime(
        'hh:nn:ss.zzz',
        Now);
    FEventLastDetails[LIndex] := ADetails;

    If IsThrottledEvent(AEventName) Then Begin
        ScheduleEventGridRefresh;
        Exit;
    End;

    If FEventGridRefreshPending Or FEventGridDirty Then
        RefreshEventGrid(True)
    Else
        RefreshEventGridRow(LIndex);
End;

Procedure TRotatedEditDemoForm.WMRefreshEventGrid(Var Message: TMessage);
Var
    LNowTick: Cardinal;
Begin
    FEventGridRefreshScheduled := False;

    If Not FEventGridDirty Then
        Exit;

    LNowTick := GetTickCount;

    //-------------------------------------------------------------------------
    //Do not repaint merely because the posted message arrived. If the last
    //visual update is too recent, keep the in-memory counters dirty and let the
    //next real event schedule another pass. This is intentionally not a timer:
    //there is no periodic repaint while the mouse and keyboard are idle.
    //-------------------------------------------------------------------------
    If (FLastEventGridRefreshTick <> 0) And
       ((LNowTick - FLastEventGridRefreshTick) < CEventGridRefreshIntervalMs) Then
        Exit;

    RefreshEventGrid(True);
End;

End.


