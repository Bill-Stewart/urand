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

unit randUtil;

{$MODE OBJFPC}
{$MODESWITCH UNICODESTRINGS}

interface

const
  MIN_BUFFER_SIZE = $000001000;  // 4KB
  DEF_BUFFER_SIZE = $000010000;  // 64KB
  MAX_BUFFER_SIZE = $020000000;  // 512MB
  MAX_OUTPUT_SIZE = $C80000000;  // 50GB

type
  TByteArray = array of Byte;
  TUTF8CharArray = array of UTF8Char;
  TRandomAlgorithm = (randAlgOS, randAlgLCG, randAlgRTL);
  TRand = class
  private
  var
    OutputFileHandle: THandle;
    Alg: TRandomAlgorithm;
    TxtOut: Boolean;
    Buf: TByteArray;
    Base64Buf: TUTF8CharArray;
    BufSize: DWORD;
    Base64Flags: DWORD;
    Error: DWORD;
  procedure SetBufferSize(const NewBufSize: DWORD);
  procedure SetSeed(const NewSeed: DWORD);
  procedure SetTextOutput(const NewTextOutput: Boolean);
  procedure SetAlgorithm(const NewAlgorithm: TRandomAlgorithm);
  function GetBase64BufSize(): DWORD;
  procedure FillBuffer();

  public
  constructor Create();
  destructor Destroy(); override;
  property ErrorCode: DWORD read Error;
  property BufferSize: DWORD write SetBufferSize;
  property Seed: DWORD write SetSeed;
  property Algorithm: TRandomAlgorithm write SetAlgorithm;
  property TextOutput: Boolean write SetTextOutput;
  procedure SetOutputFile(const FileName: string; const ForceOverwrite: Boolean);
  procedure Generate(const ByteCount: Int64);
  end;

implementation

uses
  windows;

type
  NTSTATUS = DWORD;
  TRandFunc = function(H: Integer): Integer;

const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;
  CRYPT_STRING_BASE64URI          = $0000000D;
  CRYPT_STRING_NOCRLF             = $40000000;
  STATUS_SUCCESS                  = ERROR_SUCCESS;

// Generates random bytes to a buffer
function BCryptGenRandom(hAlgorithm: HANDLE; pbBuffer: PByte;
  cbBuffer: DWORD; dwFlags: DWORD): NTSTATUS; stdcall;
  external 'bcrypt.dll';

// Converts an array of bytes into a formatted string
function CryptBinaryToStringA(pbBinary: PByte; cbBinary: DWORD; dwFlags: DWORD;
  pszString: LPSTR; var pcchString: DWORD): BOOL; stdcall;
  external 'crypt32.dll';

// Converts the specified NTSTATUS code to its equivalent system error code
function RtlNtStatusToDosError(Status: NTSTATUS): ULONG;
  stdcall; external 'ntdll.dll';

// Delphi-compatible Linear Congruential Generator (LCG) function: By default
// (at the time of this writing), the Free Pascal (FPC) runtime library (RTL)
// uses a Mersenne Twister algorithm, which has a better statistical
// distribution than the below, but it is considerably slower.
function LCGRandom(const M: Integer): Integer; inline;
var
  Temp: Int64;
begin
  Temp := (134775813 * RandSeed) + 1;
  RandSeed := Cardinal(Temp);
  result := (Int64(Cardinal(M)) * Int64(Cardinal(Temp))) shr 32;
end;

constructor TRand.Create();
begin
  OutputFileHandle := GetStdHandle(STD_OUTPUT_HANDLE);  // DWORD nStdHandle
  BufSize := DEF_BUFFER_SIZE;
  Error := ERROR_SUCCESS;
  Algorithm := randAlgOS;
  TxtOut := false;
  Base64Flags := CRYPT_STRING_BASE64URI or CRYPT_STRING_NOCRLF;
  Randomize();
end;

destructor TRand.Destroy();
begin
  if OutputFileHandle <> GetStdHandle(STD_OUTPUT_HANDLE) then  // DWORD nStdHandle
    CloseHandle(OutputFileHandle);  // HANDLE hObject
end;

procedure TRand.SetSeed(const NewSeed: DWORD);
begin
  RandSeed := NewSeed;
end;

procedure TRand.SetAlgorithm(const NewAlgorithm: TRandomAlgorithm);
begin
  Alg := NewAlgorithm;
end;

procedure TRand.SetTextOutput(const NewTextOutput: Boolean);
begin
  TxtOut := NewTextOutput;
end;

procedure TRand.SetOutputFile(const FileName: string; const ForceOverwrite: Boolean);
var
  CreationDisposition: DWORD;
begin
  if ForceOverwrite then
    CreationDisposition := CREATE_ALWAYS
  else
    CreationDisposition := CREATE_NEW;
  OutputFileHandle := CreateFileW(PChar(FileName),  // LPCWSTR               lpFileName
    GENERIC_WRITE,                                  // DWORD                 dwDesiredAccess
    FILE_SHARE_WRITE,                               // DWORD                 dwShareMode
    nil,                                            // LPSECURITY_ATTRIBUTES lpSecurityAttributes
    CreationDisposition,                            // DWORD                 dwCreationDisposition
    FILE_ATTRIBUTE_NORMAL,                          // DWORD                 dwFlagsAndAttributes
    0);                                             // HANDLE                hTemplateFile
  if OutputFileHandle = INVALID_HANDLE_VALUE then
    Error := GetLastError();
end;

procedure TRand.SetBufferSize(const NewBufSize: DWORD);
begin
  if NewBufSize <= MAX_BUFFER_SIZE then
  begin
    BufSize := NewBufSize;
    {$IFDEF DEBUG}
    WriteLn(StdErr, 'SetBufferSize = ', BufSize);
    {$ENDIF}
  end;
