# Scholarly Download (Delphi FMX) — OpenAlex Paper Downloader

Delphi FMX application to download scientific paper metadata via the **OpenAlex Works API**, display results in a `TStringGrid`, and export to **CSV / JSON / BibTeX**.

> Note: This project uses OpenAlex (not direct Google Scholar scraping), because scraping is typically unreliable / blocked and may violate terms.

---

## Features

- Download papers from OpenAlex using keyword search (paged) 
- Fields extracted per paper:
  - `title`, `authors`, `publication_year`, `abstract`, `cited_by_count`, `doi`, `url` 
- Display results in FMX UI (`TMemo` + `TStringGrid`) 
- Export formats (checkbox-driven in UI):
  - CSV
  - JSON
  - BibTeX [4]
- Sorting support inside `TPaperList`:
  - sort by title, authors, year, citations 
- `TStringGrid` helper for:
  - dynamic columns + row fill from generic record list
  - auto column sizing using text layout 

---

## Project Structure

- `Scholarly.dproj` — Delphi project file (FMX Application) 
- `Unit_TScholarly.pas`
  - `TScholarly`: OpenAlex client + download logic 
  - `TPaperRecord`: paper metadata record
  - `TPaperList`: list container + sorting + export 
- `Unit_StringGridHelper.pas`
  - `TStringGridHelper`: autosize columns + load from list 
- `GUI.FMX.ScholarlyDownload.pas/.fmx`
  - FMX main UI form, download button, query memo, results memo, stringgrid, export checkboxes 

---

## Requirements

- Embarcadero Delphi 12 (or compatible)
- FMX framework enabled
- Network access to `https://api.openalex.org`

---

## How it Works

### 1) Build OpenAlex URL
The client builds a Works endpoint URL like:

`/works?search=...&per-page=...&page=...&mailto=...` (optional) 

### 2) Download + Parse Results
The app downloads JSON pages and parses `results[]` into `TPaperRecord` entries.

### 3) Show Results
Results are displayed in the FMX UI and can be loaded into a `TStringGrid`.
The helper can create columns dynamically and fill rows from a `TList<record>` using RTTI 

### 4) Export Results
The UI has checkboxes for exporting formats (`chk_exportasJSON`, `chk_exportasBIBTEX`, `chk_exportasCSV`) .
Programmatically you can export using:

- `TScholarly.SavePaperListToCSV(...)` 
- `TScholarly.SavePaperListToJSON(...)`
- `TScholarly.SavePaperListToBIB(...)`

---

## Usage (UI)

1. Enter your search keywords in the query memo (`mmo_QueryKeyWords`) 
2. Click **Download**
3. Select export checkboxes as needed
4. Export files are written to the configured path (example shown uses `c:\temp\papers.csv`) 

---

## Usage (Code Example)

Minimal example:

```pascal
var
  S: TScholarly;
begin
  S := TScholarly.Create;
  try
    // optional but recommended:
    // S.MailTo := 'you@domain.com';

    S.DownloadPapers('graph neural networks', 150, 200, 300);  // max, per-page, delay 
    S.SavePaperListToCSV('c:\temp\papers.csv');                 // export 
  finally
    S.Free;
  end;
end;
