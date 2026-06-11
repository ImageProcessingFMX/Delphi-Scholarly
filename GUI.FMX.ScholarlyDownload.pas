unit GUI.FMX.ScholarlyDownload;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types,
  FMX.ScrollBox, FMX.Memo, FMX.Controls.Presentation, FMX.StdCtrls, FMX.Objects,

  ///
  ///
  ///
  Unit_TScholarly, Unit_StringGridHelper, System.Rtti, FMX.Grid.Style, FMX.Grid,
  FMX.Edit, FMX.ListBox;

const
  MaxPApers = 2000;

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
    EditFilename: TEdit;
    ComboBox_FilterResults: TComboBox;
    Label_SaveFile: TLabel;
    Label_SortResults: TLabel;
    ComboBox_PaperIndex: TComboBox;
    Label_PaperDetails: TLabel;
    ComboBox_MaxPapers: TComboBox;
    procedure CornerButton_DownloadClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ComboBox_PaperIndexChange(Sender: TObject);
  private

    FScholarly: TScholarly;

    FOriginalPapers: TPaperList; // Store original data

    FExportFilename: String;

    FMaxPapers: Integer;

    procedure ComboBox_FilterResultsChange(Sender: TObject);
    procedure PrintPaperRecord(aPAper: TPaperRecord);
    procedure FillPaperIndexCombo;
    procedure DumpPaperRefsToMemo(const N: Integer);
    { Private-Deklarationen }
  public
    { Public-Deklarationen }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

function SetValidExtension(const Filename, NewExt: string): string;
begin
  if FileExists(Filename) then
    Result := ChangeFileExt(Filename, NewExt)
  else
    Result := ChangeFileExt('C:\Temp\papers.csv', NewExt);
end;

procedure TMainForm.PrintPaperRecord(aPAper: TPaperRecord);
begin
  with aPAper do
  begin
    mmo_QueryResults.Lines.Add(Format('[%d] %s', [aPAper.Index, Title]));
    mmo_QueryResults.Lines.Add('Authors: ' + Authors);
    mmo_QueryResults.Lines.Add(Format('Year: %d | Citations: %d',
      [Year, Citations]));
    mmo_QueryResults.Lines.Add('DOI: ' + DOI);
    mmo_QueryResults.Lines.Add('-----------------------------------');
  end;

end;

procedure TMainForm.FillPaperIndexCombo;
var
  i: Integer;
begin
  ComboBox_PaperIndex.Clear;
  for i := 0 to FScholarly.PaperList.Count - 1 do
    ComboBox_PaperIndex.Items.Add(IntToStr(FScholarly.PaperList[i].Index));
  // or 'Index: Title'
end;

procedure TMainForm.ComboBox_PaperIndexChange(Sender: TObject);
var
  N: Integer;
begin
  if ComboBox_PaperIndex.ItemIndex < 0 then
    Exit;

  // If you store "Index: Title" in Items, parse the leading number.
  // Otherwise, if Items are just numbers, StrToInt is enough.
  N := StrToIntDef(Trim(ComboBox_PaperIndex.Items
    [ComboBox_PaperIndex.ItemIndex]), -1);

  DumpPaperRefsToMemo(N);

end;

procedure TMainForm.DumpPaperRefsToMemo(const N: Integer);
  function FindPaperPosByIndex(const AIndex: Integer): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    for i := 0 to FScholarly.PaperList.Count - 1 do
      if FScholarly.PaperList[i].Index = AIndex then
        Exit(i);
  end;

  function PaperCaptionByPos(const Pos: Integer): string;
  begin
    Result := Format('[%d] %s', [FScholarly.PaperList[Pos].Index,
      FScholarly.PaperList[Pos].Title]);
  end;

var
  PosN, i, RefIdx, PosOther: Integer;
  P: TPaperRecord;
