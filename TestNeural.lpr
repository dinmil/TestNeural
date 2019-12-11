program TestNeural;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Classes, SysUtils,
  dateutils,
  neuralnetwork,
  neuralvolume,
  neuralfit
  { you can add units after this };

const
  FAV_SYS_NEWLINE = #13#10;

const FAV_AI_APPROVED   = 0.1;
      FAV_AI_NEGOTIATED = 0.5;
      FAV_AI_REJECTED   = 0.9;
      FAV_AI_UNKNOWN    = -1;

      FAV_AI_SET        = 0.9;
      FAV_AI_MIDDLE     = 0.5;
      FAV_AI_UNSET      = 0.1;
      FAV_AI_DELTA      = FAV_AI_SET - FAV_AI_UNSET;

      IS_SET_TOLLERANCE = 0.05;

      NUMBER_TOLERANCE = 0.11;



type
  TInputArray  = array[0..92] of TNeuralFloat;
  TOutputArray =  array[0..3] of TNeuralFloat;

  TRecStatistics = record
    count_samples: integer;

    OK: integer;
    NOK: integer;
    UNKNOWN: integer;

    count_rej: Integer;
    count_neg: Integer;
    count_app: Integer;
    count_unk: Integer;

    count_output_rej: Integer;
    count_output_neg: Integer;
    count_output_app: Integer;
    count_output_unk: Integer;

    approved_but_shoud_be_rejected: Integer;
    approved_but_shoud_be_negotiated: Integer;

    negotiated_but_shoud_be_approved: Integer;
    negotiated_but_shoud_be_rejected: Integer;

    rejected_but_shoud_be_approved: Integer;
    rejected_but_shoud_be_negotiated: Integer;

    miss_rejected: integer;
    miss_negotiated: integer;
    miss_approved: integer;

    unknown_is_really_rejected: integer;
    unknown_is_really_negotiated: integer;
    unknown_is_really_approved: integer;
  end;

var
  _TrainingListLoaded: Boolean;
  _TestListLoaded: Boolean;
  _InputArray: TInputArray;
  _OutputArray: TOutputArray;
  _Input  : TNNetVolume;
  _Output : TNNetVolume;
  _Pair   : TNNetVolumePair;
  _TrainingPairs: TNNetVolumePairList;
  _TestPairs: TNNetVolumePairList;
  _NFit: TNeuralFit;
  _NNet: TNNet;
  _ComputedOutput : TNNetVolume;
  _LearnCount: Integer;
  _TestCount: Integer;
  _Statistics: TRecStatistics;


const InitTRecStatistics: TRecStatistics = ({%H-});

function FormatFloat(InNumber: Extended; InNoOfDecimalPlaces: Integer = 4): String;
begin
  Result := Format('%0.' + IntToStr(InNoOfDecimalPlaces)+ 'f', [InNumber]);
end;

