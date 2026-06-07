unit Unit_StringGridHelper;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON, System.IOUtils,
  System.Rtti, FMX.Grid, FMX.Types, FMX.TextLayout,  FMX.Graphics, FMX.StdCtrls, System.TypInfo;

type
  TStringGridHelper = class helper for TStringGrid
  public
    procedure AutoSizeColumns(MaxWidth: Single = 400);
    procedure AutoSizeToContent;
    procedure FitToForm(FormWidth, FormHeight: Single; Margin: Single = 10);
    procedure LoadFromList<T: record>(List: TList<T>; IncludeHeaders: Boolean = True);
  end;

implementation

{ TStringGridHelper }

procedure TStringGridHelper.AutoSizeColumns(MaxWidth: Single = 400);
var
  Col, Row: Integer;
  MaxLen, TextWidth: Single;
  Layout: TTextLayout;
begin
  Layout := TTextLayoutManager.DefaultTextLayout.Create;
  try
    for Col := 0 to ColumnCount - 1 do
    begin
      MaxLen := 50; // Minimum width

      // Check header
      if Assigned(Columns[Col]) then
      begin
        Layout.BeginUpdate;
        try
          Layout.Text := Columns[Col].Header;
          TextWidth := Layout.TextWidth;
        finally
          Layout.EndUpdate;
        end;

        if TextWidth > MaxLen then
          MaxLen := TextWidth;
      end;

      // Check all rows
      for Row := 0 to RowCount - 1 do
      begin
        Layout.BeginUpdate;
        try
          Layout.Text := Cells[Col, Row];
          TextWidth := Layout.TextWidth;
        finally
          Layout.EndUpdate;
        end;

        if TextWidth > MaxLen then
          MaxLen := TextWidth;
      end;

      // Add padding and limit to max width
      MaxLen := MaxLen + 20;
      if MaxLen > MaxWidth then
        MaxLen := MaxWidth;

      Columns[Col].Width := MaxLen;
    end;
  finally
    Layout.Free;
  end;
end;

procedure TStringGridHelper.AutoSizeToContent;
var
  TotalWidth: Single;
  Col: Integer;
begin
  AutoSizeColumns;

  TotalWidth := 0;
  for Col := 0 to ColumnCount - 1 do
    TotalWidth := TotalWidth + Columns[Col].Width;

  Width := TotalWidth + 20; // Add scrollbar width
end;

procedure TStringGridHelper.FitToForm(FormWidth, FormHeight: Single; Margin: Single = 10);
begin
  Width := FormWidth - Position.X - Margin;
  Height := FormHeight - Position.Y - Margin;
end;

procedure TStringGridHelper.LoadFromList<T>(List: TList<T>; IncludeHeaders: Boolean = True);
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  Fields: TArray<TRttiField>;
  I, Row, Col: Integer;
  Item: T;
  Value: TValue;
  Column: TColumn;
begin
  if List.Count = 0 then Exit;

  RttiContext := TRttiContext.Create;
  try
    RttiType := RttiContext.GetType(TypeInfo(T));
    Fields := RttiType.GetFields;

    // Clear existing columns
    while ColumnCount > 0 do
      Columns[0].Free;

    // Add columns dynamically
    for Col := 0 to Length(Fields) - 1 do
    begin
      Column := TStringColumn.Create(Self);
      Column.Parent := Self;

      if IncludeHeaders then
        Column.Header := Fields[Col].Name
      else
        Column.Header := '';

      Column.Width := 100; // Default width
    end;

    // Set row count (this works in FMX)
    RowCount := List.Count;

    // Fill data
    for I := 0 to List.Count - 1 do
    begin
      Item := List[I];
      Row := I;

      for Col := 0 to Length(Fields) - 1 do
      begin
        Value := Fields[Col].GetValue(@Item);

        case Value.Kind of
          tkInteger, tkInt64:
            Cells[Col, Row] := IntToStr(Value.AsInteger);
          tkFloat:
            Cells[Col, Row] := FloatToStr(Value.AsExtended);
          tkString, tkLString, tkWString, tkUString:
            Cells[Col, Row] := Value.AsString;
          else
            Cells[Col, Row] := Value.ToString;
        end;
      end;
    end;

    // Auto-size columns after loading
    AutoSizeColumns;

  finally
    RttiContext.Free;
  end;
end;

end.
