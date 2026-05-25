Unit VclRotatedEdit_Design;


{
  VclRotatedEdit_Design.pas

  VclRotatedEdit
  Copyright (c) 2026 Marc BAUMSTIMLER

  Design-time selection support of the VclRotatedEdit VCL component.

  Repository:
  https://github.com/mbaumsti/VclRotatedEdit

  License:
  See LICENSE file.

  ------------------------------------------------------------------------------

  Support design-time de sélection du composant VCL VclRotatedEdit.

  Cette unité appartient au paquet design-time. Elle observe la sélection de l’IDE et transmet au contrôle l’état nécessaire pour dessiner ses marqueurs de sélection.
}

Interface

Procedure RegisterRotatedEditDesignSupport;

Implementation

Uses
    System.Classes,
    DesignIntf,
    VclRotatedEdit;

Type
    {
      IDE selection observer for TRotatedEdit.

      The notifier is intentionally small:
      - it reacts to SelectionChanged;
      - it walks the components owned by the current designer root;
      - it forwards selected / multiple-selection state to TRotatedEdit;
      - it keeps no persistent component pointer cache.
    }
    TRotatedEditDesignNotifier = Class(TInterfacedObject, IDesignNotification)
    private
        Procedure ApplySelection(
            Const ADesigner: IDesigner;
            Const ASelection: IDesignerSelections);
    public
        Procedure ItemDeleted(
            Const ADesigner: IDesigner;
            AItem: TPersistent);

        Procedure ItemInserted(
            Const ADesigner: IDesigner;
            AItem: TPersistent);

        Procedure ItemsModified(
            Const ADesigner: IDesigner);

        Procedure SelectionChanged(
            Const ADesigner: IDesigner;
            Const ASelection: IDesignerSelections);

        Procedure DesignerOpened(
            Const ADesigner: IDesigner;
            AResurrecting: Boolean);

        Procedure DesignerClosed(
            Const ADesigner: IDesigner;
            AGoingDormant: Boolean);
    End;

Var
    GNotifier: IDesignNotification = Nil;

Procedure TRotatedEditDesignNotifier.ApplySelection(
    Const ADesigner: IDesigner;
    Const ASelection: IDesignerSelections);
Var
    I: Integer;
    J: Integer;
    LRoot: TComponent;
    LComponent: TComponent;
    LItem: TPersistent;
    LSelected: Boolean;
    LMultipleSelection: Boolean;
Begin
    //-------------------------------------------------------------------------
    //Synchronizes all TRotatedEdit components owned by the current designer root
    //with the IDE selection.
    //
    //Important:
    //No component pointer is stored after this method returns. This avoids the
    //invalid-pointer problems caused by stale cached selection lists during
    //package unload, form close or component deletion.
    //-------------------------------------------------------------------------
    If ADesigner = Nil Then
        Exit;

    LRoot := ADesigner.Root;

    If LRoot = Nil Then
        Exit;

    LMultipleSelection := (ASelection <> Nil) And (ASelection.Count > 1);

    For I := 0 To LRoot.ComponentCount - 1 Do Begin
        LComponent := LRoot.Components[I];

        If LComponent Is TRotatedEdit Then Begin
            LSelected := False;

            If ASelection <> Nil Then Begin
                For J := 0 To ASelection.Count - 1 Do Begin
                    LItem := ASelection.Items[J];

                    If LItem = LComponent Then Begin
                        LSelected := True;
                        Break;
                    End;
                End;
            End;

            TRotatedEdit(LComponent).SetDesignSelectionStateForDesigner(
                LSelected,
                LMultipleSelection);
        End;
    End;
End;

Procedure TRotatedEditDesignNotifier.ItemDeleted(
    Const ADesigner: IDesigner;
    AItem: TPersistent);
Begin
    //-------------------------------------------------------------------------
    //No cached component pointer: nothing to clear.
    //-------------------------------------------------------------------------
End;

Procedure TRotatedEditDesignNotifier.ItemInserted(
    Const ADesigner: IDesigner;
    AItem: TPersistent);
Begin
    //No action required.
End;

Procedure TRotatedEditDesignNotifier.ItemsModified(
    Const ADesigner: IDesigner);
Begin
    //No action required.
End;

Procedure TRotatedEditDesignNotifier.SelectionChanged(
    Const ADesigner: IDesigner;
    Const ASelection: IDesignerSelections);
Begin
    ApplySelection(
        ADesigner,
        ASelection);
End;

Procedure TRotatedEditDesignNotifier.DesignerOpened(
    Const ADesigner: IDesigner;
    AResurrecting: Boolean);
Begin
    //No action required.
End;

Procedure TRotatedEditDesignNotifier.DesignerClosed(
    Const ADesigner: IDesigner;
    AGoingDormant: Boolean);
Begin
    //No cached component pointer: nothing to clear.
End;

Procedure RegisterRotatedEditDesignSupport;
Begin
    //-------------------------------------------------------------------------
    //Registers the global design-time selection observer.
    //
    //Calling this method more than once is harmless because the notifier is
    //created only once per loaded design-time package instance.
    //-------------------------------------------------------------------------
    If GNotifier = Nil Then Begin
        GNotifier := TRotatedEditDesignNotifier.Create;
        RegisterDesignNotification(GNotifier);
    End;
End;

Initialization

Finalization
    If GNotifier <> Nil Then Begin
        UnregisterDesignNotification(GNotifier);
        GNotifier := Nil;
    End;

End.
