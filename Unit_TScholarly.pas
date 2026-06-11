unit Unit_TScholarly;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, System.NetEncoding,
  System.Net.HttpClient, System.Net.URLClient, System.IOUtils,
  System.JSON, System.DateUtils;

type
  TExportMode = (asjson, asbibtex, asCSV);

type
  TPaperRecord = record
    Index: Integer;
    Title: string;
    Authors: string;
    FirstAuthor: string;
    FirstAuthorInstitution: string;
    Year: Integer;
    Abstract: string;
    Citations: Integer;
    DOI: string;
    URL: string;
    /// <summary>
    /// OpenAlex work ID for reference matching
    /// </summary>
    OpenAlexID: string; // NEW:
    /// <summary>
    /// OpenAlex work ID for reference matching
    /// </summary>
    ReferencedBy: TArray<Integer>;
    /// <summary>
    /// Indices of papers this one cites
    /// </summary>
    References: TArray<Integer>; //
    /// <summary>
    /// OpenAlex work ID for reference matching
    /// </summary>
    ReferenceURLs: TArray<string>;

  end;
  // ***** works .-)    nor perfect 15:30  !!!!

  TPaperList = class(TList<TPaperRecord>)

  private

    FIndexMap: TDictionary<string, Integer>;
    procedure ExportToDOT(const FileName: string);
    procedure ExportToGraphML(const FileName: string);
    procedure BuildIndexMap;

    // Maps OpenAlexID to Index

  public

    procedure SortByTitle;
    procedure SortByAuthors;
    procedure SortByYear;
    procedure SortByCitations;
    procedure SortByFirstAuthor;

    constructor Create;

    destructor Destroy; override;


    // NEW: Reference management

    procedure ResolveReferences;
    function GetPaperByOpenAlexID(const OpenAlexID: string): Integer;

    function ToCSV: string;
    procedure SaveToCSVFile(const FileName: string; const UTF8: Boolean = True);
    procedure SaveToJSONFile(const FileName: string;
      const UTF8: Boolean = True);
    procedure SaveToBIBFile(const FileName: string; const UTF8: Boolean = True);
  end;

  /// <summary>
  /// "Scholarly" downloader implemented via OpenAlex Works API
  /// (Google Scholar scraping is unreliable and commonly blocked).
  /// </summary>
  TScholarly = class
  private
    FBaseURL: string; // default: https://api.openalex.org
    FUserAgent: string; // polite UA
    FMailTo: string; // OpenAlex recommends mailto=...
    FHttp: THTTPClient;
    FPaperList: TPaperList;
    FEXportMode: TExportMode;

    FQueryString: string;

    function BuildOpenAlexURL(const Query: string;
      PerPage, Page: Integer): string;
    function HttpGet(const URL: string): string;

    procedure ParseOpenAlexWorksPage(const JsonText: string);

    function JSONGetString(const Obj: TJSONObject;
      const Name, Default: string): string;
    function JSONGetInt(const Obj: TJSONObject; const Name: string;
      Default: Integer): Integer;

    function ExtractAuthors(const WorkObj: TJSONObject): string;
    function ExtractURL(const WorkObj: TJSONObject): string;
    function ExtractAbstract(const WorkObj: TJSONObject): string;
    function AbstractFromInvertedIndex(const Inverted: TJSONObject): string;

    function EscapeCSVField(const S: string): string;
    procedure ExtractAuthorDetails(const WorkObj: TJSONObject;
      var AllAuthors, FirstAuthor, FirstInstitution: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;

    /// <summary>Downloads up to MaxPapers (soft limit) using paging.</summary>
    procedure DownloadPapers(const Query: string;
      const MaxPapers: Integer = 1000; const PerPage: Integer = 200;
      // OpenAlex max is 200
      const DelayMS: Integer = 300); // be polite

    // NEW: Download references for existing papers
    procedure DownloadReferencesForPapers(const DelayMS: Integer = 300);

    /// <summary>Saves current list to CSV (Excel-friendly).</summary>
    procedure SavePaperListToCSV(const FileName: string);

    procedure SavePaperListToBIB(const FileName: string);

    procedure SavePaperListToJSON(const FileName: string);

    property BaseURL: string read FBaseURL write FBaseURL;
    property MailTo: string read FMailTo write FMailTo;
    property UserAgent: string read FUserAgent write FUserAgent;

    property PaperList: TPaperList read FPaperList;
  end;

function IntArray2Str(IntArray: TArray<Integer>): String;

implementation

function IntArray2Str(IntArray: TArray<Integer>): String;
var
  I: Integer;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('[');

    for I := Low(IntArray) to High(IntArray) do
    begin
      Builder.Append(IntArray[I]);

      if I < High(IntArray) then
        Builder.Append(', ');
    end;

    Builder.Append(']');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ ---------- TPaperList ---------- }

