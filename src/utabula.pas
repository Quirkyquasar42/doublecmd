{
   Double Commander inside Combined Windows Shell ("Tabula")

   Started with --tabula, Double Commander takes the shell's theme and lives in a window drawn in the
   shell's folder-window style: no Windows caption, a themed title bar (back, folder, path, menu,
   minimize, maximize, close) and the shell's colors, which follow the shell live. Everything else is
   stock Double Commander.

   The shell writes its colors to %APPDATA%\CombinedWindowsShell\theme.json as
   Bg, Panel, Panel2, Hover, Line, Line2, Text, Muted and Accent, each as "#RRGGBB".
}
unit uTabula;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms;

{ True when started with --tabula (checked straight from the command line, so it works before
  anything else has been set up). }
function TabulaRequested: Boolean;

{ Gives the main window the shell's title bar and colors. Call once the main window exists. }
procedure TabulaAttach(AForm: TCustomForm);

implementation

uses
  Controls, ExtCtrls, StdCtrls, Graphics, Menus, LCLType, LCLIntf, fpjson, jsonparser,
  uColors, uGlobs, fMain
  {$IFDEF MSWINDOWS}, Windows{$ENDIF};

const
  BarHeight = 34;
  TagBack = 1; TagMenu = 2; TagMin = 3; TagMax = 4; TagClose = 5;

type

  { TTabulaFrame }

  TTabulaFrame = class(TComponent)
  private
    FForm: TCustomForm;
    FBar: TPanel;
    FIcon, FTitle, FPath: TLabel;
    FButtons: array[TagBack..TagClose] of TLabel;
    FPopup: TPopupMenu;
    FTimer: TTimer;
    FThemeAge: LongInt;
    FBg, FPanel, FPanel2, FHover, FLine, FLine2, FText, FMuted, FAccent: TColor;
    function MakeButton(const ACaption, AHint: String; ATag: Integer; AAlign: TAlign): TLabel;
    procedure LoadTheme(Force: Boolean);
    procedure ApplyTheme;
    procedure ApplyToTheme(T: TColorTheme);
    procedure Restyle;
    procedure ShowMenu;
    procedure Mirror(Src, Dst: TMenuItem);
    procedure MirrorClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure BarMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BarDblClick(Sender: TObject);
    procedure ButtonClick(Sender: TObject);
    procedure ButtonEnter(Sender: TObject);
    procedure ButtonLeave(Sender: TObject);
  public
    constructor CreateFor(AForm: TCustomForm);
  end;

var
  Frame: TTabulaFrame = nil;

function TabulaRequested: Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), '--tabula') then Exit(True);
  Result := False;
end;

procedure TabulaAttach(AForm: TCustomForm);
begin
  if (Frame = nil) and TabulaRequested then
    Frame := TTabulaFrame.CreateFor(AForm);
end;

function ThemeFile: String;
begin
  Result := IncludeTrailingPathDelimiter(SysUtils.GetEnvironmentVariable('APPDATA')) +
            'CombinedWindowsShell' + PathDelim + 'theme.json';
end;

function HexColor(const S: String; Fallback: TColor): TColor;
var
  V: LongInt;
begin
  if (Length(S) = 7) and (S[1] = '#') and TryStrToInt('$' + Copy(S, 2, 6), V) then
    Result := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF)
  else
    Result := Fallback;
end;

{ TTabulaFrame }

