Program VclRotatedEditDemo;

uses
  Vcl.Forms,
  VclRotatedEditDemoMain in 'VclRotatedEditDemoMain.pas' {RotatedEditDemoForm},
  VclRotatedEdit in '..\Src\VclRotatedEdit.pas',
  VclRotatedEdit_Core in '..\Src\VclRotatedEdit_Core.pas',
  VclRotatedEdit_Types in '..\Src\VclRotatedEdit_Types.pas',
  VclRotatedEdit_Geometry in '..\Src\VclRotatedEdit_Geometry.pas',
  VclRotatedEdit_Layout in '..\Src\VclRotatedEdit_Layout.pas',
  VclRotatedEdit_EditEngine in '..\Src\VclRotatedEdit_EditEngine.pas',
  VclRotatedEdit_Render in '..\Src\VclRotatedEdit_Render.pas',
  VclRotatedEdit_Caret in '..\Src\VclRotatedEdit_Caret.pas',
  VclRotatedEdit_Clipboard in '..\Src\VclRotatedEdit_Clipboard.pas',
  VclRotatedEdit_Style in '..\Src\VclRotatedEdit_Style.pas',
  Vcl.Themes,
  Vcl.Styles;

{$R *.res}

Begin
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    TStyleManager.TrySetStyle('Windows10 SlateGray');
  Application.CreateForm(TRotatedEditDemoForm, RotatedEditDemoForm);
  Application.Run;

End.