function TPaperList.ToCSV: string;
var
  SB: TStringBuilder;
  P: TPaperRecord;
  SepStr: string;

  function E(const S: string): string;
  begin
    // CSV escape - remove separator and newlines from data
    Result := S.Replace('"', '""');
    Result := S.Replace(SepStr, ' '); // replace separator with space
    Result := S.Replace(#13, ' '); // remove CR
    Result := S.Replace(#10, ' '); // remove LF
    Result := '"' + Result + '"';
  end;

begin
  SepStr := #9; // TAB separator (best for Excel)
  // Alternative: SepStr := ';'  for semicolon

  SB := TStringBuilder.Create;
  try
    // Header line - all fields quoted consistently
    SB.Append('"title"').Append(SepStr).Append('"authors"').Append(SepStr)
      .Append('"Firstauthor"').Append(SepStr).Append('"Institution"')
      .Append(SepStr).Append('"year"').Append(SepStr).Append('"abstract"')
      .Append(SepStr).Append('"citations"').Append(SepStr).Append('"doi"')
      .Append(SepStr).Append('"url"').Append(SepStr).Append('"OpenAlexID"')
      .Append(SepStr).Append('"References"').Append(SepStr)
      .Append('"ReferencedBy"').Append(SepStr).Append('"fetched_date"')
      .AppendLine;

    // Data rows - use SepStr everywhere
    for P in Self do
    begin
      SB.Append(E(P.Title)).Append(SepStr).Append(E(P.Authors)).Append(SepStr)
        .Append(E(P.FirstAuthor)).Append(SepStr)
        .Append(E(P.FirstAuthorInstitution)).Append(SepStr)
        .Append(IntToStr(P.Year)).Append(SepStr).Append(E(P.Abstract))
        .Append(SepStr).Append(IntToStr(P.Citations)).Append(SepStr)
        .Append(E(P.DOI)).Append(SepStr).Append(E(P.URL)).Append(SepStr)
        .Append(E(P.OpenAlexID)).Append(SepStr)
        .Append(E(IntArray2Str(P.References))).Append(SepStr)
        .Append(E(IntArray2Str(P.ReferencedBy))).Append(SepStr)
        .Append(E(DateToStr(Date))).AppendLine;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TPaperList.SaveToJSONFile(const FileName: string;
  const UTF8: Boolean);
var
  JSONArray: TJSONArray;
  JSONObj: TJSONObject;
  P: TPaperRecord;
  JSONStr: string;
  Bytes: TBytes;
begin
  JSONArray := TJSONArray.Create;
  try
    // Convert each paper record to JSON object
    for P in Self do
    begin
      JSONObj := TJSONObject.Create;
      JSONObj.AddPair('title', P.Title);
      JSONObj.AddPair('authors', P.Authors);
      JSONObj.AddPair('Firstauthor', P.FirstAuthor);
      JSONObj.AddPair('Institutio', P.FirstAuthorInstitution);
      JSONObj.AddPair('year', TJSONNumber.Create(P.Year));
      JSONObj.AddPair('abstract', P.Abstract);
      JSONObj.AddPair('citations', TJSONNumber.Create(P.Citations));
      JSONObj.AddPair('doi', P.DOI);
      JSONObj.AddPair('url', P.URL);
      JSONObj.AddPair('AlexID', P.OpenAlexID);
      JSONObj.AddPair('ReferenceBy', IntArray2Str(P.ReferencedBy));
      JSONObj.AddPair('References', IntArray2Str(P.References));
      JSONObj.AddPair('fetched_date', DateToStr(Date));
      JSONArray.AddElement(JSONObj);
    end;

    // Format with indentation for readability
    JSONStr := JSONArray.Format(2);

    if UTF8 then
    begin
      // UTF-8 with BOM
      Bytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(JSONStr);
      TFile.WriteAllBytes(FileName, Bytes);
    end
    else
      TFile.WriteAllText(FileName, JSONStr, TEncoding.ANSI);
  finally
    JSONArray.Free;
  end;
end;

procedure TPaperList.BuildIndexMap;
var
  I: Integer;
  P: TPaperRecord;
begin
  FIndexMap.Clear;
  for I := 0 to Count - 1 do
  begin
    P := Items[I];
    if P.OpenAlexID <> '' then
      FIndexMap.AddOrSetValue(P.OpenAlexID, P.Index);
  end;
end;

function TPaperList.GetPaperByOpenAlexID(const OpenAlexID: string): Integer;
begin
  if FIndexMap.TryGetValue(OpenAlexID, Result) then
    Exit;
  Result := -1; // Not found
end;

// Export as GraphML (for Gephi, yEd)
procedure TPaperList.ExportToGraphML(const FileName: string);
var
  XML: TStringList;
  I, J: Integer;
  P: TPaperRecord;
begin
  XML := TStringList.Create;
  try
    XML.Add('<?xml version="1.0" encoding="UTF-8"?>');
    XML.Add('<graphml xmlns="http://graphml.graphdrawing.org/xmlns">');
    XML.Add('  <key id="label" for="node" attr.name="label" attr.type="string"/>');
    XML.Add('  <key id="citations" for="node" attr.name="citations" attr.type="int"/>');
    XML.Add('  <graph id="G" edgedefault="directed">');

    // Add nodes
    for I := 0 to Count - 1 do
    begin
      P := Items[I];
      XML.Add(Format('    <node id="n%d">', [P.Index]));
      XML.Add(Format('      <data key="label">%s</data>', [P.Title]));
      XML.Add(Format('      <data key="citations">%d</data>', [P.Citations]));
      XML.Add('    </node>');
    end;

    // Add edges (references)
    for I := 0 to Count - 1 do
    begin
      P := Items[I];
      for J := 0 to Length(P.References) - 1 do
      begin
        XML.Add(Format('    <edge source="n%d" target="n%d"/>',
          [P.Index, P.References[J]]));
      end;
    end;

    XML.Add('  </graph>');
    XML.Add('</graphml>');

    XML.SaveToFile(FileName, TEncoding.UTF8);
  finally
    XML.Free;
  end;
end;

constructor TPaperList.Create;
begin
  inherited Create;
  FIndexMap := TDictionary<string, Integer>.Create;

end;

destructor TPaperList.Destroy;
begin
  FIndexMap.Free;

  inherited;
end;

// Export as DOT (for Graphviz)
procedure TPaperList.ExportToDOT(const FileName: string);
var
  DOT: TStringList;
  I, J: Integer;
  P: TPaperRecord;
  FLabel: string;
begin
  DOT := TStringList.Create;
  try
    DOT.Add('digraph CitationNetwork {');
    DOT.Add('  rankdir=LR;');
    DOT.Add('  node [shape=box, style=filled];');

    // Add nodes with size based on citations
    for I := 0 to Count - 1 do
    begin
      P := Items[I];
      FLabel := P.Title;
      if Length(FLabel) > 50 then
        FLabel := Copy(FLabel, 1, 47) + '...';

      // Color based on citation count
      if P.Citations > 100 then
        DOT.Add(Format('  n%d [label="%s", fillcolor=red, fontsize=14];',
          [P.Index, FLabel]))
      else if P.Citations > 50 then
        DOT.Add(Format('  n%d [label="%s", fillcolor=orange];',
          [P.Index, FLabel]))
      else
        DOT.Add(Format('  n%d [label="%s", fillcolor=lightblue];',
          [P.Index, FLabel]));
    end;

    // Add edges
    for I := 0 to Count - 1 do
    begin
      P := Items[I];
      for J := 0 to Length(P.References) - 1 do
      begin
        DOT.Add(Format('  n%d -> n%d;', [P.Index, P.References[J]]));
      end;
    end;

    DOT.Add('}');
    DOT.SaveToFile(FileName, TEncoding.UTF8);
  finally
    DOT.Free;
  end;
end;

procedure TPaperList.ResolveReferences;
var
  I, J, K: Integer;
  P: TPaperRecord;
  RefURL: string;
  RefIndex: Integer;
  TempRefs: TList<Integer>;
  TempCited: TList<Integer>;
begin
  // First, build the index map: OpenAlexID -> list position
  FIndexMap.Clear;
  for I := 0 to Count - 1 do
  begin
    P := Items[I];
    if P.OpenAlexID <> '' then
      FIndexMap.AddOrSetValue(P.OpenAlexID, I);
  end;

  // Now resolve references for each paper
  for I := 0 to Count - 1 do
  begin
    P := Items[I];
    TempRefs := TList<Integer>.Create;
    try
      // For each reference URL, find the index in our list
      for J := 0 to Length(P.ReferenceURLs) - 1 do
      begin
        RefURL := P.ReferenceURLs[J];
        if RefURL <> '' then
        begin
          if FIndexMap.TryGetValue(RefURL, RefIndex) then
            TempRefs.Add(RefIndex);
        end;
      end;

      // Store the resolved indices
      SetLength(P.References, TempRefs.Count);
      for J := 0 to TempRefs.Count - 1 do
        P.References[J] := TempRefs[J];

      // Update the record in the list
      Items[I] := P;
    finally
      TempRefs.Free;
    end;
  end;

  // Build ReferencedBy (inverse relationship)
  for I := 0 to Count - 1 do
  begin
    P := Items[I];
    SetLength(P.ReferencedBy, 0); // Clear first
    Items[I] := P;
  end;

  // For each paper's References, add I to the ReferencedBy of target papers
  for I := 0 to Count - 1 do
  begin
    P := Items[I];
    for J := 0 to Length(P.References) - 1 do
    begin
      RefIndex := P.References[J];
      if (RefIndex >= 0) and (RefIndex < Count) then
      begin
        var
        TargetPaper := Items[RefIndex];
        TempCited := TList<Integer>.Create;
        try
          // Copy existing ReferencedBy
          for K := 0 to Length(TargetPaper.ReferencedBy) - 1 do
            TempCited.Add(TargetPaper.ReferencedBy[K]);

          // Add current paper index
          TempCited.Add(I);

          // Store back
          SetLength(TargetPaper.ReferencedBy, TempCited.Count);
          for K := 0 to TempCited.Count - 1 do
            TargetPaper.ReferencedBy[K] := TempCited[K];

          Items[RefIndex] := TargetPaper;
        finally
          TempCited.Free;
        end;
      end;
    end;
  end;
end;

procedure TPaperList.SaveToBIBFile(const FileName: string; const UTF8: Boolean);
var
  SB: TStringBuilder;
  P: TPaperRecord;
  CiteKey: string;
  Bytes: TBytes;

  function CleanBibTeXString(const S: string): string;
  begin
    // Escape special BibTeX characters
    Result := S.Replace('\', '\textbackslash{}').Replace('{', '\{')
      .Replace('}', '\}').Replace('&', '\&').Replace('%', '\%')
      .Replace('$', '\$').Replace('#', '\#').Replace('_', '\_')
      .Replace('~', '\~{}').Replace('^', '\^{}');
  end;

  function GenerateCiteKey(const Authors: string; Year: Integer): string;
  var
    FirstAuthor: string;
    P: Integer;
  begin
    FirstAuthor := Authors;

    // Extract first author (before first semicolon or comma)
    P := Pos(';', FirstAuthor);
    if P > 0 then
      FirstAuthor := Copy(FirstAuthor, 1, P - 1);

    P := Pos(',', FirstAuthor);
    if P > 0 then
      FirstAuthor := Copy(FirstAuthor, 1, P - 1);

    FirstAuthor := Trim(FirstAuthor);

    // Remove spaces and convert to lowercase for cite key
    FirstAuthor := FirstAuthor.Replace(' ', '').ToLower;

    // Create cite key: author+year
    if Year > 0 then
      Result := FirstAuthor + IntToStr(Year)
    else
      Result := FirstAuthor + 'unknown';
  end;

  function FormatAuthorsForBibTeX(const Authors: string): string;
  begin
    // Convert semicolon-separated to " and " separated
    Result := Authors.Replace(';', ' and ');
  end;

begin
  SB := TStringBuilder.Create;
  try
    // BibTeX file header
    SB.AppendLine('%% BibTeX Export from Scholarly Downloader');
    SB.AppendLine('%% Generated: ' + FormatDateTime
      ('yyyy-mm-dd hh:nn:ss', Now));
    SB.AppendLine('%% Total entries: ' + IntToStr(Self.Count));
    SB.AppendLine();

    // Export each paper
    for P in Self do
    begin
      if P.Title.Trim = '' then
        Continue; // Skip papers without title

      CiteKey := GenerateCiteKey(P.Authors, P.Year);

      SB.AppendLine('@article{' + CiteKey + ',');
      SB.AppendLine('  title     = {' + CleanBibTeXString(P.Title) + '},');

      if P.Authors.Trim <> '' then
        SB.AppendLine('  author    = {' + CleanBibTeXString
          (FormatAuthorsForBibTeX(P.Authors)) + '},');

      if P.Year > 0 then
        SB.AppendLine('  year      = {' + IntToStr(P.Year) + '},');

      if P.Abstract.Trim <> '' then
        SB.AppendLine('  abstract  = {' + CleanBibTeXString(P.Abstract) + '},');

      if P.Citations > 0 then
        SB.AppendLine('  note      = {Cited by: ' +
          IntToStr(P.Citations) + '},');

      if P.DOI.Trim <> '' then
        SB.AppendLine('  doi       = {' + P.DOI + '},');

      if P.URL.Trim <> '' then
        SB.AppendLine('  url       = {' + P.URL + '},');

      SB.AppendLine('}');
      SB.AppendLine();
    end;

    if UTF8 then
    begin
      // UTF-8 with BOM for better compatibility
      Bytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes
        (SB.ToString);
      TFile.WriteAllBytes(FileName, Bytes);
    end
    else
      TFile.WriteAllText(FileName, SB.ToString, TEncoding.ANSI);
  finally
    SB.Free;
  end;
end;

procedure TPaperList.SaveToCSVFile(const FileName: string; const UTF8: Boolean);
var
  CSV: string;
  Bytes: TBytes;
begin
  CSV := ToCSV;

  if UTF8 then
  begin
    // UTF-8 with BOM so Excel opens properly on many Windows locales
    Bytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(CSV);
    TFile.WriteAllBytes(FileName, Bytes);
  end
  else
    TFile.WriteAllText(FileName, CSV, TEncoding.ANSI);
end;

procedure TPaperList.SortByTitle;
begin
  Sort(TComparer<TPaperRecord>.Construct(
    function(const L, R: TPaperRecord): Integer
    begin
      Result := CompareText(L.Title, R.Title);
    end));
end;

procedure TPaperList.SortByFirstAuthor;
begin
  Sort(TComparer<TPaperRecord>.Construct(
    function(const L, R: TPaperRecord): Integer
    begin
      Result := CompareText(L.FirstAuthor, R.FirstAuthor);
    end));
end;

procedure TPaperList.SortByAuthors;
begin
  Sort(TComparer<TPaperRecord>.Construct(
    function(const L, R: TPaperRecord): Integer
    begin
      Result := CompareText(L.Authors, R.Authors);
    end));
end;

procedure TPaperList.SortByYear;
begin
  Sort(TComparer<TPaperRecord>.Construct(
    function(const L, R: TPaperRecord): Integer
    begin
      Result := R.Year - L.Year; // Descending
    end));
end;

procedure TPaperList.SortByCitations;
begin
  Sort(TComparer<TPaperRecord>.Construct(
    function(const L, R: TPaperRecord): Integer
    begin
      Result := R.Citations - L.Citations; // Descending
    end));
end;

{ ---------- TScholarly ---------- }

constructor TScholarly.Create;
begin
  inherited Create;
  FBaseURL := 'https://api.openalex.org';
  FMailTo := ''; // set to your email if you want: 'you@domain.com'
  FUserAgent := 'Delphi OpenAlex Client/1.0';
  FHttp := THTTPClient.Create;
  FHttp.ConnectionTimeout := 20000;
  FHttp.ResponseTimeout := 60000;

  FPaperList := TPaperList.Create;
end;

destructor TScholarly.Destroy;
begin
  FPaperList.Free;
  FHttp.Free;
  inherited;
end;

procedure TScholarly.Clear;
begin
  FPaperList.Clear;
end;

function TScholarly.BuildOpenAlexURL(const Query: string;
PerPage, Page: Integer): string;
begin
  Result := 'https://api.openalex.org/works?search=' + TNetEncoding.URL.Encode
    (Query) + '&per-page=' + IntToStr(PerPage) + '&page=' + IntToStr(Page) +
    '&sort=cited_by_count:desc'; // Sort by most cited

  if FMailTo <> '' then
    Result := Result + '&mailto=' + TNetEncoding.URL.Encode(FMailTo);
end;

function TScholarly.HttpGet(const URL: string): string;
var
  Response: IHTTPResponse;
  Retries: Integer;
  RetryAfter: Integer;
begin
  Retries := 0;
  while Retries < 3 do
  begin
    Response := FHttp.Get(URL);

    if Response.StatusCode = 200 then
    begin
      Result := Response.ContentAsString;
      Exit;
    end
    else if Response.StatusCode = 429 then // Too many requests
    begin
      RetryAfter := StrToIntDef(Response.HeaderValue['Retry-After'], 5);
      Sleep(RetryAfter * 1000);
      Inc(Retries);
    end
    else
      raise Exception.CreateFmt('HTTP Error %d: %s',
        [Response.StatusCode, Response.StatusText]);
  end;

  raise Exception.Create('Max retries exceeded');
end;

function TScholarly.JSONGetString(const Obj: TJSONObject;
const Name, Default: string): string;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  V := Obj.GetValue(Name);
  if V <> nil then
    Result := V.Value;
end;

function TScholarly.JSONGetInt(const Obj: TJSONObject; const Name: string;
Default: Integer): Integer;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then
    Exit;
  V := Obj.GetValue(Name);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt
  else if V <> nil then
    Result := StrToIntDef(V.Value, Default);
end;

function TScholarly.ExtractAuthors(const WorkObj: TJSONObject): string;
var
  Authorships: TJSONArray;
  I: Integer;
  AObj, AuthorObj: TJSONObject;
  Names: TStringList;
  Name: string;
begin
  Result := '';
  if WorkObj = nil then
    Exit;

  Authorships := WorkObj.GetValue<TJSONArray>('authorships');
  if Authorships = nil then
    Exit;

  Names := TStringList.Create;
  try
    Names.StrictDelimiter := True;
    Names.Delimiter := ';';

    for I := 0 to Authorships.Count - 1 do
    begin
      if not(Authorships.Items[I] is TJSONObject) then
        Continue;
      AObj := TJSONObject(Authorships.Items[I]);
      AuthorObj := AObj.GetValue<TJSONObject>('author');
      if AuthorObj = nil then
        Continue;

      Name := JSONGetString(AuthorObj, 'display_name', '');
      if Name <> '' then
        Names.Add(Name);
    end;

    // Return as "A;B;C"
    Result := Names.DelimitedText;
  finally
    Names.Free;
  end;
end;

function TScholarly.ExtractURL(const WorkObj: TJSONObject): string;
var
  PrimaryLoc: TJSONObject;
begin
  Result := '';

  // Prefer landing_page_url if present
  PrimaryLoc := WorkObj.GetValue<TJSONObject>('primary_location');
  if PrimaryLoc <> nil then
  begin
    Result := JSONGetString(PrimaryLoc, 'landing_page_url', '');
    if Result <> '' then
      Exit;
  end;

  // Fallback to OpenAlex work id URL
  Result := JSONGetString(WorkObj, 'id', '');
end;

function TScholarly.AbstractFromInvertedIndex(const Inverted
  : TJSONObject): string;
type
  TIntList = TList<Integer>;
var
  Pair: TJSONPair;
  Positions: TJSONArray;
  PosToWord: TDictionary<Integer, string>;
  PosList: TIntList;
  I, P: Integer;
  Word: string;
  SB: TStringBuilder;
begin
  Result := '';
  if (Inverted = nil) or Inverted.Null then
    Exit;

  PosToWord := TDictionary<Integer, string>.Create;
  PosList := TIntList.Create;
  try
    for Pair in Inverted do
    begin
      Word := Pair.JsonString.Value;
      Positions := Pair.JsonValue as TJSONArray;

      if Assigned(Positions) then
      begin
        for I := 0 to Positions.Count - 1 do
        begin
          if Positions.Items[I] is TJSONNumber then // ← ADD THIS CHECK
          begin
            P := TJSONNumber(Positions.Items[I]).AsInt;
            if not PosToWord.ContainsKey(P) then // ← PREVENT DUPLICATES
            begin
              PosToWord.Add(P, Word);
              PosList.Add(P);
            end;
          end;
        end;
      end;
    end;

    PosList.Sort;

    SB := TStringBuilder.Create;
    try
      for I := 0 to PosList.Count - 1 do
      begin
        if I > 0 then
          SB.Append(' ');
        SB.Append(PosToWord[PosList[I]]);
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  finally
    PosList.Free;
    PosToWord.Free;
  end;
end;

function TScholarly.ExtractAbstract(const WorkObj: TJSONObject): string;
var
  AbstractValue: TJSONValue;
  InvertedObj: TJSONObject;
begin
  Result := '';

  // Try to get abstract_inverted_index
  AbstractValue := WorkObj.GetValue('abstract_inverted_index');

  if Assigned(AbstractValue) and not AbstractValue.Null and
    (AbstractValue is TJSONObject) then
  begin
    InvertedObj := AbstractValue as TJSONObject;
    if InvertedObj.Count > 0 then // Has content
      Result := AbstractFromInvertedIndex(InvertedObj);
  end
  else
  begin
    // Fallback: some APIs might have plain 'abstract' field
    AbstractValue := WorkObj.GetValue('abstract');
    if Assigned(AbstractValue) and not AbstractValue.Null then
      Result := AbstractValue.Value;
  end;
end;

procedure TScholarly.ParseOpenAlexWorksPage(const JsonText: string);
var
  Root: TJSONObject;
  Results: TJSONArray;
  I, J: Integer;
  Work: TJSONObject;
  P: TPaperRecord;

  RefsArr: TJSONArray;
  V: TJSONValue;
  AllAuthors, FirstAuth, FirstInst: string;
begin
  Root := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
  if Root = nil then
    raise Exception.Create('Invalid JSON received.');

  try
    Results := Root.GetValue<TJSONArray>('results');
    if Results = nil then
      Exit;

    for I := 0 to Results.Count - 1 do
    begin
      if not(Results.Items[I] is TJSONObject) then
        Continue;

      Work := TJSONObject(Results.Items[I]);

      // Start with a clean record (important so arrays don't keep old values)
      FillChar(P, SizeOf(P), 0);

      // --- Existing fields (use your helpers) ---
      // Adjust these lines to match your actual TPaperRecord fields
      ExtractAuthorDetails(Work, AllAuthors, FirstAuth, FirstInst);
      P.Index := I;
      P.Authors := AllAuthors;
      P.FirstAuthor := FirstAuth;
      P.FirstAuthorInstitution := FirstInst;
      P.Title := JSONGetString(Work, 'title', '');
      if P.Title = '' then
        Continue;

      P.Year := JSONGetInt(Work, 'publication_year', 0);
      P.Citations := JSONGetInt(Work, 'cited_by_count', 0);
      P.DOI := JSONGetString(Work, 'doi', '');
      P.URL := ExtractURL(Work);
      P.Abstract := ExtractAbstract(Work);

      // --- NEW: OpenAlex work ID (this is usually in JSON field "id") ---
      // Example value: "https://openalex.org/W2741809807"
      P.OpenAlexID := JSONGetString(Work, 'id', '');

      // --- NEW: referenced_works -> ReferenceURLs ---
      // OpenAlex returns an array of work IDs/URLs in "referenced_works"
      RefsArr := Work.GetValue<TJSONArray>('referenced_works');
      if Assigned(RefsArr) then
      begin
        SetLength(P.ReferenceURLs, RefsArr.Count);
        for J := 0 to RefsArr.Count - 1 do
        begin
          V := RefsArr.Items[J];

          // Typically these are JSON strings. Use Value to get the string content.
          if Assigned(V) then
            P.ReferenceURLs[J] := V.Value
          else
            P.ReferenceURLs[J] := '';
        end;
      end
      else
      begin
        SetLength(P.ReferenceURLs, 0);
      end;

      // These two are NOT directly in the OpenAlex JSON (they are indices in your list),
      // so they will remain empty until you run your "resolve references/citations" step later.
      SetLength(P.References, 0);
      SetLength(P.ReferencedBy, 0);

      // Finally add the paper to your list/collection (adjust to your container)
      PaperList.Add(P);
    end;

  finally
    Root.Free;
  end;
end;

procedure TScholarly.DownloadPapers(const Query: string;
const MaxPapers, PerPage, DelayMS: Integer);
var
  Page: Integer;
  URL, Resp: string;
  EffectivePerPage: Integer;
  PreviousCount, NewPapersAdded: Integer;
begin
  if Query.Trim = '' then
    raise Exception.Create('Query is empty.');

  EffectivePerPage := PerPage;
  if EffectivePerPage <= 0 then
    EffectivePerPage := 50;
  if EffectivePerPage > 200 then
    EffectivePerPage := 200; // OpenAlex max [4]

  Page := 1;
  while FPaperList.Count < MaxPapers do
  begin
    PreviousCount := FPaperList.Count;

    URL := BuildOpenAlexURL(Query, EffectivePerPage, Page);
    Resp := HttpGet(URL);
    ParseOpenAlexWorksPage(Resp);

    NewPapersAdded := FPaperList.Count - PreviousCount;

    // Stop if no new papers were added (end of results)
    if NewPapersAdded = 0 then
      Break;

    Inc(Page);
    Sleep(DelayMS); // Respect rate limits
  end;
end;

procedure TScholarly.DownloadReferencesForPapers(const DelayMS: Integer);
begin
  // After downloading all papers, resolve references
  FPaperList.ResolveReferences;
end;

procedure TScholarly.SavePaperListToBIB(const FileName: string);
begin
  if FileName.Trim = '' then
    raise Exception.Create('FileName is empty.');
  FPaperList.SaveToBIBFile(FileName, True);
end;

procedure TScholarly.SavePaperListToCSV(const FileName: string);
begin
  if FileName.Trim = '' then
    raise Exception.Create('FileName is empty.');
  FPaperList.SaveToCSVFile(FileName, True);
end;

procedure TScholarly.SavePaperListToJSON(const FileName: string);
begin
  if FileName.Trim = '' then
    raise Exception.Create('FileName is empty.');
  FPaperList.SaveToJSONFile(FileName, True);
end;

function TScholarly.EscapeCSVField(const S: string): string;
begin
  Result := '"' + S.Replace('"', '""') + '"';
end;

procedure TScholarly.ExtractAuthorDetails(const WorkObj: TJSONObject;
var AllAuthors, FirstAuthor, FirstInstitution: string);
var
  Authorships: TJSONArray;
  Auth: TJSONObject;
  AuthorObj: TJSONObject;
  Institutions: TJSONArray;
  Inst: TJSONObject;
  AuthorList: TStringList;
  I: Integer;
begin
  AllAuthors := '';
  FirstAuthor := '';
  FirstInstitution := '';

  Authorships := WorkObj.GetValue<TJSONArray>('authorships');
  if not Assigned(Authorships) or (Authorships.Count = 0) then
    Exit;

  AuthorList := TStringList.Create;
  try
    for I := 0 to Authorships.Count - 1 do
    begin
      Auth := Authorships.Items[I] as TJSONObject;
      AuthorObj := Auth.GetValue<TJSONObject>('author');

      if Assigned(AuthorObj) then
      begin
        AuthorList.Add(JSONGetString(AuthorObj, 'display_name', 'Unknown'));

        // First author (I=0)
        if I = 0 then
        begin
          FirstAuthor := JSONGetString(AuthorObj, 'display_name', '');

          // Extract first institution for first author
          Institutions := Auth.GetValue<TJSONArray>('institutions');
          if Assigned(Institutions) and (Institutions.Count > 0) then
          begin
            Inst := Institutions.Items[0] as TJSONObject;
            if Assigned(Inst) then
              FirstInstitution := JSONGetString(Inst, 'display_name', '');
          end;
        end;
      end;
    end;

    AllAuthors := AuthorList.DelimitedText; // or use your semicolon separator
  finally
    AuthorList.Free;
  end;
end;

end.