constructor TTabulaFrame.CreateFor(AForm: TCustomForm);
begin
  inherited Create(AForm);
  FForm := AForm;
  // the Destiny defaults, until the shell's theme file is read
  FBg := $1A1714; FPanel := $241F1B; FPanel2 := $2E2924; FHover := $3A332C; FLine := $332D28;
  FLine2 := $443C35; FText := $F0EAE6; FMuted := $A89F99; FAccent := $3AA1E5;

  FBar := TPanel.Create(Self);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.Top := -1000;   // above the toolbar and everything else aligned to the top
  FBar.Height := FForm.Scale96ToForm(BarHeight);
  FBar.BevelOuter := bvNone;
  FBar.ParentBackground := False;
  FBar.OnMouseDown := @BarMouseDown;
  FBar.OnDblClick := @BarDblClick;

  // right to left: close, maximize, minimize, menu
  FButtons[TagClose] := MakeButton('✕', 'Close', TagClose, alRight);
  FButtons[TagMax] := MakeButton('☐', 'Maximize or restore', TagMax, alRight);
  FButtons[TagMin] := MakeButton('—', 'Minimize', TagMin, alRight);
  FButtons[TagMenu] := MakeButton('☰', 'Menu', TagMenu, alRight);
  // left to right: back, folder icon, title, path
  FButtons[TagBack] := MakeButton('‹', 'Back', TagBack, alLeft);

  FIcon := TLabel.Create(Self);
  FIcon.Parent := FBar; FIcon.Align := alLeft; FIcon.Layout := tlCenter;
  FIcon.Caption := '▰'; FIcon.BorderSpacing.Left := FForm.Scale96ToForm(4);
  FIcon.OnMouseDown := @BarMouseDown; FIcon.OnDblClick := @BarDblClick;

  FTitle := TLabel.Create(Self);
  FTitle.Parent := FBar; FTitle.Align := alLeft; FTitle.Layout := tlCenter;
  FTitle.BorderSpacing.Left := FForm.Scale96ToForm(8);
  FTitle.Font.Style := [fsBold];
  FTitle.OnMouseDown := @BarMouseDown; FTitle.OnDblClick := @BarDblClick;

  FPath := TLabel.Create(Self);
  FPath.Parent := FBar; FPath.Align := alClient; FPath.Layout := tlCenter;
  FPath.BorderSpacing.Left := FForm.Scale96ToForm(10);
  FPath.OnMouseDown := @BarMouseDown; FPath.OnDblClick := @BarDblClick;

  FPopup := TPopupMenu.Create(Self);

  // the main menu moves behind the ☰ button; the Windows caption goes (the bar above replaces it)
  gMainMenu := False;
  frmMain.Commands.DoShowMainMenu(False);

  LoadTheme(True);

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 500;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;
  Tick(nil);
end;

function TTabulaFrame.MakeButton(const ACaption, AHint: String; ATag: Integer; AAlign: TAlign): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := FBar;
  Result.Align := AAlign;
  Result.AutoSize := False;
  Result.Width := FForm.Scale96ToForm(40);
  Result.Alignment := taCenter;
  Result.Layout := tlCenter;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.Tag := ATag;
  Result.Transparent := False;
  Result.Cursor := crHandPoint;
  Result.Font.Size := 11;
  Result.OnClick := @ButtonClick;
  Result.OnMouseEnter := @ButtonEnter;
  Result.OnMouseLeave := @ButtonLeave;
end;

procedure TTabulaFrame.LoadTheme(Force: Boolean);
var
  Age: LongInt;
  Data: TJSONData = nil;
  Obj: TJSONObject;
  Text: TStringList;

  function Get(const Key: String; Fallback: TColor): TColor;
  begin
    Result := HexColor(Obj.Get(Key, ''), Fallback);
  end;

begin
  Age := FileAge(ThemeFile);
  if (not Force) and (Age = FThemeAge) then Exit;
  FThemeAge := Age;
  if Age <> -1 then
  begin
    Text := TStringList.Create;
    try
      try
        Text.LoadFromFile(ThemeFile);
        Data := GetJSON(Text.Text);
        if Data is TJSONObject then
        begin
          Obj := TJSONObject(Data);
          FBg := Get('Bg', FBg); FPanel := Get('Panel', FPanel); FPanel2 := Get('Panel2', FPanel2);
          FHover := Get('Hover', FHover); FLine := Get('Line', FLine); FLine2 := Get('Line2', FLine2);
          FText := Get('Text', FText); FMuted := Get('Muted', FMuted); FAccent := Get('Accent', FAccent);
        end;
      except
        // a half-written or broken file: keep the colors we have, try again when it changes
      end;
    finally
      Data.Free;
      Text.Free;
    end;
  end;
  ApplyTheme;
end;

procedure TTabulaFrame.ApplyToTheme(T: TColorTheme);
begin
  if T = nil then Exit;
  with T.FilePanel do
  begin
    ForeColor := FText; BackColor := FBg; BackColor2 := FPanel; GridLine := FLine;
    CursorBorderColor := FAccent; CursorColor := FHover; CursorText := FText;
    InactiveCursorColor := FPanel2; MarkColor := FAccent; InactiveMarkColor := FAccent;
  end;
  with T.Path do
  begin
    ActiveColor := FPanel2; ActiveFontColor := FText; InactiveColor := FPanel; InactiveFontColor := FMuted;
  end;
  with T.FreeSpaceInd do
  begin
    ForeColor := FAccent; BackColor := FPanel;
  end;
  with T.TreeViewMenu do
  begin
    BackgroundColor := FPanel; NormalTextColor := FText; SecondaryTextColor := FMuted; ShortcutColor := FMuted;
    CursorColor := FHover; NormalTextUnderCursor := FText; SecondaryTextUnderCursor := FText; ShortcutUnderCursor := FText;
  end;
  with T.Viewer do
  begin
    BookBackgroundColor := FBg; BookFontColor := FText;
  end;
end;

procedure TTabulaFrame.ApplyTheme;
begin
  ApplyToTheme(gColors.GetTheme(LIGHT_THEME));
  ApplyToTheme(gColors.GetTheme(DARK_THEME));
  Restyle;
  frmMain.UpdateWindowView;