procedure FavLogToConsole(InString: String);
begin
  if IsConsole then begin
    try
      {$ifdef Windows}
      Writeln(StdOut, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), ': ', InString);
      {$else}
      Write(StdOut, FavToNiceStringDateAndTimeAndMSec(FavUTCNow), ': ', InString, #13#10);
      {$endif}
    except
    end;
  end;
end;


procedure FavSaveToFile(InFileName: String; const InString: String;
  InRaiseError: Boolean);
var MyFile: Text;
    MyFileAssigned: Boolean;
    MyFileOpened: Boolean;
begin
  MyFileAssigned:=False;
  MyFileOpened:=False;
  try
    AssignFile(MyFile, InFileName);
    MyFileAssigned:=True;
    Rewrite(MyFile);
    MyFileOpened:=True;
    Write(MyFile, InString);
    Flush(MyFile);
    CloseFile(MyFile);
    MyFileOpened:=False;
    MyFileAssigned:=False;
  except
    on E: Exception do begin
      if MyFileAssigned then begin
        try
          if MyFileOpened then begin
            CloseFile(MyFile);
          end;
        except
        end;
      end;
      if InRaiseError then begin;
        raise;
      end;
    end;
  end;
end;

function FavLoadFromFile(InFileName: String; InRaiseErrorIfNotExists: Boolean = False): String;
var MyFile: Text;
    MyFileAssigned: Boolean;
    MyFileOpened: Boolean;
    MyBuffer: String;
    MyString: String;
begin
  MyFileAssigned:=False;
  MyFileOpened:=False;
  MyString := '';

  if InRaiseErrorIfNotExists then begin
    if FileExists(InFileName) = false then begin
      raise Exception.Create('File: "' + InFileName + '" does not exists!');
    end;
  end;
  try
    AssignFile(MyFile, InFileName);
    MyFileAssigned:=True;
    Reset(MyFile);
    MyFileOpened := true;
    while not Eof(MyFile) do begin
      ReadLn(MyFile, MyBuffer);
      if MyString <> '' then MyString := MyString + #13#10;
      MyString := MyString + MyBuffer;
    end;
    CloseFile(MyFile);
    MyFileOpened := False;
    MyFileAssigned:=False;
  except
    on E: Exception do begin
      if MyFileAssigned then begin
        try
          if MyFileOpened then begin
            CloseFile(MyFile);
          end;
        except
        end;
      end;
      raise;
    end;
  end;
  Result := MyString;
end;

procedure FavAppendToFile(InFileName: String; const InString: String);
var MyFile: Text;
    MyFileAssigned: Boolean;
    MyFileOpened: Boolean;
begin
  MyFileAssigned:=False;
  MyFileOpened := False;
  try
    AssignFile(MyFile, InFileName);
    MyFileAssigned:=True;
    if FileExists(InFileName) then begin
      Append(MyFile);
      MyFileOpened := True;
    end
    else begin
      Rewrite(MyFile);
      MyFileOpened := True;
    end;
    Write(MyFile, InString);
    Flush(MyFile);
    CloseFile(MyFile);
    MyFileOpened := False;
    MyFileAssigned:=False;
  except
    on E: Exception do begin
      if MyFileAssigned then begin
        try
          if MyFileOpened then begin
            CloseFile(MyFile);
          end;
        except
        end;
      end;
      raise;
    end;
  end;
end;

function IsSet(InValue: Extended; InMedium: Extended): Boolean;
begin
  Result := (InValue > (InMedium - IS_SET_TOLLERANCE)) and (InValue < (InMedium + IS_SET_TOLLERANCE))
end;

function FixNumber(InValue: Extended; InToleranceSet, InToleranceUnset: Extended): Extended;
var MyResult: Extended;
begin
  // MyResult := round(InFloat);


  if (InValue > (FAV_AI_SET - InToleranceSet)) and (InValue < (FAV_AI_SET + InToleranceSet)) then MyResult := FAV_AI_SET
  else if (InValue > (FAV_AI_UNSET - InToleranceUnset)) and (InValue < (FAV_AI_UNSET + InToleranceUnset)) then MyResult := FAV_AI_UNSET
  else MyResult := FAV_AI_UNKNOWN;

  Result := MyResult;
end;

procedure CalculateLayerCounts(InNumberOfInputs, InNumberOfOutputs: Integer; InNumberOfSamples: Integer; var OutOneLayer,
  OutTwoLayersFirst, OutTwoLayersSecond: Integer);
begin
  // Found in some book
  // N -- number of training data N sampes  - 4 samples
  // m -- number of output neurons = 3 outputs
  // 1st layer: SQRT((m + 2) * N) + 2 * SQRT(N/(m+2)) = SQRT((3+2) * 4) + 2 * SQRT(4 / (3 +2)) = 4,4721 + 1,7889 = 6,26 = 7
  // 2nd layer: m * SQLRT(N/(m+2)) = 3 * SQRT(4/(3+2)) = 2.68 = 3

  FavLogToConsole('Number of samples: ' + IntToStr(InNumberOfSamples));
  FavLogToConsole('Number of inputs: ' + IntToStr(InNumberOfInputs));
  FavLogToConsole('Number of outputs: ' + IntToStr(InNumberOfOutputs));

  OutOneLayer := Trunc(sqrt((InNumberOfOutputs + 2) * InNumberOfSamples)) + 1;

  OutTwoLayersFirst := Trunc(sqrt((InNumberOfOutputs+2) * InNumberOfSamples) + 2 * sqrt(4 / (InNumberOfOutputs + 2))) + 1;
  OutTwoLayersSecond := Trunc(InNumberOfOutputs * sqrt(4 / (InNumberOfOutputs+2)) + 1);

  FavLogToConsole('OneLayer: ' + IntToStr(OutOneLayer));
  FavLogToConsole('TwoLayersFirst: ' + IntToStr(OutTwoLayersFirst));
  FavLogToConsole('TwoLayersSecond: ' + IntToStr(OutTwoLayersSecond));
end;

procedure LoadLearnData;
var MyStringsInput: TStrings;
    MyStringsOutput: TStrings;
    MyInputString: String;
    MyOutputString: String;
    F: Integer;
begin
  MyStringsInput  := nil;
  MyStringsOutput := nil;
  MyInputString   := '';
  MyOutputString  := '';
  try
    if FileExists('train_input.csv') and FileExists('train_output.csv') then begin
      FavLogToConsole('Loading training data from training files');
      MyStringsInput := TStringList.Create;
      MyStringsInput.LoadFromFile('train_input.csv');
      MyStringsOutput := TStringList.Create;
      MyStringsOutput.LoadFromFile('train_output.csv');

      if (MyStringsInput.Count > 0) and (MyStringsInput.Count = MyStringsOutput.Count) then begin
        _LearnCount := MyStringsInput.Count;
        for F := 0 to _LearnCount-1 do begin
          _Input  := TNNetVolume.Create(Length(TInputArray));
          _Input.LoadFromString(MyStringsInput.Strings[F]);
          _Output  := TNNetVolume.Create(Length(TOutputArray));
          _Output.LoadFromString(MyStringsOutput.Strings[F]);
          _Pair   :=  TNNetVolumePair.Create(_Input, _Output);
          _TrainingPairs.Add(_Pair);

          MyInputString := MyInputString + _Input.SaveToString() + FAV_SYS_NEWLINE;
          MyOutputString := MyOutputString + _Output.SaveToString() + FAV_SYS_NEWLINE;
        end;
        _TrainingListLoaded := True;
      end;

      FreeAndNil(MyStringsInput);
      FreeAndNil(MyStringsOutput);

      if _TrainingListLoaded = false then begin
        FavLogToConsole('*****************************************');
        FavLogToConsole('Learn/Training files are not loaded. Maybe count of records in files are not the same');
      end;

      FavLogToConsole('Saving train_input1.csv and train_output1.csv...');
      FavSaveToFile('train_input1.csv', MyInputString, false);
      FavSaveToFile('train_output1.csv', MyOutputString, false);
    end
    else begin
      FavLogToConsole('*****************************************');
      FavLogToConsole('File train_input.csv or file train_output.csv does not exists');
    end;
  except
  end;
end;

procedure CreateNetwork;
var MyOneLayerCount: Integer;
    MyFirstLayerCount: Integer;
    MySecondLayerCount: Integer;
    MyTestCount: Integer;
begin
  MyTestCount := _TrainingPairs.Count;

  CalculateLayerCounts(Length(_InputArray), Length(_OutputArray), MyTestCount, MyOneLayerCount, MyFirstLayerCount, MySecondLayerCount);

  // Create network - so far 93 params
  _NNet.AddLayer(TNNetInput.Create(Length(TInputArray)));

  // dummy if
  if true = false then begin
    FavLogToConsole('Using one layers');
    _NNet.AddLayer( TNNetFullConnectReLU.Create(MyOneLayerCount) );
    _NNet.AddLayer( TNNetFullConnectLinear.Create(Length(TOutputArray)) );
    _NNet.AddLayer( TNNetSoftMax.Create());
  end
  else begin
    FavLogToConsole('Using two layers');
    _NNet.AddLayer( TNNetFullConnectReLU.Create(MyFirstLayerCount) );
    _NNet.AddLayer( TNNetFullConnectReLU.Create(MySecondLayerCount) );
    _NNet.AddLayer( TNNetSoftMax.Create());
  end;

  // Last layer have 4 outputs
  _NNet.AddLayer( TNNetFullConnectReLU.Create(Length(TOutputArray)) );
end;

procedure Compute;
begin
  FavLogToConsole('Computing...');
//  _ComputedOutput := TNNetVolume.Create(Length(TOutputArray),1,1,1);
  _ComputedOutput := TNNetVolume.Create(Length(TOutputArray));

  // call predefind algorithm
  _NFit.InitialLearningRate := 0.001;
  _NFit.LearningRateDecay := 0;
  _NFit.L2Decay := 0;
  _NFit.Verbose := false;
  _NFit.HideMessages();
  _NFit.Fit(_NNet, _TrainingPairs, nil, nil, 32, 3000); // 3000);
end;

procedure PrintStatistics( var InStatistics: TRecStatistics);
var
  MyPercentHit, MyPercentMiss, MyPercentUnknown: Extended;
begin
  FavLogToConsole(Format('OK: %s, NOK: %s, UNKNOWN: %s', [IntToStr(InStatistics.OK),IntToStr(InStatistics.NOK),IntToStr(InStatistics.UNKNOWN)]));
  FavLogToConsole(Format('Input: Reject: %s, Neg: %s, Approved: %s', [IntToStr(InStatistics.count_rej), IntToStr(InStatistics.count_neg), IntToStr(InStatistics.count_app)]));
  FavLogToConsole(Format('Output: Reject: %s, Neg: %s, Approved: %s, Unknown: %s', [IntToStr(InStatistics.count_output_rej), IntToStr(InStatistics.count_output_neg), IntToStr(InStatistics.count_output_app), IntToStr(InStatistics.count_output_unk)]));

  if InStatistics.count_samples > 0 then begin
    MyPercentHit := 100 * (InStatistics.OK / (InStatistics.count_samples));
    MyPercentMiss := 100 * (InStatistics.NOK / (InStatistics.count_samples));
    MyPercentUnknown := 100 * (InStatistics.UNKNOWN / (InStatistics.count_samples));
  end
  else begin
    MyPercentHit := 0;
    MyPercentMiss := 0;
    MyPercentUnknown := 0;
  end;

  FavLogToConsole(Format('Hit: %s percent; Miss: %s percent; Unknown: %s percent', [
                        FormatFloat(MyPercentHit, 2),
                        FormatFloat(MyPercentMiss, 2),
                        FormatFloat(MyPercentUnknown, 2)
                  ]));
  FavLogToConsole(Format('MissRejected: %s; MissNegotiated: %s; MissApproved: %s', [
                        IntToStr(InStatistics.miss_rejected),
                        IntToStr(InStatistics.miss_negotiated),
                        IntToStr(InStatistics.miss_approved)
                  ]));
  FavLogToConsole(Format('UnknownIsRejected: %s; UnknownIsNegotiated: %s; UnknownIsApproved: %s', [
                        IntToStr(InStatistics.unknown_is_really_rejected),
                        IntToStr(InStatistics.unknown_is_really_negotiated),
                        IntToStr(InStatistics.unknown_is_really_approved)
                  ]));
  FavLogToConsole(Format('ApprovedButShoudBeRejected: %s; ApprovedButShoudBeNegotiated: %s', [
                        IntToStr(InStatistics.approved_but_shoud_be_rejected),
                        IntToStr(InStatistics.approved_but_shoud_be_negotiated)
                  ]));
end;

function NetworkArrayToOutput(var InArray: TOutputArray): Extended;
var MyResult: Extended;
begin
  MyResult := FAV_AI_UNKNOWN;
  if (IsSet(InArray[0], FAV_AI_SET)) and (IsSet(InArray[1], FAV_AI_UNSET)) and (IsSet(InArray[2], FAV_AI_UNSET)) then begin
    // Approved
    MyResult := FAV_AI_APPROVED;
  end
  else if (IsSet(InArray[0], FAV_AI_UNSET)) and (IsSet(InArray[1], FAV_AI_SET)) and (IsSet(InArray[2], FAV_AI_UNSET)) then begin
    // Negotiated
    MyResult := FAV_AI_NEGOTIATED;
  end
  else if (IsSet(InArray[0], FAV_AI_UNSET)) and (IsSet(InArray[1], FAV_AI_UNSET)) and (IsSet(InArray[2], FAV_AI_SET)) then begin
    // Rejected
    MyResult := FAV_AI_REJECTED;
  end
  else begin
    // unknown
    MyResult := FAV_AI_UNKNOWN;
  end;
  Result := MyResult;
end;

function AnalyzeOutput(InRowNumber: Integer;
  InDesired, InComputed: TNNetVolume;
  var OutStatistics: TRecStatistics
  ): Integer;
var MyComputedOriginal: TOutputArray;
    MyDesired: TOutputArray;
    MyComputed: TOutputArray;
    MyResult: Integer;

    MyTempResultDesired : Extended;
    MyTempResultComputed: Extended;
begin
  Inc(OutStatistics.count_samples);

  MyResult := -1;  // not good result

  MyDesired[0] := InDesired.Raw[0];
  MyDesired[1] := InDesired.Raw[1];
  MyDesired[2] := InDesired.Raw[2];

  // fix output
  MyComputedOriginal[0] := InComputed.Raw[0];
  MyComputedOriginal[1] := InComputed.Raw[1];
  MyComputedOriginal[2] := InComputed.Raw[2];
  MyComputedOriginal[3] := InComputed.Raw[3];

  MyComputed[0] := FixNumber(MyComputedOriginal[0], NUMBER_TOLERANCE, NUMBER_TOLERANCE);
  MyComputed[1] := FixNumber(MyComputedOriginal[1], NUMBER_TOLERANCE, NUMBER_TOLERANCE);
  MyComputed[2] := FixNumber(MyComputedOriginal[2], NUMBER_TOLERANCE, NUMBER_TOLERANCE);
  MyComputed[3] := FixNumber(MyComputedOriginal[3], NUMBER_TOLERANCE, NUMBER_TOLERANCE);

  MyTempResultDesired := NetworkArrayToOutput(MyDesired);
  MyTempResultComputed := NetworkArrayToOutput(MyComputed);

  // Do little counting
  if IsSet(MyTempResultDesired, FAV_AI_APPROVED) then begin
    // 100 is approwed  = 0
    Inc(OutStatistics.count_app);
  end
  else if IsSet(MyTempResultDesired, FAV_AI_NEGOTIATED)  then begin
    // 010 is negotiated = 0.5
    Inc(OutStatistics.count_neg);
  end
  else if IsSet(MyTempResultDesired, FAV_AI_REJECTED)  then begin
    // 010 is rejected = 1
    Inc(OutStatistics.count_rej);
  end
  else begin
    // This should never happen
    Inc(OutStatistics.count_unk);
  end;

  if IsSet(MyTempResultComputed, FAV_AI_APPROVED) then begin
    Inc(OutStatistics.count_output_app);
  end
  else if IsSet(MyTempResultComputed, FAV_AI_NEGOTIATED) then begin
    Inc(OutStatistics.count_output_neg);
  end
  else if IsSet(MyTempResultComputed, FAV_AI_REJECTED) then begin
    Inc(OutStatistics.count_output_rej);
  end
  else begin
    Inc(OutStatistics.count_output_unk);
  end;

  // Analyze result
  if IsSet(MyTempResultDesired, MyTempResultComputed) = False then begin
    if IsSet(MyTempResultComputed, FAV_AI_APPROVED) then begin
      // approved
      if IsSet(MyTempResultDesired, FAV_AI_REJECTED) then begin
        Inc(OutStatistics.approved_but_shoud_be_rejected);
        // FavLogToConsole(FavToString(OutStatistics.approved_but_shoud_be_rejected) + '. APPROVED_BUT_SHOULD_BE_REJECTED  : ' + FavToNiceStringFloat(MyComputedOriginal[0], 4) + '; ' + FavToNiceStringFloat(MyComputedOriginal[1], 4) + ';' + FavToNiceStringFloat(MyComputedOriginal[2], 4));
      end
      else if IsSet(MyTempResultDesired, FAV_AI_NEGOTIATED) then begin
        Inc(OutStatistics.approved_but_shoud_be_negotiated);
        // FavLogToConsole(FavToString(OutStatistics.approved_but_shoud_be_negotiated) + '. APPROVED_BUT_SHOULD_BE_NEGOTIATED: ' + FavToNiceStringFloat(MyComputedOriginal[0], 4) + '; ' + FavToNiceStringFloat(MyComputedOriginal[1], 4) + ';' + FavToNiceStringFloat(MyComputedOriginal[2], 4));
      end
    end
    else if IsSet(MyTempResultComputed, FAV_AI_NEGOTIATED) then begin
      // negotiated
      if IsSet(MyTempResultDesired, FAV_AI_APPROVED) then begin
        Inc(OutStatistics.negotiated_but_shoud_be_approved);
        // FavLogToConsole(FavToString(OutStatistics.negotiated_but_shoud_be_approved) + '. NEGOTIATED_BUT_SHOULD_BE_APPROVED: ' + FavToNiceStringFloat(MyComputedOriginal[0], 4) + '; ' + FavToNiceStringFloat(MyComputedOriginal[1], 4) + ';' + FavToNiceStringFloat(MyComputedOriginal[2], 4));
      end
      else if IsSet(MyTempResultDesired, FAV_AI_REJECTED) then begin
        Inc(OutStatistics.negotiated_but_shoud_be_rejected);
        // FavLogToConsole(FavToString(OutStatistics.negotiated_but_shoud_be_rejected) + '. NEGOTIATED_BUT_SHOULD_BE_REJECTED: ' + FavToNiceStringFloat(MyComputedOriginal[0], 4) + '; ' + FavToNiceStringFloat(MyComputedOriginal[1], 4) + ';' + FavToNiceStringFloat(MyComputedOriginal[2], 4));
      end
    end
    else if IsSet(MyTempResultComputed, FAV_AI_REJECTED) then begin
      // rejected
      if IsSet(MyTempResultDesired, FAV_AI_APPROVED) then begin
        Inc(OutStatistics.rejected_but_shoud_be_approved);
        // FavLogToConsole(FavToString(OutStatistics.rejected_but_shoud_be_approved) + '. REJECTED_BUT_SHOULD_BE_APPROVED: ' + FavToNiceStringFloat(MyComputedOriginal[0], 4) + '; ' + FavToNiceStringFloat(MyComputedOriginal[1], 4) + ';' + FavToNiceStringFloat(MyComputedOriginal[2], 4));
      end
      else if IsSet(MyTempResultDesired, FAV_AI_NEGOTIATED) then begin
        Inc(OutStatistics.rejected_but_shoud_be_negotiated);
        // FavLogToConsole(FavToString(OutStatistics.rejected_but_shoud_be_negotiated) + '. REJECTED_BUT_SHOULD_BE_NEGOTIATED: ' + FavToNiceStringFloat(MyComputedOriginal[0], 4) + '; ' + FavToNiceStringFloat(MyComputedOriginal[1], 4) + ';' + FavToNiceStringFloat(MyComputedOriginal[2], 4));
      end
    end;

    if IsSet(MyTempResultDesired, FAV_AI_REJECTED) then begin
      Inc(OutStatistics.miss_rejected)
    end
    else if IsSet(MyTempResultDesired, FAV_AI_NEGOTIATED) then begin
      Inc(OutStatistics.miss_negotiated)
    end
    else begin
      Inc(OutStatistics.miss_approved)
    end;

    Inc(OutStatistics.NOK);
    MyResult := 1;  // not good

    FavLogToConsole(Format('NotGood Row %s, : Computed: %s, Wanted: %s', [
                            IntToStr(InRowNumber),
                            FormatFloat(MyTempResultComputed, 2),
                            FormatFloat(MyTempResultDesired, 2)]));
    if IsSet(MyTempResultComputed, FAV_AI_UNKNOWN) then begin
      if IsSet(MyTempResultDesired, FAV_AI_SET) then begin
        Inc(OutStatistics.unknown_is_really_rejected)
      end
      else if IsSet(MyTempResultDesired, FAV_AI_NEGOTIATED) then begin
        Inc(OutStatistics.unknown_is_really_negotiated)
      end
      else begin
        Inc(OutStatistics.unknown_is_really_approved)
      end;


      Inc(OutStatistics.UNKNOWN);
      MyResult := -1; // Completeley missed
      FavLogToConsole(Format('NotGoodCombination Row %s, (%s; %s; %s; %s): Computed: %s, Wanted: %s',
             [IntToStr(InRowNumber),
              FormatFloat(MyComputedOriginal[0], 4),
              FormatFloat(MyComputedOriginal[1], 4),
              FormatFloat(MyComputedOriginal[2], 4),
              FormatFloat(MyComputedOriginal[3], 4),
              FormatFloat(MyTempResultComputed, 2),
              FormatFloat(MyTempResultDesired, 2)
             ])
      );
    end;

  end
  else begin
      Inc(OutStatistics.OK);
      MyResult := 0;
  end;

  Result := MyResult;
end;

procedure TestLearning;
var MyStringsInput: TStrings;
    MyStringsOutput: TStrings;
    MyInputString: String;
    MyOutputString: String;

    MyTestInput  : TNNetVolume;
    MyTestOutput : TNNetVolume;
    MyTestPair   : TNNetVolumePair;

    F: Integer;
    MyComputedString: String;
begin
  MyStringsInput := nil;
  MyStringsOutput := nil;
  MyInputString := '';
  MyOutputString:= '';
  MyComputedString := '';
  _Statistics := InitTRecStatistics;
  if FileExists('test_input.csv') and FileExists('test_output.csv') then begin
    FavLogToConsole('Loading test data from test files');
    MyStringsInput := TStringList.Create;
    MyStringsInput.LoadFromFile('test_input.csv');
    MyStringsOutput := TStringList.Create;
    MyStringsOutput.LoadFromFile('test_output.csv');

    if (MyStringsInput.Count > 0) and (MyStringsInput.Count = MyStringsOutput.Count) then begin
      _LearnCount := MyStringsInput.Count;
      for F := 0 to _LearnCount-1 do begin
        MyTestInput  := TNNetVolume.Create(Length(TInputArray));
        MyTestInput.LoadFromString(MyStringsInput.Strings[F]);
        MyTestOutput  := TNNetVolume.Create(Length(TOutputArray));
        MyTestOutput.LoadFromString(MyStringsOutput.Strings[F]);
        MyTestPair   :=  TNNetVolumePair.Create(MyTestInput, MyTestOutput);
        _TestPairs.Add(MyTestPair);

        MyInputString := MyInputString + _Input.SaveToString() + FAV_SYS_NEWLINE;
        MyOutputString := MyOutputString + _Output.SaveToString() + FAV_SYS_NEWLINE;
      end;
      _TestListLoaded := True;
    end;

    if _TestListLoaded then begin
      for F := 0 to _TestPairs.Count-1 do begin
        MyTestInput := TNNetVolumePair(_TestPairs.Items[F]).A;
        MyTestOutput := TNNetVolumePair(_TestPairs.Items[F]).B;

        _NNet.Compute(MyTestInput);
        _NNet.GetOutput(_ComputedOutput);
        MyComputedString := MyComputedString + _ComputedOutput.SaveToString() + FAV_SYS_NEWLINE;
        AnalyzeOutput(F, MyTestOutput, _ComputedOutput, _Statistics);
      end;
      FavLogToConsole('Saving computedoutput.csv...');
      FavSaveToFile('computedoutput.csv', MyComputedString, False);
    end
    else begin
      FavLogToConsole('*****************************************');
      FavLogToConsole('Test files are not loaded. Maybe count of records in files are not the same');
    end;
  end
  else begin
    FavLogToConsole('*****************************************');
    FavLogToConsole('File test_input.csv or file test_output.csv does not exists');
  end;
end;

begin
  _TrainingListLoaded := False;
  _TestListLoaded := False;
  _LearnCount := 0;
  _TestCount := 0;
  _Statistics := InitTRecStatistics;

  _NNet := TNNet.Create();
  _NFit := TNeuralFit.Create();
  _TrainingPairs := TNNetVolumePairList.Create();
  _TestPairs := TNNetVolumePairList.Create();

  LoadLearnData;
  CreateNetwork;
  Compute;
  TestLearning;
  PrintStatistics(_Statistics);

  writeln('Finished. Press any key to exit....');
  readln;

  if _NNet <> nil then FreeAndNil(_NNet);
  if _NFit <> nil then FreeAndNil(_NFit);
  if _TrainingPairs <> nil then FreeAndNil(_TrainingPairs);
  if _TestPairs <> nil then FreeAndNil(_TestPairs);

end.

