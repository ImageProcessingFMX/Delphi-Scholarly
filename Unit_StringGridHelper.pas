unit Unit_StringGridHelper;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  System.IOUtils, System.Rtti, FMX.Grid, FMX.Types, FMX.TextLayout,
  FMX.Graphics, FMX.StdCtrls, System.TypInfo;

type
  TStringGridHelper = class helper for TStringGrid
  public
    // VCL-like API
    procedure SetColCount(const ACount: Integer);
    procedure SetRowCount(const ACount: Integer);
    procedure SetCell(const ACol, ARow: Integer; const AText: string);
    function GetCell(const ACol, ARow: Integer): string;

    // Safe grid reset for multi-run usage
    procedure ClearColumnsSafe;
    procedure ClearGrid;

    // loader   for TList <Record>
    procedure LoadFromList<T: record >(List: TList<T>;
      IncludeHeaders: Boolean = True);
  end;

implementation

{ TStringGridHelper }

procedure TStringGridHelper.LoadFromList<T>(List: TList<T>;
  IncludeHeaders: Boolean = True);
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Fields: TArray<TRttiField>;
  Row, Col: Integer;
  Item: T;
  V: TValue;
  HeaderRowOffset: Integer;
begin

  ClearGrid;

  BeginUpdate;
  try
    // Make it safe to call multiple times:

    if (List = nil) or (List.Count = 0) then
      Exit;

    RttiContext := TRttiContext.Create;
    try
      RttiType := RttiContext.GetType(TypeInfo(T));
      Fields := RttiType.GetFields; // you currently use fields [4]
      if Length(Fields) = 0 then
        Exit;

      // Create columns (VCL-like)
      SetColCount(Length(Fields));

      // Optional headers
      HeaderRowOffset := 0;
      if IncludeHeaders then
      begin
        HeaderRowOffset := 1;
        SetRowCount(List.Count + 1); // header + data
        for Col := 0 to High(Fields) do
          SetCell(Col, 0, Fields[Col].Name);
      end
      else
        SetRowCount(List.Count);

      // Fill data
      for Row := 0 to List.Count - 1 do
      begin
        Item := List[Row];
        for Col := 0 to High(Fields) do
        begin
          V := Fields[Col].GetValue(@Item);
          SetCell(Col, Row + HeaderRowOffset, V.ToString);
        end;
      end;

    finally
      // (TRttiContext is a record; no Free needed)
    end;

  finally
    EndUpdate;
  end;
end;

procedure TStringGridHelper.SetColCount(const ACount: Integer);
var
  I: Integer;
  Col: TColumn;
begin
  if ACount < 0 then
    Exit;

  BeginUpdate;
  try
    // shrink
    while ColumnCount > ACount do
      Columns[ColumnCount - 1].DisposeOf;

    // grow
    for I := ColumnCount to ACount - 1 do
    begin
      Col := TColumn.Create(Self);
      Col.Parent := Self;
      Col.Header := ''; // FMX column title
      Col.Width := 120;
    end;
  finally
    EndUpdate;
  end;
end;

procedure TStringGridHelper.SetRowCount(const ACount: Integer);
begin
  // FMX has RowCount like VCL
  RowCount := ACount;
end;

procedure TStringGridHelper.SetCell(const ACol, ARow: Integer;
  const AText: string);
begin
  Cells[ACol, ARow] := AText;
end;

function TStringGridHelper.GetCell(const ACol, ARow: Integer): string;
begin
  Result := Cells[ACol, ARow];
end;

procedure TStringGridHelper.ClearColumnsSafe;
var
  I: Integer;
begin
  // IMPORTANT: dispose from last to first to avoid index shifting problems
  for I := ColumnCount - 1 downto 0 do
    // Columns[i].DisposeOf;
    Self.RemoveObject(Columns[I])

end;

procedure TStringGridHelper.ClearGrid;
begin
  BeginUpdate;
  try
    // Clear cell data first
    RowCount := 0;

    // Then clear columns safely
    ClearColumnsSafe;
  finally
    EndUpdate;
  end;
end;

end.
