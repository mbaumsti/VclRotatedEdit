object RotatedEditDemoForm: TRotatedEditDemoForm
  Left = 0
  Top = 0
  Caption = 'TRotatedEdit demo'
  ClientHeight = 747
  ClientWidth = 1108
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 17
  object StandardLabel: TLabel
    Left = 21
    Top = 102
    Width = 86
    Height = 17
    Caption = 'Standard TEdit'
  end
  object HorizontalLabel: TLabel
    Left = 21
    Top = 181
    Width = 86
    Height = 17
    Caption = 'Horizontal edit'
  end
  object VerticalDownLabel: TLabel
    Left = 21
    Top = 529
    Width = 104
    Height = 17
    Caption = 'Vertical down edit'
  end
  object VerticalUpLabel: TLabel
    Left = 158
    Top = 529
    Width = 87
    Height = 17
    Caption = 'Vertical up edit'
  end
  object FreeAngleLabel: TLabel
    Left = 19
    Top = 312
    Width = 87
    Height = 17
    Caption = 'Free angle edit'
  end
  object TopPanel: TPanel
    Left = 0
    Top = 0
    Width = 1108
    Height = 80
    Align = alTop
    BevelOuter = bvNone
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object TitleLabel: TLabel
      Left = 20
      Top = 14
      Width = 147
      Height = 21
      Caption = 'TRotatedEdit demo'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object InfoLabel: TLabel
      Left = 20
      Top = 44
      Width = 860
      Height = 17
      Caption = 
        'Horizontal, vertical and custom-angle owner-drawn edits. Use the' +
        ' 45'#176' edit to test editing, selection, mouse, wheel, validation a' +
        'nd event notifications.'
    end
  end
  object StandardEdit: TEdit
    Left = 21
    Top = 124
    Width = 240
    Height = 25
    BiDiMode = bdLeftToRight
    Ctl3D = True
    ParentBiDiMode = False
    ParentCtl3D = False
    TabOrder = 1
    Text = 'Native TEdit reference'
  end
  object HorizontalEdit: TRotatedEdit
    Left = 19
    Top = 216
    Width = 237
    Height = 25
    Cursor = crIBeam
    ParentColor = False
    TabOrder = 2
    Text = 'Horizontal editable text'
    Orientation = reoCustomAngle
    LogicalLength = 237
    LogicalThickness = 25
    InternalOriginActive = True
    InternalOriginX = 0.000000000000000000
    InternalOriginY = 0.000000000000000000
  end
  object VerticalDownEdit: TRotatedEdit
    Left = 56
    Top = 557
    Width = 26
    Height = 150
    Cursor = crIBeam
    ParentColor = False
    TabOrder = 3
    Text = 'Vertical down'
    Orientation = reoVerticalDown
    Angle = 270.000000000000000000
    LogicalLength = 150
    LogicalThickness = 25
    InternalOriginActive = True
    InternalOriginX = 25.000000000000030000
    InternalOriginY = 0.000000000000004592
  end
  object VerticalUpEdit: TRotatedEdit
    Left = 187
    Top = 557
    Width = 26
    Height = 150
    Cursor = crIBeam
    ParentColor = False
    TabOrder = 4
    Text = 'Vertical up'
    Orientation = reoVerticalUp
    Angle = 90.000000000000000000
    LogicalLength = 150
    LogicalThickness = 25
    InternalOriginActive = True
    InternalOriginX = 0.000000000000000000
    InternalOriginY = 150.000000000000000000
  end
  object FreeAngleEdit: TRotatedEdit
    Left = 18
    Top = 422
    Width = 145
    Height = 50
    Cursor = crIBeam
    Hint = 'Zone de saisie'
    ParentColor = False
    ParentShowHint = False
    ShowHint = True
    TabOrder = 5
    Text = 'Angle 10 degrees'
    Orientation = reoCustomAngle
    Angle = 10.000000000000000000
    LogicalLength = 142
    LogicalThickness = 25
    MaxLength = 20
    Alignment = taCenter
    TextHint = 'Test de Hint'
    InternalOriginActive = True
    InternalOriginX = 0.000000000000000000
    InternalOriginY = 24.658041228704110000
  end
  object TrackBarRotation: TTrackBar
    Left = 19
    Top = 331
    Width = 237
    Height = 45
    Max = 360
    Frequency = 10
    Position = 10
    TabOrder = 6
    OnChange = TrackBarRotationChange
  end
  object GroupBoxEvents: TGroupBox
    AlignWithMargins = True
    Left = 277
    Top = 80
    Width = 823
    Height = 659
    Margins.Left = 0
    Margins.Top = 0
    Margins.Right = 8
    Margins.Bottom = 8
    Align = alRight
    Caption = 'EVENTS TESTS'
    TabOrder = 7
    object CustomAngleLabel: TLabel
      Left = 20
      Top = 40
      Width = 86
      Height = 17
      Caption = 'Event test edit '
    end
    object EventsLabel: TLabel
      Left = 160
      Top = 40
      Width = 85
      Height = 17
      Caption = 'Event counters'
    end
    object EventGrid: TStringGrid
      Left = 156
      Top = 66
      Width = 646
      Height = 559
      ColCount = 4
      DefaultRowHeight = 22
      FixedCols = 0
      RowCount = 23
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRangeSelect, goRowSelect]
      TabOrder = 0
      ColWidths = (
        130
        55
        90
        360)
    end
    object ResetEventsButton: TButton
      Left = 676
      Top = 37
      Width = 123
      Height = 25
      Caption = 'Reset counters'
      TabOrder = 1
      OnClick = ResetEventsButtonClick
    end
    object RotatedEdit1: TRotatedEdit
      Left = 18
      Top = 66
      Width = 127
      Height = 126
      Cursor = crIBeam
      ParentColor = False
      TabOrder = 2
      Text = 'Angle 45 degrees'
      Orientation = reoCustomAngle
      Angle = 45.000000000000000000
      LogicalLength = 153
      LogicalThickness = 25
      OnChange = CustomAngleEditChange
      OnSelectionChange = CustomAngleEditSelectionChange
      OnEditingStart = CustomAngleEditEditingStart
      OnCanChange = CustomAngleEditCanChange
      OnValidate = CustomAngleEditValidate
      OnEditingDone = CustomAngleEditEditingDone
      OnClick = CustomAngleEditClick
      OnContextPopup = CustomAngleEditContextPopup
      OnDblClick = CustomAngleEditDblClick
      OnEnter = CustomAngleEditEnter
      OnExit = CustomAngleEditExit
      OnKeyDown = CustomAngleEditKeyDown
      OnKeyPress = CustomAngleEditKeyPress
      OnKeyUp = CustomAngleEditKeyUp
      OnMouseDown = CustomAngleEditMouseDown
      OnMouseEnter = CustomAngleEditMouseEnter
      OnMouseLeave = CustomAngleEditMouseLeave
      OnMouseMove = CustomAngleEditMouseMove
      OnMouseUp = CustomAngleEditMouseUp
      OnMouseWheel = CustomAngleEditMouseWheel
      OnMouseWheelDown = CustomAngleEditMouseWheelDown
      OnMouseWheelUp = CustomAngleEditMouseWheelUp
      InternalOriginActive = True
      InternalOriginX = 1.134992948794533000
      InternalOriginY = 108.322330470336300000
    end
  end
end
