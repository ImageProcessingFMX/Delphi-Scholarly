unit GUI.FMX.ScholarlyDownload;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types,
  FMX.ScrollBox, FMX.Memo, FMX.Controls.Presentation, FMX.StdCtrls, FMX.Objects,

  ///
  ///
  ///
   Unit_TScholarly,  Unit_StringGridHelper, System.Rtti, FMX.Grid.Style, FMX.Grid,
  FMX.Edit ;

type
  TMainForm = class(TForm)
    rctngl1: TRectangle;
    pnl1: TPanel;
    mmo_QueryResults: TMemo;
    mmo_QueryKeyWords: TMemo;
    CornerButton_Close: TCornerButton;
    CornerButton_Download: TCornerButton;
    lbl1_SearchKeywords: TLabel;
    StringGrid1: TStringGrid;
    chk_exportasJSON: TCheckBox;
    chk_exportasBIBTEX: TCheckBox;
    chk_exportasCSV: TCheckBox;
    Edit1: TEdit;
    procedure CornerButton_DownloadClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private




    FScholarly: TScholarly;

    FOriginalPapers: TPaperList;  // Store original data

    FExportFilename : String ;


    procedure SetupGrid;
    { Private-Deklarationen }
  public
    { Public-Deklarationen }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

procedure TMainForm.CornerButton_DownloadClick(Sender: TObject);
var
      i : Integer;
      QueryStr : String;
begin


    QueryStr := mmo_QueryKeyWords.Text;



    // S.MailTo := 'you@domain.com'; // optional but recommended
    FScholarly.DownloadPapers(QueryStr, 1000, 200, 300);



        // Display in Memo
    mmo_QueryResults.Lines.Clear;
    mmo_QueryResults.Lines.Add('Total Papers: ' + IntToStr( FScholarly.PaperList.Count));
    mmo_QueryResults.Lines.Add('-----------------------------------');
    for I := 0 to FScholarly.PaperList.Count - 1 do
    begin
      with FScholarly.PaperList[I] do
      begin
        mmo_QueryResults.Lines.Add(Format('[%d] %s', [I+1, Title]));
        mmo_QueryResults.Lines.Add('Authors: ' + Authors);
        mmo_QueryResults.Lines.Add(Format('Year: %d | Citations: %d', [Year, Citations]));
        mmo_QueryResults.Lines.Add('DOI: ' + DOI);
        mmo_QueryResults.Lines.Add('-----------------------------------');
      end;
    end;


        // Load into StringGrid with auto headers
    StringGrid1.LoadFromList<TPaperRecord>(FScholarly.PaperList);



// Export based on checkbox selections
    if chk_exportasCSV.IsChecked then
      FScholarly.SavePaperListToCSV('c:\temp\papers.csv');

    if chk_exportasJSON.IsChecked then
       FScholarly.SavePaperListToJSON('c:\temp\papers.json');

    if chk_exportasBIBTEX.IsChecked then
       FScholarly.SavePaperListToBIB('c:\temp\papers.bib');

end;



procedure TMainForm.FormCreate(Sender: TObject);
begin
        FScholarly := TScholarly.Create;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
      FScholarly.Free;
end;

procedure TMainForm.SetupGrid;
begin

end;




end.
