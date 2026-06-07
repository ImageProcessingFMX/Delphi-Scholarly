program Scholarly;

uses
  System.StartUpCopy,
  FMX.Forms,
  GUI.FMX.ScholarlyDownload in 'GUI.FMX.ScholarlyDownload.pas' {MainForm},
  Unit_TScholarly in 'Unit_TScholarly.pas',
  Unit_StringGridHelper in 'Unit_StringGridHelper.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
