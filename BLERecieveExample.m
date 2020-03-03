% Check if the 'Communications Toolbox Library for the Bluetooth Protocol'
% support package is installed or not.
commSupportPackageCheck('BLUETOOTH');
phyMode = 'LE1M';
bleParam = helperBLEReceiverConfig(phyMode);

    % First check if the HSP exists
    if isempty(which('plutoradio.internal.getRootDir'))
        error(message('comm_demos:common:NoSupportPackage', ...
                      'Communications Toolbox Support Package for ADALM-PLUTO Radio',...
                      ['<a href="https://www.mathworks.com/hardware-support/' ...
                      'adalm-pluto-radio.html">ADALM-PLUTO Radio Support From Communications Toolbox</a>']));
    end

    bbSampleRate = bleParam.SymbolRate * bleParam.SamplesPerSymbol;
    sigSrc = sdrrx('Pluto',...
        'RadioID',             'usb:0',...
        'CenterFrequency',     2.402e9,...
        'BasebandSampleRate',  bbSampleRate,...
        'SamplesPerFrame',     1e7,...
        'GainSource',         'Manual',...
        'Gain',                25,...
        'OutputDataType',     'double');
    
% Setup spectrum viewer
spectrumScope = dsp.SpectrumAnalyzer( ...
    'SampleRate',       bbSampleRate,...
    'SpectrumType',     'Power density', ...
    'SpectralAverages', 10, ...
    'YLimits',          [-130 -30], ...
    'Title',            'Received Baseband BLE Signal Spectrum', ...
    'YLabel',           'Power spectral density');
% The transmitted waveform is captured as a burst
dataCaptures = sigSrc();

% Show power spectral density of the received waveform
spectrumScope(dataCaptures);
% Initialize System objects for receiver processing
agc = comm.AGC('MaxPowerGain',20,'DesiredOutputPower',2);

freqCompensator = comm.CoarseFrequencyCompensator('Modulation', 'OQPSK',...
                'SampleRate',bbSampleRate,...
                'SamplesPerSymbol',2*bleParam.SamplesPerSymbol,...
                'FrequencyResolution',100);

prbDet = comm.PreambleDetector(bleParam.RefSeq,'Detections','First');

% Initialize counter variables
pktCnt = 0;
crcCnt = 0;
displayFlag = false; % true if the received data is to be printed

% Loop to decode the captured BLE samples
while length(dataCaptures) > bleParam.MinimumPacketLen

    % Consider two frames from the captured signal for each iteration
    startIndex = 1;
    endIndex = min(length(dataCaptures),2*bleParam.FrameLength);
    rcvSig = dataCaptures(startIndex:endIndex);

    rcvAGC = agc(rcvSig); % Perform AGC
    rcvDCFree = rcvAGC - mean(rcvAGC); % Remove the DC offset
    rcvFreqComp = freqCompensator(rcvDCFree); % Estimate and compensate for the carrier frequency offset
    rcvFilt = conv(rcvFreqComp,bleParam.h,'same'); % Perform gaussian matched filtering

    % Perform frame timing synchronization
    [~, dtMt] = prbDet(rcvFilt);
    release(prbDet)
    prbDet.Threshold = max(dtMt);
    prbIdx = prbDet(rcvFilt);

    % Extract message information
    [cfgLLAdv,pktCnt,crcCnt,remStartIdx] = helperBLEPhyBitRecover(rcvFilt,...
                                prbIdx,pktCnt,crcCnt,bleParam);

    % Remaining signal in the burst captures
    dataCaptures = dataCaptures(1+remStartIdx:end);

    % Display the decoded information
    if displayFlag && ~isempty(cfgLLAdv)
        fprintf('Advertising PDU Type: %s\n', cfgLLAdv.PDUType);
        fprintf('Advertising Address: %s\n', cfgLLAdv.AdvertiserAddress);
    end

    % Release System objects
    release(freqCompensator)
    release(prbDet)
end

% Release the signal source
release(sigSrc)

% Determine the PER
if pktCnt
    per = 1-(crcCnt/pktCnt);
    fprintf('Packet error rate for %s mode is %f.\n',bleParam.Mode,per);
else
    fprintf('\n No BLE packets were detected.\n')
end