end;

function TRand.GetBase64BufSize(): DWORD;
var
  TempBuf: TByteArray;
begin
  // Call API with dummy buffer to get size
  SetLength(TempBuf, BufSize);
  FillChar(TempBuf[0], BufSize, #97);  // Fill with 'a'
  if not CryptBinaryToStringA(@TempBuf[0],  // PBYTE  pbBinary
    BufSize,                                // DWORD  cbBinary
    Base64Flags,                            // DWORD  dwFlags
    nil,                                    // LPSTR  pszString
    result) then                            // DWORD  *pcchString
  begin
    Error := GetLastError();
  end
  else
  begin
    {$IFDEF DEBUG}
    WriteLn(StdErr, 'Base64BufSize = ', result);
    {$ENDIF}
  end;
end;

// Fills Buf with random data using the requested algorithm; if text-only,
// convert Buf to base64 (in Base64Buf)
procedure TRand.FillBuffer();
var
  NumBytes, NumChars: DWORD;
  RandFunc: TRandFunc;
  I: Integer;
begin
  NumBytes := Length(Buf);
  if Alg = randAlgOS then
  begin
    Error := BCryptGenRandom(0,          // BCRYPT_ALG_HANDLE hAlgorithm
      @Buf[0],                           // PUCHAR            pbBuffer
      NumBytes,                          // ULONG             cbBuffer
      BCRYPT_USE_SYSTEM_PREFERRED_RNG);  // ULONG             dwFlags
    if Error <> STATUS_SUCCESS then
    begin
      // I considered using RtlNtStatusToDosError here, but decided to leave
      // Error as an NTSTATUS value so it would be easier to identify that it
      // was this function that returned the error.
      //Error := RtlNtStatusToDosError(Error);
      exit;
    end;
  end
  else
  begin
    case Alg of
      randAlgLCG: RandFunc := TRandFunc(@LCGRandom);
      randAlgRTL: RandFunc := TRandFunc(@System.Random);
    else
      RandFunc := nil;
    end;
    for I := 0 to NumBytes - 1 do
    begin
      Buf[I] := RandFunc(High(Byte) + 1);
    end;
  end;
  {$IFDEF DEBUG}
  WriteLn(StdErr, 'Filled buffer with ', NumBytes, ' bytes using ', Alg);
  {$ENDIF}
  if TxtOut then
  begin
    NumChars := Length(Base64Buf);
    if CryptBinaryToStringA(@Buf[0],  // PBYTE  pbBinary
      NumBytes,                       // DWORD  cbBinary
      Base64Flags,                    // DWORD  dwflags
      @Base64Buf[0],                  // LPSTR  pszString
      NumChars) then                  // PDWORD pcchString
    begin
      {$IFDEF DEBUG}
      WriteLn(StdErr, 'Base64-encoded ', NumBytes, ' bytes to ', NumChars, ' characters');
      {$ENDIF}
    end
    else
      Error := GetLastError();
  end;
end;

procedure TRand.Generate(const ByteCount: Int64);
var
  Chunks, Rest, I: Integer;
  Base64BufSize, BytesWritten: DWORD;
  pOutBuf: Pointer;
  {$IFDEF DEBUG}
  TotalBytesWritten: Int64;
  {$ENDIF}
begin
  if ByteCount < BufSize then
    BufSize := ByteCount;
  SetLength(Buf, BufSize);
  if TxtOut then
  begin
    Base64BufSize := GetBase64BufSize();
    if Error <> ERROR_SUCCESS then
      exit;
    SetLength(Base64Buf, Base64BufSize);
    pOutBuf := @Base64Buf[0];
  end
  else
    pOutBuf := @Buf[0];
  Chunks := ByteCount div BufSize;
  {$IFDEF DEBUG}
  TotalBytesWritten := 0;
  {$ENDIF}
  for I := 1 to Chunks do
  begin
    FillBuffer();
    if Error <> ERROR_SUCCESS then
      break;
    if not WriteFile(OutputFileHandle,  // HANDLE       hFile
      pOutBuf^,                         // LPCVOID      lpBuffer
      BufSize,                          // DWORD        nNumberOfBytesToWrite
      BytesWritten,                     // LPDWORD      lpNumberOfBytesWritten
      nil) then                         // LPOVERLAPPED lpOverlapped
    begin
      Error := GetLastError();
      break;
    end
    else
    begin
      {$IFDEF DEBUG}
      WriteLn(StdErr, 'Wrote ', BytesWritten, ' byte(s)');
      Inc(TotalBytesWritten, BytesWritten);
      {$ENDIF}
    end;
  end;
  if Error = ERROR_SUCCESS then
  begin
    Rest := ByteCount mod BufSize;
    if Rest > 0 then
    begin
      BufSize := Rest;
      SetLength(Buf, BufSize);  // Truncate to remainder's size
      FillBuffer();
      if Error = ERROR_SUCCESS then
      begin
        if not WriteFile(OutputFileHandle,  // HANDLE       hFile
          pOutBuf^,                         // LPCVOID      lpBuffer
          BufSize,                          // DWORD        nNumberOfBytesToWrite
          BytesWritten,                     // LPDWORD      lpNumberOfBytesWritten
          nil) then                         // LPOVERLAPPED lpOverlapped
        begin
          Error := GetLastError();
        end
        else
        begin
          {$IFDEF DEBUG}
          Inc(TotalBytesWritten, BytesWritten);
          {$ENDIF}
        end;
      end;
    end;
  end;
  {$IFDEF DEBUG}
  if Error = ERROR_SUCCESS then
    WriteLn(StdErr, 'Wrote ', TotalBytesWritten, ' total byte(s)');
  {$ENDIF}
end;

begin
end.
