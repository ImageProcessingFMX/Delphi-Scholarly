unit Unit_TScholarly;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,  System.Generics.Defaults , System.NetEncoding,
  System.Net.HttpClient, System.Net.URLClient, System.IOUtils,
  System.JSON, System.DateUtils;



type TExportMode = ( asjson, asbibtex, asCSV )  ;


type
  TPaperRecord = record
    Index : Integer;
    Title: string;
    Authors: string;
    Year: Integer;
    Abstract: string;
    Citations: Integer;
    DOI: string;
    URL: string;
  end;

  TPaperList = class(TList<TPaperRecord>)
  public


    procedure SortByTitle;
    procedure SortByAuthors;
    procedure SortByYear;
    procedure SortByCitations;


    function ToCSV: string;
    procedure SaveToCSVFile(const FileName: string; const UTF8: Boolean = True);
     procedure SaveToJSONFile(const FileName: string; const UTF8: Boolean = True);
      procedure SaveToBIBFile(const FileName: string; const UTF8: Boolean = True);
  end;

  /// <summary>
  ///  "Scholarly" downloader implemented via OpenAlex Works API
  ///  (Google Scholar scraping is unreliable and commonly blocked).
  /// </summary>
  TScholarly = class
  private
    FBaseURL: string;          // default: https://api.openalex.org
    FUserAgent: string;        // polite UA
    FMailTo: string;           // OpenAlex recommends mailto=...
    FHttp: THTTPClient;
    FPaperList: TPaperList;
    FEXportMode : TExportMode;

    FQueryString : string;

    function BuildOpenAlexURL(const Query: string; PerPage, Page: Integer): string;
    function HttpGet(const URL: string): string;

    procedure ParseOpenAlexWorksPage(const JsonText: string);

    function JSONGetString(const Obj: TJSONObject; const Name, Default: string): string;
    function JSONGetInt(const Obj: TJSONObject; const Name: string; Default: Integer): Integer;

    function ExtractAuthors(const WorkObj: TJSONObject): string;
    function ExtractURL(const WorkObj: TJSONObject): string;
    function ExtractAbstract(const WorkObj: TJSONObject): string;
    function AbstractFromInvertedIndex(const Inverted: TJSONObject): string;

    function EscapeCSVField(const S: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;

    /// <summary>Downloads up to MaxPapers (soft limit) using paging.</summary>
    procedure DownloadPapers(const Query: string;
      const MaxPapers: Integer = 1000;
      const PerPage: Integer = 200;      // OpenAlex max is 200
      const DelayMS: Integer = 300);     // be polite

    /// <summary>Saves current list to CSV (Excel-friendly).</summary>
    procedure SavePaperListToCSV(const FileName: string);


     procedure SavePaperListToBIB(const FileName: string);


      procedure SavePaperListToJSON(const FileName: string);

    property BaseURL: string read FBaseURL write FBaseURL;
    property MailTo: string read FMailTo write FMailTo;
    property UserAgent: string read FUserAgent write FUserAgent;

    property PaperList: TPaperList read FPaperList;
  end;

implementation

{ ---------- TPaperList ---------- }

function TPaperList.ToCSV: string;
var
  SB: TStringBuilder;
  P: TPaperRecord;

  function E(const S: string): string;
  begin
    // CSV escape
    Result := S.Replace('"', '""');
    Result := '"' + Result + '"';
  end;

begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('"title","authors","year","abstract","citations","doi","url","fetched_date"');

    for P in Self do
    begin
      SB.Append(E(P.Title)).Append(',')
        .Append(E(P.Authors)).Append(',')
        .Append(IntToStr(P.Year)).Append(',')
        .Append(E(P.Abstract)).Append(',')
        .Append(IntToStr(P.Citations)).Append(',')
        .Append(E(P.DOI)).Append(',')
        .Append(E(P.URL)).Append(',')
        .Append(E(DateToStr(Date))) // fetched_date
        .AppendLine;
    end;

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;



procedure TPaperList.SaveToJSONFile(const FileName: string; const UTF8: Boolean);
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
      JSONObj.AddPair('year', TJSONNumber.Create(P.Year));
      JSONObj.AddPair('abstract', P.Abstract);
      JSONObj.AddPair('citations', TJSONNumber.Create(P.Citations));
      JSONObj.AddPair('doi', P.DOI);
      JSONObj.AddPair('url', P.URL);
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

procedure TPaperList.SaveToBIBFile(const FileName: string; const UTF8: Boolean);
var
  SB: TStringBuilder;
  P: TPaperRecord;
  CiteKey: string;
  Bytes: TBytes;

  function CleanBibTeXString(const S: string): string;
  begin
    // Escape special BibTeX characters
    Result := S.Replace('\', '\textbackslash{}')
               .Replace('{', '\{')
               .Replace('}', '\}')
               .Replace('&', '\&')
               .Replace('%', '\%')
               .Replace('$', '\$')
               .Replace('#', '\#')
               .Replace('_', '\_')
               .Replace('~', '\~{}')
               .Replace('^', '\^{}');
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
    SB.AppendLine('%% Generated: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
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
        SB.AppendLine('  author    = {' + CleanBibTeXString(FormatAuthorsForBibTeX(P.Authors)) + '},');

      if P.Year > 0 then
        SB.AppendLine('  year      = {' + IntToStr(P.Year) + '},');

      if P.Abstract.Trim <> '' then
        SB.AppendLine('  abstract  = {' + CleanBibTeXString(P.Abstract) + '},');

      if P.Citations > 0 then
        SB.AppendLine('  note      = {Cited by: ' + IntToStr(P.Citations) + '},');

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
      Bytes := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(SB.ToString);
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
      Result := R.Year - L.Year;  // Descending
    end));
end;
procedure TPaperList.SortByCitations;
begin
  Sort(TComparer<TPaperRecord>.Construct(
    function(const L, R: TPaperRecord): Integer
    begin
      Result := R.Citations - L.Citations;  // Descending
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

function TScholarly.BuildOpenAlexURL(const Query: string; PerPage, Page: Integer): string;
var
  EncQ: string;
  MailToParam: string;
begin
  EncQ := TNetEncoding.URL.Encode(Query);

  // OpenAlex suggests adding mailto=... in queries to identify your client
  if FMailTo <> '' then
    MailToParam := '&mailto=' + TNetEncoding.URL.Encode(FMailTo)
  else
    MailToParam := '';

  Result := Format('%s/works?search=%s&per-page=%d&page=%d%s',
    [FBaseURL, EncQ, PerPage, Page, MailToParam]);
end;

function TScholarly.HttpGet(const URL: string): string;
var
  Resp: IHTTPResponse;
begin
  FHttp.CustomHeaders['User-Agent'] := FUserAgent;
  FHttp.CustomHeaders['Accept'] := 'application/json';

  Resp := FHttp.Get(URL);
  if Resp.StatusCode < 200 then
    raise Exception.CreateFmt('HTTP error %d', [Resp.StatusCode]);
  if Resp.StatusCode >= 300 then
    raise Exception.CreateFmt('HTTP error %d: %s', [Resp.StatusCode, Resp.StatusText]);

  Result := Resp.ContentAsString(TEncoding.UTF8);
end;

function TScholarly.JSONGetString(const Obj: TJSONObject; const Name, Default: string): string;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then Exit;
  V := Obj.GetValue(Name);
  if V <> nil then
    Result := V.Value;
end;

function TScholarly.JSONGetInt(const Obj: TJSONObject; const Name: string; Default: Integer): Integer;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then Exit;
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
  if WorkObj = nil then Exit;

  Authorships := WorkObj.GetValue<TJSONArray>('authorships');
  if Authorships = nil then Exit;

  Names := TStringList.Create;
  try
    Names.StrictDelimiter := True;
    Names.Delimiter := ';';

    for I := 0 to Authorships.Count - 1 do
    begin
      if not (Authorships.Items[I] is TJSONObject) then
        Continue;
      AObj := TJSONObject(Authorships.Items[I]);
      AuthorObj := AObj.GetValue<TJSONObject>('author');
      if AuthorObj = nil then Continue;

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
    if Result <> '' then Exit;
  end;

  // Fallback to OpenAlex work id URL
  Result := JSONGetString(WorkObj, 'id', '');
end;



function TScholarly.AbstractFromInvertedIndex(const Inverted: TJSONObject): string;
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
  if (Inverted = nil) or Inverted.Null then Exit;

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
          if Positions.Items[I] is TJSONNumber then  // ← ADD THIS CHECK
          begin
            P := TJSONNumber(Positions.Items[I]).AsInt;
            if not PosToWord.ContainsKey(P) then  // ← PREVENT DUPLICATES
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
        if I > 0 then SB.Append(' ');
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

  if Assigned(AbstractValue) and
     not AbstractValue.Null and
     (AbstractValue is TJSONObject) then
  begin
    InvertedObj := AbstractValue as TJSONObject;
    if InvertedObj.Count > 0 then  // Has content
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
  I: Integer;
  Work: TJSONObject;
  P: TPaperRecord;
begin
  Root := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
  if Root = nil then
    raise Exception.Create('Invalid JSON received.');

  try
    Results := Root.GetValue<TJSONArray>('results');
    if Results = nil then Exit;

    for I := 0 to Results.Count - 1 do
    begin
      if not (Results.Items[I] is TJSONObject) then
        Continue;
      Work := TJSONObject(Results.Items[I]);

      P.Title := JSONGetString(Work, 'title', '');
      if P.Title = '' then
        Continue;

      P.Authors := ExtractAuthors(Work);
      P.Year := JSONGetInt(Work, 'publication_year', 0);
      P.Citations := JSONGetInt(Work, 'cited_by_count', 0);
      P.DOI := JSONGetString(Work, 'doi', '');
      P.URL := ExtractURL(Work);
      P.Abstract := ExtractAbstract(Work);

      FPaperList.Add(P);
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
begin
  if Query.Trim = '' then
    raise Exception.Create('Query is empty.');

  EffectivePerPage := PerPage;
  if EffectivePerPage <= 0 then EffectivePerPage := 50;
  if EffectivePerPage > 200 then EffectivePerPage := 200; // OpenAlex max

  Page := 1;
  while FPaperList.Count < MaxPapers do
  begin
    URL := BuildOpenAlexURL(Query, EffectivePerPage, Page);

    Resp := HttpGet(URL);

    // Parse and append
    ParseOpenAlexWorksPage(Resp);

    // If this page added nothing, stop (likely end of results)
    // (Simple heuristic: if no growth, break.)
    // Could be refined by checking meta->count and meta->page/...
    if (FPaperList.Count = 0) and (Page > 1) then
      Break;

    // If last page had fewer than per-page results, we are likely done.
    // We can detect by parsing length of results in Parse; but we didn’t return it.
    // For simplicity: stop if response has '"results":[]'
    if Resp.Contains('"results":[]') then
      Break;

    Inc(Page);
    if DelayMS > 0 then
      Sleep(DelayMS);
  end;

  // Hard trim in case we exceeded MaxPapers due to page size
  while FPaperList.Count > MaxPapers do
    FPaperList.Delete(FPaperList.Count - 1);
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

end.
