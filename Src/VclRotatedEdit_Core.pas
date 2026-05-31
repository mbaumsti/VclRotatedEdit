Unit VclRotatedEdit_Core;


{
  VclRotatedEdit_Core.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Core control class of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Classe cœur du contrôle VCL VclRotatedEdit.

  Cette unité possède l’état public du contrôle, les propriétés publiées, les notifications d’édition, la gestion souris/clavier, la synchronisation des dimensions logiques avec les bounds VCL et les protections design-time.
}

Interface

{$IF CompilerVersion >= 34.0}
  {$DEFINE VCLROTATEDEDIT_HAS_CONTROL_STYLE_NAME}
{$IFEND}

Uses
    Winapi.Windows,
    Winapi.Messages,
    System.Classes,
    System.SysUtils,
    System.Math,
    System.UITypes,
    Vcl.Controls,
    Vcl.Graphics,
    Vcl.Forms,
    Vcl.StdCtrls,
    VclRotatedEdit_Types,
    VclRotatedEdit_Caret,
    VclRotatedEdit_Style,
    VclRotatedEdit_RenderBackend;

Type
    {
      Palette mode used by TRotatedEdit.

      repmStyle:
        The component follows the active VCL style for the editable surface when
        StyleServices is available.

      repmCustom:
        The component uses explicit user colors:
        Color for the background, Font.Color for the text and BorderColor for
        the frame.

      This deliberately replaces PaletteMode / PaletteMode combinations. The
      public model is simple: either the palette comes from the style, or it
      comes from the component properties.
    }
    TRotatedEditPaletteMode = (
        repmStyle,
        repmCustom
    );

    {
      Internal design-time resize grip inferred from SetBounds.

      Delphi's designer does not pass "the user dragged this handle" to the
      control. It changes Left / Top / Width / Height. The component can however
      infer the likely handle by comparing the previous physical bounds with the
      new requested bounds.

      IMPORTANT DESIGN-TIME RULE
      --------------------------
      These values describe the PHYSICAL designer handle, not the logical edit
      dimension directly. The mapping from handle to LogicalLength or
      LogicalThickness is intentionally centralized in
      DesignerResizeGripTargetsLength.

      Do not decide in SetBounds that "Width means length" and "Height means
      thickness". That is wrong as soon as the edit surface is rotated. At 45
      degrees, for example, a physical top-right corner drag is supposed to
      edit only LogicalLength, even if Delphi later sends intermediate bounds
      that look like a top-side or right-side resize.
    }
    TRotatedEditDesignerResizeGrip = (
        rerzNone,
        rerzLeft,
        rerzTop,
        rerzRight,
        rerzBottom,
        rerzTopLeft,
        rerzTopRight,
        rerzBottomLeft,
        rerzBottomRight
    );

    {
      Base implementation class for TRotatedEdit.

      The class is public because the final TRotatedEdit wrapper derives from
      it, but applications should normally use TRotatedEdit from
      VclRotatedEdit.pas. This class owns the editing state, the public
      properties, the design-time resize policy and the bridge to layout,
      rendering, style and clipboard helpers.
    }
    TRotatedEditCore = Class(TCustomControl)
    private
        FText:        String;
        FOrientation: TRotatedEditOrientation;
        FAngle:       Double;

        //-----------------------------------------------------------------
        //Logical edit surface dimensions.
        //
        //Do not confuse these values with the inherited VCL Width / Height.
        //Width / Height describe the physical rectangular window of the
        //control. LogicalLength / LogicalThickness describe the canonical
        //editable surface before rotation.
        //-----------------------------------------------------------------
        FLogicalLength:    Integer;
        FLogicalThickness: Integer;

        //-----------------------------------------------------------------
        //Native-like automatic logical thickness.
        //
        //This AutoSize is deliberately about the edit surface thickness, not
        //about the rotated rectangular host bounds. AutoSizeBounds already owns
        //the latter concern. When AutoSize is enabled, font/style/border changes
        //can update LogicalThickness to the preferred single-line edit height.
        //When AutoSize is disabled, users may reduce LogicalThickness manually;
        //the layout still receives the preferred height as a reference so the
        //normal top margin is preserved and the lower part clips like TEdit.
        //-----------------------------------------------------------------
        FAutoSize: Boolean;
        FPreferredLogicalThickness: Integer;
        FPreferredLogicalThicknessValid: Boolean;

        //-----------------------------------------------------------------
        //Automatic physical bounding box management.
        //
        //LogicalLength / LogicalThickness describe the editable surface.
        //Width / Height are only the physical VCL bounding box needed to
        //contain that projected surface.
        //
        //When AutoSizeBounds is enabled, external resize attempts are not used
        //as edit-surface dimensions. The control keeps the requested Left / Top
        //but recomputes Width / Height from LogicalLength / LogicalThickness
        //and Angle.
        //
        //This is a core rule of the component:
        //application code changes the logical edit surface;
        //the component derives its physical window rectangle.
        //-----------------------------------------------------------------
        FAutoSizeBounds: Boolean;
        FUpdatingBounds: Boolean;
        FApplyingLogicalBounds: Boolean;

        //-----------------------------------------------------------------
        //Stable center used during consecutive angle/orientation changes.
        //
        //Changing Angle from a trackbar or from the Object Inspector can send
        //many consecutive angle values. If each step reuses the current integer
        //BoundsRect center as the new reference, odd Width/Height values can
        //introduce half-pixel truncation. Repeated rotations then produce a
        //small visible drift.
        //
        //These fields keep the original floating-point center for the whole
        //programmatic rotation sequence. They are reset whenever an operation
        //other than this center-preserving rotation changes the external bounds
        //or the logical size.
        //-----------------------------------------------------------------
        FRotationCenterValid: Boolean;
        FRotationCenterX: Double;
        FRotationCenterY: Double;

        //-----------------------------------------------------------------
        //Design-time resize session.
        //
        //The VCL designer sends repeated SetBounds calls while the user drags a
        //handle. It does not give the control a clean "resize started with this
        //handle" notification. Therefore the component must infer and then
        //LOCK the logical resize session itself.
        //
        //This is not an optimization. It is required for correctness.
        //
        //Example that previously caused a regression:
        //- edit angle = 45 degrees;
        //- the user drags the physical top-right designer handle;
        //- the first SetBounds call correctly looks like rerzTopRight;
        //- later SetBounds calls during the same drag can look like rerzTop only
        //  or rerzRight only because Delphi updates the temporary BoundsRect in
        //  several steps.
        //
        //If the component reinterprets each intermediate call as a new resize
        //gesture, the target can switch from LogicalLength to LogicalThickness.
        //That breaks the golden rule:
        //
        //  one designer drag changes either LogicalLength or LogicalThickness,
        //  never both.
        //
        //These fields lock:
        //- the first meaningful physical grip;
        //- whether that grip targets LogicalLength or LogicalThickness;
        //- the logical base size used for all deltas in the current session;
        //- the opposite anchor, so the edit surface grows/shrinks naturally
        //  inside the external Delphi BoundsRect.
        //-----------------------------------------------------------------
        FDesignerResizeGrip: TRotatedEditDesignerResizeGrip;
        FDesignerResizeTargetsLength: Boolean;
        FDesignerResizeBaseBounds: TRect;
        FDesignerResizeBaseLength: Integer;
        FDesignerResizeBaseThickness: Integer;
        FDesignerResizeAnchorScreenX: Double;
        FDesignerResizeAnchorScreenY: Double;
        FDesignerResizeLastTick: Cardinal;

        //-----------------------------------------------------------------
        //Last fully accepted design-time resize geometry.
        //
        //This snapshot is deliberately stronger than the current BoundsRect
        //alone. When Delphi sends an impossible or inverted resize rectangle,
        //the component must restore not only the visible host bounds, but also
        //the logical size and the internal origin that were valid before the
        //bad request. Otherwise the IDE selection rectangle can continue to
        //drift while the internal edit surface is already being rejected.
        //-----------------------------------------------------------------
        FDesignerResizeLastValidBounds: TRect;
        FDesignerResizeLastValidLength: Integer;
        FDesignerResizeLastValidThickness: Integer;
        FDesignerResizeLastValidOriginX: Double;
        FDesignerResizeLastValidOriginY: Double;
        FDesignerResizeHasLastValidGeometry: Boolean;

        FDesignerResizeApplyingBounds: Boolean;

        //-----------------------------------------------------------------
        //Design-time visual markers.
        //
        //Delphi's native multi-selection handles can be clipped by the shaped
        //window region. Instead of trying to read the IDE selection state, the
        //component exposes a simple explicit design-time marker switch.
        //-----------------------------------------------------------------
        FShowDesignMarkers: Boolean;

        //-----------------------------------------------------------------
        //Design-time selection state.
        //
        //Updated only by the optional design-time registration unit. Runtime
        //applications never depend on DesignIntf / ToolsAPI.
        //-----------------------------------------------------------------
        FDesignSelectionSelected: Boolean;
        FDesignSelectionMultiple: Boolean;

        //-----------------------------------------------------------------
        //Internal edit placement.
        //
        //The external VCL BoundsRect belongs to Delphi and the form designer.
        //The rotated edit surface is placed inside ClientRect through an
        //internal actual origin. This avoids fighting the designer by repeatedly
        //correcting Left / Top / Width / Height during mouse resize.
        //
        //Only a real custom internal origin is persisted through DefineProperties.
        //The default centered layout is deterministic and must remain unstreamed;
        //otherwise a plain designer text/form round-trip could convert the
        //default layout into a custom placement and move rotated controls.
        //-----------------------------------------------------------------
        FUseInternalOrigin: Boolean;
        FInternalOriginX: Double;
        FInternalOriginY: Double;

        FReadOnly:  Boolean;
        FMaxLength: Integer;
        FAlignment: TAlignment;
        FCharCase: TEditCharCase;
        FTextHint: String;
        FNumbersOnly: Boolean;

        FCaretIndex:   Integer;
        FSelStart:     Integer;
        FSelLength:    Integer;
        FScrollOffset: Integer;

        FBorderStyle:         TBorderStyle;
        FBorderColor:         TColor;
        FPaletteMode:          TRotatedEditPaletteMode;
        FPaddingLeft:         Integer;
        FPaddingRight:        Integer;
        FCaretThickness:      Integer;
        FSelectionAnchor:     Integer;
        FMouseSelecting:      Boolean;
        FLastClickTick:       Cardinal;
        FLastClickPos:        TPoint;
        FClickCount:          Integer;

        FCaretController: TRotatedEditCaretController;

        //-----------------------------------------------------------------
        //Caret blink invalidation cache.
        //
        //The caret is not part of FContentBitmap: it blinks independently over
        //the cached non-caret content. Older versions invalidated the whole
        //control on every blink. On freely rotated controls this forced the
        //transparent parent background to be restored at the caret timer rate,
        //which could look like a periodic flicker in the demo when the edit had
        //focus.
        //
        //These fields remember the last small screen-space rectangle occupied
        //by the caret so the next blink can invalidate only the union of the old
        //and current caret area. Full invalidations are still used for text,
        //layout, color, style and backend changes.
        //-----------------------------------------------------------------
        FLastCaretInvalidateRect: TRect;
        FLastCaretInvalidateRectValid: Boolean;

        //-----------------------------------------------------------------
        //Rendering backend selection.
        //
        //FRenderBackendKind stores the requested backend exposed by the
        //component. FRenderBackend stores the effective backend instance
        //created by the backend factory. rebDirect2D is the default renderer
        //and draws through the native Direct2D/DirectWrite backend when those
        //resources are available. rebGDI remains available as the historical
        //compatibility renderer and as the fallback path used by the Direct2D
        //backend when native rendering cannot be initialized or completed.
        //-----------------------------------------------------------------
        FRenderBackendKind: TRotatedEditRenderBackendKind;
        FRenderBackend: IRotatedEditRenderBackend;

        //-----------------------------------------------------------------
        //Cached canonical background.
        //
        //This bitmap contains only the style/background/border of the edit
        //surface in canonical horizontal coordinates. Text, selection and
        //caret are intentionally drawn separately so caret blinking does not
        //rebuild the background.
        //-----------------------------------------------------------------
        FBackgroundBitmap:      TBitmap;
        FBackgroundBitmapValid: Boolean;

        //-----------------------------------------------------------------
        //Cached canonical content surface.
        //
        //This bitmap contains the complete non-caret visual content of the edit
        //surface in canonical horizontal coordinates:
        //- styled background and border copied from FBackgroundBitmap;
        //- selection background;
        //- text drawn horizontally.
        //
        //It is then projected as one opaque bitmap. This avoids the clFuchsia
        //transparent-color problem previously seen with a separate text bitmap,
        //and it also avoids the caret/text drift caused by drawing text directly
        //under a GDI world transform.
        //
        //The caret is intentionally not part of this bitmap. It blinks
        //independently and is drawn from projected layout geometry.
        //-----------------------------------------------------------------
        FContentBitmap:      TBitmap;
        FContentBitmapValid: Boolean;

        //-----------------------------------------------------------------
        //Orientation-aware hover cursor.
        //
        //The Windows Cursor property can only reference a fixed TCursor value.
        //A rotated edit needs a cursor whose I-beam follows the same direction
        //as the insertion caret. We therefore create a native HCURSOR and apply
        //it in WM_SETCURSOR for client-area hover.
        //
        //Ownership rule:
        //FHoverCursorHandle is owned by this control and must be destroyed with
        //DestroyCursor when invalidated or when the component is destroyed.
        //-----------------------------------------------------------------
        FHoverCursorHandle: HCURSOR;
        FHoverCursorAngle: Double;

        //-----------------------------------------------------------------
        //Debug-only visual aid.
        //
        //When enabled, a dotted rectangle is drawn around the physical VCL
        //ClientRect. It helps verify whether Width / Height correctly
        //contain the projected LogicalLength / LogicalThickness surface.
        //It is not part of the edit rendering itself.
        //-----------------------------------------------------------------
        FShowDebugBounds: Boolean;

        //-----------------------------------------------------------------
        //Native Windows region management.
        //
        //TRotatedEdit is still hosted by a rectangular VCL window, but the
        //effective Windows region can be restricted to the projected edit
        //surface.
        //
        //This is not only cosmetic. Without a window region, the rectangular
        //bounding box would still receive mouse messages in visually transparent
        //areas. A professional rotated edit control should not intercept events
        //outside its visible editable surface.
        //-----------------------------------------------------------------
        FUseWindowRegion: Boolean;

        //-----------------------------------------------------------------
        //Editing session state and public edit notifications.
        //
        //FEditingStarted is not the focus state. It is set only when the first
        //accepted user text mutation starts an editing session, then cleared
        //when EditingDone completes.
        //-----------------------------------------------------------------
        FEditingStarted: Boolean;

        FOnChange:          TNotifyEvent;
        FOnSelectionChange: TNotifyEvent;
        FOnEditingStart:    TNotifyEvent;
        FOnCanChange:       TRotatedEditCanChangeEvent;
        FOnValidate:        TRotatedEditValidateEvent;
        FOnEditingDone:     TRotatedEditEditingDoneEvent;

        Procedure SetText(Const Value: String);
        Procedure SetOrientation(Const Value: TRotatedEditOrientation);
        Procedure SetAngle(Const Value: Double);
        Procedure SetLogicalLength(Const Value: Integer);
        Procedure SetLogicalThickness(Const Value: Integer);
        Procedure SetAutoSize(Const Value: Boolean);
        Procedure SetAutoSizeBounds(Const Value: Boolean);
        Procedure SetReadOnly(Const Value: Boolean);
        Procedure SetMaxLength(Const Value: Integer);
        Procedure SetAlignment(Const Value: TAlignment);
        Procedure SetCharCase(Const Value: TEditCharCase);
        Procedure SetTextHint(Const Value: String);
        Procedure SetNumbersOnly(Const Value: Boolean);
        Function NormalizeAssignedText(Const AText: String): String;
        Function NormalizeInsertedText(Const AText: String): String;
        Procedure SetCaretIndex(Const Value: Integer);
        Procedure SetSelStart(Const Value: Integer);
        Procedure SetSelLength(Const Value: Integer);
        Function GetSelText: String;
        Procedure SetSelText(Const Value: String);
        Procedure SetBorderStyle(Const Value: TBorderStyle);
        Procedure SetBorderColor(Const Value: TColor);
        Procedure SetPaletteMode(Const Value: TRotatedEditPaletteMode);
        Procedure SetRenderBackendKind(Const Value: TRotatedEditRenderBackendKind);
        Procedure RecreateRenderBackend;
        Procedure TraceRenderBackendState(Const AReason: String);

        Procedure SetTextPaddingStart(Const Value: Integer);
        Procedure SetTextPaddingEnd(Const Value: Integer);
        Procedure SetCaretThickness(Const Value: Integer);
        Procedure SetShowDebugBounds(Const Value: Boolean);
        Procedure SetUseWindowRegion(Const Value: Boolean);
        Procedure SetShowDesignMarkers(Const Value: Boolean);

        Procedure ReadInternalOriginActive(AReader: TReader);
        Procedure WriteInternalOriginActive(AWriter: TWriter);
        Procedure ReadInternalOriginX(AReader: TReader);
        Procedure WriteInternalOriginX(AWriter: TWriter);
        Procedure ReadInternalOriginY(AReader: TReader);
        Procedure WriteInternalOriginY(AWriter: TWriter);

        Procedure InvalidateBackgroundCache;
        Procedure InvalidateContentBitmap;
        Procedure InvalidatePreferredLogicalThickness;
        Function ResolvePreferredLogicalThickness: Integer;
        Procedure ApplyAutoSizeLogicalThickness;
        Procedure UpdatePhysicalBoundsFromLogicalSize;
        Procedure ApplyExternalBoundsFromLogicalSize;
        Procedure ApplyExternalBoundsFromLogicalSizeKeepingCenter;
        Procedure InvalidateRotationCenter;

        Procedure CalcProjectedEditBoundsForLogicalSize(
            ALogicalLength: Integer;
            ALogicalThickness: Integer;
            Out AMinX: Double;
            Out AMinY: Double;
            Out AMaxX: Double;
            Out AMaxY: Double);

        Procedure ResolveExternalBoundsAnchorFractions(
            Out AAnchorX: Double;
            Out AAnchorY: Double);

        Procedure ResolveCurrentProjectedEditBoundsInParent(
            Out ALeft: Double;
            Out ATop: Double;
            Out ARight: Double;
            Out ABottom: Double);
        Procedure UpdateWindowRegion;

        Procedure CalcPhysicalSizeForLogicalSize(
            ALogicalLength: Integer;
            ALogicalThickness: Integer;
            Out APhysicalWidth: Integer;
            Out APhysicalHeight: Integer);

        Function InferDesignerResizeGrip(
            ALeft: Integer;
            ATop: Integer;
            AWidth: Integer;
            AHeight: Integer): TRotatedEditDesignerResizeGrip;

        Function DesignerResizeGripTargetsLength(
            AGrip: TRotatedEditDesignerResizeGrip): Boolean;

        Procedure InvalidateDesignerResizeBounds(
            Const AOldBounds: TRect);

        Function TryApplyDesignerResize(
            Var ALeft: Integer;
            Var ATop: Integer;
            Var AWidth: Integer;
            Var AHeight: Integer): Boolean;
        Procedure ClearWindowRegion;
        Function CreateRegionFromCurrentLayout: HRGN;

        Procedure CaretChanged(Sender: TObject);
        Function BuildCaretInvalidationRect(Out ARect: TRect): Boolean;
        Procedure InvalidateCaretArea;
        Procedure PaintTransparentBackground(ACanvas: TCanvas);
        Procedure DrawDesignSelectionMarkers(
            ACanvas: TCanvas;
            Const ALayout: TRotatedEditLayoutResult);

        Procedure DestroyHoverCursor;
        Procedure InvalidateHoverCursor;
        Function EnsureHoverCursor: HCURSOR;
        Function CreateOrientationAwareHoverCursor(AAngle: Double): HCURSOR;
        Procedure DrawHoverCursorShape(
            ACanvas: TCanvas;
            ACenterX: Integer;
            ACenterY: Integer;
            AAngle: Double;
            AColor: TColor;
            APenWidth: Integer);

        Procedure DrawHoverCursorStroke(
            ACanvas: TCanvas;
            ACenterX: Integer;
            ACenterY: Integer;
            AAngle: Double;
            APenWidth: Integer);

        Procedure SetCursorPlaneBit(
            Var APlane: TBytes;
            AWidth: Integer;
            AHeight: Integer;
            AX: Integer;
            AY: Integer;
            AValue: Boolean);

        Procedure DrawCursorMaskLine(
            Var APlane: TBytes;
            AWidth: Integer;
            AHeight: Integer;
            AX1: Integer;
            AY1: Integer;
            AX2: Integer;
            AY2: Integer);

        Procedure DrawCursorMaskShape(
            Var AXorPlane: TBytes;
            AWidth: Integer;
            AHeight: Integer;
            ACenterX: Integer;
            ACenterY: Integer;
            AAngle: Double);

        Function NormalizeTextIndex(AIndex: Integer): Integer;
        Function IsWordChar(AChar: Char): Boolean;
        Function FindWordStart(ACharIndex: Integer): Integer;
        Function FindWordEnd(ACharIndex: Integer): Integer;
        Function UpdateClickCount(
            AX: Integer;
            AY: Integer): Integer;

        Procedure SelectRange(
            AAnchorIndex: Integer;
            ACaretIndex: Integer);

        Procedure SetCaretAndSelection(
            ACaretIndex: Integer;
            AExtendSelection: Boolean);

        Procedure SelectWordAt(AIndex: Integer);
        Procedure SelectAllInternal;

    protected
        Procedure CreateWnd; Override;
        Procedure DestroyWnd; Override;
        Procedure Resize; Override;
        Procedure WMEraseBkgnd(Var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
        Procedure WMGetDlgCode(Var Message: TWMGetDlgCode); message WM_GETDLGCODE;
        Procedure WMSetCursor(Var Message: TWMSetCursor); message WM_SETCURSOR;
        Procedure WMLButtonDblClk(Var Message: TWMLButtonDblClk); message WM_LBUTTONDBLCLK;

        Procedure CMColorChanged(Var Message: TMessage); message CM_COLORCHANGED;
        Procedure CMFontChanged(Var Message: TMessage); message CM_FONTCHANGED;
        Procedure CMDesignHitTest(Var Message: TCMDesignHitTest); message CM_DESIGNHITTEST;
        Procedure CMEnabledChanged(Var Message: TMessage); message CM_ENABLEDCHANGED;
        Procedure CMStyleChanged(Var Message: TMessage); message CM_STYLECHANGED;

        Procedure Paint; Override;
        Procedure Loaded; Override;
        Procedure DefineProperties(AFiler: TFiler); Override;
        Procedure KeyDown(
            Var Key: Word;
            Shift: TShiftState); Override;
        Procedure KeyPress(Var Key: Char); Override;
        Procedure MouseDown(
            Button: TMouseButton;
            Shift: TShiftState;
            X: Integer;
            Y: Integer); Override;
        Procedure MouseMove(
            Shift: TShiftState;
            X: Integer;
            Y: Integer); Override;
        Procedure MouseUp(
            Button: TMouseButton;
            Shift: TShiftState;
            X: Integer;
            Y: Integer); Override;
        Procedure DblClick; Override;
        Procedure DoEnter; Override;
        Procedure DoExit; Override;

        Function CanApplyTextChange(
            Const AOldText: String;
            Const ANewText: String): Boolean; Virtual;
        Procedure EditingStart; Virtual;
        Procedure TextChanged; Virtual;
        Procedure SelectionChanged; Virtual;
        Procedure EditingDone(AReason: TRotatedEditEditingDoneReason); Virtual;

        Function BuildCurrentLayout: TRotatedEditLayoutResult; Virtual;

        Procedure ApplyEditState(
            Const AText: String;
            ACaretIndex: Integer;
            ASelStart: Integer;
            ASelLength: Integer); Virtual;

    public


        {
          Updates the design-time selected state.

          This method is called by the optional design-time package. It keeps the
          runtime component independent from DesignIntf / ToolsAPI while still
          allowing Paint to know whether this specific control is selected in
          the IDE form designer.
        }
        Procedure SetDesignSelectionStateForDesigner(
            ASelected: Boolean;
            AMultipleSelection: Boolean);
        {
          Overrides the VCL physical bounds update.

          At runtime and for normal property changes, bounds are the external
          Windows rectangle that contains the rotated logical edit surface.
          During design-time resizing, this method also protects the invariant
          that a single drag session changes either LogicalLength or
          LogicalThickness, but never both.
        }
        Procedure SetBounds(
            ALeft: Integer;
            ATop: Integer;
            AWidth: Integer;
            AHeight: Integer); Override;

        {Creates the owner-drawn edit control and initializes its logical model.}
        Constructor Create(AOwner: TComponent); Override;

        {Releases cached rendering resources, hover cursor and caret controller.}
        Destructor Destroy; Override;

        {Clears the text through the same change-validation pipeline as user edits.}
        Procedure Clear;

        {Selects the full current text and moves the caret to the end of it.}
        Procedure SelectAll;

        {Deletes the current selection through the normal edit pipeline.}
        Procedure ClearSelection;

        {Copies the current selection to the Windows clipboard.}
        Procedure CopyToClipboard;

        {Copies the current selection to the clipboard and removes it if editable.}
        Procedure CutToClipboard;

        {Pastes text from the Windows clipboard through the normal edit pipeline.}
        Procedure PasteFromClipboard;

        {
          Recomputes Width / Height so the physical VCL window can contain the
          rotated logical edit surface.

          This is an explicit user/code operation. It is intentionally different
          from loading a DFM, where the streamed external bounds must remain the
          authority and must not be recalculated automatically.
        }
        Procedure AutoSizeToLogicalBounds;

        {Zero-based insertion index of the caret in Text.}
        Property CaretIndex: Integer Read FCaretIndex Write SetCaretIndex;

        {Zero-based start index of the normalized selection range.}
        Property SelStart: Integer Read FSelStart Write SetSelStart;

        {Length of the normalized selection range.}
        Property SelLength: Integer Read FSelLength Write SetSelLength;

        {
          Text currently selected by SelStart / SelLength.

          Reading returns an empty string when there is no selection. Writing
          replaces the current selection, or inserts at the caret when the
          selection is empty, using the same normalization, MaxLength,
          OnCanChange, OnEditingStart, OnChange and OnSelectionChange pipeline
          as keyboard and clipboard editing.
        }
        Property SelText: String Read GetSelText Write SetSelText;

        {Horizontal scroll offset in canonical, unrotated text coordinates.}
        Property ScrollOffset: Integer Read FScrollOffset;

    published

        {
          Draws small XOR selection markers when the component is selected in
          the Delphi form designer.

          These markers compensate for the clipped/shaped window region used by
          rotated controls and do not replace the IDE selection model.
        }
        Property ShowDesignMarkers: Boolean
            Read FShowDesignMarkers
            Write SetShowDesignMarkers
            Default True;

        Property Align;
        Property Anchors;
        Property Color Default clWindow;
        Property Constraints;
        Property Enabled;
        Property Font;
        Property ParentColor;
        Property ParentFont;
        Property StyleElements;
        {$IFDEF VCLROTATEDEDIT_HAS_CONTROL_STYLE_NAME}
        Property StyleName;
        {$ENDIF}
        Property ParentShowHint;
        Property PopupMenu;
        Property ShowHint;
        Property TabOrder;
        Property TabStop Default True;
        Property Visible;

        {Text stored and edited by the control.}
        Property Text:        String Read FText Write SetText;

        {Convenience orientation for the common horizontal and vertical modes.}
        Property Orientation: TRotatedEditOrientation Read FOrientation Write SetOrientation Default reoHorizontal;

        {Rotation angle in degrees. Used directly when Orientation is reoCustomAngle.}
        Property Angle:       Double Read FAngle Write SetAngle;

        {Automatically keeps LogicalThickness at the native-like single-line edit height.}
        Property AutoSize:    Boolean Read FAutoSize Write SetAutoSize Default True;

        {Logical dimension in the text flow direction.}
        Property LogicalLength: Integer Read FLogicalLength Write SetLogicalLength Default 120;

        {Logical dimension perpendicular to the text flow direction.}
        Property LogicalThickness: Integer Read FLogicalThickness Write SetLogicalThickness Default 24;

        {Prevents user text mutations while preserving selection and clipboard copy.}
        Property ReadOnly:    Boolean Read FReadOnly Write SetReadOnly Default False;

        {Maximum accepted text length. Zero means no component-level limit.}
        Property MaxLength:   Integer Read FMaxLength Write SetMaxLength Default 0;

        {Canonical horizontal text alignment before rotation.}
        Property Alignment:   TAlignment Read FAlignment Write SetAlignment Default taLeftJustify;

        {Character case normalization applied to assigned and inserted text.}
        Property CharCase:    TEditCharCase Read FCharCase Write SetCharCase Default ecNormal;

        {Hint text displayed when Text is empty and the control does not have focus.}
        Property TextHint:    String Read FTextHint Write SetTextHint;

        {Allows only decimal digits in user and programmatic text candidates.}
        Property NumbersOnly: Boolean Read FNumbersOnly Write SetNumbersOnly Default False;

        {VCL-style border mode used by the owner-drawn edit surface.}
        Property BorderStyle: TBorderStyle Read FBorderStyle Write SetBorderStyle Default bsSingle;

        {Fallback/custom border color used when PaletteMode or StyleElements require it.}
        Property BorderColor: TColor Read FBorderColor Write SetBorderColor Default clBtnShadow;

        {
          Selects the palette source.

          repmStyle uses the resolved VCL style palette and honors
          StyleElements. Runtime keeps the established style-service order
          because it already returns the expected application colors.
          Design-time prefers the parent/control style context so the
          owner-drawn surface matches the form designer style more closely.

          repmCustom uses Color / Font.Color / BorderColor.
        }
        Property PaletteMode: TRotatedEditPaletteMode Read FPaletteMode Write SetPaletteMode Default repmStyle;

        {
          Requested rendering backend.

          rebDirect2D is the default backend. It uses Direct2D for final-shape
          geometry and DirectWrite for text, selection and caret metrics. The
          backend draws in the final oriented coordinate system and falls back
          internally to the GDI backend if native Direct2D resources are not
          available or if a Direct2D paint pass fails.

          rebGDI keeps the historical GDI renderer available for compatibility
          and explicit testing. It is also the safety fallback used by the
          Direct2D backend.
        }
        Property RenderBackend: TRotatedEditRenderBackendKind
            Read FRenderBackendKind
            Write SetRenderBackendKind
            Default rebDirect2D;

        {
          Logical margin at the start of the text flow.
          Internally this maps to the canonical left padding before rotation.
        }
        Property TextPaddingStart: Integer Read FPaddingLeft Write SetTextPaddingStart Default 3;

        {
          Logical margin at the end of the text flow.
          Internally this maps to the canonical right padding before rotation.
        }
        Property TextPaddingEnd: Integer Read FPaddingRight Write SetTextPaddingEnd Default 3;

        Property OnChange: TNotifyEvent Read FOnChange Write FOnChange;

        {
          Fired when CaretIndex, SelStart or SelLength changes.

          TEdit does not expose this notification directly, but TRotatedEdit
          publishes caret/selection state. A consolidated event is therefore
          useful and avoids forcing callers to infer selection changes from
          keyboard or mouse messages.
        }
        Property OnSelectionChange: TNotifyEvent Read FOnSelectionChange Write FOnSelectionChange;

        {
          Fired once when the first accepted user text mutation starts an
          editing session. Focus changes and pure selection moves do not trigger
          this event.
        }
        Property OnEditingStart: TNotifyEvent Read FOnEditingStart Write FOnEditingStart;

        {
          Allows callers to reject a normalized text candidate before it becomes
          the stored Text value.
        }
        Property OnCanChange: TRotatedEditCanChangeEvent Read FOnCanChange Write FOnCanChange;

        Property OnValidate:    TRotatedEditValidateEvent Read FOnValidate Write FOnValidate;
        Property OnEditingDone: TRotatedEditEditingDoneEvent Read FOnEditingDone Write FOnEditingDone;

        Property OnClick;
        Property OnContextPopup;
        Property OnDblClick;
        Property OnEnter;
        Property OnExit;
        Property OnKeyDown;
        Property OnKeyPress;
        Property OnKeyUp;
        Property OnMouseDown;
        Property OnMouseEnter;
        Property OnMouseLeave;
        Property OnMouseMove;
        Property OnMouseUp;
        Property OnMouseWheel;
        Property OnMouseWheelDown;
        Property OnMouseWheelUp;
    End;

Implementation

Uses
    Vcl.Themes,
    VclRotatedEdit_Geometry,
    VclRotatedEdit_Layout,
    VclRotatedEdit_EditEngine,
    VclRotatedEdit_Clipboard;

Constructor TRotatedEditCore.Create(AOwner: TComponent);
Begin
    Inherited Create(AOwner);

    //---------------------------------------------------------------------
    //Le contrôle n'est volontairement pas opaque.
    //
    //La surface éditable peut être tournée. La bounding box VCL physique
    //contient alors des zones qui ne doivent pas être peintes par le
    //contrôle, afin de laisser apparaître le parent et les contrôles voisins.
    //
    //Seule la surface logique projetée est dessinée. Cette règle est
    //essentielle pour les angles libres comme 45 degrés.
    //---------------------------------------------------------------------
    ControlStyle := ControlStyle + [csClickEvents, csDoubleClicks];
    ControlStyle := ControlStyle - [csOpaque];

    FLogicalLength := 120;
    FLogicalThickness := 24;
    FAutoSize := True;
    FPreferredLogicalThickness := 0;
    FPreferredLogicalThicknessValid := False;
    FAutoSizeBounds := True;
    FDesignerResizeGrip := rerzNone;
    FDesignerResizeTargetsLength := True;
    FDesignerResizeBaseBounds := Rect(0, 0, 0, 0);
    FDesignerResizeBaseLength := 0;
    FDesignerResizeBaseThickness := 0;
    FDesignerResizeAnchorScreenX := 0.0;
    FDesignerResizeAnchorScreenY := 0.0;
    FDesignerResizeLastTick := 0;

    FDesignerResizeLastValidBounds := Rect(0, 0, 0, 0);
    FDesignerResizeLastValidLength := 0;
    FDesignerResizeLastValidThickness := 0;
    FDesignerResizeLastValidOriginX := 0.0;
    FDesignerResizeLastValidOriginY := 0.0;
    FDesignerResizeHasLastValidGeometry := False;

    FDesignerResizeApplyingBounds := False;
    FShowDesignMarkers := True;
    FDesignSelectionSelected := False;
    FDesignSelectionMultiple := False;
    FUseInternalOrigin := False;
    FInternalOriginX := 0.0;
    FInternalOriginY := 0.0;
    FUpdatingBounds := False;
    FApplyingLogicalBounds := False;

    Width := FLogicalLength;
    Height := FLogicalThickness;
    TabStop := True;

    Color := clWindow;
    ParentColor := False;

    FText := '';
    FOrientation := reoHorizontal;
    FAngle := 0.0;
    FReadOnly := False;
    FMaxLength := 0;
    FAlignment := taLeftJustify;
    FCharCase := ecNormal;
    FTextHint := '';
    FNumbersOnly := False;
    FCaretIndex := 0;
    FSelStart := 0;
    FSelLength := 0;
    FScrollOffset := 0;
    FSelectionAnchor := 0;
    FMouseSelecting := False;
    FLastClickTick := 0;
    FLastClickPos := Point(
        0,
        0);
    FBorderStyle := bsSingle;
    FBorderColor := clBtnShadow;
    FPaletteMode := repmStyle;
    FRenderBackendKind := rebDirect2D;

    FPaddingLeft := 3;
    FPaddingRight := 3;
    FCaretThickness := 1;
    FEditingStarted := False;

    FCaretController := TRotatedEditCaretController.Create(Self);
    FCaretController.OnCaretChanged := CaretChanged;

    FLastCaretInvalidateRect := Rect(0, 0, 0, 0);
    FLastCaretInvalidateRectValid := False;

    //---------------------------------------------------------------------
    //Rendering backend.
    //
    //The initial backend is deliberately the historical GDI implementation.
    //The core already talks to it through IRotatedEditRenderBackend so the
    //future Direct2D/DirectWrite backend can own both drawing and text metrics
    //without mixing GDI measurements with DirectWrite rendering.
    //---------------------------------------------------------------------
    RecreateRenderBackend;

    FBackgroundBitmap := TBitmap.Create;
    FBackgroundBitmap.PixelFormat := pf32bit;
    FBackgroundBitmapValid := False;
    FContentBitmapValid := False;

    FContentBitmap := TBitmap.Create;
    FContentBitmap.PixelFormat := pf32bit;
    FContentBitmapValid := False;
    FUseWindowRegion := True;

    Cursor := crIBeam;
End;

Destructor TRotatedEditCore.Destroy;
Begin
    DestroyHoverCursor;
    FContentBitmap.Free;
    FBackgroundBitmap.Free;
    FCaretController.Free;

    Inherited Destroy;
End;


Procedure TRotatedEditCore.CalcPhysicalSizeForLogicalSize(
    ALogicalLength: Integer;
    ALogicalThickness: Integer;
    Out APhysicalWidth: Integer;
    Out APhysicalHeight: Integer);
Var
    LRad: Double;
    LCos: Double;
    LSin: Double;
Begin
    //-------------------------------------------------------------------------
    //Converts the logical edit surface into its physical bounding box.
    //
    //LogicalLength follows the text flow. LogicalThickness is perpendicular to
    //the text flow. Width / Height are only the VCL rectangular host needed to
    //contain the rotated surface.
    //
    //This helper centralizes the formula so SetBounds, AutoSizeToLogicalBounds
    //and design-time resize all use the same rule.
    //-------------------------------------------------------------------------
    If ALogicalLength < 1 Then
        ALogicalLength := 1;

    If ALogicalThickness < 1 Then
        ALogicalThickness := 1;

    LRad := TRotatedEditGeometry.NormalizeAngle(FAngle) * Pi / 180.0;
    LCos := Abs(Cos(LRad));
    LSin := Abs(Sin(LRad));

    APhysicalWidth := Ceil((ALogicalLength * LCos) + (ALogicalThickness * LSin));
    APhysicalHeight := Ceil((ALogicalLength * LSin) + (ALogicalThickness * LCos));

    If APhysicalWidth < 1 Then
        APhysicalWidth := 1;

    If APhysicalHeight < 1 Then
        APhysicalHeight := 1;
End;

Function TRotatedEditCore.InferDesignerResizeGrip(
    ALeft: Integer;
    ATop: Integer;
    AWidth: Integer;
    AHeight: Integer): TRotatedEditDesignerResizeGrip;
Var
    LOldRight: Integer;
    LOldBottom: Integer;
    LNewRight: Integer;
    LNewBottom: Integer;
    LLeftChanged: Boolean;
    LTopChanged: Boolean;
    LRightChanged: Boolean;
    LBottomChanged: Boolean;
Begin
    //-------------------------------------------------------------------------
    //Infers the designer handle from the requested bounds.
    //
    //The VCL designer manipulates the physical BoundsRect. It does not expose
    //the selected resize handle to the component. Comparing old and new edges is
    //therefore the most reliable information available from inside SetBounds.
    //
    //This method is intentionally conservative. If the requested bounds do not
    //look like a resize handle operation, rerzNone is returned and SetBounds uses
    //the normal move/resize path.
    //-------------------------------------------------------------------------
    Result := rerzNone;

    LOldRight := Left + Width;
    LOldBottom := Top + Height;

    LNewRight := ALeft + AWidth;
    LNewBottom := ATop + AHeight;

    LLeftChanged := ALeft <> Left;
    LTopChanged := ATop <> Top;
    LRightChanged := LNewRight <> LOldRight;
    LBottomChanged := LNewBottom <> LOldBottom;

    If LLeftChanged And LTopChanged Then
        Result := rerzTopLeft
    Else If LRightChanged And LTopChanged Then
        Result := rerzTopRight
    Else If LLeftChanged And LBottomChanged Then
        Result := rerzBottomLeft
    Else If LRightChanged And LBottomChanged Then
        Result := rerzBottomRight
    Else If LLeftChanged Then
        Result := rerzLeft
    Else If LRightChanged Then
        Result := rerzRight
    Else If LTopChanged Then
        Result := rerzTop
    Else If LBottomChanged Then
        Result := rerzBottom;
End;

Function TRotatedEditCore.DesignerResizeGripTargetsLength(
    AGrip: TRotatedEditDesignerResizeGrip): Boolean;
Var
    LAngle: Double;
    LQuadrant: Integer;
    LCos: Double;
    LSin: Double;
    LDiagonalTopLeftBottomRight: Boolean;
    LDiagonalTopRightBottomLeft: Boolean;
Begin
    //-------------------------------------------------------------------------
    //Maps a PHYSICAL designer resize handle to the single LOGICAL dimension it
    //must edit.
    //
    //This function is the official policy for design-time resizing. Keep all
    //dimension-selection decisions here. Do not duplicate this mapping in
    //SetBounds, in the renderer, or in mouse handlers.
    //
    //Golden rule:
    //
    //  one designer drag changes either LogicalLength or LogicalThickness,
    //  never both.
    //
    //Corner rule:
    //
    //- for quadrants 0 and 2:
    //    top-left / bottom-right change thickness,
    //    top-right / bottom-left change length;
    //
    //- for quadrants 1 and 3:
    //    top-left / bottom-right change length,
    //    top-right / bottom-left change thickness.
    //
    //Concrete reference case:
    //At 45 degrees, the top-right physical designer handle must edit
    //LogicalLength only. LogicalThickness must stay at its session-base value.
    //This exact case is intentionally documented because it previously
    //regressed when intermediate SetBounds calls were reclassified as side
    //resizes.
    //
    //Side-handle rule:
    //The nearest logical axis wins. If the text flow is closer to horizontal,
    //left/right handles edit LogicalLength. If the text flow is closer to
    //vertical, top/bottom handles edit LogicalLength.
    //-------------------------------------------------------------------------
    Result := True;

    LAngle := TRotatedEditGeometry.NormalizeAngle(FAngle);
    LQuadrant := Trunc(LAngle / 90.0) Mod 4;

    LDiagonalTopLeftBottomRight :=
        (AGrip = rerzTopLeft) Or
        (AGrip = rerzBottomRight);

    LDiagonalTopRightBottomLeft :=
        (AGrip = rerzTopRight) Or
        (AGrip = rerzBottomLeft);

    If LDiagonalTopLeftBottomRight Or LDiagonalTopRightBottomLeft Then Begin
        If (LQuadrant = 0) Or (LQuadrant = 2) Then
            Result := LDiagonalTopRightBottomLeft
        Else
            Result := LDiagonalTopLeftBottomRight;

        Exit;
    End;

    LAngle := LAngle * Pi / 180.0;
    LCos := Abs(Cos(LAngle));
    LSin := Abs(Sin(LAngle));

    Case AGrip Of
        rerzLeft,
        rerzRight:
            Result := LCos >= LSin;

        rerzTop,
        rerzBottom:
            Result := LSin > LCos;
    Else
        Result := True;
    End;
End;


Procedure TRotatedEditCore.InvalidateDesignerResizeBounds(
    Const AOldBounds: TRect);
Var
    LNewBounds: TRect;
Begin
    //-------------------------------------------------------------------------
    //Invalidates both the old and the new host rectangles after a corrected
    //design-time resize.
    //
    //Why this helper exists
    //----------------------
    //During IDE resizing the designer sends temporary physical rectangles.
    //TRotatedEdit then computes its real bounds from:
    //
    //  LogicalLength + LogicalThickness + Angle + locked anchor point
    //
    //The old host rectangle and the final host rectangle can therefore differ
    //from the temporary designer rectangle. Invalidating both areas prevents
    //visual remnants when the control is moved to its corrected anchored
    //position.
    //
    //The erase flag is deliberately False. Asking Windows to erase the parent
    //background at every designer mouse move creates visible flicker.
    //
    //VCL Anchors note
    //----------------
    //This helper works in the parent client coordinate system, which is the
    //coordinate system used by Left / Top / BoundsRect. The normal VCL Anchors
    //property only affects automatic repositioning during parent resize; it does
    //not change the meaning of BoundsRect during a direct SetBounds call.
    //-------------------------------------------------------------------------
    If Parent = Nil Then
        Exit;

    If Not Parent.HandleAllocated Then
        Exit;

    LNewBounds := BoundsRect;

    InvalidateRect(
        Parent.Handle,
        @AOldBounds,
        False);

    InvalidateRect(
        Parent.Handle,
        @LNewBounds,
        False);
End;

Function TRotatedEditCore.TryApplyDesignerResize(
    Var ALeft: Integer;
    Var ATop: Integer;
    Var AWidth: Integer;
    Var AHeight: Integer): Boolean;
Var
    LGrip: TRotatedEditDesignerResizeGrip;
    LCurrentGrip: TRotatedEditDesignerResizeGrip;
    LTargetsLength: Boolean;
    LAngle: Double;
    LCosAbs: Double;
    LSinAbs: Double;
    LRequestedWidth: Integer;
    LRequestedHeight: Integer;
    LBaseWidth: Integer;
    LBaseHeight: Integer;
    LNewLogicalLength: Integer;
    LNewLogicalThickness: Integer;
    LAnchorCanonicalX: Double;
    LAnchorCanonicalY: Double;
    LAnchorClientX: Double;
    LAnchorClientY: Double;
    LRotatedAnchorX: Double;
    LRotatedAnchorY: Double;
    LProjectedMinX: Double;
    LProjectedMinY: Double;
    LProjectedMaxX: Double;
    LProjectedMaxY: Double;

    Procedure ResolveOppositeAnchorCanonical(
        AGrip: TRotatedEditDesignerResizeGrip;
        ALogicalLength: Integer;
        ALogicalThickness: Integer;
        Out AX: Double;
        Out AY: Double);
    Begin
        //---------------------------------------------------------------------
        //Returns the canonical point opposite to the dragged handle.
        //
        //This point is the fixed point of the internal edit surface during the
        //designer resize. It is not always bottom-left:
        //- top-right keeps bottom-left;
        //- bottom-left keeps top-right;
        //- right keeps middle-left;
        //- bottom keeps middle-top.
        //---------------------------------------------------------------------
        Case AGrip Of
            rerzTopLeft:
                Begin
                    AX := ALogicalLength;
                    AY := ALogicalThickness;
                End;

            rerzTopRight:
                Begin
                    AX := 0.0;
                    AY := ALogicalThickness;
                End;

            rerzBottomLeft:
                Begin
                    AX := ALogicalLength;
                    AY := 0.0;
                End;

            rerzBottomRight:
                Begin
                    AX := 0.0;
                    AY := 0.0;
                End;

            rerzLeft:
                Begin
                    AX := ALogicalLength;
                    AY := ALogicalThickness / 2.0;
                End;

            rerzRight:
                Begin
                    AX := 0.0;
                    AY := ALogicalThickness / 2.0;
                End;

            rerzTop:
                Begin
                    AX := ALogicalLength / 2.0;
                    AY := ALogicalThickness;
                End;

            rerzBottom:
                Begin
                    AX := ALogicalLength / 2.0;
                    AY := 0.0;
                End;
        Else
            Begin
                AX := 0.0;
                AY := 0.0;
            End;
        End;
    End;

    Procedure RotateCanonicalPoint(
        ACanonicalX: Double;
        ACanonicalY: Double;
        Out AX: Double;
        Out AY: Double);
    Var
        LRad: Double;
        LC: Double;
        LS: Double;
    Begin
        //---------------------------------------------------------------------
        //Projects a canonical point to a local vector using the same convention
        //as the renderer/layout:
        //- public positive angle is counter-clockwise;
        //- Windows Y grows downward.
        //---------------------------------------------------------------------
        LRad := TRotatedEditGeometry.NormalizeAngle(FAngle) * Pi / 180.0;
        LC := Cos(LRad);
        LS := Sin(LRad);

        AX := (ACanonicalX * LC) + (ACanonicalY * LS);
        AY := (-ACanonicalX * LS) + (ACanonicalY * LC);
    End;

    Procedure CalcProjectedBounds(
        ALogicalLength: Integer;
        ALogicalThickness: Integer;
        Out AMinX: Double;
        Out AMinY: Double;
        Out AMaxX: Double;
        Out AMaxY: Double);
    Var
        X0: Double;
        Y0: Double;
        X1: Double;
        Y1: Double;
        X2: Double;
        Y2: Double;
        X3: Double;
        Y3: Double;
    Begin
        //---------------------------------------------------------------------
        //Returns the projected bounds of the canonical edit rectangle around
        //origin (0,0). FInternalOriginX/Y later places these bounds inside the
        //external VCL ClientRect.
        //---------------------------------------------------------------------
        RotateCanonicalPoint(
            0.0,
            0.0,
            X0,
            Y0);

        RotateCanonicalPoint(
            ALogicalLength,
            0.0,
            X1,
            Y1);

        RotateCanonicalPoint(
            ALogicalLength,
            ALogicalThickness,
            X2,
            Y2);

        RotateCanonicalPoint(
            0.0,
            ALogicalThickness,
            X3,
            Y3);

        AMinX := Min(Min(X0, X1), Min(X2, X3));
        AMaxX := Max(Max(X0, X1), Max(X2, X3));
        AMinY := Min(Min(Y0, Y1), Min(Y2, Y3));
        AMaxY := Max(Max(Y0, Y1), Max(Y2, Y3));
    End;

    Function MaxLengthInsideRect(
        AAvailableWidth: Integer;
        AAvailableHeight: Integer;
        AFixedThickness: Integer): Integer;
    Var
        LMaxByWidth: Double;
        LMaxByHeight: Double;
        LCandidate: Double;
    Begin
        //---------------------------------------------------------------------
        //Computes the maximum LogicalLength that keeps the projected edit
        //surface inside the external ClientRect while LogicalThickness remains
        //strictly unchanged.
        //---------------------------------------------------------------------
        LMaxByWidth := 1.0E12;
        LMaxByHeight := 1.0E12;

        If LCosAbs > 0.0001 Then
            LMaxByWidth := (AAvailableWidth - (AFixedThickness * LSinAbs)) / LCosAbs;

        If LSinAbs > 0.0001 Then
            LMaxByHeight := (AAvailableHeight - (AFixedThickness * LCosAbs)) / LSinAbs;

        LCandidate := Min(LMaxByWidth, LMaxByHeight);

        Result := Round(LCandidate);

        If Result < 1 Then
            Result := 1;
    End;

    Function MaxThicknessInsideRect(
        AAvailableWidth: Integer;
        AAvailableHeight: Integer;
        AFixedLength: Integer): Integer;
    Var
        LMaxByWidth: Double;
        LMaxByHeight: Double;
        LCandidate: Double;
    Begin
        //---------------------------------------------------------------------
        //Computes the maximum LogicalThickness that keeps the projected edit
        //surface inside the external ClientRect while LogicalLength remains
        //strictly unchanged.
        //---------------------------------------------------------------------
        LMaxByWidth := 1.0E12;
        LMaxByHeight := 1.0E12;

        If LSinAbs > 0.0001 Then
            LMaxByWidth := (AAvailableWidth - (AFixedLength * LCosAbs)) / LSinAbs;

        If LCosAbs > 0.0001 Then
            LMaxByHeight := (AAvailableHeight - (AFixedLength * LSinAbs)) / LCosAbs;

        LCandidate := Min(LMaxByWidth, LMaxByHeight);

        Result := Round(LCandidate);

        If Result < 1 Then
            Result := 1;
    End;

    Function LogicalSizeFitsInsideRequestedRect(
        ALogicalLength: Integer;
        ALogicalThickness: Integer): Boolean;
    Var
        LProjectedWidth: Double;
        LProjectedHeight: Double;
    Begin
        //---------------------------------------------------------------------
        //Validates that the candidate internal edit surface can still be hosted
        //by the external rectangle currently requested by the designer.
        //
        //This guard protects the important edge case where the user drags a
        //designer handle so far that the physical BoundsRect becomes too small
        //to contain the fixed logical dimension plus the minimum value of the
        //dimension being resized.
        //
        //Example:
        //- angle around 45 degrees;
        //- LogicalThickness is locked by the current drag session;
        //- the designer rectangle is made smaller than the projected thickness
        //  contribution itself.
        //
        //In that situation the old code clamped the recomputed dimension to 1
        //and still accepted the external bounds. The internal edit surface could
        //then no longer be represented correctly inside the host rectangle.
        //
        //The current rule is deliberately conservative:
        //
        //  invalid candidate => keep the last valid geometry
        //
        //Do not silently change Orientation or Angle here. Crossing an axis is
        //a semantic mirror operation, not a pure resize. If it is implemented
        //later, it should be explicit and optional.
        //---------------------------------------------------------------------
        If ALogicalLength < 1 Then
            ALogicalLength := 1;

        If ALogicalThickness < 1 Then
            ALogicalThickness := 1;

        LProjectedWidth :=
            (ALogicalLength * LCosAbs) +
            (ALogicalThickness * LSinAbs);

        LProjectedHeight :=
            (ALogicalLength * LSinAbs) +
            (ALogicalThickness * LCosAbs);

        Result :=
            (LProjectedWidth <= LRequestedWidth + 0.0001) And
            (LProjectedHeight <= LRequestedHeight + 0.0001);
    End;

    Procedure StoreLastValidDesignerGeometry;
    Begin
        //---------------------------------------------------------------------
        //Stores the last complete geometry accepted during the current
        //design-time resize session.
        //
        //A valid geometry is not only the external VCL BoundsRect. For this
        //component, the real visual state also includes:
        //- LogicalLength;
        //- LogicalThickness;
        //- the internal projected edit origin.
        //
        //Keeping these values together allows an invalid designer request to be
        //rejected without letting the external selection rectangle drift away
        //from the internal edit surface.
        //---------------------------------------------------------------------
        FDesignerResizeLastValidBounds := BoundsRect;
        FDesignerResizeLastValidLength := FLogicalLength;
        FDesignerResizeLastValidThickness := FLogicalThickness;
        FDesignerResizeLastValidOriginX := FInternalOriginX;
        FDesignerResizeLastValidOriginY := FInternalOriginY;
        FDesignerResizeHasLastValidGeometry := True;
    End;

    Procedure RestoreLastValidGeometryToRequest;
    Var
        LRestoreBounds: TRect;
    Begin
        //---------------------------------------------------------------------
        //Rejects the current designer resize candidate and forces Delphi's
        //physical rectangle back to the last complete valid geometry.
        //
        //Why restoring only the logical values is not enough
        //--------------------------------------------------
        //SetBounds receives Delphi's temporary selection rectangle by value. If
        //the component merely refuses to update LogicalLength/LogicalThickness
        //but still lets the requested physical rectangle reach inherited
        //SetBounds, the IDE can keep dragging the external selection rectangle
        //into an impossible state. Subsequent SetBounds calls are then based on
        //that bad rectangle and the control appears to drift.
        //
        //Therefore an invalid candidate must restore both sides of the model:
        //
        //  internal geometry  => LogicalLength / LogicalThickness / origin
        //  external geometry  => ALeft / ATop / AWidth / AHeight
        //
        //This is intentionally not an auto-flip. The user's proposed future
        //mirror rule is documented here for later implementation:
        //
        //- crossing the Y axis => mirror on Y;
        //- crossing the X axis => mirror on X;
        //- crossing both axes  => full mirror.
        //
        //Such a mirror would imply a controlled Orientation/Angle
        //transformation and must not be hidden inside this conservative
        //validation path.
        //---------------------------------------------------------------------
        If FDesignerResizeHasLastValidGeometry Then Begin
            LRestoreBounds := FDesignerResizeLastValidBounds;

            FLogicalLength := FDesignerResizeLastValidLength;
            FLogicalThickness := FDesignerResizeLastValidThickness;
            FInternalOriginX := FDesignerResizeLastValidOriginX;
            FInternalOriginY := FDesignerResizeLastValidOriginY;
            FUseInternalOrigin := True;
        End Else Begin
            //-----------------------------------------------------------------
            //Fallback for a rejection occurring before the first valid
            //candidate of the session was stored. This should be rare, but it
            //keeps the component deterministic.
            //-----------------------------------------------------------------
            LRestoreBounds := FDesignerResizeBaseBounds;

            If (LRestoreBounds.Right <= LRestoreBounds.Left) Or
               (LRestoreBounds.Bottom <= LRestoreBounds.Top) Then
                LRestoreBounds := BoundsRect;
        End;

        ALeft := LRestoreBounds.Left;
        ATop := LRestoreBounds.Top;
        AWidth := LRestoreBounds.Right - LRestoreBounds.Left;
        AHeight := LRestoreBounds.Bottom - LRestoreBounds.Top;

        If AWidth < 1 Then
            AWidth := 1;

        If AHeight < 1 Then
            AHeight := 1;

        InvalidateBackgroundCache;
        InvalidateContentBitmap;
        Invalidate;
    End;

    Function IsSideGripPartOfCorner(
        ACornerGrip: TRotatedEditDesignerResizeGrip;
        ASideGrip: TRotatedEditDesignerResizeGrip): Boolean;
    Begin
        //---------------------------------------------------------------------
        //Returns True when ASideGrip is one of the two physical sides that form
        //ACornerGrip.
        //
        //Why this helper exists
        //----------------------
        //During a Delphi designer corner-resize operation, SetBounds can be
        //called several times with slightly different physical edge deltas. For
        //example, a real top-right drag on a 45 degree control may first look
        //like rerzTopRight, then like rerzTop only, depending on how Delphi
        //updates the temporary external BoundsRect.
        //
        //That second call must still belong to the same corner session. If we
        //treat it as a new top-side resize, the target dimension can switch
        //from LogicalLength to LogicalThickness, which breaks the golden rule:
        //one design-time drag changes only one logical dimension.
        //
        //Do not remove this compatibility check because the visual designer can
        //emit such intermediate side-like SetBounds calls even while the user
        //is still dragging the same corner handle. The top-right-at-45-degrees
        //case depends on this helper.
        //---------------------------------------------------------------------
        Result := False;

        Case ACornerGrip Of
            rerzTopLeft:
                Result :=
                    (ASideGrip = rerzTop) Or
                    (ASideGrip = rerzLeft);

            rerzTopRight:
                Result :=
                    (ASideGrip = rerzTop) Or
                    (ASideGrip = rerzRight);

            rerzBottomLeft:
                Result :=
                    (ASideGrip = rerzBottom) Or
                    (ASideGrip = rerzLeft);

            rerzBottomRight:
                Result :=
                    (ASideGrip = rerzBottom) Or
                    (ASideGrip = rerzRight);
        End;
    End;

    Function CurrentGripBelongsToLockedSession(
        ALockedGrip: TRotatedEditDesignerResizeGrip;
        ACurrentGrip: TRotatedEditDesignerResizeGrip): Boolean;
    Begin
        //---------------------------------------------------------------------
        //Keeps a corner resize session stable when Delphi temporarily reports
        //one of the two sides that compose the same corner.
        //
        //Only corner-to-side compatibility is accepted deliberately. If the
        //locked session is a side resize, and Delphi later reports a corner, we
        //do not silently promote the side to a corner because the opposite
        //anchor and target dimension were chosen from the side semantics.
        //---------------------------------------------------------------------
        Result := ALockedGrip = ACurrentGrip;

        If Result Then
            Exit;

        Result := IsSideGripPartOfCorner(
            ALockedGrip,
            ACurrentGrip);
    End;

Begin
    //-------------------------------------------------------------------------
    //Updates the INTERNAL edit surface from a designer bounds resize.
    //
    //Golden rule:
    //A design-time resize changes either LogicalLength or LogicalThickness, but
    //never both at the same time.
    //
    //Internal-bounds rule:
    //The external VCL BoundsRect is owned by Delphi/the designer. The component
    //derives an internal drawing rectangle that always remains inside the
    //external ClientRect. The drag rectangle is used to select the available
    //space; the final edit surface is then fitted inside that space while
    //preserving the locked opposite anchor.
    //
    //Session-lock rule:
    //The first meaningful inferred grip decides the target logical dimension
    //for the whole active drag. Later SetBounds calls are allowed to update the
    //available rectangle, but they must not change the target from length to
    //thickness or from thickness to length unless they clearly represent a new,
    //incompatible resize gesture.
    //
    //Why this matters:
    //At non-orthogonal angles, especially around 45 degrees, Delphi may report
    //a real corner drag as a sequence of corner and side-looking bounds changes.
    //Without this lock, dragging the top-right handle can accidentally modify
    //LogicalThickness after first modifying LogicalLength.
    //-------------------------------------------------------------------------
    Result := False;

    If Not (csDesigning In ComponentState) Then
        Exit;

    If csLoading In ComponentState Then
        Exit;

    LRequestedWidth := AWidth;
    LRequestedHeight := AHeight;

    If LRequestedWidth < 1 Then
        LRequestedWidth := 1;

    If LRequestedHeight < 1 Then
        LRequestedHeight := 1;

    //---------------------------------------------------------------------
    //Resize-session lifetime.
    //
    //The direction and anchor are locked for one inferred handle session.
    //
    //Important design-time limitation:
    //Delphi's designer manipulates the external BoundsRect but does not give us
    //a reliable resize-handle start/end notification. Therefore the component
    //must also watch the currently inferred grip. If the grip changes to an
    //incompatible handle, a new session is started so the target dimension can
    //change too.
    //
    //Compatible corner/side transitions are deliberately NOT treated as a new
    //session. Example: locked rerzTopRight followed by rerzTop or rerzRight is
    //still the same top-right drag. This preserves the originally selected
    //logical target.
    //
    //When the mouse button is not down, the next SetBounds is not part of an
    //active designer handle drag and any previous session must be discarded.
    //---------------------------------------------------------------------
    If (GetAsyncKeyState(VK_LBUTTON) And $8000) = 0 Then Begin
        FDesignerResizeGrip := rerzNone;
        FDesignerResizeLastTick := 0;
        Exit;
    End;

    FDesignerResizeLastTick := GetTickCount;

    LCurrentGrip := InferDesignerResizeGrip(
        ALeft,
        ATop,
        LRequestedWidth,
        LRequestedHeight);

    If LCurrentGrip = rerzNone Then
        Exit;

    If (FDesignerResizeGrip <> rerzNone) And
       Not CurrentGripBelongsToLockedSession(
           FDesignerResizeGrip,
           LCurrentGrip) Then Begin
        //-----------------------------------------------------------------
        //New handle / new direction detected.
        //
        //The VCL designer does not reliably send MouseUp/MouseDown messages to
        //the component when resize handles are manipulated. A previous gesture
        //can therefore leave FDesignerResizeGrip locked.
        //
        //If the currently inferred grip is not compatible with the locked grip,
        //treat this as a new resize session. Compatibility is important for
        //corner drags: during a real top-right drag, Delphi may briefly report
        //only the top or right side. That must not switch the resize from
        //LogicalLength to LogicalThickness.
        //
        //This preserves the important rule:
        //
        //  one designer resize edits either LogicalLength or LogicalThickness,
        //  never both.
        //-----------------------------------------------------------------
        FDesignerResizeGrip := rerzNone;
    End;

    If FDesignerResizeGrip = rerzNone Then Begin
        LGrip := LCurrentGrip;

        FDesignerResizeGrip := LGrip;
        FDesignerResizeTargetsLength := DesignerResizeGripTargetsLength(LGrip);
        FDesignerResizeBaseBounds := BoundsRect;
        FDesignerResizeBaseLength := FLogicalLength;
        FDesignerResizeBaseThickness := FLogicalThickness;

        StoreLastValidDesignerGeometry;

        //-----------------------------------------------------------------
        //Lock the anchor point once at the beginning of this resize session.
        //-----------------------------------------------------------------
        ResolveOppositeAnchorCanonical(
            FDesignerResizeGrip,
            FDesignerResizeBaseLength,
            FDesignerResizeBaseThickness,
            LAnchorCanonicalX,
            LAnchorCanonicalY);

        RotateCanonicalPoint(
            LAnchorCanonicalX,
            LAnchorCanonicalY,
            LRotatedAnchorX,
            LRotatedAnchorY);

        FDesignerResizeAnchorScreenX := Left + FInternalOriginX + LRotatedAnchorX;
        FDesignerResizeAnchorScreenY := Top + FInternalOriginY + LRotatedAnchorY;
    End;

    LGrip := FDesignerResizeGrip;
    LTargetsLength := FDesignerResizeTargetsLength;

    LBaseWidth := FDesignerResizeBaseBounds.Right - FDesignerResizeBaseBounds.Left;
    LBaseHeight := FDesignerResizeBaseBounds.Bottom - FDesignerResizeBaseBounds.Top;

    If LBaseWidth < 1 Then
        LBaseWidth := Width;

    If LBaseHeight < 1 Then
        LBaseHeight := Height;

    LNewLogicalLength := FDesignerResizeBaseLength;
    LNewLogicalThickness := FDesignerResizeBaseThickness;

    LAngle := TRotatedEditGeometry.NormalizeAngle(FAngle) * Pi / 180.0;
    LCosAbs := Abs(Cos(LAngle));
    LSinAbs := Abs(Sin(LAngle));

    //---------------------------------------------------------------------
    //Dimension selection.
    //
    //The existing direction-selection algorithm is preserved. Once it has
    //selected length or thickness, only that dimension is recomputed. The other
    //one is restored from the base session values.
    //
    //The recomputed value is the largest value that keeps the projected edit
    //surface inside the requested external bounds. This fixes the previous
    //version where the internal edit surface could move partly outside the
    //component.
    //---------------------------------------------------------------------
    If LTargetsLength Then Begin
        LNewLogicalLength := MaxLengthInsideRect(
            LRequestedWidth,
            LRequestedHeight,
            FDesignerResizeBaseThickness);

        LNewLogicalThickness := FDesignerResizeBaseThickness;
    End Else Begin
        LNewLogicalThickness := MaxThicknessInsideRect(
            LRequestedWidth,
            LRequestedHeight,
            FDesignerResizeBaseLength);

        LNewLogicalLength := FDesignerResizeBaseLength;
    End;

    If LNewLogicalLength < 1 Then
        LNewLogicalLength := 1;

    If LNewLogicalThickness < 1 Then
        LNewLogicalThickness := 1;

    //-------------------------------------------------------------------------
    //Boundary validation.
    //
    //The resized logical dimension is computed from the physical rectangle
    //requested by the designer. At extreme sizes, especially with a non-zero
    //angle, the requested rectangle may no longer be able to contain the fixed
    //dimension from the locked resize session.
    //
    //In that case, do not accept a nearly collapsed logical size and do not let
    //the external host rectangle collapse either. The component keeps the last
    //valid geometry. This protects the design-time resize model until an
    //optional explicit mirror/auto-flip feature is designed.
    //-------------------------------------------------------------------------
    If Not LogicalSizeFitsInsideRequestedRect(
        LNewLogicalLength,
        LNewLogicalThickness) Then Begin
        RestoreLastValidGeometryToRequest;

        Result := True;
        Exit;
    End;

    FLogicalLength := LNewLogicalLength;
    FLogicalThickness := LNewLogicalThickness;

    //---------------------------------------------------------------------
    //Place the projected edit surface inside the external ClientRect while
    //keeping the locked opposite anchor as stable as possible.
    //---------------------------------------------------------------------
    ResolveOppositeAnchorCanonical(
        LGrip,
        FLogicalLength,
        FLogicalThickness,
        LAnchorCanonicalX,
        LAnchorCanonicalY);

    RotateCanonicalPoint(
        LAnchorCanonicalX,
        LAnchorCanonicalY,
        LRotatedAnchorX,
        LRotatedAnchorY);

    LAnchorClientX := FDesignerResizeAnchorScreenX - ALeft;
    LAnchorClientY := FDesignerResizeAnchorScreenY - ATop;

    FInternalOriginX := LAnchorClientX - LRotatedAnchorX;
    FInternalOriginY := LAnchorClientY - LRotatedAnchorY;

    CalcProjectedBounds(
        FLogicalLength,
        FLogicalThickness,
        LProjectedMinX,
        LProjectedMinY,
        LProjectedMaxX,
        LProjectedMaxY);

    //---------------------------------------------------------------------
    //Final containment clamp.
    //
    //This clamp should normally be a no-op because the logical dimension was
    //already limited to fit inside the external bounds. It remains here as a
    //safety net for rounding errors and extreme angles.
    //---------------------------------------------------------------------
    If FInternalOriginX + LProjectedMinX < 0 Then
        FInternalOriginX := -LProjectedMinX;

    If FInternalOriginY + LProjectedMinY < 0 Then
        FInternalOriginY := -LProjectedMinY;

    If FInternalOriginX + LProjectedMaxX > LRequestedWidth Then
        FInternalOriginX := LRequestedWidth - LProjectedMaxX;

    If FInternalOriginY + LProjectedMaxY > LRequestedHeight Then
        FInternalOriginY := LRequestedHeight - LProjectedMaxY;

    FUseInternalOrigin := True;

    //---------------------------------------------------------------------
    //The candidate is valid. Store the full geometry that will be current
    //after SetBounds applies ALeft/ATop/AWidth/AHeight. BoundsRect still
    //contains the previous values at this point, so the external snapshot must
    //be built from the by-reference SetBounds arguments.
    //---------------------------------------------------------------------
    FDesignerResizeLastValidBounds := Rect(
        ALeft,
        ATop,
        ALeft + LRequestedWidth,
        ATop + LRequestedHeight);
    FDesignerResizeLastValidLength := FLogicalLength;
    FDesignerResizeLastValidThickness := FLogicalThickness;
    FDesignerResizeLastValidOriginX := FInternalOriginX;
    FDesignerResizeLastValidOriginY := FInternalOriginY;
    FDesignerResizeHasLastValidGeometry := True;

    InvalidateBackgroundCache;
    InvalidateContentBitmap;
    Invalidate;

    Result := True;
End;

Procedure TRotatedEditCore.SetDesignSelectionStateForDesigner(
    ASelected: Boolean;
    AMultipleSelection: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Updates the design-time selection state forwarded by the design-time unit.
    //
    //The runtime component does not depend on DesignIntf. The design-time
    //package observes the IDE selection and calls this method with the current
    //state.
    //
    //For now, the marker drawing only needs to know whether this specific
    //control is selected. The multiple-selection flag is still stored because it
    //may become useful later for different marker styles.
    //-------------------------------------------------------------------------
    If (FDesignSelectionSelected = ASelected) And
       (FDesignSelectionMultiple = AMultipleSelection) Then
        Exit;

    FDesignSelectionSelected := ASelected;
    FDesignSelectionMultiple := AMultipleSelection;

    If csDesigning In ComponentState Then
        Invalidate;
End;

Procedure TRotatedEditCore.SetShowDesignMarkers(Const Value: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Enables or disables lightweight design-time corner markers.
    //
    //Why this property exists
    //------------------------
    //TRotatedEdit uses SetWindowRgn to keep its shaped edit surface accurate.
    //That can clip or hide Delphi's native selection handles, especially during
    //multi-selection. Reading the IDE selection state through design notifiers
    //proved too fragile across Delphi versions, so the robust solution is a
    //plain component property used together with the current designer selection:
    //
    //  csDesigning + ShowDesignMarkers = True
    //
    //Important:
    //The property is not intended to mean "this component is selected". It is a
    //manual design aid for problematic forms where native Delphi handles are
    //hidden by the shaped window region. Only the selected-state flag forwarded by the design-time unit decides which
    //TRotatedEdit controls actually draw markers.
    //
    //The markers are small, gray, internal to the edit region and non-
    //interactive. They do not affect runtime behavior.
    //-------------------------------------------------------------------------
    If FShowDesignMarkers = Value Then
        Exit;

    FShowDesignMarkers := Value;

    If csDesigning In ComponentState Then
        Invalidate;
End;

Procedure TRotatedEditCore.SetBounds(
    ALeft: Integer;
    ATop: Integer;
    AWidth: Integer;
    AHeight: Integer);
Var
    LMinWidth: Integer;
    LMinHeight: Integer;
Begin
    //-------------------------------------------------------------------------
    //External bounds rule.
    //
    //The VCL BoundsRect belongs to Delphi and the form designer, except when
    //LogicalLength / LogicalThickness are explicitly changed by the user. In the
    //latter case ApplyExternalBoundsFromLogicalSize drives SetBounds and sets
    //FApplyingLogicalBounds so the external-resize interpreter is bypassed.
    //
    //This distinction is essential:
    //- external designer resize
    //    updates the internal edit geometry while keeping the external designer
    //    rectangle requested by Delphi;
    //
    //- manual LogicalLength / LogicalThickness change
    //    updates the external VCL bounds because the logical edit surface is the
    //    user-requested source of truth.
    //
    //Do not simplify this into a direct Width/Height-to-LogicalLength/
    //LogicalThickness mapping. That would reintroduce the design-time resize regression: a rotated
    //corner drag could change both logical
    //dimensions.
    //-------------------------------------------------------------------------
    //---------------------------------------------------------------------
    //Minimum external size.
    //
    //The VCL designer can let a selection rectangle become extremely small or
    //visually cross its opposite side. The component cannot fully prevent the
    //designer's own visual feedback from flipping, but it can keep its real
    //host rectangle from collapsing. This reduces cases where the inferred
    //handle/direction becomes meaningless.
    //---------------------------------------------------------------------
    LMinWidth := 8;
    LMinHeight := 8;

    If AWidth < LMinWidth Then
        AWidth := LMinWidth;

    If AHeight < LMinHeight Then
        AHeight := LMinHeight;

    If Not FApplyingLogicalBounds Then Begin
        //----------------------------------------------------------------------
        //Any external SetBounds request that does not come from the internal
        //logical-size projection invalidates the stable rotation center.
        //
        //This covers normal moves/resizes from code and design-time resize
        //operations. The next Angle / Orientation change must capture the new
        //current center instead of reusing the center from an older rotation
        //sequence.
        //----------------------------------------------------------------------
        InvalidateRotationCenter;

        If (csDesigning In ComponentState) And
           Not (csLoading In ComponentState) And
           Not FUpdatingBounds And
           ((GetAsyncKeyState(VK_LBUTTON) And $8000) <> 0) Then
            TryApplyDesignerResize(
                ALeft,
                ATop,
                AWidth,
                AHeight);
    End;

    Inherited SetBounds(
        ALeft,
        ATop,
        AWidth,
        AHeight);

    UpdateWindowRegion;
End;

Procedure TRotatedEditCore.SetText(Const Value: String);
Var
    LNewText: String;
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Assigns text programmatically.
    //
    //TRotatedEdit is single-line. CR/LF are always stripped. CharCase and
    //NumbersOnly are also applied here so programmatic assignment follows the
    //same public contract as keyboard and paste input.
    //
    //MaxLength is enforced on assignment as well. This keeps the public Text
    //property consistent with the edit engine.
    //
    //OnCanChange is called even for programmatic assignment because it is the
    //central immediate veto point for Text mutation. OnEditingStart is not
    //raised here because assigning Text from code is not a user editing gesture.
    //-------------------------------------------------------------------------
    LNewText := NormalizeAssignedText(Value);

    If FText = LNewText Then
        Exit;

    If Not CanApplyTextChange(
        FText,
        LNewText) Then
        Exit;

    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    FText := LNewText;

    If FCaretIndex > Length(FText) Then
        FCaretIndex := Length(FText);

    If FSelStart > Length(FText) Then
        FSelStart := Length(FText);

    If FSelStart + FSelLength > Length(FText) Then
        FSelLength := Length(FText) - FSelStart;

    TextChanged;

    If (LOldCaretIndex <> FCaretIndex) Or
       (LOldSelStart <> FSelStart) Or
       (LOldSelLength <> FSelLength) Then
        SelectionChanged;

    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SetOrientation(Const Value: TRotatedEditOrientation);
Begin
    If FOrientation = Value Then
        Exit;

    FOrientation := Value;

    If FOrientation <> reoCustomAngle Then
        FAngle := TRotatedEditGeometry.OrientationToAngle(
            FOrientation,
            FAngle);

    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;
    FUseInternalOrigin := False;

    //-------------------------------------------------------------------------
    //Angle/orientation coherence rule.
    //
    //Changing Orientation changes the projection of the same logical edit
    //surface. LogicalLength and LogicalThickness remain the source values, but
    //the external VCL BoundsRect must be recomputed so the newly projected
    //surface is not clipped.
    //
    //Important positioning rule:
    //- LogicalLength / LogicalThickness changes keep the existing anchored
    //  visual point stable. This is handled by ApplyExternalBoundsFromLogicalSize.
    //
    //- Angle / Orientation changes keep the external center stable. A rotation
    //  is a change of projection, not a change of logical size. Preserving
    //  Left/Top or an anchor-dependent point makes the component visually jump
    //  while rotating, especially from a demo trackbar or the Object Inspector.
    //
    //When AutoSizeBounds is disabled, the external BoundsRect intentionally
    //remains owned by the caller/designer and only the window region is updated.
    //-------------------------------------------------------------------------
    InvalidateBackgroundCache;
    InvalidateHoverCursor;

    //-------------------------------------------------------------------------
    //DFM loading guard.
    //
    //Published property setters are called while Delphi reads the DFM. During
    //that phase, Left / Top / Width / Height already come from the streamed DFM
    //and must remain authoritative. Recomputing external bounds here would move
    //the control merely because the designer switched from text view back to
    //form view, or because the application started at runtime.
    //
    //Therefore Angle / Orientation setters only store their values while
    //csLoading is active. Loaded will rebuild the window region without changing
    //the external BoundsRect.
    //-------------------------------------------------------------------------
    If csLoading In ComponentState Then
        Exit;

    If FAutoSizeBounds Then
        ApplyExternalBoundsFromLogicalSizeKeepingCenter
    Else
        UpdateWindowRegion;

    Invalidate;
End;

Procedure TRotatedEditCore.SetAngle(Const Value: Double);
Begin
    If Abs(FAngle - Value) < 0.0001 Then
        Exit;

    FAngle := TRotatedEditGeometry.NormalizeAngle(Value);
    FOrientation := reoCustomAngle;

    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;
    FUseInternalOrigin := False;

    //-------------------------------------------------------------------------
    //Angle/orientation coherence rule.
    //
    //Changing Angle changes only the projection of the current logical edit
    //surface. It must not silently change LogicalLength or LogicalThickness,
    //but the external VCL BoundsRect has to be recomputed when AutoSizeBounds
    //is active. This keeps the public contract consistent:
    //
    //  LogicalLength / LogicalThickness / Angle -> external BoundsRect
    //
    //Important positioning rule:
    //- LogicalLength / LogicalThickness changes keep the existing anchored
    //  visual point stable.
    //
    //- Angle / Orientation changes keep the external center stable. A rotation
    //  is perceived as a turn around the component itself, not as a resize from
    //  its top-left corner. This prevents visible jumps while the angle is
    //  edited interactively.
    //
    //Without this recalculation, an angle change made from the Object Inspector
    //or from code can leave the component hosted in the old rectangle, causing
    //clipping and an incorrect design-time preview.
    //-------------------------------------------------------------------------
    InvalidateBackgroundCache;
    InvalidateHoverCursor;

    //-------------------------------------------------------------------------
    //DFM loading guard.
    //
    //Angle is a published property. Its setter is therefore invoked while the
    //DFM is being read. At that time the streamed BoundsRect must not be
    //recalculated from LogicalLength / LogicalThickness / Angle. Otherwise a
    //simple text/form designer round-trip can modify Left / Top for rotated
    //controls.
    //-------------------------------------------------------------------------
    If csLoading In ComponentState Then
        Exit;

    If FAutoSizeBounds Then
        ApplyExternalBoundsFromLogicalSizeKeepingCenter
    Else
        UpdateWindowRegion;

    Invalidate;
End;

Procedure TRotatedEditCore.SetLogicalLength(Const Value: Integer);
Begin
    If FLogicalLength = Value Then
        Exit;

    FLogicalLength := Value;

    If FLogicalLength < 1 Then
        FLogicalLength := 1;

    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;

    InvalidateBackgroundCache;
    InvalidateRotationCenter;

    //-------------------------------------------------------------------------
    //DFM loading guard.
    //
    //LogicalLength is persisted together with Left / Top / Width / Height. While
    //loading, the external BoundsRect belongs to the DFM and must not be rebuilt
    //by the logical-size engine. Explicit user changes after loading still use
    //ApplyExternalBoundsFromLogicalSize as before.
    //-------------------------------------------------------------------------
    If csLoading In ComponentState Then
        Exit;

    ApplyExternalBoundsFromLogicalSize;
    Invalidate;
End;

Procedure TRotatedEditCore.SetLogicalThickness(Const Value: Integer);
Var
    LLogicalThickness: Integer;
Begin
    //-------------------------------------------------------------------------
    //Manual logical-thickness update.
    //
    //When AutoSize is enabled, LogicalThickness follows the preferred native-like
    //single-line edit height, as TEdit does with Height. To test or intentionally
    //clip a thinner edit band, callers must first set AutoSize to False.
    //-------------------------------------------------------------------------
    LLogicalThickness := Value;

    If LLogicalThickness < 1 Then
        LLogicalThickness := 1;

    If FAutoSize And Not (csLoading In ComponentState) Then
        LLogicalThickness := ResolvePreferredLogicalThickness;

    If FLogicalThickness = LLogicalThickness Then
        Exit;

    FLogicalThickness := LLogicalThickness;

    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;

    InvalidateBackgroundCache;
    InvalidateRotationCenter;

    //-------------------------------------------------------------------------
    //DFM loading guard.
    //
    //LogicalThickness follows the same rule as LogicalLength: loading a streamed
    //property must not move the streamed external BoundsRect. Only explicit
    //post-load user/code changes are allowed to drive the external bounds.
    //-------------------------------------------------------------------------
    If csLoading In ComponentState Then
        Exit;

    ApplyExternalBoundsFromLogicalSize;
    Invalidate;
End;


Procedure TRotatedEditCore.SetAutoSize(Const Value: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Enables or disables native-like automatic logical thickness.
    //
    //The property intentionally follows the TEdit name. In this rotated control
    //it does not mean "resize the rectangular host directly"; it means "keep the
    //single-line edit surface thickness at the expected native TEdit height for
    //the current font/border/style". AutoSizeBounds remains responsible for the
    //external projected Width / Height.
    //-------------------------------------------------------------------------
    If FAutoSize = Value Then
        Exit;

    FAutoSize := Value;

    If csLoading In ComponentState Then
        Exit;

    If FAutoSize Then
        ApplyAutoSizeLogicalThickness
    Else Begin
        InvalidateContentBitmap;
        Invalidate;
    End;
End;

Procedure TRotatedEditCore.SetAutoSizeBounds(Const Value: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Controls whether logical size drives the external bounds after explicit
    //logical edits / DFM load.
    //
    //When enabled, changing LogicalLength / LogicalThickness updates Width /
    //Height. During direct designer mouse resizing, the external rectangle still
    //belongs to Delphi and the internal surface adapts to it.
    //-------------------------------------------------------------------------
    If FAutoSizeBounds = Value Then
        Exit;

    FAutoSizeBounds := Value;
    InvalidateRotationCenter;

    //-------------------------------------------------------------------------
    //DFM loading guard.
    //
    //AutoSizeBounds controls whether later logical edits resize the external
    //host rectangle. Reading the property itself from the DFM is not such a
    //logical edit and must never reposition the component.
    //-------------------------------------------------------------------------
    If csLoading In ComponentState Then
        Exit;

    If FAutoSizeBounds Then
        ApplyExternalBoundsFromLogicalSize
    Else
        UpdateWindowRegion;

    Invalidate;
End;

Procedure TRotatedEditCore.SetReadOnly(Const Value: Boolean);
Begin
    If FReadOnly = Value Then
        Exit;

    FReadOnly := Value;
    InvalidateBackgroundCache;
    Invalidate;
End;

Procedure TRotatedEditCore.SetMaxLength(Const Value: Integer);
Var
    LMaxLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Updates the maximum text length.
    //
    //When the new limit is shorter than the current text, the text is truncated
    //immediately. This is stricter than a native EDIT handle, but it is safer for
    //an owner-drawn component because every input path stays consistent.
    //-------------------------------------------------------------------------
    LMaxLength := Value;

    If LMaxLength < 0 Then
        LMaxLength := 0;

    If FMaxLength = LMaxLength Then
        Exit;

    FMaxLength := LMaxLength;

    If (FMaxLength > 0) And (Length(FText) > FMaxLength) Then
        SetText(Copy(FText, 1, FMaxLength));
End;

Procedure TRotatedEditCore.SetAlignment(Const Value: TAlignment);
Begin
    //-------------------------------------------------------------------------
    //Changes canonical text alignment.
    //
    //Alignment is resolved by the layout engine in canonical coordinates. The
    //same rule therefore works for horizontal, vertical and arbitrary angles.
    //-------------------------------------------------------------------------
    If FAlignment = Value Then
        Exit;

    FAlignment := Value;

    FScrollOffset := 0;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SetCharCase(Const Value: TEditCharCase);
Begin
    //-------------------------------------------------------------------------
    //Changes the input character-case policy.
    //
    //Existing text is normalized immediately so the visual state and the public
    //Text property remain coherent after the property changes.
    //-------------------------------------------------------------------------
    If FCharCase = Value Then
        Exit;

    FCharCase := Value;
    SetText(FText);
End;

Procedure TRotatedEditCore.SetTextHint(Const Value: String);
Begin
    //-------------------------------------------------------------------------
    //Sets the placeholder text displayed when Text is empty.
    //
    //The hint is rendering-only. It never participates in caret placement,
    //selection, clipboard operations or Text itself.
    //-------------------------------------------------------------------------
    If FTextHint = Value Then
        Exit;

    FTextHint := Value;

    If FText = '' Then Begin
        InvalidateContentBitmap;
        Invalidate;
    End;
End;

Procedure TRotatedEditCore.SetNumbersOnly(Const Value: Boolean);
Begin
    //-------------------------------------------------------------------------
    //Changes the numeric input policy.
    //
    //This is intentionally equivalent to a simple "digits only" edit. It does
    //not implement signs, decimal separators or locale-specific number formats.
    //A richer numeric mode should be a separate future feature.
    //-------------------------------------------------------------------------
    If FNumbersOnly = Value Then
        Exit;

    FNumbersOnly := Value;
    SetText(FText);
End;

Function TRotatedEditCore.NormalizeAssignedText(Const AText: String): String;
Begin
    //-------------------------------------------------------------------------
    //Normalizes text assigned through the public Text property.
    //
    //Single-line rule:
    //CR/LF are removed.
    //
    //Input policy rule:
    //CharCase and NumbersOnly are applied here so SetText, paste and keyboard
    //input converge toward the same stored value.
    //-------------------------------------------------------------------------
    Result := NormalizeInsertedText(AText);

    If (FMaxLength > 0) And (Length(Result) > FMaxLength) Then
        Result := Copy(Result, 1, FMaxLength);
End;

Function TRotatedEditCore.NormalizeInsertedText(Const AText: String): String;
Var
    I: Integer;
    LChar: Char;
Begin
    //-------------------------------------------------------------------------
    //Normalizes text inserted by keyboard or clipboard.
    //
    //This method does not enforce MaxLength because the edit engine already
    //limits insertion against the current text and selection. It only applies
    //single-line filtering, NumbersOnly and CharCase.
    //-------------------------------------------------------------------------
    Result := '';

    For I := 1 To Length(AText) Do Begin
        LChar := AText[I];

        If (LChar = #13) Or (LChar = #10) Then
            Continue;

        If FNumbersOnly And Not (LChar In ['0'..'9']) Then
            Continue;

        Case FCharCase Of
            ecUpperCase:
                LChar := UpCase(LChar);

            ecLowerCase:
                LChar := LowerCase(LChar)[1];
        End;

        Result := Result + LChar;
    End;
End;

Procedure TRotatedEditCore.SetCaretIndex(Const Value: Integer);
Var
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    FCaretIndex := Value;

    If FCaretIndex < 0 Then
        FCaretIndex := 0;

    If FCaretIndex > Length(FText) Then
        FCaretIndex := Length(FText);

    FSelStart := FCaretIndex;
    FSelLength := 0;
    FSelectionAnchor := FCaretIndex;

    If (LOldCaretIndex <> FCaretIndex) Or
       (LOldSelStart <> FSelStart) Or
       (LOldSelLength <> FSelLength) Then
        SelectionChanged;

    FCaretController.ResetBlink;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SetSelStart(Const Value: Integer);
Var
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    FSelStart := Value;

    If FSelStart < 0 Then
        FSelStart := 0;

    If FSelStart > Length(FText) Then
        FSelStart := Length(FText);

    If FSelStart + FSelLength > Length(FText) Then
        FSelLength := Length(FText) - FSelStart;

    If (LOldSelStart <> FSelStart) Or
       (LOldSelLength <> FSelLength) Then
        SelectionChanged;

    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SetSelLength(Const Value: Integer);
Var
    LOldSelLength: Integer;
Begin
    LOldSelLength := FSelLength;

    FSelLength := Value;

    If FSelLength < 0 Then
        FSelLength := 0;

    If FSelStart + FSelLength > Length(FText) Then
        FSelLength := Length(FText) - FSelStart;

    If LOldSelLength <> FSelLength Then
        SelectionChanged;

    InvalidateContentBitmap;
    Invalidate;
End;


Function TRotatedEditCore.GetSelText: String;
Begin
    //-------------------------------------------------------------------------
    //Returns the text currently covered by the normalized selection range.
    //
    //TRotatedEdit exposes SelStart / SelLength as zero-based values, while the
    //Delphi Copy function is one-based. The +1 conversion is therefore kept in
    //this single helper to avoid duplicating that convention in user code.
    //-------------------------------------------------------------------------
    If FSelLength <= 0 Then Begin
        Result := '';
        Exit;
    End;

    Result := Copy(
        FText,
        FSelStart + 1,
        FSelLength);
End;

Procedure TRotatedEditCore.SetSelText(Const Value: String);
Var
    LState: TRotatedEditEditState;
Begin
    //-------------------------------------------------------------------------
    //Replaces the current selection with the supplied text.
    //
    //This follows the same editing pipeline as paste and keyboard input:
    //- ReadOnly is honored;
    //- inserted text is normalized by NormalizeInsertedText;
    //- MaxLength is enforced by TRotatedEditEditEngine.InsertText;
    //- OnCanChange can veto the final text candidate;
    //- OnEditingStart / OnChange / OnSelectionChange are raised by
    //  ApplyEditState when the mutation is accepted.
    //
    //When SelLength is zero, this behaves as an insertion at CaretIndex, which
    //matches the usual edit-control meaning of assigning SelText.
    //-------------------------------------------------------------------------
    If FReadOnly Then
        Exit;

    LState.Text := FText;
    LState.CaretIndex := FCaretIndex;
    LState.SelStart := FSelStart;
    LState.SelLength := FSelLength;
    LState.ReadOnly := FReadOnly;
    LState.MaxLength := FMaxLength;

    TRotatedEditEditEngine.InsertText(
        LState,
        NormalizeInsertedText(Value));

    ApplyEditState(
        LState.Text,
        LState.CaretIndex,
        LState.SelStart,
        LState.SelLength);
End;

Procedure TRotatedEditCore.SetBorderStyle(Const Value: TBorderStyle);
Begin
    If FBorderStyle = Value Then
        Exit;

    FBorderStyle := Value;

    InvalidatePreferredLogicalThickness;
    InvalidateBackgroundCache;

    If FAutoSize Then
        ApplyAutoSizeLogicalThickness
    Else
        UpdateWindowRegion;

    Invalidate;
End;

Procedure TRotatedEditCore.SetBorderColor(Const Value: TColor);
Begin
    //-------------------------------------------------------------------------
    //Changes the border color used in custom palette mode.
    //
    //BorderColor is intentionally simple. The component does not emulate
    //custom 3D border emulation/WS_EX_CLIENTEDGE; it draws either a styled frame or a flat custom
    //frame depending on PaletteMode.
    //-------------------------------------------------------------------------
    If FBorderColor = Value Then
        Exit;

    FBorderColor := Value;

    InvalidateBackgroundCache;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SetPaletteMode(Const Value: TRotatedEditPaletteMode);
Begin
    //-------------------------------------------------------------------------
    //Changes the palette source.
    //
    //TRotatedEdit is an owner-drawn projected edit. It does not expose the full
    //VCL PaletteMode matrix because that creates ambiguous hybrid states for a
    //small edit control.
    //
    //Instead, the public rule is explicit:
    //- repmStyle  = ask the active VCL style for the edit surface colors;
    //- repmCustom = use Color, Font.Color and BorderColor.
    //
    //Changing this property affects the canonical background and the composed
    //content bitmap.
    //-------------------------------------------------------------------------
    If FPaletteMode = Value Then
        Exit;

    FPaletteMode := Value;

    InvalidatePreferredLogicalThickness;
    InvalidateBackgroundCache;
    InvalidateContentBitmap;

    If FAutoSize Then
        ApplyAutoSizeLogicalThickness;

    Invalidate;
End;

Procedure TRotatedEditCore.SetRenderBackendKind(
    Const Value: TRotatedEditRenderBackendKind);
Begin
    If FRenderBackendKind = Value Then
        Exit;

    FRenderBackendKind := Value;

    //---------------------------------------------------------------------
    //Backend changes invalidate every cached bitmap and every text-metric
    //dependent value. Changing the requested backend may switch between
    //different native rendering engines, so this invalidation rule is deliberately written as
    //the future-safe rule for the real Direct2D/DirectWrite backend.
    //---------------------------------------------------------------------
    RecreateRenderBackend;
    InvalidateBackgroundCache;
    InvalidateContentBitmap;
    InvalidatePreferredLogicalThickness;
    InvalidateHoverCursor;
    UpdateWindowRegion;
    Invalidate;
End;

Procedure TRotatedEditCore.RecreateRenderBackend;
Begin
    FRenderBackend := CreateRotatedEditRenderBackend(FRenderBackendKind);

    //---------------------------------------------------------------------
    // Keep backend state traces out of the published API. OutputDebugString is
    // intentionally used as a lightweight development/debug stream: it can be
    // observed from the IDE or from tools such as DebugView, but it does not
    // change the component contract and it does not introduce another
    // design-time property.
    //---------------------------------------------------------------------
    TraceRenderBackendState('backend recreated');
End;

Procedure TRotatedEditCore.TraceRenderBackendState(Const AReason: String);
Var
    LBackendName: String;
    LControlName: String;
    LRequestedBackendName: String;
Begin
    //-------------------------------------------------------------------------
    // Emits a lightweight backend diagnostic in the Windows debug stream.
    //
    // The method is deliberately private and side-effect free. It makes the
    // requested backend and the effective backend state visible during
    // development without committing to a public diagnostic API. The backend
    // itself remains the source of truth for the readable active state through
    // IRotatedEditRenderBackend.GetBackendName.
    //
    // The trace also prints the requested published backend value. This matters
    // because rebDirect2D can legitimately fall back to GDI when Direct2D /
    // DirectWrite initialization or a Direct2D paint pass fails.
    //-------------------------------------------------------------------------
    If FRenderBackend = Nil Then
        LBackendName := '<none>'
    Else
        LBackendName := FRenderBackend.GetBackendName;

    Case FRenderBackendKind Of
        rebGDI:
            LRequestedBackendName := 'rebGDI';

        rebDirect2D:
            LRequestedBackendName := 'rebDirect2D';
    Else
        LRequestedBackendName := '<unknown>';
    End;

    LControlName := Name;

    If LControlName = '' Then
        LControlName := ClassName;

    OutputDebugString(PChar(Format(
        'VclRotatedEdit: %s: %s: requested=%s; active=%s',
        [
            LControlName,
            AReason,
            LRequestedBackendName,
            LBackendName
        ])));
End;

Procedure TRotatedEditCore.SetTextPaddingStart(Const Value: Integer);
Begin
    //-------------------------------------------------------------------------
    //Changes the logical padding at the start of the text flow.
    //
    //The public property is expressed in text-flow terms. Internally it maps to
    //the canonical left/right padding before rotation.
    //
    //Padding affects CanonicalContentRect, text origin, selection geometry and
    //hit-testing. The scroll offset is reset because a stale scroll value can
    //hide the effect of the new padding while the text still fits. InvalidateBackgroundCache also invalidates the composed
    //content bitmap by contract.
    //-------------------------------------------------------------------------
    FPaddingLeft := Value;

    If FPaddingLeft < 0 Then
        FPaddingLeft := 0;

    FScrollOffset := 0;

    InvalidateBackgroundCache;
    UpdateWindowRegion;
    Invalidate;
End;

Procedure TRotatedEditCore.SetTextPaddingEnd(Const Value: Integer);
Begin
    //-------------------------------------------------------------------------
    //Changes the logical padding at the end of the text flow.
    //
    //The public property is expressed in text-flow terms. Internally it maps to
    //the canonical left/right padding before rotation.
    //
    //Padding affects CanonicalContentRect, text origin, selection geometry and
    //hit-testing. The scroll offset is reset because a stale scroll value can
    //hide the effect of the new padding while the text still fits. InvalidateBackgroundCache also invalidates the composed
    //content bitmap by contract.
    //-------------------------------------------------------------------------
    FPaddingRight := Value;

    If FPaddingRight < 0 Then
        FPaddingRight := 0;

    FScrollOffset := 0;

    InvalidateBackgroundCache;
    UpdateWindowRegion;
    Invalidate;
End;

Procedure TRotatedEditCore.SetCaretThickness(Const Value: Integer);
Begin
    FCaretThickness := Value;

    If FCaretThickness < 1 Then
        FCaretThickness := 1;

    Invalidate;
End;

Procedure TRotatedEditCore.SetShowDebugBounds(Const Value: Boolean);
Begin
    If FShowDebugBounds = Value Then
        Exit;

    FShowDebugBounds := Value;
    Invalidate;
End;

Procedure TRotatedEditCore.SetUseWindowRegion(Const Value: Boolean);
Begin
    If FUseWindowRegion = Value Then
        Exit;

    FUseWindowRegion := Value;

    //-------------------------------------------------------------------------
    //Changing this property changes the native hit-test shape of the control,
    //not only its rendering. The region must be updated immediately.
    //-------------------------------------------------------------------------
    UpdateWindowRegion;
    Invalidate;
End;

Procedure TRotatedEditCore.InvalidateBackgroundCache;
Begin
    //-------------------------------------------------------------------------
    //Invalidates the canonical background/border surface.
    //
    //Important dependency rule:
    //FContentBitmap is composed from FBackgroundBitmap. Therefore every
    //background invalidation must also invalidate the content bitmap.
    //
    //This is especially important for TextPaddingStart/TextPaddingEnd: changing
    //a padding modifies CanonicalContentRect and text origin. If only the
    //background bitmap is invalidated, the already-composed content bitmap can
    //remain visually unchanged and make it look as if the padding no longer
    //works.
    //
    //Do not modify FUseWindowRegion here. Region ownership is handled by
    //SetUseWindowRegion / UpdateWindowRegion / ClearWindowRegion.
    //-------------------------------------------------------------------------
    FBackgroundBitmapValid := False;
    FContentBitmapValid := False;
End;

Procedure TRotatedEditCore.InvalidateContentBitmap;
Begin
    //-------------------------------------------------------------------------
    //Invalidates only the canonical content surface.
    //
    //This is deliberately separate from InvalidateBackgroundCache:
    //- background changes when style, color, border or logical size changes;
    //- content surface changes when text, selection, font, text color or scroll changes;
    //- caret blink must not invalidate either cache.
    //
    //The current implementation keeps the invalidation rule simple. Later, this
    //method can be expanded to support selected-text recoloring or IME overlays.
    //-------------------------------------------------------------------------

    FContentBitmapValid := False;
End;



Procedure TRotatedEditCore.InvalidatePreferredLogicalThickness;
Begin
    //-------------------------------------------------------------------------
    //Invalidates the cached native-like single-line edit height.
    //
    //The value depends on Font, BorderStyle and the active VCL style. It is not
    //a paint cache: it is a layout reference used both by AutoSize and by the
    //"manual thickness smaller than normal" clipping rule.
    //-------------------------------------------------------------------------
    FPreferredLogicalThicknessValid := False;
End;

Function TRotatedEditCore.ResolvePreferredLogicalThickness: Integer;
Var
    LEdit: TEdit;
    LPreferredHeight: Integer;
Begin
    //-------------------------------------------------------------------------
    //Resolves the normal single-line edit height by asking a real VCL TEdit.
    //
    //This is intentionally not guessed from tmHeight, TextHeight('Wg') or a
    //hard-coded padding table. Native/styled TEdit height depends on font
    //metrics, border style, DPI, active VCL style and parent style context.
    //
    //Important compatibility rule:
    //The temporary TEdit must be attached to the same parent window/context as
    //the rotated edit whenever possible. A TEdit created only with
    //ParentWindow := GetDesktopWindow can report a smaller AutoSize height on
    //some styled configurations, because it does not resolve the same themed
    //edit frame/content metrics as a normal TEdit placed on the form. In the
    //reported case this returned 23 while a real styled TEdit used 25.
    //
    //The returned value is a LOGICAL thickness: at Angle = 0 it corresponds to
    //the normal TEdit outer height, including the edit border. The rotated
    //physical host bounds are still computed later by
    //ApplyExternalBoundsFromLogicalSize.
    //-------------------------------------------------------------------------
    If FPreferredLogicalThicknessValid Then Begin
        Result := FPreferredLogicalThickness;
        Exit;
    End;

    LPreferredHeight := FLogicalThickness;

    LEdit := TEdit.Create(Nil);
    Try
        //---------------------------------------------------------------------
        //Attach the probe edit to the real parent when available. This makes
        //the VCL style service, DPI context and non-client/border sizing path
        //match a normal TEdit on the same form.
        //
        //The fallback ParentWindow path is kept only for early construction or
        //test harnesses where the rotated edit has no parent yet.
        //---------------------------------------------------------------------
        LEdit.Visible := False;

        If Parent <> Nil Then
            LEdit.Parent := Parent
        Else
            LEdit.ParentWindow := GetDesktopWindow;

        LEdit.Font.Assign(Font);
        LEdit.BorderStyle := FBorderStyle;
        LEdit.StyleElements := StyleElements;
        LEdit.AutoSize := True;

        //---------------------------------------------------------------------
        //Force handle creation after all relevant properties have been copied.
        //The native EDIT/VCL AutoSize logic can then include the actual styled
        //border and the current parent/DPI context in the returned Height.
        //---------------------------------------------------------------------
        LEdit.HandleNeeded;
        LPreferredHeight := LEdit.Height;
    Finally
        LEdit.Free;
    End;

    If LPreferredHeight < 1 Then
        LPreferredHeight := FLogicalThickness;

    If LPreferredHeight < 1 Then
        LPreferredHeight := 1;

    FPreferredLogicalThickness := LPreferredHeight;
    FPreferredLogicalThicknessValid := True;

    Result := FPreferredLogicalThickness;
End;

Procedure TRotatedEditCore.ApplyAutoSizeLogicalThickness;
Var
    LPreferredThickness: Integer;
Begin
    //-------------------------------------------------------------------------
    //Applies AutoSize to the logical thickness only.
    //
    //AutoSizeBounds and AutoSize are deliberately separate:
    //- AutoSize decides the canonical edit thickness from the current font and
    //  border, like TEdit does for its Height;
    //- AutoSizeBounds decides whether the outer rotated VCL rectangle is rebuilt
    //  from the logical dimensions.
    //-------------------------------------------------------------------------
    If Not FAutoSize Then
        Exit;

    LPreferredThickness := ResolvePreferredLogicalThickness;

    If LPreferredThickness < 1 Then
        Exit;

    If FLogicalThickness = LPreferredThickness Then
        Exit;

    FLogicalThickness := LPreferredThickness;

    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;

    InvalidateBackgroundCache;
    InvalidateRotationCenter;

    If csLoading In ComponentState Then
        Exit;

    ApplyExternalBoundsFromLogicalSize;
    Invalidate;
End;

Procedure TRotatedEditCore.CalcProjectedEditBoundsForLogicalSize(
    ALogicalLength: Integer;
    ALogicalThickness: Integer;
    Out AMinX: Double;
    Out AMinY: Double;
    Out AMaxX: Double;
    Out AMaxY: Double);
Var
    LRad: Double;
    LCos: Double;
    LSin: Double;
    X0: Double;
    Y0: Double;
    X1: Double;
    Y1: Double;
    X2: Double;
    Y2: Double;
    X3: Double;
    Y3: Double;
Begin
    //-------------------------------------------------------------------------
    //Returns the projected bounds of the logical edit rectangle around the
    //canonical origin.
    //
    //This helper is intentionally independent from ClientRect. It answers:
    //"How large is the projected rotated edit surface for this logical size and
    //angle?"
    //
    //The returned bounds are relative to ActualOrigin. A caller can therefore
    //choose its own placement policy:
    //- centered in ClientRect;
    //- fitted to the external bounds;
    //- anchored to a stable parent coordinate.
    //-------------------------------------------------------------------------
    If ALogicalLength < 1 Then
        ALogicalLength := 1;

    If ALogicalThickness < 1 Then
        ALogicalThickness := 1;

    LRad := TRotatedEditGeometry.NormalizeAngle(FAngle) * Pi / 180.0;
    LCos := Cos(LRad);
    LSin := Sin(LRad);

    X0 := 0.0;
    Y0 := 0.0;

    X1 := ALogicalLength * LCos;
    Y1 := -ALogicalLength * LSin;

    X2 := (ALogicalLength * LCos) + (ALogicalThickness * LSin);
    Y2 := (-ALogicalLength * LSin) + (ALogicalThickness * LCos);

    X3 := ALogicalThickness * LSin;
    Y3 := ALogicalThickness * LCos;

    AMinX := Min(Min(X0, X1), Min(X2, X3));
    AMaxX := Max(Max(X0, X1), Max(X2, X3));
    AMinY := Min(Min(Y0, Y1), Min(Y2, Y3));
    AMaxY := Max(Max(Y0, Y1), Max(Y2, Y3));
End;

Procedure TRotatedEditCore.ResolveExternalBoundsAnchorFractions(
    Out AAnchorX: Double;
    Out AAnchorY: Double);
Begin
    //-------------------------------------------------------------------------
    //Chooses which visual point must remain stable when LogicalLength or
    //LogicalThickness is changed directly.
    //
    //This is the inverse path of the designer-resize logic:
    //- designer resize changes the external bounds and adapts the internal edit;
    //- logical resize changes the internal edit and adapts the external bounds.
    //
    //Anchors rule
    //------------
    //For alNone, VCL Anchors are used as a hint for the stable point:
    //- left-only  -> keep the left side stable;
    //- right-only -> keep the right side stable;
    //- both/neither -> keep the center stable.
    //
    //Align rule
    //----------
    //When Align is not alNone, the parent layout owns the external bounds. This
    //helper still returns a meaningful default, but ApplyExternalBoundsFrom-
    //LogicalSize will not force SetBounds in that case.
    //-------------------------------------------------------------------------
    AAnchorX := 0.5;
    AAnchorY := 0.5;

    If Align <> alNone Then
        Exit;

    If (akLeft In Anchors) And Not (akRight In Anchors) Then
        AAnchorX := 0.0
    Else If (akRight In Anchors) And Not (akLeft In Anchors) Then
        AAnchorX := 1.0
    Else
        AAnchorX := 0.5;

    If (akTop In Anchors) And Not (akBottom In Anchors) Then
        AAnchorY := 0.0
    Else If (akBottom In Anchors) And Not (akTop In Anchors) Then
        AAnchorY := 1.0
    Else
        AAnchorY := 0.5;
End;

Procedure TRotatedEditCore.ResolveCurrentProjectedEditBoundsInParent(
    Out ALeft: Double;
    Out ATop: Double;
    Out ARight: Double;
    Out ABottom: Double);
Var
    LMinX: Double;
    LMinY: Double;
    LMaxX: Double;
    LMaxY: Double;
    LOriginX: Double;
    LOriginY: Double;
    LProjectedWidth: Double;
    LProjectedHeight: Double;
Begin
    //-------------------------------------------------------------------------
    //Returns the current projected edit bounds in parent-client coordinates.
    //
    //If an internal origin is active, it is used directly. Otherwise the layout
    //centers the projected edit surface inside ClientRect, so this helper uses
    //the same centering rule.
    //-------------------------------------------------------------------------
    CalcProjectedEditBoundsForLogicalSize(
        FLogicalLength,
        FLogicalThickness,
        LMinX,
        LMinY,
        LMaxX,
        LMaxY);

    LProjectedWidth := LMaxX - LMinX;
    LProjectedHeight := LMaxY - LMinY;

    If FUseInternalOrigin Then Begin
        LOriginX := FInternalOriginX;
        LOriginY := FInternalOriginY;
    End Else Begin
        LOriginX := (ClientWidth - LProjectedWidth) / 2.0 - LMinX;
        LOriginY := (ClientHeight - LProjectedHeight) / 2.0 - LMinY;
    End;

    ALeft := Left + LOriginX + LMinX;
    ATop := Top + LOriginY + LMinY;
    ARight := Left + LOriginX + LMaxX;
    ABottom := Top + LOriginY + LMaxY;
End;

Procedure TRotatedEditCore.ApplyExternalBoundsFromLogicalSize;
Var
    LOldLeft: Double;
    LOldTop: Double;
    LOldRight: Double;
    LOldBottom: Double;
    LStableX: Double;
    LStableY: Double;
    LAnchorX: Double;
    LAnchorY: Double;
    LMinX: Double;
    LMinY: Double;
    LMaxX: Double;
    LMaxY: Double;
    LProjectedWidth: Double;
    LProjectedHeight: Double;
    LRequiredWidth: Integer;
    LRequiredHeight: Integer;
    LNewLeft: Integer;
    LNewTop: Integer;
Begin
    //-------------------------------------------------------------------------
    //Applies the inverse path: logical size -> external VCL bounds.
    //
    //There are now two resize directions:
    //
    //1. External resize path
    //   The Delphi designer changes BoundsRect. TRotatedEdit derives its
    //   internal edit surface from the external rectangle.
    //
    //2. Internal resize path
    //   The user changes LogicalLength / LogicalThickness in the Object
    //   Inspector or in code. In that case the logical edit surface is the
    //   source of truth and the external BoundsRect must be resized to contain
    //   it.
    //
    //Stable-position rule
    //--------------------
    //When the logical size changes, the edit must not appear to jump. We first
    //resolve a stable visual point from the current projected edit bounds, using
    //Anchors as a hint. Then we compute the new tight external bounds and place
    //them so the same visual point remains at the same parent coordinate.
    //
    //Align rule
    //----------
    //If Align is not alNone, the parent layout owns the external BoundsRect. In
    //that case we do not call SetBounds; we only reset internal placement and
    //refresh the region/caches.
    //-------------------------------------------------------------------------
    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;

    ResolveCurrentProjectedEditBoundsInParent(
        LOldLeft,
        LOldTop,
        LOldRight,
        LOldBottom);

    ResolveExternalBoundsAnchorFractions(
        LAnchorX,
        LAnchorY);

    LStableX := LOldLeft + ((LOldRight - LOldLeft) * LAnchorX);
    LStableY := LOldTop + ((LOldBottom - LOldTop) * LAnchorY);

    CalcProjectedEditBoundsForLogicalSize(
        FLogicalLength,
        FLogicalThickness,
        LMinX,
        LMinY,
        LMaxX,
        LMaxY);

    LProjectedWidth := LMaxX - LMinX;
    LProjectedHeight := LMaxY - LMinY;

    LRequiredWidth := Ceil(LProjectedWidth);
    LRequiredHeight := Ceil(LProjectedHeight);

    If LRequiredWidth < 1 Then
        LRequiredWidth := 1;

    If LRequiredHeight < 1 Then
        LRequiredHeight := 1;

    //---------------------------------------------------------------------
    //The external bounds become a tight host for the projected edit surface.
    //The internal origin is therefore simply the inverse projected min corner.
    //---------------------------------------------------------------------
    FUseInternalOrigin := True;
    FInternalOriginX := -LMinX;
    FInternalOriginY := -LMinY;

    If Align <> alNone Then Begin
        InvalidateBackgroundCache;
        UpdateWindowRegion;
        Exit;
    End;

    LNewLeft := Round(LStableX - (LRequiredWidth * LAnchorX));
    LNewTop := Round(LStableY - (LRequiredHeight * LAnchorY));

    FApplyingLogicalBounds := True;
    FUpdatingBounds := True;
    Try
        SetBounds(
            LNewLeft,
            LNewTop,
            LRequiredWidth,
            LRequiredHeight);
    Finally
        FUpdatingBounds := False;
        FApplyingLogicalBounds := False;
    End;

    UpdateWindowRegion;
End;

Procedure TRotatedEditCore.ApplyExternalBoundsFromLogicalSizeKeepingCenter;
Var
    LNewWidth: Integer;
    LNewHeight: Integer;
    LNewLeft: Integer;
    LNewTop: Integer;
Begin
    //-------------------------------------------------------------------------
    //Recomputes the external BoundsRect after an Angle / Orientation change
    //while preserving a stable floating-point external center.
    //
    //Why a persistent center is required
    //----------------------------------
    //A BoundsRect is integer based, but its real geometric center can be a
    //half-pixel value whenever Width or Height is odd:
    //
    //  Left = 10, Width = 101  ->  CenterX = 60.5
    //
    //If every angle step recomputes the center from the current integer bounds,
    //the half-pixel information can be rounded away differently as projected
    //Width/Height alternate between odd and even values. When the angle is
    //changed several times in a row, this produces a small but visible drift.
    //
    //The rule is therefore:
    //- the first Angle / Orientation change captures the current external center
    //  as Double;
    //- following Angle / Orientation changes reuse the same center;
    //- any unrelated external bounds or logical-size change invalidates that
    //  stored center.
    //
    //Important regression guard
    //--------------------------
    //Do NOT duplicate the logical-size -> external-bounds mathematics here.
    //That path is delicate because it must remain compatible with:
    //- LogicalLength / LogicalThickness edits from the Object Inspector;
    //- design-time resize sessions;
    //- internal/external bounds separation;
    //- the last-valid-geometry protection for invalid designer rectangles.
    //
    //The safe rule remains:
    //1. Capture/reuse the stable external center.
    //2. Let ApplyExternalBoundsFromLogicalSize perform the complete projection.
    //3. Translate the resulting rectangle so it is centered on the stable point.
    //-------------------------------------------------------------------------
    If Align <> alNone Then Begin
        InvalidateRotationCenter;
        ApplyExternalBoundsFromLogicalSize;
        Exit;
    End;

    If Not FRotationCenterValid Then Begin
        FRotationCenterX := (BoundsRect.Left + BoundsRect.Right) / 2.0;
        FRotationCenterY := (BoundsRect.Top + BoundsRect.Bottom) / 2.0;
        FRotationCenterValid := True;
    End;

    //---------------------------------------------------------------------
    //Use the single validated internal -> external resize engine.
    //This call updates Width / Height and the internal origin consistently.
    //---------------------------------------------------------------------
    ApplyExternalBoundsFromLogicalSize;

    LNewWidth := Width;
    LNewHeight := Height;

    If LNewWidth < 1 Then
        LNewWidth := 1;

    If LNewHeight < 1 Then
        LNewHeight := 1;

    LNewLeft := Round(FRotationCenterX - (LNewWidth / 2.0));
    LNewTop := Round(FRotationCenterY - (LNewHeight / 2.0));

    //---------------------------------------------------------------------
    //Only translate the already computed rectangle.
    //
    //Use inherited SetBounds deliberately. Calling the overridden SetBounds
    //would re-enter the design-time resize interpreter, whereas this operation
    //is not a designer resize; it is the final placement correction after a
    //programmatic Angle / Orientation change.
    //---------------------------------------------------------------------
    FApplyingLogicalBounds := True;
    FUpdatingBounds := True;
    Try
        Inherited SetBounds(
            LNewLeft,
            LNewTop,
            LNewWidth,
            LNewHeight);
    Finally
        FUpdatingBounds := False;
        FApplyingLogicalBounds := False;
    End;

    UpdateWindowRegion;
End;

Procedure TRotatedEditCore.InvalidateRotationCenter;
Begin
    //-------------------------------------------------------------------------
    //Forgets the stable center used by consecutive Angle / Orientation changes.
    //
    //This must be called whenever the component is moved/resized or when the
    //logical size changes. After such an operation, the next rotation sequence
    //must use the new current BoundsRect center as its reference.
    //
    //Do not call this from ApplyExternalBoundsFromLogicalSizeKeepingCenter after
    //its final inherited SetBounds translation: that translation is part of the
    //same rotation sequence and must keep using the same floating-point center.
    //-------------------------------------------------------------------------
    FRotationCenterValid := False;
    FRotationCenterX := 0.0;
    FRotationCenterY := 0.0;
End;


Procedure TRotatedEditCore.DefineProperties(AFiler: TFiler);
Begin
    Inherited DefineProperties(AFiler);

    //-------------------------------------------------------------------------
    //Hidden DFM state: internal edit origin.
    //
    //Left / Top / Width / Height describe the external VCL host rectangle.
    //LogicalLength / LogicalThickness / Angle describe the editable surface.
    //Most controls use the deterministic centered layout, which must not be
    //streamed as custom state.
    //
    //The internal origin is streamed only when FUseInternalOrigin is True. That
    //means a real custom placement exists, typically after a design-time resize
    //where the external designer rectangle is preserved while one logical axis
    //is adjusted.
    //
    //These properties are deliberately hidden from the Object Inspector. They
    //exist only to preserve a real internal/external bounds separation across a
    //DFM round-trip; they must never be used to convert the default centered
    //layout into a custom one.
    //-------------------------------------------------------------------------
    AFiler.DefineProperty(
        'InternalOriginActive',
        ReadInternalOriginActive,
        WriteInternalOriginActive,
        FUseInternalOrigin);

    AFiler.DefineProperty(
        'InternalOriginX',
        ReadInternalOriginX,
        WriteInternalOriginX,
        FUseInternalOrigin);

    AFiler.DefineProperty(
        'InternalOriginY',
        ReadInternalOriginY,
        WriteInternalOriginY,
        FUseInternalOrigin);
End;

Procedure TRotatedEditCore.ReadInternalOriginActive(AReader: TReader);
Begin
    FUseInternalOrigin := AReader.ReadBoolean;
End;

Procedure TRotatedEditCore.WriteInternalOriginActive(AWriter: TWriter);
Begin
    //-------------------------------------------------------------------------
    //Streams whether the component really has a custom internal origin.
    //
    //Do not force this value to True. If the component uses the default centered
    //layout, there is nothing to persist and the DFM must remain free of hidden
    //origin state.
    //-------------------------------------------------------------------------
    AWriter.WriteBoolean(FUseInternalOrigin);
End;

Procedure TRotatedEditCore.ReadInternalOriginX(AReader: TReader);
Begin
    FInternalOriginX := AReader.ReadFloat;
End;

Procedure TRotatedEditCore.WriteInternalOriginX(AWriter: TWriter);
Begin
    //-------------------------------------------------------------------------
    //Only real custom origins are streamed. DefineProperties prevents this
    //writer from being called for the default centered layout.
    //-------------------------------------------------------------------------
    AWriter.WriteFloat(FInternalOriginX);
End;

Procedure TRotatedEditCore.ReadInternalOriginY(AReader: TReader);
Begin
    FInternalOriginY := AReader.ReadFloat;
End;

Procedure TRotatedEditCore.WriteInternalOriginY(AWriter: TWriter);
Begin
    //-------------------------------------------------------------------------
    //Only real custom origins are streamed. DefineProperties prevents this
    //writer from being called for the default centered layout.
    //-------------------------------------------------------------------------
    AWriter.WriteFloat(FInternalOriginY);
End;

Procedure TRotatedEditCore.UpdatePhysicalBoundsFromLogicalSize;
Begin
    //-------------------------------------------------------------------------
    //Compatibility wrapper kept for older internal call sites.
    //-------------------------------------------------------------------------
    ApplyExternalBoundsFromLogicalSize;
End;

Procedure TRotatedEditCore.AutoSizeToLogicalBounds;
Begin
    //-------------------------------------------------------------------------
    //Compatibility wrapper kept for older internal call sites and DFM/API
    //continuity.
    //-------------------------------------------------------------------------
    ApplyExternalBoundsFromLogicalSize;
End;



Procedure TRotatedEditCore.CMDesignHitTest(Var Message: TCMDesignHitTest);
Begin
    //-------------------------------------------------------------------------
    //Design-time mouse ownership rule.
    //
    //CM_DESIGNHITTEST has a counter-intuitive meaning:
    //
    //- Result = 0:
    //    the form designer keeps the mouse event and can select / drag /
    //    resize the component;
    //
    //- Result <> 0:
    //    the component receives the mouse event even at design time.
    //
    //The previous attempt returned 1 when the click was inside the edit surface.
    //That made the component behave like a live edit at design time:
    //double-click and triple-click selected text, and normal designer drag was
    //broken.
    //
    //For now, TRotatedEdit must remain a normal designable component. The IDE
    //designer must keep the mouse event so native selection, dragging and
    //resizing keep working.
    //
    //Important regression note:
    //Do not return HTTRANSPARENT from WM_NCHITTEST in design-time to filter the
    //rectangular BoundsRect. That was tested previously and broke the designer
    //resize workflow because some resize handles live outside the projected
    //rotated edit surface.
    //-------------------------------------------------------------------------
    Message.Result := 0;
End;

Procedure TRotatedEditCore.CMColorChanged(Var Message: TMessage);
Begin
    Inherited;

    //-------------------------------------------------------------------------
    //Color changes affect the canonical background and therefore the composed
    //content bitmap.
    //
    //Even when VCL styles are active, Color may still be used when seClient is
    //removed from PaletteMode. The cache must therefore be invalidated
    //unconditionally.
    //-------------------------------------------------------------------------
    InvalidateBackgroundCache;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.CMFontChanged(Var Message: TMessage);
Begin
    Inherited;

    //-------------------------------------------------------------------------
    //Font changes affect text metrics, caret placement, selection geometry and
    //the composed content bitmap.
    //
    //The physical window region does not need to be rebuilt because
    //LogicalLength / LogicalThickness remain the explicit edit-surface size.
    //-------------------------------------------------------------------------
    InvalidatePreferredLogicalThickness;
    InvalidateContentBitmap;

    If FAutoSize Then
        ApplyAutoSizeLogicalThickness;

    Invalidate;
End;

Procedure TRotatedEditCore.CMStyleChanged(Var Message: TMessage);
Begin
    Inherited;

    //-------------------------------------------------------------------------
    //PaletteMode / global style changes can affect background,
    //border, text color, selection color and caret color.
    //
    //The component uses bitmap caches, so a normal Invalidate is not enough:
    //both canonical caches must be dropped before repaint.
    //-------------------------------------------------------------------------
    InvalidatePreferredLogicalThickness;
    InvalidateBackgroundCache;
    InvalidateContentBitmap;

    If FAutoSize Then
        ApplyAutoSizeLogicalThickness;

    Invalidate;
End;

Procedure TRotatedEditCore.CMEnabledChanged(Var Message: TMessage);
Begin
    Inherited;

    //-------------------------------------------------------------------------
    //Enabled affects text, hint and caret colors. Because those colors are
    //cached in FContentBitmap, a plain repaint is not sufficient.
    //-------------------------------------------------------------------------
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.DestroyHoverCursor;
Begin
    //-------------------------------------------------------------------------
    //Destroys the cached native hover cursor.
    //
    //The handle is not stored in Screen.Cursors. It belongs only to this control
    //and is applied directly through WM_SETCURSOR. That keeps ownership local
    //and avoids leaking global cursor slots.
    //-------------------------------------------------------------------------
    If FHoverCursorHandle <> 0 Then Begin
        DestroyCursor(FHoverCursorHandle);
        FHoverCursorHandle := 0;
    End;
End;

Procedure TRotatedEditCore.InvalidateHoverCursor;
Begin
    //-------------------------------------------------------------------------
    //Invalidates the generated cursor.
    //
    //The cursor depends on Angle only. If more visual cursor options are added
    //later, this method is the single place to extend the invalidation rule.
    //-------------------------------------------------------------------------
    DestroyHoverCursor;
    FHoverCursorAngle := -1.0;
End;

Function TRotatedEditCore.EnsureHoverCursor: HCURSOR;
Begin
    //-------------------------------------------------------------------------
    //Returns a cursor whose I-beam follows the insertion-caret orientation.
    //
    //The cursor is generated lazily because most controls are never hovered
    //during a paint pass. Lazy creation also avoids creating cursor handles in
    //situations where the component is only streamed or inspected.
    //-------------------------------------------------------------------------
    If (FHoverCursorHandle = 0) Or
       (Abs(TRotatedEditGeometry.NormalizeAngle(FHoverCursorAngle) -
            TRotatedEditGeometry.NormalizeAngle(FAngle)) > 0.001) Then Begin
        DestroyHoverCursor;

        FHoverCursorHandle := CreateOrientationAwareHoverCursor(FAngle);
        FHoverCursorAngle := FAngle;
    End;

    Result := FHoverCursorHandle;
End;

Procedure TRotatedEditCore.DrawHoverCursorShape(
    ACanvas: TCanvas;
    ACenterX: Integer;
    ACenterY: Integer;
    AAngle: Double;
    AColor: TColor;
    APenWidth: Integer);
Var
    LRad: Double;
    LCaretDX: Double;
    LCaretDY: Double;
    LFlowDX: Double;
    LFlowDY: Double;
    LStemHalf: Double;
    LCapHalf: Double;
    X1: Integer;
    Y1: Integer;
    X2: Integer;
    Y2: Integer;
Begin
    //-------------------------------------------------------------------------
    //Draws the I-beam cursor shape.
    //
    //Geometry rule:
    //The cursor stem follows the same direction as the insertion caret, not the
    //text flow direction.
    //
    //For text flow angle A:
    //- the text flow vector is the transformed canonical X axis;
    //- the caret/cursor vector is the transformed canonical Y axis.
    //
    //Examples:
    //- Angle 0   -> vertical I-beam;
    //- Angle 90  -> horizontal I-beam;
    //- Angle 240 -> oblique I-beam matching the projected insertion caret.
    //-------------------------------------------------------------------------
    LRad := AAngle * Pi / 180.0;

    LCaretDX := Sin(LRad);
    LCaretDY := Cos(LRad);

    LFlowDX := Cos(LRad);
    LFlowDY := -Sin(LRad);

    LStemHalf := 8.0;
    LCapHalf := 3.0;

    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Color := AColor;
    ACanvas.Pen.Width := APenWidth;

    X1 := Round(ACenterX - (LCaretDX * LStemHalf));
    Y1 := Round(ACenterY - (LCaretDY * LStemHalf));
    X2 := Round(ACenterX + (LCaretDX * LStemHalf));
    Y2 := Round(ACenterY + (LCaretDY * LStemHalf));

    ACanvas.MoveTo(X1, Y1);
    ACanvas.LineTo(X2, Y2);

    ACanvas.MoveTo(
        Round(X1 - (LFlowDX * LCapHalf)),
        Round(Y1 - (LFlowDY * LCapHalf)));
    ACanvas.LineTo(
        Round(X1 + (LFlowDX * LCapHalf)),
        Round(Y1 + (LFlowDY * LCapHalf)));

    ACanvas.MoveTo(
        Round(X2 - (LFlowDX * LCapHalf)),
        Round(Y2 - (LFlowDY * LCapHalf)));
    ACanvas.LineTo(
        Round(X2 + (LFlowDX * LCapHalf)),
        Round(Y2 + (LFlowDY * LCapHalf)));
End;

Procedure TRotatedEditCore.DrawHoverCursorStroke(
    ACanvas: TCanvas;
    ACenterX: Integer;
    ACenterY: Integer;
    AAngle: Double;
    APenWidth: Integer);
Begin
    //-------------------------------------------------------------------------
    //Draws the monochrome cursor stroke used by the mask bitmap.
    //
    //The goal is to stay visually close to the native Windows I-beam cursor:
    //thin, monochrome and not surrounded by a heavy white outline.
    //
    //The previous version used a color cursor with a thick white outline and a
    //black inner line. It was readable, but visually too far from the native
    //I-beam. The monochrome mask cursor lets Windows combine the black cursor
    //shape with the background in the standard way.
    //-------------------------------------------------------------------------
    DrawHoverCursorShape(
        ACanvas,
        ACenterX,
        ACenterY,
        AAngle,
        clBlack,
        APenWidth);
End;


Procedure TRotatedEditCore.SetCursorPlaneBit(
    Var APlane: TBytes;
    AWidth: Integer;
    AHeight: Integer;
    AX: Integer;
    AY: Integer;
    AValue: Boolean);
Var
    LRowBytes: Integer;
    LByteIndex: Integer;
    LBitMask: Byte;
Begin
    //-------------------------------------------------------------------------
    //Sets one bit in a 1-bpp cursor plane.
    //
    //CreateCursor expects scanlines to be word-aligned. Bit 7 is the leftmost
    //pixel of each byte.
    //-------------------------------------------------------------------------
    If (AX < 0) Or (AY < 0) Or (AX >= AWidth) Or (AY >= AHeight) Then
        Exit;

    LRowBytes := ((AWidth + 15) Div 16) * 2;
    LByteIndex := (AY * LRowBytes) + (AX Div 8);
    LBitMask := Byte($80 Shr (AX Mod 8));

    If AValue Then
        APlane[LByteIndex] := APlane[LByteIndex] Or LBitMask
    Else
        APlane[LByteIndex] := APlane[LByteIndex] And Not LBitMask;
End;

Procedure TRotatedEditCore.DrawCursorMaskLine(
    Var APlane: TBytes;
    AWidth: Integer;
    AHeight: Integer;
    AX1: Integer;
    AY1: Integer;
    AX2: Integer;
    AY2: Integer);
Var
    LDX: Integer;
    LDY: Integer;
    LSX: Integer;
    LSY: Integer;
    LErr: Integer;
    LE2: Integer;
    LX: Integer;
    LY: Integer;
Begin
    //-------------------------------------------------------------------------
    //Draws a one-pixel line into a cursor bit plane using Bresenham.
    //
    //The line is used for the XOR plane of an inverting cursor. It is
    //deliberately thin to stay close to the native I-beam shape.
    //-------------------------------------------------------------------------
    LX := AX1;
    LY := AY1;

    LDX := Abs(AX2 - AX1);
    LDY := -Abs(AY2 - AY1);

    If AX1 < AX2 Then
        LSX := 1
    Else
        LSX := -1;

    If AY1 < AY2 Then
        LSY := 1
    Else
        LSY := -1;

    LErr := LDX + LDY;

    While True Do Begin
        SetCursorPlaneBit(
            APlane,
            AWidth,
            AHeight,
            LX,
            LY,
            True);

        If (LX = AX2) And (LY = AY2) Then
            Break;

        LE2 := 2 * LErr;

        If LE2 >= LDY Then Begin
            LErr := LErr + LDY;
            LX := LX + LSX;
        End;

        If LE2 <= LDX Then Begin
            LErr := LErr + LDX;
            LY := LY + LSY;
        End;
    End;
End;

Procedure TRotatedEditCore.DrawCursorMaskShape(
    Var AXorPlane: TBytes;
    AWidth: Integer;
    AHeight: Integer;
    ACenterX: Integer;
    ACenterY: Integer;
    AAngle: Double);
Var
    LRad: Double;
    LCaretDX: Double;
    LCaretDY: Double;
    LFlowDX: Double;
    LFlowDY: Double;
    LStemHalf: Double;
    LCapHalf: Double;
    X1: Integer;
    Y1: Integer;
    X2: Integer;
    Y2: Integer;
Begin
    //-------------------------------------------------------------------------
    //Draws the XOR part of the orientation-aware I-beam.
    //
    //Mask rule:
    //AND plane remains 1 everywhere, XOR plane is 1 only on the I-beam. This
    //produces an inverting cursor:
    //
    //  final_pixel = screen_pixel XOR 1
    //
    //That is the Win32-style solution that works independently from the VCL
    //style palette.
    //-------------------------------------------------------------------------
    LRad := AAngle * Pi / 180.0;

    LCaretDX := Sin(LRad);
    LCaretDY := Cos(LRad);

    LFlowDX := Cos(LRad);
    LFlowDY := -Sin(LRad);

    LStemHalf := 8.0;
    LCapHalf := 3.0;

    X1 := Round(ACenterX - (LCaretDX * LStemHalf));
    Y1 := Round(ACenterY - (LCaretDY * LStemHalf));
    X2 := Round(ACenterX + (LCaretDX * LStemHalf));
    Y2 := Round(ACenterY + (LCaretDY * LStemHalf));

    DrawCursorMaskLine(
        AXorPlane,
        AWidth,
        AHeight,
        X1,
        Y1,
        X2,
        Y2);

    DrawCursorMaskLine(
        AXorPlane,
        AWidth,
        AHeight,
        Round(X1 - (LFlowDX * LCapHalf)),
        Round(Y1 - (LFlowDY * LCapHalf)),
        Round(X1 + (LFlowDX * LCapHalf)),
        Round(Y1 + (LFlowDY * LCapHalf)));

    DrawCursorMaskLine(
        AXorPlane,
        AWidth,
        AHeight,
        Round(X2 - (LFlowDX * LCapHalf)),
        Round(Y2 - (LFlowDY * LCapHalf)),
        Round(X2 + (LFlowDX * LCapHalf)),
        Round(Y2 + (LFlowDY * LCapHalf)));
End;

Function TRotatedEditCore.CreateOrientationAwareHoverCursor(AAngle: Double): HCURSOR;
Var
    LWidth: Integer;
    LHeight: Integer;
    LCenterX: Integer;
    LCenterY: Integer;
    LRowBytes: Integer;
    LPlaneSize: Integer;
    LAndPlane: TBytes;
    LXorPlane: TBytes;
    I: Integer;
Begin
    //-------------------------------------------------------------------------
    //Creates a style-independent orientation-aware I-beam cursor.
    //
    //This version uses CreateCursor with explicit AND/XOR bit planes.
    //
    //Why this approach?
    //------------------
    //Win32 monochrome cursors are defined by AND/XOR masks. Microsoft documents
    //the display rule as:
    //
    //  AND=1, XOR=0 -> screen unchanged
    //  AND=1, XOR=1 -> reverse screen
    //
    //Using an inverting cursor is the closest style-independent behavior to the
    //native I-beam: it becomes light on dark backgrounds and dark on light
    //backgrounds without depending on VCL style colors.
    //
    //Why not a fixed style color?
    //----------------------------
    //A mouse cursor is not a VCL styled element. It is drawn by the OS over many
    //possible backgrounds, including non-VCL windows. A fixed VCL style color
    //would be less robust than a contrast/inverting mask.
    //
    //Ownership rule
    //--------------
    //CreateCursor returns an HCURSOR owned by the caller. The component stores
    //it in FHoverCursorHandle and destroys it with DestroyCursor.
    //-------------------------------------------------------------------------
    LWidth := GetSystemMetrics(SM_CXCURSOR);
    LHeight := GetSystemMetrics(SM_CYCURSOR);

    If LWidth < 24 Then
        LWidth := 24;

    If LHeight < 24 Then
        LHeight := 24;

    LCenterX := LWidth Div 2;
    LCenterY := LHeight Div 2;

    LRowBytes := ((LWidth + 15) Div 16) * 2;
    LPlaneSize := LRowBytes * LHeight;

    SetLength(
        LAndPlane,
        LPlaneSize);

    SetLength(
        LXorPlane,
        LPlaneSize);

    //---------------------------------------------------------------------
    //AND plane:
    //All bits set to 1 means "keep the screen". The cursor itself is created
    //only by setting XOR bits on top of that preserved screen.
    //---------------------------------------------------------------------
    For I := 0 To High(LAndPlane) Do
        LAndPlane[I] := $FF;

    //---------------------------------------------------------------------
    //XOR plane:
    //0 everywhere = no inversion. Cursor pixels are set to 1 by
    //DrawCursorMaskShape, creating an inverting I-beam.
    //---------------------------------------------------------------------
    For I := 0 To High(LXorPlane) Do
        LXorPlane[I] := 0;

    DrawCursorMaskShape(
        LXorPlane,
        LWidth,
        LHeight,
        LCenterX,
        LCenterY,
        AAngle);

    Result := CreateCursor(
        HInstance,
        LCenterX,
        LCenterY,
        LWidth,
        LHeight,
        @LAndPlane[0],
        @LXorPlane[0]);

    If Result = 0 Then
        Result := Screen.Cursors[crIBeam];
End;

Procedure TRotatedEditCore.CreateWnd;
Begin
    Inherited CreateWnd;

    //-------------------------------------------------------------------------
    //The native region belongs to the window handle. Whenever the handle is
    //created or recreated, the region must be rebuilt from the current logical
    //layout.
    //-------------------------------------------------------------------------
    UpdateWindowRegion;
End;

Procedure TRotatedEditCore.DestroyWnd;
Begin
    //-------------------------------------------------------------------------
    //Reset the region before the handle disappears.
    //
    //Passing 0 removes the current region from the window. Windows owns a region
    //after a successful SetWindowRgn call, so we must not keep or delete that
    //handle ourselves.
    //-------------------------------------------------------------------------
    ClearWindowRegion;

    Inherited DestroyWnd;
End;

Procedure TRotatedEditCore.Resize;
Begin
    Inherited Resize;

    //-------------------------------------------------------------------------
    //The projected edit surface is centered inside ClientRect. A physical resize
    //therefore changes the actual position of the region, even if Angle and
    //LogicalLength / LogicalThickness did not change.
    //-------------------------------------------------------------------------
    UpdateWindowRegion;
End;



Procedure TRotatedEditCore.WMLButtonDblClk(Var Message: TWMLButtonDblClk);
Var
    LLayout: TRotatedEditLayoutResult;
    LHit: TRotatedEditHitTestResult;
    LPoint: TPoint;
Begin
    //-------------------------------------------------------------------------
    //Handles the second click of a double-click sequence.
    //
    //Why handle WM_LBUTTONDBLCLK directly?
    //------------------------------------
    //Relying only on MouseDown + DblClick can produce different behavior
    //depending on how VCL routes double-click messages. Handling the native
    //message gives us a single reliable place for "second click = select word".
    //
    //Triple-click remains a normal following WM_LBUTTONDOWN. Because this method
    //sets FClickCount to 2 and refreshes FLastClickTick/FLastClickPos, the next
    //click inside the system double-click time/rectangle becomes click count 3.
    //-------------------------------------------------------------------------
    Inherited;

    LPoint := Point(
        Message.XPos,
        Message.YPos);

    SetFocus;

    LLayout := BuildCurrentLayout;

    LHit := FRenderBackend.HitTest(
        Canvas,
        LLayout,
        LPoint);

    SelectWordAt(LHit.InsertionIndex);

    FLastClickTick := GetTickCount;
    FLastClickPos := LPoint;
    FClickCount := 2;

    FMouseSelecting := False;
    MouseCapture := False;

    Message.Result := 0;
End;

Procedure TRotatedEditCore.WMSetCursor(Var Message: TWMSetCursor);
Var
    LCursor: HCURSOR;
Begin
    //-------------------------------------------------------------------------
    //Applies the orientation-aware hover cursor at runtime only.
    //
    //Design-time rule:
    //When the component is manipulated in the IDE designer, the cursor must stay
    //under the designer's control. If we force the edit I-beam cursor here, the
    //component becomes difficult to select and move in design mode.
    //
    //Runtime rule:
    //The cursor is visual feedback for the insertion caret direction. It does
    //not participate in hit-testing. Hit-testing still converts the actual
    //mouse position to canonical coordinates through the layout engine.
    //
    //Only HTCLIENT is handled here. Border/caption hit-testing must stay under
    //normal Windows/VCL control.
    //-------------------------------------------------------------------------
    If csDesigning In ComponentState Then Begin
        Inherited;
        Exit;
    End;

    If Message.HitTest = HTCLIENT Then Begin
        LCursor := EnsureHoverCursor;

        If LCursor <> 0 Then Begin
            SetCursor(LCursor);
            Message.Result := 1;
            Exit;
        End;
    End;

    Inherited;
End;

Procedure TRotatedEditCore.WMEraseBkgnd(Var Message: TWMEraseBkgnd);
Begin
    //-------------------------------------------------------------------------
    //Disable the standard rectangular background erase.
    //
    //The control is region-shaped. Letting Windows/VCL erase the whole physical
    //bounding box would repaint pixels outside the projected edit surface and
    //would break the transparent behavior.
    //
    //The parent background is restored explicitly at the beginning of Paint.
    //-------------------------------------------------------------------------
    Message.Result := 1;
End;

Procedure TRotatedEditCore.WMGetDlgCode(Var Message: TWMGetDlgCode);
Begin
    Inherited;

    //-------------------------------------------------------------------------
    //Keyboard navigation rule.
    //
    //TRotatedEdit is an edit control. Arrow keys are editing keys, not dialog
    //navigation keys.
    //
    //Without DLGC_WANTARROWS, Windows/VCL may treat Left / Right / Up / Down as
    //focus navigation, which can make them behave like Tab on some forms.
    //
    //DLGC_WANTCHARS keeps normal character input routed to the control. We do
    //not request DLGC_WANTTAB for now, so Tab remains normal focus navigation.
    //-------------------------------------------------------------------------
    Message.Result := Message.Result Or DLGC_WANTARROWS Or DLGC_WANTCHARS;
End;

Function TRotatedEditCore.CreateRegionFromCurrentLayout: HRGN;
Var
    LLayout: TRotatedEditLayoutResult;
    LPoints: Array [0 .. 3] Of TPoint;
Begin
    //-------------------------------------------------------------------------
    //Builds a native HRGN from the projected edit surface.
    //
    //Coordinates passed to SetWindowRgn are client-window coordinates. The
    //layout's ActualEditQuad is already expressed in the control client
    //coordinate system, so no screen conversion is performed here.
    //
    //Ownership rule:
    //The caller owns the returned HRGN until it is successfully passed to
    //SetWindowRgn. After a successful SetWindowRgn call, Windows owns it and the
    //caller must not delete it.
    //-------------------------------------------------------------------------

    Result := 0;

    If Not HandleAllocated Then
        Exit;

    Canvas.Font.Assign(Font);

    LLayout := BuildCurrentLayout;

    LPoints[0] := Point(
        Round(LLayout.ActualEditQuad.P1.X),
        Round(LLayout.ActualEditQuad.P1.Y));

    LPoints[1] := Point(
        Round(LLayout.ActualEditQuad.P2.X),
        Round(LLayout.ActualEditQuad.P2.Y));

    LPoints[2] := Point(
        Round(LLayout.ActualEditQuad.P3.X),
        Round(LLayout.ActualEditQuad.P3.Y));

    LPoints[3] := Point(
        Round(LLayout.ActualEditQuad.P4.X),
        Round(LLayout.ActualEditQuad.P4.Y));

    Result := CreatePolygonRgn(
        LPoints,
        Length(LPoints),
        WINDING);
End;

Procedure TRotatedEditCore.ClearWindowRegion;
Begin
    If Not HandleAllocated Then
        Exit;

    //-------------------------------------------------------------------------
    //Remove any native region from the control.
    //
    //This is used when UseWindowRegion is disabled and before handle
    //destruction. No HRGN ownership issue exists here because 0 means "remove
    //the current region".
    //-------------------------------------------------------------------------
    SetWindowRgn(
        Handle,
        0,
        True);
End;

Procedure TRotatedEditCore.UpdateWindowRegion;
Var
    LRegion: HRGN;
Begin
    If Not HandleAllocated Then
        Exit;

    If Not FUseWindowRegion Then Begin
        ClearWindowRegion;
        Exit;
    End;

    LRegion := CreateRegionFromCurrentLayout;

    If LRegion = 0 Then Begin
        ClearWindowRegion;
        Exit;
    End;

    //-------------------------------------------------------------------------
    //SetWindowRgn ownership rule:
    //- success: Windows owns LRegion; do not call DeleteObject;
    //- failure: we still own LRegion and must delete it.
    //-------------------------------------------------------------------------
    If SetWindowRgn(Handle, LRegion, True) = 0 Then
        DeleteObject(LRegion);
End;

Function TRotatedEditCore.BuildCaretInvalidationRect(Out ARect: TRect): Boolean;
Var
    LLayout: TRotatedEditLayoutResult;
    LMinX: Double;
    LMaxX: Double;
    LMinY: Double;
    LMaxY: Double;
    LInflate: Integer;
Begin
    //-------------------------------------------------------------------------
    //Builds the smallest practical physical rectangle covering the projected
    //caret. This method is used only for caret blinking. It must not invalidate
    //text, selection or background caches: those caches are handled by the
    //normal editing/layout setters.
    //
    //The caret quad is already part of the common layout result. Using it here
    //keeps the invalidation rectangle consistent for horizontal, vertical and
    //free-angle orientations, including 45-degree controls.
    //-------------------------------------------------------------------------
    Result := False;
    ARect := Rect(0, 0, 0, 0);

    If Not HandleAllocated Then
        Exit;

    Canvas.Font.Assign(Font);

    LLayout := BuildCurrentLayout;

    LMinX := Min(
        Min(LLayout.Caret.ActualQuad.P1.X, LLayout.Caret.ActualQuad.P2.X),
        Min(LLayout.Caret.ActualQuad.P3.X, LLayout.Caret.ActualQuad.P4.X));
    LMaxX := Max(
        Max(LLayout.Caret.ActualQuad.P1.X, LLayout.Caret.ActualQuad.P2.X),
        Max(LLayout.Caret.ActualQuad.P3.X, LLayout.Caret.ActualQuad.P4.X));
    LMinY := Min(
        Min(LLayout.Caret.ActualQuad.P1.Y, LLayout.Caret.ActualQuad.P2.Y),
        Min(LLayout.Caret.ActualQuad.P3.Y, LLayout.Caret.ActualQuad.P4.Y));
    LMaxY := Max(
        Max(LLayout.Caret.ActualQuad.P1.Y, LLayout.Caret.ActualQuad.P2.Y),
        Max(LLayout.Caret.ActualQuad.P3.Y, LLayout.Caret.ActualQuad.P4.Y));

    ARect := Rect(
        Floor(LMinX),
        Floor(LMinY),
        Ceil(LMaxX),
        Ceil(LMaxY));

    //-------------------------------------------------------------------------
    //Give GDI a small safety margin. The caret may be antialiased or drawn with
    //a pen width greater than one pixel, and free-angle transforms can touch
    //neighboring pixels. The margin stays deliberately small so blinking does
    //not repaint the entire rotated edit surface anymore.
    //-------------------------------------------------------------------------
    LInflate := Max(3, FCaretThickness + 2);
    InflateRect(
        ARect,
        LInflate,
        LInflate);

    IntersectRect(
        ARect,
        ARect,
        ClientRect);

    Result := Not IsRectEmpty(ARect);
End;

Procedure TRotatedEditCore.InvalidateCaretArea;
Var
    LCaretRect: TRect;
    LDirtyRect: TRect;
Begin
    //-------------------------------------------------------------------------
    //Caret blinking is driven by a timer. Invalidating the whole custom control
    //on every tick is visually expensive because PaintTransparentBackground may
    //ask the parent to repaint through the control DC. Restricting the update
    //region to the caret's old/current location removes the visible heartbeat
    //while preserving the normal blinking behavior.
    //-------------------------------------------------------------------------
    If Not BuildCaretInvalidationRect(LCaretRect) Then Begin
        Invalidate;
        Exit;
    End;

    LDirtyRect := LCaretRect;

    If FLastCaretInvalidateRectValid Then
        UnionRect(
            LDirtyRect,
            LDirtyRect,
            FLastCaretInvalidateRect);

    FLastCaretInvalidateRect := LCaretRect;
    FLastCaretInvalidateRectValid := True;

    If HandleAllocated Then
        InvalidateRect(
            Handle,
            @LDirtyRect,
            False)
    Else
        Invalidate;
End;

Procedure TRotatedEditCore.CaretChanged(Sender: TObject);
Begin
    InvalidateCaretArea;
End;

Procedure TRotatedEditCore.Loaded;
Begin
    Inherited;

    //-------------------------------------------------------------------------
    //DFM coherence rule.
    //
    //At load time the streamed VCL bounds must be respected exactly. Loaded is
    //not allowed to call ApplyExternalBoundsFromLogicalSize because that would
    //rebuild a new external rectangle from LogicalLength / LogicalThickness /
    //Angle and could move the control compared with its design-time position.
    //
    //The important point is that the external BoundsRect is not the whole
    //geometry. For a rotated control, the actual projected edit surface also has
    //an internal origin inside that host rectangle. Design-time resize can move
    //that internal surface while the designer owns the external rectangle.
    //
    //When FUseInternalOrigin / FInternalOriginX / FInternalOriginY were streamed,
    //their reader methods have already restored them before Loaded is called.
    //When they were absent, the constructor/default setter path leaves
    //FUseInternalOrigin False, so the layout engine uses its deterministic
    //centered origin. Loaded must not invent a tight top-left origin.
    //
    //Authoritative rules:
    //- DFM loading preserves streamed Left / Top / Width / Height;
    //- published setters do not resize external bounds while csLoading is active;
    //- hidden internal-origin state is used only when it was explicitly streamed;
    //- LogicalLength / LogicalThickness setters may resize external bounds after
    //  loading;
    //- Angle / Orientation setters may resize external bounds after loading while
    //  preserving the external center.
    //-------------------------------------------------------------------------
    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;
    InvalidateRotationCenter;
    InvalidatePreferredLogicalThickness;

    If FAutoSize Then
        ApplyAutoSizeLogicalThickness
    Else
        UpdateWindowRegion;
End;

Procedure TRotatedEditCore.PaintTransparentBackground(ACanvas: TCanvas);
Var
    LSaveIndex: Integer;
    LPoint:     TPoint;
Begin
    //-------------------------------------------------------------------------
    //Simule la transparence VCL du contrôle.
    //
    //TRotatedEdit est un contrôle fenêtré rectangulaire, mais sa surface
    //éditable peut être tournée. Les zones du ClientRect situées hors de la
    //surface projetée ne doivent donc pas être remplies avec la couleur edit.
    //
    //On restaure d'abord le fond du parent dans notre Canvas, puis on dessine
    //uniquement la surface éditable projetée.
    //
    //Important :
    //- ce n'est pas une vraie transparence Windows ;
    //- c'est le comportement classique attendu pour un contrôle VCL custom ;
    //- il faut le faire à chaque Paint, notamment à cause du blink du caret.
    //-------------------------------------------------------------------------
    If Parent = Nil Then Begin
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := Color;
        ACanvas.FillRect(ClientRect);
        Exit;
    End;

    //-------------------------------------------------------------------------
    //Fallback fill before asking the parent to erase/paint itself.
    //
    //The off-screen Paint path composes the transparent background into a
    //memory bitmap first. During design-time drag operations the designer may
    //call the control paint while the parent does not fully repaint that memory
    //DC. If the temporary bitmap is left with its default pixels, the rectangular
    //host area around the rotated edit can briefly appear white.
    //
    //We therefore seed the buffer with the parent's current brush color before
    //the regular transparency emulation. Runtime parent painting still has the
    //last word when it succeeds, but the design-time fallback is no longer the
    //uninitialized/white bitmap content.
    //-------------------------------------------------------------------------
    If Not (csDesigning In ComponentState) Then Begin
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := Parent.Brush.Color;
        ACanvas.FillRect(ClientRect);
    End;

    LSaveIndex := SaveDC(ACanvas.Handle);
    Try
        LPoint := Point(
            Left,
            Top);

        MoveWindowOrg(
            ACanvas.Handle,
            LPoint.X,
            LPoint.Y);

        Parent.Perform(
            WM_ERASEBKGND,
            ACanvas.Handle,
            0);

        //---------------------------------------------------------------------
        //Runtime transparency emulation can ask the parent to paint itself into
        //our DC so the rectangular window area outside the rotated edit surface
        //matches the surrounding form.
        //
        //Design-time exception:
        //while the IDE is dragging the component over another control such as a
        //TGroupBox, asking the parent for WM_PAINT can sample underlying child
        //controls and temporarily paint their border/caption inside our own
        //background. During design-time painting we therefore keep only the
        //erase-background step. This gives a stable parent-colored background
        //without copying sibling/underlying control details during the drag.
        //---------------------------------------------------------------------
        If Not (csDesigning In ComponentState) Then
            Parent.Perform(
                WM_PAINT,
                ACanvas.Handle,
                0);
    Finally RestoreDC(
            ACanvas.Handle,
            LSaveIndex);
    End;
End;

Procedure TRotatedEditCore.DrawDesignSelectionMarkers(
    ACanvas: TCanvas;
    Const ALayout: TRotatedEditLayoutResult);
Var
    LOldPenColor: TColor;
    LOldPenStyle: TPenStyle;
    LOldPenMode: TPenMode;
    LOldBrushColor: TColor;
    LOldBrushStyle: TBrushStyle;
    LHandleSize: Double;
    LHalfHandle: Double;
    LUx: Double;
    LUy: Double;
    LVx: Double;
    LVy: Double;

    Procedure NormalizeVector(
        Var AX: Double;
        Var AY: Double);
    Var
        LLen: Double;
    Begin
        //---------------------------------------------------------------------
        //Normalizes a 2D vector used to orient design-time markers.
        //
        //The projected edit surface can be horizontal, vertical or freely
        //rotated. The markers therefore use the actual projected edit axes
        //instead of drawing non-oriented screen rectangles.
        //---------------------------------------------------------------------
        LLen := Sqrt((AX * AX) + (AY * AY));

        If LLen <= 0.0001 Then
            Exit;

        AX := AX / LLen;
        AY := AY / LLen;
    End;

    Procedure DrawOrientedHandle(
        Const ACornerX: Double;
        Const ACornerY: Double;
        Const ADirUX: Double;
        Const ADirUY: Double;
        Const ADirVX: Double;
        Const ADirVY: Double);
    Var
        LCx: Double;
        LCy: Double;
        LPoints: Array [0 .. 3] Of TPoint;
    Begin
        //---------------------------------------------------------------------
        //Draws one small oriented square strictly inside the projected edit
        //surface.
        //
        //The marker is moved inward from the actual corner by half its size in
        //both local edit directions. This is important because the component's
        //native window region clips everything outside the edit surface. If the
        //marker were centered directly on the corner, half of it would be
        //outside the region and could disappear.
        //
        //These markers are visual hints only. They are not real IDE handles and
        //do not alter selection, resizing or hit-testing.
        //---------------------------------------------------------------------
        LCx := ACornerX + (ADirUX * LHalfHandle) + (ADirVX * LHalfHandle);
        LCy := ACornerY + (ADirUY * LHalfHandle) + (ADirVY * LHalfHandle);

        LPoints[0] := Point(
            Round(LCx - (ADirUX * LHalfHandle) - (ADirVX * LHalfHandle)),
            Round(LCy - (ADirUY * LHalfHandle) - (ADirVY * LHalfHandle)));

        LPoints[1] := Point(
            Round(LCx + (ADirUX * LHalfHandle) - (ADirVX * LHalfHandle)),
            Round(LCy + (ADirUY * LHalfHandle) - (ADirVY * LHalfHandle)));

        LPoints[2] := Point(
            Round(LCx + (ADirUX * LHalfHandle) + (ADirVX * LHalfHandle)),
            Round(LCy + (ADirUY * LHalfHandle) + (ADirVY * LHalfHandle)));

        LPoints[3] := Point(
            Round(LCx - (ADirUX * LHalfHandle) + (ADirVX * LHalfHandle)),
            Round(LCy - (ADirUY * LHalfHandle) + (ADirVY * LHalfHandle)));

        ACanvas.Polygon(LPoints);
    End;

Begin
    //-------------------------------------------------------------------------
    //Draws optional lightweight design-time corner markers.
    //
    //The previous version drew an external BoundsRect and an edit outline. That
    //was visually too intrusive and could look like a large rounded/rectangular
    //selection frame around the whole edit.
    //
    //The intended behavior is closer to shaped controls such as TJvShapedButton:
    //when native designer handles are hidden or clipped by SetWindowRgn,
    //the component can paint its own small corner cues.
    //
    //Important rules:
    //- draw only four small markers;
    //- keep every marker inside the projected edit region;
    //- orient the markers with the edit itself;
    //- do not take ownership of mouse/design events;
    //- use ShowDesignMarkers as the explicit design-time enable switch;
    //- draw only when this component is currently selected by the designer;
    //- use XOR drawing so the cue remains visible over both light and dark
    //  styled backgrounds, just like the custom hover cursor mask.
    //-------------------------------------------------------------------------
    If Not (csDesigning In ComponentState) Then
        Exit;

    If Not FShowDesignMarkers Then
        Exit;

    If Not FDesignSelectionSelected Then
        Exit;

    LOldPenColor := ACanvas.Pen.Color;
    LOldPenStyle := ACanvas.Pen.Style;
    LOldPenMode := ACanvas.Pen.Mode;
    LOldBrushColor := ACanvas.Brush.Color;
    LOldBrushStyle := ACanvas.Brush.Style;

    Try
        //---------------------------------------------------------------------
        //Projected local axes.
        //
        //U follows the text direction from P1 to P2.
        //V follows the thickness direction from P1 to P4.
        //---------------------------------------------------------------------
        LUx := ALayout.ActualEditQuad.P2.X - ALayout.ActualEditQuad.P1.X;
        LUy := ALayout.ActualEditQuad.P2.Y - ALayout.ActualEditQuad.P1.Y;
        LVx := ALayout.ActualEditQuad.P4.X - ALayout.ActualEditQuad.P1.X;
        LVy := ALayout.ActualEditQuad.P4.Y - ALayout.ActualEditQuad.P1.Y;

        NormalizeVector(
            LUx,
            LUy);

        NormalizeVector(
            LVx,
            LVy);

        //---------------------------------------------------------------------
        //Design marker drawing mode.
        //
        //The custom hover cursor is built from a monochrome AND/XOR mask so it
        //remains readable over any background. The design-time markers follow
        //the same principle directly on the component canvas.
        //
        //Using pmXor with clWhite inverts the destination pixels:
        //- on a light styled background, the markers become dark;
        //- on a dark styled background, the markers become light.
        //
        //This is more robust than using a fixed gray or even a resolved style
        //color, because the markers are drawn over the final rendered surface.
        //---------------------------------------------------------------------
        LHandleSize := 6.0;
        LHalfHandle := LHandleSize / 2.0;

        ACanvas.Pen.Mode := pmXor;
        ACanvas.Pen.Color := clWhite;
        ACanvas.Pen.Style := psSolid;
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := clWhite;

        //---------------------------------------------------------------------
        //Each corner receives the two inward directions that keep the marker
        //inside the actual edit quadrilateral.
        //---------------------------------------------------------------------
        DrawOrientedHandle(
            ALayout.ActualEditQuad.P1.X,
            ALayout.ActualEditQuad.P1.Y,
            LUx,
            LUy,
            LVx,
            LVy);

        DrawOrientedHandle(
            ALayout.ActualEditQuad.P2.X,
            ALayout.ActualEditQuad.P2.Y,
            -LUx,
            -LUy,
            LVx,
            LVy);

        DrawOrientedHandle(
            ALayout.ActualEditQuad.P3.X,
            ALayout.ActualEditQuad.P3.Y,
            -LUx,
            -LUy,
            -LVx,
            -LVy);

        DrawOrientedHandle(
            ALayout.ActualEditQuad.P4.X,
            ALayout.ActualEditQuad.P4.Y,
            LUx,
            LUy,
            -LVx,
            -LVy);
    Finally
        ACanvas.Pen.Color := LOldPenColor;
        ACanvas.Pen.Style := LOldPenStyle;
        ACanvas.Pen.Mode := LOldPenMode;
        ACanvas.Brush.Color := LOldBrushColor;
        ACanvas.Brush.Style := LOldBrushStyle;
    End;
End;

Procedure TRotatedEditCore.Paint;
Var
    LLayout: TRotatedEditLayoutResult;
    LColors: TRotatedEditStyleColors;
    LPaintBuffer: TBitmap;
    LPaintCanvas: TCanvas;

    Procedure DrawRotatedEditVisuals(ACanvas: TCanvas);
    Begin
        //---------------------------------------------------------------------
        //Draws the complete rotated edit visual state on the supplied canvas.
        //
        //This local helper deliberately contains the common part of both paint
        //paths:
        //- runtime path: draw into an off-screen bitmap, then BitBlt once;
        //- design-time path: draw directly on the control DC.
        //
        //Keeping the drawing sequence in one place avoids future divergences
        //between runtime and design-time rendering while allowing design-time
        //drag operations to bypass the runtime off-screen transparency emulation
        //that introduced a white rectangular host background in the IDE.
        //---------------------------------------------------------------------
        PaintTransparentBackground(ACanvas);

        ACanvas.Font.Assign(Font);
        Canvas.Font.Assign(Font);

        LLayout := BuildCurrentLayout;

        LColors := TRotatedEditStyle.ResolveColors(
            Self,
            Enabled,
            Focused,
            Color,
            Font.Color,
            FBorderColor,
            FPaletteMode = repmStyle,
            {$IFDEF VCLROTATEDEDIT_HAS_CONTROL_STYLE_NAME}
            StyleName,
            {$ELSE}
            '',
            {$ENDIF}
            StyleElements,
            FBorderStyle);

        //---------------------------------------------------------------------
        //Non-caret content.
        //
        //This call composes background, selection and text into a canonical opaque
        //surface, then projects it. There is no transparent color key, so the old
        //clFuchsia artifact cannot appear.
        //---------------------------------------------------------------------
        FRenderBackend.DrawContent(
            ACanvas,
            LLayout,
            LColors,
            FBackgroundBitmap,
            FBackgroundBitmapValid,
            FContentBitmap,
            FContentBitmapValid,
            FShowDebugBounds,
            FTextHint);

        //---------------------------------------------------------------------
        //Caret d'insertion.
        //
        //The caret stays outside the content bitmap. Its blink only invalidates the
        //control paint, not the cached background/content surfaces.
        //---------------------------------------------------------------------
        FRenderBackend.DrawCaret(
            ACanvas,
            LLayout,
            LColors,
            Focused And FCaretController.CaretVisible);

        DrawDesignSelectionMarkers(
            ACanvas,
            LLayout);
    End;

Begin
    //-------------------------------------------------------------------------
    //The control is not opaque.
    //
    //Runtime painting keeps the off-screen composition because it removes
    //the visible intermediate frame where the parent background is restored
    //before the rotated edit content is drawn.
    //
    //Design-time painting intentionally keeps the older direct-to-window path.
    //The IDE can repaint a component while it is being dragged/resized in ways
    //that do not behave like a normal runtime WM_PAINT. In that situation the
    //temporary bitmap could expose a white rectangular host area around the
    //rotated edit. Drawing directly in design-time restores the previous designer
    //behaviour while preserving the runtime flicker fix.
    //-------------------------------------------------------------------------

    If (ClientWidth <= 0) Or (ClientHeight <= 0) Then
        Exit;

    If csDesigning In ComponentState Then Begin
        DrawRotatedEditVisuals(Canvas);
        Exit;
    End;

    LPaintBuffer := TBitmap.Create;
    Try
        LPaintBuffer.PixelFormat := pf32bit;
        LPaintBuffer.SetSize(
            ClientWidth,
            ClientHeight);

        LPaintCanvas := LPaintBuffer.Canvas;

        DrawRotatedEditVisuals(LPaintCanvas);

        BitBlt(
            Canvas.Handle,
            0,
            0,
            ClientWidth,
            ClientHeight,
            LPaintCanvas.Handle,
            0,
            0,
            SRCCOPY);
    Finally
        LPaintBuffer.Free;
    End;
End;


Function TRotatedEditCore.BuildCurrentLayout: TRotatedEditLayoutResult;
Var
    LInput: TRotatedEditLayoutInput;
    LOldScrollOffset: Integer;
Begin
    //-------------------------------------------------------------------------
    //Builds the transient layout used by the current paint or hit-test pass.
    //
    //Important cache rule:
    //The layout may adjust FScrollOffset to keep the caret visible. Because the
    //content bitmap is drawn in canonical coordinates using that scroll offset, a
    //scroll change invalidates only the text bitmap. The caret cache does not
    //exist and the background cache is not affected.
    //-------------------------------------------------------------------------
    Canvas.Font.Assign(Font);

    LOldScrollOffset := FScrollOffset;

    LInput.ClientRect := ClientRect;
    LInput.LogicalLength := FLogicalLength;
    LInput.LogicalThickness := FLogicalThickness;
    LInput.PreferredLogicalThickness := ResolvePreferredLogicalThickness;
    //-------------------------------------------------------------------------
    //Border metrics rule.
    //
    //Do not model the edit frame as a hard-coded 1-pixel inset here. The active
    //VCL style may draw a normal TEdit with a 2-pixel frame, and the content
    //rectangle can be asymmetric. The layout must use the same inner rectangle
    //as the renderer so text, caret, selection and hit-testing stay aligned.
    //
    //BorderWidth is kept as a legacy scalar fallback for code that still reads
    //the input record. New layout code uses BorderMetrics.
    //-------------------------------------------------------------------------
    LInput.BorderWidth := Ord(FBorderStyle = bsSingle);
    LInput.BorderMetrics := TRotatedEditStyle.ResolveBorderMetrics(
        Canvas,
        Self,
        FPaletteMode = repmStyle,
        {$IFDEF VCLROTATEDEDIT_HAS_CONTROL_STYLE_NAME}
        StyleName,
        {$ELSE}
        '',
        {$ENDIF}
        StyleElements,
        FBorderStyle);
    LInput.PaddingLeft := FPaddingLeft;

    //---------------------------------------------------------------------
    //Single-line edit rule.
    //
    //Only TextPaddingStart/TextPaddingEnd are public. Cross-axis padding is
    //kept at zero because a mono-line edit should be centered inside
    //LogicalThickness unless a future explicit vertical alignment property is
    //introduced.
    //---------------------------------------------------------------------
    LInput.PaddingTop := 0;
    LInput.PaddingRight := FPaddingRight;
    LInput.PaddingBottom := 0;
    LInput.Text := FText;
    LInput.Angle := FAngle;
    LInput.ScrollOffset := FScrollOffset;
    LInput.CaretIndex := FCaretIndex;
    LInput.SelStart := FSelStart;
    LInput.SelLength := FSelLength;
    //---------------------------------------------------------------------
    // Keep the logical selection when focus is lost, but hide its visual
    // highlight for this paint/layout pass. This mirrors the default TEdit
    // behaviour and applies equally to the GDI and Direct2D backends.
    //---------------------------------------------------------------------
    LInput.SelectionVisible := Focused;
    LInput.CaretThickness := FCaretThickness;
    LInput.Alignment := FAlignment;
    LInput.UseCustomActualOrigin := FUseInternalOrigin;
    LInput.CustomActualOriginX := FInternalOriginX;
    LInput.CustomActualOriginY := FInternalOriginY;

    Result := FRenderBackend.BuildLayout(
        Canvas,
        LInput);

    FScrollOffset := Result.ScrollOffset;

    If FScrollOffset <> LOldScrollOffset Then
        InvalidateContentBitmap;
End;

Function TRotatedEditCore.NormalizeTextIndex(AIndex: Integer): Integer;
Begin
    //-------------------------------------------------------------------------
    //Normalizes any logical text index to the valid caret range.
    //
    //Caret indexes are zero-based insertion positions:
    //- 0 means before the first character;
    //- Length(Text) means after the last character.
    //
    //All keyboard and mouse selection code must pass through this rule before
    //writing FCaretIndex or FSelectionAnchor.
    //-------------------------------------------------------------------------
    Result := AIndex;

    If Result < 0 Then
        Result := 0;

    If Result > Length(FText) Then
        Result := Length(FText);
End;

Function TRotatedEditCore.IsWordChar(AChar: Char): Boolean;
Begin
    //-------------------------------------------------------------------------
    //Defines the V1 word-selection rule.
    //
    //A word is currently an ASCII identifier-like sequence:
    //letters, digits or underscore.
    //
    //This rule is intentionally simple and predictable. Unicode word breaking
    //can be introduced later without changing the double-click selection
    //contract.
    //-------------------------------------------------------------------------
    Result := (AChar >= 'A') And (AChar <= 'Z') Or (AChar >= 'a') And (AChar <= 'z') Or (AChar >= '0') And (AChar <= '9') Or (AChar = '_');
End;

Function TRotatedEditCore.FindWordStart(ACharIndex: Integer): Integer;
Begin
    //-------------------------------------------------------------------------
    //Returns the first 1-based character index of the word containing
    //ACharIndex.
    //
    //ACharIndex must point to a word character. The caller is responsible for
    //choosing the word character from the caret insertion index.
    //-------------------------------------------------------------------------
    Result := ACharIndex;

    While (Result > 1) And IsWordChar(FText[Result - 1]) Do
        Dec(Result);
End;

Function TRotatedEditCore.FindWordEnd(ACharIndex: Integer): Integer;
Begin
    //-------------------------------------------------------------------------
    //Returns the first 1-based character index after the word containing
    //ACharIndex.
    //
    //This "first after" convention maps directly to SelStart/SelLength:
    //SelStart  = WordStart - 1
    //SelLength = WordEnd - WordStart
    //-------------------------------------------------------------------------
    Result := ACharIndex;

    While (Result <= Length(FText)) And IsWordChar(FText[Result]) Do
        Inc(Result);
End;

Function TRotatedEditCore.UpdateClickCount(
    AX: Integer;
    AY: Integer): Integer;
Var
    LTick: Cardinal;
    LDeltaX: Integer;
    LDeltaY: Integer;
    LSameClickSequence: Boolean;
Begin
    //-------------------------------------------------------------------------
    //Updates and returns the current click count.
    //
    //This method centralizes the edit-click model:
    //- 1 click  = place caret / start drag selection;
    //- 2 clicks = select word;
    //- 3 clicks = select all text because TRotatedEdit is single-line.
    //
    //Why not rely only on DblClick?
    //-----------------------------
    //VCL double-click message ordering can vary depending on control state and
    //message handling. Some versions/routes call MouseDown around a double-click
    //message, others mostly expose DblClick. Keeping an explicit click counter
    //lets MouseDown and DblClick cooperate without turning a normal double-click
    //into a triple-click.
    //
    //The system double-click time and rectangle are used so the component follows
    //the user's Windows settings.
    //-------------------------------------------------------------------------
    LTick := GetTickCount;

    LDeltaX := Abs(AX - FLastClickPos.X);
    LDeltaY := Abs(AY - FLastClickPos.Y);

    LSameClickSequence :=
        (LTick - FLastClickTick <= Cardinal(GetDoubleClickTime)) And
        (LDeltaX <= GetSystemMetrics(SM_CXDOUBLECLK)) And
        (LDeltaY <= GetSystemMetrics(SM_CYDOUBLECLK));

    If LSameClickSequence Then
        Inc(FClickCount)
    Else
        FClickCount := 1;

    If FClickCount > 3 Then
        FClickCount := 1;

    FLastClickTick := LTick;
    FLastClickPos := Point(AX, AY);

    Result := FClickCount;
End;

Procedure TRotatedEditCore.SelectRange(
    AAnchorIndex: Integer;
    ACaretIndex: Integer);
Var
    LAnchor: Integer;
    LCaret:  Integer;
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Applies a selection from anchor to caret.
    //
    //FSelectionAnchor keeps the fixed end of the selection.
    //FCaretIndex keeps the active end.
    //FSelStart / FSelLength expose the normalized range.
    //
    //Never update SelStart/SelLength for extended selection without updating
    //the anchor and caret consistently, or Shift+Arrow and mouse drag will
    //start behaving differently.
    //-------------------------------------------------------------------------
    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    LAnchor := NormalizeTextIndex(AAnchorIndex);
    LCaret := NormalizeTextIndex(ACaretIndex);

    FSelectionAnchor := LAnchor;
    FCaretIndex := LCaret;

    If LCaret < LAnchor Then Begin
        FSelStart := LCaret;
        FSelLength := LAnchor - LCaret;
    End Else Begin
        FSelStart := LAnchor;
        FSelLength := LCaret - LAnchor;
    End;

    If (LOldCaretIndex <> FCaretIndex) Or
       (LOldSelStart <> FSelStart) Or
       (LOldSelLength <> FSelLength) Then
        SelectionChanged;

    FCaretController.ResetBlink;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SetCaretAndSelection(
    ACaretIndex: Integer;
    AExtendSelection: Boolean);
Var
    LCaret: Integer;
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Central caret movement rule.
    //
    //Without extension:
    //- move the caret;
    //- clear the selection;
    //- move the selection anchor to the caret.
    //
    //With extension:
    //- keep the existing anchor;
    //- move only the active caret;
    //- normalize SelStart/SelLength from anchor and caret.
    //
    //This method is used by both keyboard and mouse code so both inputs share
    //the same behavior.
    //-------------------------------------------------------------------------
    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    LCaret := NormalizeTextIndex(ACaretIndex);

    If AExtendSelection Then
        SelectRange(
            FSelectionAnchor,
            LCaret)
    Else Begin
        FCaretIndex := LCaret;
        FSelectionAnchor := LCaret;
        FSelStart := LCaret;
        FSelLength := 0;

        If (LOldCaretIndex <> FCaretIndex) Or
           (LOldSelStart <> FSelStart) Or
           (LOldSelLength <> FSelLength) Then
            SelectionChanged;

        InvalidateContentBitmap;
        FCaretController.ResetBlink;
        Invalidate;
    End;
End;

Procedure TRotatedEditCore.SelectWordAt(AIndex: Integer);
Var
    LIndex:     Integer;
    LCharIndex: Integer;
    LStartChar: Integer;
    LEndChar:   Integer;
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Selects the word under a caret insertion index.
    //
    //Hit-testing returns insertion indexes, not character indexes. If the caret
    //is before a word character, that character is used. If it is after a word
    //character, the previous character is used.
    //
    //If no adjacent word character exists, the selection is cleared at the
    //clicked caret position.
    //-------------------------------------------------------------------------
    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    LIndex := NormalizeTextIndex(AIndex);
    LCharIndex := 0;

    If (LIndex < Length(FText)) And IsWordChar(FText[LIndex + 1]) Then
        LCharIndex := LIndex + 1
    Else If (LIndex > 0) And IsWordChar(FText[LIndex]) Then
        LCharIndex := LIndex;

    If LCharIndex = 0 Then Begin
        SetCaretAndSelection(
            LIndex,
            False);
        Exit;
    End;

    LStartChar := FindWordStart(LCharIndex);
    LEndChar := FindWordEnd(LCharIndex);

    FSelectionAnchor := LStartChar - 1;
    FCaretIndex := LEndChar - 1;
    FSelStart := LStartChar - 1;
    FSelLength := LEndChar - LStartChar;

    If (LOldCaretIndex <> FCaretIndex) Or
       (LOldSelStart <> FSelStart) Or
       (LOldSelLength <> FSelLength) Then
        SelectionChanged;

    FCaretController.ResetBlink;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.SelectAllInternal;
Var
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Selects the whole single-line edit content.
    //
    //For a mono-line edit control, triple-click selection of the line is the
    //same operation as SelectAll.
    //-------------------------------------------------------------------------
    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    FSelectionAnchor := 0;
    FCaretIndex := Length(FText);
    FSelStart := 0;
    FSelLength := Length(FText);

    If (LOldCaretIndex <> FCaretIndex) Or
       (LOldSelStart <> FSelStart) Or
       (LOldSelLength <> FSelLength) Then
        SelectionChanged;

    FCaretController.ResetBlink;
    InvalidateContentBitmap;
    Invalidate;
End;

Procedure TRotatedEditCore.KeyDown(
    Var Key: Word;
    Shift: TShiftState);
Var
    LState:   TRotatedEditEditState;
    LChanged: Boolean;
Begin
    Inherited KeyDown(Key, Shift);

    

    If csDesigning In ComponentState Then
        Exit;

LChanged := False;

    //-------------------------------------------------------------------------
    //Arrow/Home/End selection is handled in the core, not in the edit engine.
    //
    //Reason:
    //The edit engine knows how to mutate text, but extended selection requires
    //a persistent anchor. That anchor is UI state owned by the control.
    //-------------------------------------------------------------------------
    Case Key Of
        VK_LEFT: Begin
                SetCaretAndSelection(
                    FCaretIndex - 1,
                    ssShift In Shift);
                Key := 0;
                Exit;
            End;

        VK_RIGHT: Begin
                SetCaretAndSelection(
                    FCaretIndex + 1,
                    ssShift In Shift);
                Key := 0;
                Exit;
            End;

        VK_HOME: Begin
                SetCaretAndSelection(
                    0,
                    ssShift In Shift);
                Key := 0;
                Exit;
            End;

        VK_END: Begin
                SetCaretAndSelection(
                    Length(FText),
                    ssShift In Shift);
                Key := 0;
                Exit;
            End;

        Ord('A'):
            If ssCtrl In Shift Then Begin
                SelectAllInternal;
                Key := 0;
                Exit;
            End;

        Ord('C'):
            If ssCtrl In Shift Then Begin
                CopyToClipboard;
                Key := 0;
                Exit;
            End;

        Ord('X'):
            If ssCtrl In Shift Then Begin
                CutToClipboard;
                Key := 0;
                Exit;
            End;

        Ord('V'):
            If ssCtrl In Shift Then Begin
                PasteFromClipboard;
                Key := 0;
                Exit;
            End;

        VK_RETURN: Begin
                EditingDone(redrEnter);
                Key := 0;
                Exit;
            End;

        VK_ESCAPE: Begin
                EditingDone(redrEscape);
                Key := 0;
                Exit;
            End;
    End;

    //-------------------------------------------------------------------------
    //Text mutation keys are still delegated to the edit engine.
    //-------------------------------------------------------------------------
    LState.Text := FText;
    LState.CaretIndex := FCaretIndex;
    LState.SelStart := FSelStart;
    LState.SelLength := FSelLength;
    LState.ReadOnly := FReadOnly;
    LState.MaxLength := FMaxLength;

    Case Key Of
        VK_BACK: Begin
                TRotatedEditEditEngine.DeleteBackward(LState);
                LChanged := True;
            End;

        VK_DELETE: Begin
                TRotatedEditEditEngine.DeleteForward(LState);
                LChanged := True;
            End;
    End;

    If LChanged Then Begin
        ApplyEditState(
            LState.Text,
            LState.CaretIndex,
            LState.SelStart,
            LState.SelLength);

        Key := 0;
    End;
End;

Procedure TRotatedEditCore.KeyPress(Var Key: Char);
Var
    LState: TRotatedEditEditState;
    LInsertText: String;
Begin
    Inherited KeyPress(Key);

    

    If csDesigning In ComponentState Then
        Exit;

If Key < #32 Then
        Exit;

    LInsertText := NormalizeInsertedText(Key);

    If LInsertText = '' Then Begin
        Key := #0;
        Exit;
    End;

    LState.Text := FText;
    LState.CaretIndex := FCaretIndex;
    LState.SelStart := FSelStart;
    LState.SelLength := FSelLength;
    LState.ReadOnly := FReadOnly;
    LState.MaxLength := FMaxLength;

    TRotatedEditEditEngine.InsertText(
        LState,
        LInsertText);

    ApplyEditState(
        LState.Text,
        LState.CaretIndex,
        LState.SelStart,
        LState.SelLength);

    Key := #0;
End;

Procedure TRotatedEditCore.MouseDown(
    Button: TMouseButton;
    Shift: TShiftState;
    X: Integer;
    Y: Integer);
Var
    LLayout: TRotatedEditLayoutResult;
    LHit: TRotatedEditHitTestResult;
    LClickCount: Integer;
Begin
    Inherited MouseDown(Button, Shift, X, Y);

    //-------------------------------------------------------------------------
    //Designer-resize session cleanup.
    //
    //This reset intentionally happens BEFORE the design-time exit below.
    //
    //A previous cleanup cleared the designer resize lock when a normal mouse interaction
    //started. Later versions added an early design-time exit so the IDE designer
    //could keep ownership of selection and drag gestures, but that also skipped
    //this cleanup. A stale FDesignerResizeGrip can make a later designer resize
    //reuse an old target dimension / old anchor and visually behave as if both
    //logical directions were changing.
    //
    //The edit engine still does not handle the design-time click. We only reset
    //the internal resize session state that belongs to the component.
    //-------------------------------------------------------------------------
    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;

    //-------------------------------------------------------------------------
    //At design time the IDE designer owns mouse gestures. The edit engine must
    //not interpret clicks, drags, double-clicks or selection gestures while the
    //component is being positioned on a form.
    //-------------------------------------------------------------------------
    If csDesigning In ComponentState Then
        Exit;

    If Button <> mbLeft Then
        Exit;

    SetFocus;

    LClickCount := UpdateClickCount(
        X,
        Y);

    LLayout := BuildCurrentLayout;

    LHit := FRenderBackend.HitTest(
        Canvas,
        LLayout,
        Point(X, Y));

    Case LClickCount Of
        1:
            Begin
                If ssShift In Shift Then Begin
                    //-----------------------------------------------------------------
                    //Shift-click extends the existing selection anchor.
                    //-----------------------------------------------------------------
                    SetCaretAndSelection(
                        LHit.InsertionIndex,
                        True);
                End Else Begin
                    //-----------------------------------------------------------------
                    //Normal click starts a new possible mouse-drag selection.
                    //-----------------------------------------------------------------
                    SetCaretAndSelection(
                        LHit.InsertionIndex,
                        False);

                    FSelectionAnchor := FCaretIndex;
                End;

                FMouseSelecting := True;
                MouseCapture := True;
            End;

        2:
            Begin
                //---------------------------------------------------------------------
                //Double-click selects the word under the pointer.
                //
                //Do not start drag selection here. The current selection is a semantic
                //selection, not a mouse-capture operation.
                //---------------------------------------------------------------------
                SelectWordAt(LHit.InsertionIndex);
                FMouseSelecting := False;
                MouseCapture := False;
            End;

        3:
            Begin
                //---------------------------------------------------------------------
                //Triple-click selects the whole single-line edit content.
                //---------------------------------------------------------------------
                SelectAllInternal;
                FMouseSelecting := False;
                MouseCapture := False;
                FClickCount := 0;
            End;
    End;
End;

Procedure TRotatedEditCore.MouseMove(
    Shift: TShiftState;
    X: Integer;
    Y: Integer);
Var
    LLayout: TRotatedEditLayoutResult;
    LHit:    TRotatedEditHitTestResult;
Begin
    Inherited MouseMove(Shift, X, Y);

    

    //-------------------------------------------------------------------------
    //At design time the IDE designer owns mouse gestures. The edit engine must
    //not interpret clicks, drags, double-clicks or selection gestures while the
    //component is being positioned on a form.
    //-------------------------------------------------------------------------
    If csDesigning In ComponentState Then
        Exit;

//-------------------------------------------------------------------------
    //Hover cursor rule.
    //
    //The cursor is handled in WM_SETCURSOR, not in MouseMove. MouseMove owns
    //selection tracking only. Keeping cursor selection out of this method avoids
    //mixing visual feedback with drag-selection logic.
    //-------------------------------------------------------------------------

    If Not FMouseSelecting Then
        Exit;

    If GetKeyState(VK_LBUTTON) >= 0 Then Begin
        FMouseSelecting := False;
        MouseCapture := False;
        Exit;
    End;

    //-------------------------------------------------------------------------
    //Mouse drag selection rule.
    //
    //The mouse point is always hit-tested through the layout engine, therefore
    //screen coordinates are converted back to canonical coordinates before an
    //insertion index is calculated.
    //-------------------------------------------------------------------------
    LLayout := BuildCurrentLayout;

    LHit := FRenderBackend.HitTest(
        Canvas,
        LLayout,
        Point(X, Y));

    SelectRange(
        FSelectionAnchor,
        LHit.InsertionIndex);
End;

Procedure TRotatedEditCore.MouseUp(
    Button: TMouseButton;
    Shift: TShiftState;
    X: Integer;
    Y: Integer);
Begin
    Inherited MouseUp(Button, Shift, X, Y);

    //-------------------------------------------------------------------------
    //Designer-resize session cleanup.
    //
    //This reset intentionally happens BEFORE the design-time exit below.
    //
    //The Delphi designer does not give this control a clean resize-begin /
    //resize-end notification. The component therefore relies on ordinary mouse messages
    //to clear the inferred resize grip between gestures.
    //
    //When the design-time early exit was introduced, this cleanup was skipped.
    //That could keep FDesignerResizeGrip / the locked resize direction alive
    //after the gesture had ended. The next resize could then reuse stale session
    //state and lose the golden rule: one designer resize edits either
    //LogicalLength or LogicalThickness, never both.
    //-------------------------------------------------------------------------
    FDesignerResizeGrip := rerzNone;
    FDesignerResizeLastTick := 0;

    //-------------------------------------------------------------------------
    //At design time the IDE designer owns mouse gestures. The edit engine must
    //not interpret clicks, drags, double-clicks or selection gestures while the
    //component is being positioned on a form.
    //-------------------------------------------------------------------------
    If csDesigning In ComponentState Then
        Exit;

    If Button = mbLeft Then Begin
        //-------------------------------------------------------------------------
        //Mouse capture is used only while dragging a selection. It must be
        //released as soon as the button is released, otherwise the control would
        //continue to receive mouse messages that belong to other controls.
        //-------------------------------------------------------------------------
        FMouseSelecting := False;
        MouseCapture := False;
    End;
End;

Procedure TRotatedEditCore.DblClick;
Var
    LLayout: TRotatedEditLayoutResult;
    LHit: TRotatedEditHitTestResult;
    LPoint: TPoint;
Begin
    Inherited DblClick;

    //-------------------------------------------------------------------------
    //Double-click fallback.
    //
    //The primary double-click path is WMLButtonDblClk because it gives direct
    //access to the click coordinates and avoids ambiguity with MouseDown click
    //counting. This override remains as a safety net for VCL message routes that
    //call DblClick without passing through our message method.
    //
    //Important:
    //DblClick must never select the full text. Triple-click is handled only by
    //a later WM_LBUTTONDOWN reaching click count 3.
    //-------------------------------------------------------------------------
    LPoint := ScreenToClient(Mouse.CursorPos);

    LLayout := BuildCurrentLayout;

    LHit := FRenderBackend.HitTest(
        Canvas,
        LLayout,
        LPoint);

    SelectWordAt(LHit.InsertionIndex);

    FLastClickTick := GetTickCount;
    FLastClickPos := LPoint;
    FClickCount := 2;

    FMouseSelecting := False;
    MouseCapture := False;
End;

Procedure TRotatedEditCore.DoEnter;
Begin
    Inherited DoEnter;

    FCaretController.StartBlink;
    Invalidate;
End;

Procedure TRotatedEditCore.DoExit;
Begin
    Inherited DoExit;

    FCaretController.StopBlink;
    EditingDone(redrFocusLost);
    Invalidate;
End;

Function TRotatedEditCore.CanApplyTextChange(
    Const AOldText: String;
    Const ANewText: String): Boolean;
Begin
    //-------------------------------------------------------------------------
    //Central immediate text-change veto point.
    //
    //Every path that wants to replace the stored Text value must pass through
    //this method before assigning FText. This keeps keyboard input, clipboard
    //operations and programmatic Text assignment consistent.
    //
    //Do not call OnValidate here. OnValidate belongs to the end of an editing
    //session; OnCanChange belongs to an individual candidate mutation.
    //-------------------------------------------------------------------------
    Result := True;

    If AOldText = ANewText Then
        Exit;

    If Assigned(FOnCanChange) Then
        FOnCanChange(
            Self,
            AOldText,
            ANewText,
            Result);
End;

Procedure TRotatedEditCore.EditingStart;
Begin
    //-------------------------------------------------------------------------
    //Starts a logical editing session.
    //
    //This method is intentionally not called from DoEnter. A user can focus the
    //control, move the caret or select text without modifying the value. The
    //event is raised only before the first accepted user text mutation.
    //-------------------------------------------------------------------------
    If FEditingStarted Then
        Exit;

    FEditingStarted := True;

    If Assigned(FOnEditingStart) Then
        FOnEditingStart(Self);
End;

Procedure TRotatedEditCore.TextChanged;
Begin
    If Assigned(FOnChange) Then
        FOnChange(Self);
End;

Procedure TRotatedEditCore.SelectionChanged;
Begin
    If Assigned(FOnSelectionChange) Then
        FOnSelectionChange(Self);
End;

Procedure TRotatedEditCore.EditingDone(AReason: TRotatedEditEditingDoneReason);
Var
    LValidation: TRotatedEditValidationResult;
Begin
    LValidation := revAccept;

    If Assigned(FOnValidate) Then
        FOnValidate(
            Self,
            FText,
            LValidation);

    If LValidation = revReject Then
        Exit;

    FEditingStarted := False;

    If Assigned(FOnEditingDone) Then
        FOnEditingDone(
            Self,
            AReason);
End;

Procedure TRotatedEditCore.ApplyEditState(
    Const AText: String;
    ACaretIndex: Integer;
    ASelStart: Integer;
    ASelLength: Integer);
Var
    LTextChanged: Boolean;
    LSelectionChanged: Boolean;
    LOldCaretIndex: Integer;
    LOldSelStart: Integer;
    LOldSelLength: Integer;
Begin
    //-------------------------------------------------------------------------
    //Applies the result of a user edit operation.
    //
    //This is the central commit point for keyboard editing, cut and paste. It
    //raises OnCanChange before assigning FText, raises OnEditingStart only for
    //accepted user mutations, and then emits OnChange / OnSelectionChange from
    //the final normalized state.
    //-------------------------------------------------------------------------
    LTextChanged := FText <> AText;

    If LTextChanged And
       Not CanApplyTextChange(
           FText,
           AText) Then
        Exit;

    LOldCaretIndex := FCaretIndex;
    LOldSelStart := FSelStart;
    LOldSelLength := FSelLength;

    If LTextChanged Then
        EditingStart;

    FText := AText;
    FCaretIndex := NormalizeTextIndex(ACaretIndex);
    FSelStart := NormalizeTextIndex(ASelStart);
    FSelLength := ASelLength;

    If FSelLength < 0 Then
        FSelLength := 0;

    If FSelStart + FSelLength > Length(FText) Then
        FSelLength := Length(FText) - FSelStart;

    If FSelLength = 0 Then
        FSelectionAnchor := FCaretIndex
    Else
        FSelectionAnchor := FSelStart;

    LSelectionChanged :=
        (LOldCaretIndex <> FCaretIndex) Or
        (LOldSelStart <> FSelStart) Or
        (LOldSelLength <> FSelLength);

    If LTextChanged Then Begin
        TextChanged;
        InvalidateContentBitmap;
    End;

    If LSelectionChanged Then
        SelectionChanged;

    FCaretController.ResetBlink;
    Invalidate;
End;

Procedure TRotatedEditCore.Clear;
Begin
    SetText('');
End;

Procedure TRotatedEditCore.SelectAll;
Begin
    //-------------------------------------------------------------------------
    //Public SelectAll entry point.
    //
    //The internal method centralizes anchor/caret/range consistency.
    //-------------------------------------------------------------------------
    SelectAllInternal;
End;


Procedure TRotatedEditCore.ClearSelection;
Var
    LState: TRotatedEditEditState;
Begin
    //-------------------------------------------------------------------------
    //Deletes the current selection without touching the clipboard.
    //
    //This is the public counterpart of the internal selection deletion used by
    //Backspace, Delete and Cut. It deliberately uses ApplyEditState instead of
    //editing fields directly so validation, notifications, caret normalization
    //and rendering invalidation remain centralized.
    //-------------------------------------------------------------------------
    If FReadOnly Then
        Exit;

    If FSelLength <= 0 Then
        Exit;

    LState.Text := FText;
    LState.CaretIndex := FCaretIndex;
    LState.SelStart := FSelStart;
    LState.SelLength := FSelLength;
    LState.ReadOnly := FReadOnly;
    LState.MaxLength := FMaxLength;

    TRotatedEditEditEngine.DeleteSelection(LState);

    ApplyEditState(
        LState.Text,
        LState.CaretIndex,
        LState.SelStart,
        LState.SelLength);
End;

Procedure TRotatedEditCore.CopyToClipboard;
Begin
    If FSelLength <= 0 Then
        Exit;

    TRotatedEditClipboard.SetClipboardText(Copy(FText, FSelStart + 1, FSelLength));
End;

Procedure TRotatedEditCore.CutToClipboard;
Var
    LState: TRotatedEditEditState;
Begin
    If FReadOnly Then
        Exit;

    CopyToClipboard;

    LState.Text := FText;
    LState.CaretIndex := FCaretIndex;
    LState.SelStart := FSelStart;
    LState.SelLength := FSelLength;
    LState.ReadOnly := FReadOnly;
    LState.MaxLength := FMaxLength;

    TRotatedEditEditEngine.DeleteSelection(LState);

    ApplyEditState(
        LState.Text,
        LState.CaretIndex,
        LState.SelStart,
        LState.SelLength);
End;

Procedure TRotatedEditCore.PasteFromClipboard;
Var
    LState: TRotatedEditEditState;
Begin
    If FReadOnly Then
        Exit;

    If Not TRotatedEditClipboard.CanPasteText Then
        Exit;

    LState.Text := FText;
    LState.CaretIndex := FCaretIndex;
    LState.SelStart := FSelStart;
    LState.SelLength := FSelLength;
    LState.ReadOnly := FReadOnly;
    LState.MaxLength := FMaxLength;

    TRotatedEditEditEngine.InsertText(
        LState,
        NormalizeInsertedText(TRotatedEditClipboard.GetClipboardText));

    ApplyEditState(
        LState.Text,
        LState.CaretIndex,
        LState.SelStart,
        LState.SelLength);
End;

Initialization
    //-------------------------------------------------------------------------
    //Register a neutral VCL style hook for the base control class.
    //
    //TRotatedEditCore remains fully owner-drawn: the hook is not expected to
    //paint the rotated edit surface. The visual result still comes from Paint,
    //TRotatedEditStyle and the active render backend.
    //
    //The hook is kept as a compatibility/integration aid so the VCL style
    //engine can treat the control as style-aware. The registration deliberately uses the
    //neutral TStyleHook rather than TEditStyleHook because this control is not a
    //native TEdit and does not let the edit style hook perform the painting.
    //-------------------------------------------------------------------------
    TCustomStyleEngine.RegisterStyleHook(
        TRotatedEditCore,
        TStyleHook);

Finalization
    TCustomStyleEngine.UnregisterStyleHook(
        TRotatedEditCore,
        TStyleHook);

End.