begin
  mmo_QueryResults.Lines.BeginUpdate;
  try
    mmo_QueryResults.Lines.Clear;

    if FScholarly.PaperList.Count = 0 then
    begin
      mmo_QueryResults.Lines.Add('No papers downloaded.');
      Exit;
    end;

    PosN := FindPaperPosByIndex(N);
    if PosN < 0 then
    begin
      mmo_QueryResults.Lines.Add(Format('Paper with Index %d not found.', [N]));
      Exit;
    end;

    P := FScholarly.PaperList[PosN];

    mmo_QueryResults.Lines.Add('Selected paper:');
    mmo_QueryResults.Lines.Add('  ' + PaperCaptionByPos(PosN));
    mmo_QueryResults.Lines.Add('');

    // ---- References (outgoing) ----
    mmo_QueryResults.Lines.Add(Format('References (papers that [%d] cites): %d',
      [P.Index, Length(P.References)]));
    if Length(P.References) = 0 then
      mmo_QueryResults.Lines.Add('  (none)')
    else
    begin
      for i := 0 to High(P.References) do
      begin
        RefIdx := P.References[i];

        // If "References" stores positions, this will work directly.
        // If it stores "Index" values instead, we try to find by Index too.
        if (RefIdx >= 0) and (RefIdx < FScholarly.PaperList.Count) then
          mmo_QueryResults.Lines.Add('  -> ' + PaperCaptionByPos(RefIdx))
        else
        begin
          PosOther := FindPaperPosByIndex(RefIdx);
          if PosOther >= 0 then
            mmo_QueryResults.Lines.Add('  -> ' + PaperCaptionByPos(PosOther))
          else
            mmo_QueryResults.Lines.Add
              (Format('  -> [%d] (not found in current list)', [RefIdx]));
        end;
      end;
    end;

    mmo_QueryResults.Lines.Add('');
    mmo_QueryResults.Lines.Add('-----------------------------------');
    mmo_QueryResults.Lines.Add('');

    // ---- ReferencedBy (incoming) ----
    mmo_QueryResults.Lines.Add
      (Format('ReferencedBy (papers that cite [%d]): %d',
      [P.Index, Length(P.ReferencedBy)]));
    if Length(P.ReferencedBy) = 0 then
      mmo_QueryResults.Lines.Add('  (none)')
    else
    begin
      for i := 0 to High(P.ReferencedBy) do
      begin
        RefIdx := P.ReferencedBy[i];

        // In your inverse-building code, ReferencedBy stores positions (I) [4]
        if (RefIdx >= 0) and (RefIdx < FScholarly.PaperList.Count) then
          mmo_QueryResults.Lines.Add('  <- ' + PaperCaptionByPos(RefIdx))
        else
        begin
          PosOther := FindPaperPosByIndex(RefIdx);
          if PosOther >= 0 then
            mmo_QueryResults.Lines.Add('  <- ' + PaperCaptionByPos(PosOther))
          else
            mmo_QueryResults.Lines.Add
              (Format('  <- [%d] (not found in current list)', [RefIdx]));
        end;
      end;
    end;

  finally
    mmo_QueryResults.Lines.EndUpdate;
  end;
end;

procedure TMainForm.CornerButton_DownloadClick(Sender: TObject);
var
  i: Integer;
  QueryStr: String;
  FMinDelay: Integer;
  FMaxDelay: Integer;