end;

procedure TTabulaFrame.Restyle;
var
  I: Integer;
begin
  FBar.Color := FPanel;
  FIcon.Font.Color := FAccent;
  FTitle.Font.Color := FText;
  FPath.Font.Color := FMuted;
  for I := Low(FButtons) to High(FButtons) do
  begin
    FButtons[I].Color := FPanel;
    FButtons[I].Font.Color := FText;
  end;
  FForm.Color := FBg;
end;

procedure TTabulaFrame.ButtonEnter(Sender: TObject);
begin
  if TLabel(Sender).Tag = TagClose then TLabel(Sender).Color := RGBToColor($C4, $2B, $1C)
  else TLabel(Sender).Color := FHover;
end;

procedure TTabulaFrame.ButtonLeave(Sender: TObject);
begin
  TLabel(Sender).Color := FPanel;
end;

procedure TTabulaFrame.ButtonClick(Sender: TObject);
begin
  case TLabel(Sender).Tag of
    TagBack:  frmMain.Commands.Commands.ExecuteCommand('cm_ViewHistoryPrev', []);
    TagMenu:  ShowMenu;
    TagMin:   Application.Minimize;
    TagMax:   if FForm.WindowState = wsMaximized then FForm.WindowState := wsNormal else FForm.WindowState := wsMaximized;
    TagClose: FForm.Close;
  end;
end;

procedure TTabulaFrame.Mirror(Src, Dst: TMenuItem);
var
  I: Integer;
  S, D: TMenuItem;
begin
  for I := 0 to Src.Count - 1 do
  begin
    S := Src.Items[I];
    if not S.Visible then Continue;
    D := TMenuItem.Create(FPopup);
    D.Caption := S.Caption;
    D.Enabled := S.Enabled;
    D.Checked := S.Checked;
    D.RadioItem := S.RadioItem;
    D.ShortCut := S.ShortCut;
    D.ImageIndex := S.ImageIndex;
    D.Tag := PtrInt(S);
    if S.Count > 0 then Mirror(S, D) else D.OnClick := @MirrorClick;
    Dst.Add(D);
  end;
end;

procedure TTabulaFrame.MirrorClick(Sender: TObject);
begin
  TMenuItem(TMenuItem(Sender).Tag).Click;
end;

{ The main menu, as a popup under the ☰ button: rebuilt each time so it shows the current state. }
procedure TTabulaFrame.ShowMenu;
var
  P: TPoint;
begin
  FPopup.Items.Clear;
  FPopup.Images := frmMain.mnuMain.Images;
  Mirror(frmMain.mnuMain.Items, FPopup.Items);
  P := FButtons[TagMenu].ClientToScreen(Point(0, FButtons[TagMenu].Height));
  FPopup.PopUp(P.X, P.Y);
end;

procedure TTabulaFrame.Tick(Sender: TObject);
var
  Path, Folder: String;
{$IFDEF MSWINDOWS}
  Style: LONG_PTR;
{$ENDIF}
begin
  LoadTheme(False);
{$IFDEF MSWINDOWS}
  // no Windows caption: the themed bar is the title bar. Checked on every tick because Windows and the
  // widget set put the caption back when a window is recreated.
  if FForm.HandleAllocated then
  begin
    Style := GetWindowLongPtr(FForm.Handle, GWL_STYLE);
    if (Style and WS_CAPTION) <> 0 then
    begin
      SetWindowLongPtr(FForm.Handle, GWL_STYLE, (Style and not WS_CAPTION) or WS_THICKFRAME);
      SetWindowPos(FForm.Handle, 0, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_FRAMECHANGED);
    end;
  end;
{$ENDIF}
  if gMainMenu then
  begin
    gMainMenu := False;
    frmMain.Commands.DoShowMainMenu(False);
  end;
  if Assigned(frmMain.ActiveFrame) then
  begin
    Path := frmMain.ActiveFrame.CurrentPath;
    Folder := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
    if Folder = '' then Folder := Path;
    if FTitle.Caption <> Folder then FTitle.Caption := Folder;
    if FPath.Caption <> Path then FPath.Caption := Path;
  end;
end;

procedure TTabulaFrame.BarMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or (ssDouble in Shift) then Exit;
{$IFDEF MSWINDOWS}
  // move the window as if its caption were dragged (snap, shake and the shell's tiling all keep working)
  ReleaseCapture;
  SendMessage(FForm.Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
{$ENDIF}
end;

procedure TTabulaFrame.BarDblClick(Sender: TObject);
begin
  if FForm.WindowState = wsMaximized then FForm.WindowState := wsNormal else FForm.WindowState := wsMaximized;
end;

end.
