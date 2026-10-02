{ Copyright (C) 2026 by Bill Stewart (bstewart at iname.com)

  This program is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free Software
  Foundation, either version 3 of the License, or (at your option) any later
  version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
  details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see https://www.gnu.org/licenses/.

}

program urand;

{$MODE OBJFPC}
{$MODESWITCH UNICODESTRINGS}
{$R *.res}

uses
  windows,
  wargcv,           // https://github.com/Bill-Stewart/wargcv
  wgetopts,         // https://github.com/Bill-Stewart/wargcv
  WindowsMessages,  // https://github.com/Bill-Stewart/WindowsMessages
  WindowsString,    // https://github.com/Bill-Stewart/WindowsString
  randUtil;

const
  PROGRAM_NAME = 'urand';
  PROGRAM_COPYRIGHT = 'Copyright (C) 2026 by Bill Stewart';

type
  TCommandLine = object
    Error: DWORD;
    ErrorMsg: string;
    BufSize: DWORD;
    OutputFileName: string;
    ForceOverwrite: Boolean;
    ByteCount: Int64;
    Algorithm: TRandomAlgorithm;
    Seed: DWORD;
    TextOutput: Boolean;
    Help: Boolean;
    Quiet: Boolean;
    procedure Parse();
  end;

function IntToStr(const I: Int64): string;
begin
  Str(I, result);
end;

function GetFileVersion(const FileName: string): string;
var
  VerInfoSize, Handle: DWORD;
  pBuffer: Pointer;
  pFileInfo: ^VS_FIXEDFILEINFO;
  Len: UINT;
begin
  result := '';
  VerInfoSize := GetFileVersionInfoSizeW(PChar(FileName),  // LPCWSTR lptstrFilename
    Handle);                                               // LPDWORD lpdwHandle
  if VerInfoSize > 0 then
  begin
    GetMem(pBuffer, VerInfoSize);
    if GetFileVersionInfoW(PChar(FileName),  // LPCWSTR lptstrFilename
      Handle,                                // DWORD   dwHandle
      VerInfoSize,                           // DWORD   dwLen
      pBuffer) then                          // LPVOID  lpData
    begin
      if VerQueryValueW(pBuffer,  // LPCVOID pBlock
        '\',                      // LPCWSTR lpSubBlock
        pFileInfo,                // LPVOID  *lplpBuffer
        Len) then                 // PUINT   puLen
      begin
        with pFileInfo^ do
        begin
          result := IntToStr(HiWord(dwFileVersionMS)) + '.' +
            IntToStr(LoWord(dwFileVersionMS)) + '.' +
            IntToStr(HiWord(dwFileVersionLS));
        end;
      end;
    end;
    FreeMem(pBuffer);
  end;
end;

procedure Usage();
begin
  WriteLn(PROGRAM_NAME, ' ', GetFileVersion(ParamStr(0)), ' - ', PROGRAM_COPYRIGHT);
  WriteLn('This is free software and comes with ABSOLUTELY NO WARRANTY.');
  WriteLn();
  WriteLn('Generates random output.');
  WriteLn();
  WriteLn('USAGE');
  WriteLn();
  WriteLn(PROGRAM_NAME, ' <bytecount> [--out=<filename> [--force]] [--text] [--algorithm=<name>]');
  WriteLn('[--buffersize=<n>] [--seed=<n>] [--quiet]');
  WriteLn();
  WriteLn('<bytecount>                      Number of random bytes to generate');
  WriteLn('--out=<filename>, -o <filename>  Output file name (omit to output to stdout)');
  WriteLn('--force                          Overwrite existing output file');
  WriteLn('--text, -t                       Output as text (recommended if no output file)');
  WriteLn('--algorithm=<name>, -a <name>    Algorithm: OS (default), LCG, or RTL');
  WriteLn('--buffersize=<n>, -B <n>         Buffer size in KB (default is 64)');
  WriteLn('--seed=<n>                       Seed for LCG or RTL algorithms (not OS)');
  WriteLn('--quiet, -q                      Suppress error messages');
  WriteLn('--help, -h                       This usage message');
end;

function StrToDWORD(const S: string; Min, Max: DWORD; out I: DWORD): Boolean;
var
  N: DWORD;
  Code: Integer;
begin
  Val(S, N, Code);
  result := (Code = 0) and (N <= Max) and (N >= Min);
  if result then
    I := N;
end;

function StrToInt64(const S: string; Min, Max: Int64; out I: Int64): Boolean;
var
  N: Int64;
  Code: Integer;
begin
  Val(S, N, Code);
  result := (Code = 0) and (N <= Max) and  (N >= Min);
  if result then
    I := N;
end;

procedure TCommandLine.Parse();
var
  Opts: array[1..9] of TOption;
  Opt: Char;
  I: Integer;