begin

  QueryStr := mmo_QueryKeyWords.Text;

  FExportFilename := EditFilename.Text;

  // Get MaxPapers from UI with validation
  if not TryStrToInt(ComboBox_MaxPapers.Items[ComboBox_MaxPapers.ItemIndex],
    FMaxPapers) then
    FMaxPapers := 500; // default
  // Validate range
  if FMaxPapers < 1 then
    FMaxPapers := 1;
  if FMaxPapers > 1000 then
    FMaxPapers := 1000; // reasonable limit
  // Adaptive delays based on paper count
  if FMaxPapers <= 100 then
  begin
    FMinDelay := 150;
    FMaxDelay := 250;
  end
  else if FMaxPapers <= 500 then
  begin
    FMinDelay := 200;
    FMaxDelay := 300;
  end
  else
  begin
    FMinDelay := 250;
    FMaxDelay := 400;
  end;

  // FScholarly.MailTo := 'xxxx.yyyy@zzzz.com'; // optional but recommended
  FScholarly.DownloadPapers(QueryStr, FMaxPapers, 200, FMaxDelay);


  // Apply initial sort  , does run time error fix later
  // ComboBox_FilterResults.ItemIndex := 3; // Sort by citations
  // FScholarly.PaperList.SortByCitations;

  /// Display in Memo
  mmo_QueryResults.Lines.Clear;
  mmo_QueryResults.Lines.Add('Total Papers: ' +
    IntToStr(FScholarly.PaperList.Count));
  mmo_QueryResults.Lines.Add('-----------------------------------');
  for i := 0 to FScholarly.PaperList.Count - 1 do
  begin

    PrintPaperRecord(FScholarly.PaperList[i]);

  end;

  // Resolve references between downloaded papers
  FScholarly.DownloadReferencesForPapers(round(FMaxPapers / 3));

  // Load into grid ONLY if papers were downloaded
  if FScholarly.PaperList.Count > 0 then
  begin
    StringGrid1.LoadFromList<TPaperRecord>(FScholarly.PaperList);
    mmo_QueryResults.Lines.Add
      (Format('Downloaded %d papers (Paper and references) ',
      [FScholarly.PaperList.Count]));
  end
  else
    mmo_QueryResults.Lines.Add('No papers found for query: ' + QueryStr);

  // Export based on checkbox selections
  if chk_exportasCSV.IsChecked then
    FScholarly.SavePaperListToCSV(SetValidExtension(FExportFilename, '.csv'));

  if chk_exportasJSON.IsChecked then
    FScholarly.SavePaperListToJSON(SetValidExtension(FExportFilename, '.json'));

  if chk_exportasBIBTEX.IsChecked then
    FScholarly.SavePaperListToBIB(SetValidExtension(FExportFilename, '.bib'));

  ///
  ///
  ///

  FillPaperIndexCombo;

end;

procedure TMainForm.ComboBox_FilterResultsChange(Sender: TObject);
begin
  // CHECK VALID STATE
  if not Assigned(FScholarly) then
    Exit;
  if FScholarly.PaperList.Count = 0 then
    Exit;
  if ComboBox_FilterResults.ItemIndex < 0 then
    Exit;

  // SORT THE LIST
  case ComboBox_FilterResults.ItemIndex of
    0:
      FScholarly.PaperList.SortByTitle;
    1:
      FScholarly.PaperList.SortByAuthors;
    2:
      FScholarly.PaperList.SortByFirstAuthor;
    3:
      FScholarly.PaperList.SortByYear;
    4:
      FScholarly.PaperList.SortByCitations;
  end;

  // RELOAD GRID SAFELY
  try
    StringGrid1.LoadFromList<TPaperRecord>(FScholarly.PaperList);
    mmo_QueryResults.Lines.Add('Sorted by: ' + ComboBox_FilterResults.Items
      [ComboBox_FilterResults.ItemIndex]);
  except
    on E: Exception do
      mmo_QueryResults.Lines.Add('Sort error: ' + E.Message);
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FScholarly := TScholarly.Create;

  // Setup sort combobox
  ComboBox_FilterResults.Items.Clear;
  ComboBox_FilterResults.Items.Add('Sort by Title');
  ComboBox_FilterResults.Items.Add('Sort by Authors');
  ComboBox_FilterResults.Items.Add('Sort by First Author');
  ComboBox_FilterResults.Items.Add('Sort by Year');
  ComboBox_FilterResults.Items.Add('Sort by Citations');
  ComboBox_FilterResults.ItemIndex := 0;

  // Connect event handler
  ComboBox_FilterResults.OnChange := ComboBox_FilterResultsChange;

  FMaxPapers := 500;

end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FScholarly.Free;
end;

///
/// creates run time  error

end.