begin
  with Opts[1] do
  begin
    Name := 'algorithm';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'a';
  end;
  with Opts[2] do
  begin
    Name := 'buffersize';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'B';
  end;
  with Opts[3] do
  begin
    Name := 'force';
    Has_arg := No_Argument;
    Flag := nil;
    Value := #0;
  end;
  with Opts[4] do
  begin
    Name := 'help';
    Has_arg := No_Argument;
    Flag := nil;
    Value := 'h';
  end;
  with Opts[5] do
  begin
    Name := 'out';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'o';
  end;
  with Opts[6] do
  begin
    Name := 'quiet';
    Has_arg := Required_Argument;
    Flag := nil;
    Value := 'q';
  end;
  with Opts[7] do
  begin
    Name := 'seed';
    Has_arg := Required_Argument;
    flag := nil;
    value := #0;
  end;
  with Opts[8] do
  begin
    Name := 'text';
    Has_arg := No_Argument;
    Flag := nil;
    Value := 't';
  end;
  with Opts[9] do
  begin
    Name := '';
    Has_arg := No_Argument;
    Flag := nil;
    Value := #0;
  end;
  Error := ERROR_SUCCESS;
  ErrorMsg := '';
  BufSize := 0;
  OutputFileName := '';
  Algorithm := randAlgOS;
  ByteCount := 0;
  Seed := 0;
  TextOutput := false;
  ForceOverwrite := false;
  Help := false;
  Quiet := false;
  OptErr := false;  // no error reporting from wgetopts
  repeat
    Opt := GetLongOpts('a:B:c:fho:qt', @Opts[1], I);
    case Opt of
      'a':  // --algorithm
      begin
        case UppercaseString(OptArg) of
          'OS':  Algorithm := randAlgOS;
          'LCG': Algorithm := randAlgLCG;
          'RTL': Algorithm := randAlgRTL;
        else
          begin
            Error := ERROR_INVALID_PARAMETER;
            ErrorMsg := 'The --algorithm (-a) parameter''s argument must be one of: OS LCG RTL';
          end;
        end;
      end;
      'B':  // --buffersize
      begin
        if StrToDWORD(OptArg, (MIN_BUFFER_SIZE div 1024),
          (MAX_BUFFER_SIZE div 1024), BufSize) then
        begin
          BufSize := BufSize * 1024;
        end
        else
        begin
          Error := ERROR_INVALID_PARAMETER;
          ErrorMsg := 'The --buffersize (-B) parameter requires an argument in the range '
            + IntToStr(MIN_BUFFER_SIZE div 1024)
            + ' to '
            + IntToStr(MAX_BUFFER_SIZE div 1024);
        end;
      end;
      'h':  // --help
      begin
        Help := true;
      end;
      'o':  // --out
      begin
        OutputFileName := OptArg;
      end;
      'q':  // --quiet
      begin
        Quiet := true;
      end;
      't':  // --text
      begin
        TextOutput := true;
      end;
      #0:
      case Opts[I].Name of
        'force':
        begin
          ForceOverwrite := true;
        end;
        'seed':
        begin
          if not StrToDWORD(OptArg, 1, High(DWORD), Seed) then
          begin
            Error := ERROR_INVALID_PARAMETER;
            ErrorMsg := 'The --seed parameter requires an argument in the range 1 to '
              + IntToStr(High(DWORD));
          end;
        end;
      end;
      '?':
      begin
        Error := ERROR_INVALID_PARAMETER;
        ErrorMsg := GetWindowsMessage(Error);
      end;
    end;
    if Error <> ERROR_SUCCESS then
      break;
  until Opt = EndOfOptions;
  if Error <> ERROR_SUCCESS then
    exit;
  if ParamStr(OptInd) = '' then
  begin
    Error := ERROR_INVALID_PARAMETER;
    ErrorMsg := 'You must specify a random byte count';
  end
  else
  begin
    if not StrToInt64(ParamStr(OptInd), 1, MAX_OUTPUT_SIZE, ByteCount) then
    begin
      Error := ERROR_INVALID_PARAMETER;
      ErrorMsg := 'Byte count must be in the range 1 through ' + IntToStr(MAX_OUTPUT_SIZE);
    end;
  end;
end;

var
  CmdLine: TCommandLine;
  Rand: TRand;
  ResultCode: DWORD;

begin
  CmdLine.Parse();

  if CmdLine.Help then
  begin
    Usage();
    exit;
  end;

  if CmdLine.Error <> ERROR_SUCCESS then
  begin
    WriteLn(StdErr, CmdLine.ErrorMsg);
    WriteLn(StdErr, 'Use --help (-h) for usage information');
    ExitCode := Integer(CmdLine.Error);
    exit;
  end;

  Rand := TRand.Create();

  if CmdLine.OutputFilename <> '' then
    Rand.SetOutputFile(CmdLine.OutputFileName, CmdLine.ForceOverwrite);
  if Rand.ErrorCode = ERROR_SUCCESS then
  begin
    if CmdLine.BufSize > 0 then
      Rand.BufferSize := CmdLine.BufSize;
    Rand.Algorithm := CmdLine.Algorithm;
    if CmdLine.Seed > 0 then
      Rand.Seed := CmdLine.Seed;
    if CmdLine.TextOutput then
      Rand.TextOutput := true;
    Rand.Generate(CmdLine.ByteCount);
  end;

  ResultCode := Rand.ErrorCode;
  Rand.Destroy();

  if not CmdLine.Quiet then
  begin
    if ResultCode <> ERROR_SUCCESS then
      WriteLn(StdErr, GetWindowsMessage(ResultCode, true));
  end;

  ExitCode := Integer(ResultCode);
end.
